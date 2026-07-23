import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:sembast/sembast.dart';

/// Synchronous authenticated AES-256-GCM codec used by Sembast on mobile.
/// Each record receives a fresh 96-bit nonce and includes its authentication
/// tag in the encoded ciphertext.
final class AesGcmJsonCodec extends Codec<Object?, String> {
  AesGcmJsonCodec(Uint8List key)
    : assert(key.length == 32),
      _cipher = _FastAesGcm(Uint8List.fromList(key));

  final _FastAesGcm _cipher;

  @override
  Converter<String, Object?> get decoder => _AesGcmDecoder(_cipher);

  @override
  Converter<Object?, String> get encoder => _AesGcmEncoder(_cipher);
}

/// Asynchronous Sembast adapter that performs the synchronous cryptography and
/// JSON conversion on a worker isolate.
///
/// Sembast awaits [decodeAsync] and [encodeAsync] between records, so database
/// ordering and transaction durability are unchanged while Android's platform
/// thread remains free to acknowledge focus and lifecycle events.
///
/// The work goes to one long-lived worker rather than a fresh `Isolate.run`
/// per call. Sembast invokes the codec once per record, and spawning an
/// isolate — then rebuilding this key's GHASH table inside it — costs more
/// than the cryptography itself once a mirror holds thousands of records. One
/// worker pays both costs once and then answers over a port.
///
/// The worker exits on its own after [_idleTimeout] without work, so a
/// database that is opened and then left alone does not pin an isolate for the
/// life of the process. The next record spawns a fresh one.
final class IsolateAesGcmJsonCodec extends AsyncContentCodecBase {
  IsolateAesGcmJsonCodec(Uint8List key)
    : assert(key.length == 32),
      _key = Uint8List.fromList(key);

  static const Duration _idleTimeout = Duration(seconds: 15);

  final Uint8List _key;
  Future<_CodecWorker>? _worker;
  int _spawns = 0;

  /// How many worker isolates this codec has started, for tests. One spawn
  /// covering many records is the entire point of the class, so it is worth
  /// being able to assert on.
  int get workerSpawnCount => _spawns;

  @override
  Future<Object?> decodeAsync(String encoded) async {
    final worker = await _readyWorker();
    return worker.convert(encode: false, payload: encoded);
  }

  @override
  Future<String> encodeAsync(Object? input) async {
    final worker = await _readyWorker();
    return await worker.convert(encode: true, payload: input) as String;
  }

  /// Releases the worker now instead of waiting for it to time out. Optional —
  /// nothing leaks without it — but tests and short-lived tooling can reclaim
  /// the isolate immediately.
  Future<void> close() async {
    final pending = _worker;
    _worker = null;
    if (pending == null) return;
    try {
      (await pending).shutdown();
    } on Object {
      // A worker that never started needs no shutdown.
    }
  }

  Future<_CodecWorker> _readyWorker() async {
    while (true) {
      final pending = _worker;
      if (pending != null) {
        final worker = await pending;
        if (!worker.isClosed) return worker;
        // It timed out between the last record and this one; drop it and
        // spawn again on the next turn of the loop.
        if (identical(_worker, pending)) _worker = null;
        continue;
      }
      _spawns++;
      final spawning = _CodecWorker.spawn(_key, idleTimeout: _idleTimeout);
      _worker = spawning;
      try {
        return await spawning;
      } on Object {
        if (identical(_worker, spawning)) _worker = null;
        rethrow;
      }
    }
  }
}

/// The main-isolate half of the codec worker: one command port out, one
/// response port back, and a request id so replies can be matched even if
/// Sembast ever overlaps two records.
final class _CodecWorker {
  _CodecWorker._(
    this._isolate,
    this._commands,
    this._responses,
    this._idleTimeout,
  );

  static Future<_CodecWorker> spawn(
    Uint8List key, {
    required Duration idleTimeout,
  }) async {
    final setup = ReceivePort();
    final responses = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _codecWorkerMain,
        (setup.sendPort, responses.sendPort, Uint8List.fromList(key)),
        // A worker that dies unexpectedly sends null here, which fails every
        // in-flight record rather than leaving Sembast awaiting forever.
        onExit: responses.sendPort,
      );
    } on Object {
      setup.close();
      responses.close();
      rethrow;
    }
    final commands = await setup.first as SendPort;
    setup.close();
    final worker = _CodecWorker._(isolate, commands, responses, idleTimeout);
    responses.listen(worker._onResponse);
    return worker;
  }

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _responses;
  final Duration _idleTimeout;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  Timer? _idle;
  int _nextId = 0;
  bool _closed = false;

  bool get isClosed => _closed;

  Future<Object?> convert({required bool encode, required Object? payload}) {
    if (_closed) {
      return Future<Object?>.error(StateError('The codec worker is closed.'));
    }
    _idle?.cancel();
    _idle = null;
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send((id, encode, payload));
    return completer.future;
  }

  void shutdown() {
    if (_closed) return;
    _closed = true;
    _idle?.cancel();
    _idle = null;
    _commands.send(null);
    _responses.close();
    _failPending(StateError('The codec worker shut down.'));
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  void _onResponse(Object? message) {
    if (message == null) {
      // onExit: the worker is gone and nothing in flight can be answered.
      _closed = true;
      _idle?.cancel();
      _idle = null;
      _responses.close();
      _failPending(StateError('The codec worker exited unexpectedly.'));
      return;
    }
    final (id, value, failure) = message as (int, Object?, (String, String)?);
    final completer = _pending.remove(id);
    if (completer != null) {
      if (failure == null) {
        completer.complete(value);
      } else {
        final (kind, text) = failure;
        completer.completeError(
          kind == _formatFailure ? FormatException(text) : StateError(text),
        );
      }
    }
    if (_pending.isEmpty && !_closed) {
      _idle = Timer(_idleTimeout, shutdown);
    }
  }

  void _failPending(Object error) {
    final waiting = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in waiting) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }
}

/// Marks a failure that must arrive back on the main isolate as a
/// [FormatException] rather than as text.
const String _formatFailure = 'format';

void _codecWorkerMain((SendPort, SendPort, Uint8List) setup) {
  final (ready, responses, key) = setup;
  // Built once for the life of the worker; this is the cost that made a
  // per-record isolate wasteful.
  final codec = AesGcmJsonCodec(key);
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  commands.listen((message) {
    if (message == null) {
      commands.close();
      return;
    }
    final (id, encode, payload) = message as (int, bool, Object?);
    try {
      responses.send((
        id,
        encode
            ? codec.encoder.convert(payload)
            : codec.decoder.convert(payload as String),
        null,
      ));
    } on FormatException catch (error) {
      // OfflineDatabase.openRecovering decides to delete and rebuild by
      // testing `is FormatException`, so the type has to survive the port, not
      // just the message. A rotated workspace key depends on it.
      responses.send((id, null, (_formatFailure, error.message)));
    } on Object catch (error) {
      responses.send((id, null, ('error', error.toString())));
    }
  });
}

final class _AesGcmEncoder extends Converter<Object?, String> {
  const _AesGcmEncoder(this.cipher);

  final _FastAesGcm cipher;

  @override
  String convert(Object? input) {
    final nonce = Uint8List(12);
    final random = Random.secure();
    for (var index = 0; index < nonce.length; index++) {
      nonce[index] = random.nextInt(256);
    }
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(input)));
    final ciphertext = cipher.encrypt(plaintext, nonce);
    return base64UrlEncode(Uint8List.fromList([...nonce, ...ciphertext]));
  }
}

final class _AesGcmDecoder extends Converter<String, Object?> {
  const _AesGcmDecoder(this.cipher);

  final _FastAesGcm cipher;

  @override
  Object? convert(String input) {
    final encoded = base64Url.decode(input);
    if (encoded.length < 12 + 16) {
      throw const FormatException('Encrypted Sembast record is truncated.');
    }
    final nonce = Uint8List.sublistView(encoded, 0, 12);
    final ciphertext = Uint8List.sublistView(encoded, 12);
    try {
      return jsonDecode(utf8.decode(cipher.decrypt(ciphertext, nonce)));
    } on InvalidCipherTextException catch (error) {
      throw FormatException(
        'Encrypted Sembast record failed authentication.',
        error,
      );
    }
  }
}

/// Test-only access to [_FastAesGcm] for published known-answer vectors.
final class FastAesGcmTestHarness {
  FastAesGcmTestHarness(Uint8List key)
    : _cipher = _FastAesGcm(Uint8List.fromList(key));

  final _FastAesGcm _cipher;

  Uint8List encrypt(Uint8List plaintext, Uint8List nonce) =>
      _cipher.encrypt(plaintext, nonce);

  Uint8List decrypt(Uint8List sealed, Uint8List nonce) =>
      _cipher.decrypt(sealed, nonce);
}

/// One-shot AES-GCM specialized for Sembast's synchronous content-codec API.
///
/// PointyCastle's general GCM implementation multiplies each 128-bit block one
/// bit at a time and allocates inside that loop. That is reasonable for small
/// messages, but Sembast passes a complete transaction line to its codec. A
/// transaction containing an offline photo can therefore be several megabytes
/// and used to occupy Flutter's UI isolate long enough for Android to report an
/// input-dispatch ANR.
///
/// This implementation uses the same standard AES-GCM wire format while
/// precomputing GHASH's byte contributions for this workspace key. The table is
/// indexed by ciphertext (not secret data), and authentication tags are still
/// compared without an early exit.
final class _FastAesGcm {
  _FastAesGcm(Uint8List key) : _aes = AESEngine() {
    _aes.init(true, KeyParameter(key));
    final hashSubkey = Uint8List(_blockSize);
    _aes.processBlock(Uint8List(_blockSize), 0, hashSubkey, 0);
    _ghashTable = _buildGhashTable(hashSubkey);
  }

  static const int _blockSize = 16;
  static const int _nonceSize = 12;
  static const int _tagSize = 16;

  final AESEngine _aes;
  late final Uint32List _ghashTable;

  Uint8List encrypt(Uint8List plaintext, Uint8List nonce) {
    _checkNonce(nonce);
    final ciphertext = _cryptCtr(plaintext, nonce);
    final tag = _authenticationTag(ciphertext, nonce);
    return Uint8List(ciphertext.length + _tagSize)
      ..setRange(0, ciphertext.length, ciphertext)
      ..setRange(ciphertext.length, ciphertext.length + _tagSize, tag);
  }

  Uint8List decrypt(Uint8List sealed, Uint8List nonce) {
    _checkNonce(nonce);
    if (sealed.length < _tagSize) {
      throw InvalidCipherTextException('GCM ciphertext is truncated.');
    }

    final ciphertext = Uint8List.sublistView(
      sealed,
      0,
      sealed.length - _tagSize,
    );
    final suppliedTag = Uint8List.sublistView(sealed, sealed.length - _tagSize);
    final expectedTag = _authenticationTag(ciphertext, nonce);
    var difference = 0;
    for (var index = 0; index < _tagSize; index++) {
      difference |= suppliedTag[index] ^ expectedTag[index];
    }
    if (difference != 0) {
      throw InvalidCipherTextException('GCM authentication failed.');
    }
    return _cryptCtr(ciphertext, nonce);
  }

  Uint8List _cryptCtr(Uint8List input, Uint8List nonce) {
    final counter = _initialCounter(nonce);
    final streamBlock = Uint8List(_blockSize);
    final output = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += _blockSize) {
      _incrementCounter(counter);
      _aes.processBlock(counter, 0, streamBlock, 0);
      final count = min(_blockSize, input.length - offset);
      for (var index = 0; index < count; index++) {
        output[offset + index] = input[offset + index] ^ streamBlock[index];
      }
    }
    return output;
  }

  Uint8List _authenticationTag(Uint8List ciphertext, Uint8List nonce) {
    final state = Uint8List(_blockSize);
    for (var offset = 0; offset < ciphertext.length; offset += _blockSize) {
      final count = min(_blockSize, ciphertext.length - offset);
      for (var index = 0; index < count; index++) {
        state[index] ^= ciphertext[offset + index];
      }
      _multiplyByHashSubkey(state);
    }

    // Nyumba supplies no additional authenticated data. The first 64 bits of
    // GCM's length block are therefore zero and the last 64 are ciphertext
    // length in bits, encoded big-endian.
    final bitLength = ciphertext.length * 8;
    for (var index = 0; index < 8; index++) {
      state[15 - index] ^= (bitLength >>> (index * 8)) & 0xff;
    }
    _multiplyByHashSubkey(state);

    final encryptedInitialCounter = Uint8List(_blockSize);
    _aes.processBlock(_initialCounter(nonce), 0, encryptedInitialCounter, 0);
    for (var index = 0; index < _tagSize; index++) {
      state[index] ^= encryptedInitialCounter[index];
    }
    return state;
  }

  void _multiplyByHashSubkey(Uint8List value) {
    var word0 = 0;
    var word1 = 0;
    var word2 = 0;
    var word3 = 0;
    for (var position = 0; position < _blockSize; position++) {
      final offset = ((position << 8) + value[position]) << 2;
      word0 ^= _ghashTable[offset];
      word1 ^= _ghashTable[offset + 1];
      word2 ^= _ghashTable[offset + 2];
      word3 ^= _ghashTable[offset + 3];
    }
    _writeWord(value, 0, word0);
    _writeWord(value, 4, word1);
    _writeWord(value, 8, word2);
    _writeWord(value, 12, word3);
  }

  static Uint32List _buildGhashTable(Uint8List hashSubkey) {
    final basis = Uint32List(128 * 4);
    for (var word = 0; word < 4; word++) {
      basis[word] = _readWord(hashSubkey, word * 4);
    }
    for (var bit = 1; bit < 128; bit++) {
      final previous = (bit - 1) * 4;
      final current = bit * 4;
      final word0 = basis[previous];
      final word1 = basis[previous + 1];
      final word2 = basis[previous + 2];
      final word3 = basis[previous + 3];
      final reduce = word3 & 1;
      basis[current] = (word0 >>> 1) ^ (reduce == 0 ? 0 : 0xe1000000);
      basis[current + 1] = (word1 >>> 1) | ((word0 & 1) << 31);
      basis[current + 2] = (word2 >>> 1) | ((word1 & 1) << 31);
      basis[current + 3] = (word3 >>> 1) | ((word2 & 1) << 31);
    }

    final table = Uint32List(_blockSize * 256 * 4);
    for (var position = 0; position < _blockSize; position++) {
      for (var byte = 1; byte < 256; byte++) {
        final tableOffset = ((position << 8) + byte) << 2;
        for (var bit = 0; bit < 8; bit++) {
          if (byte & (0x80 >>> bit) == 0) continue;
          final basisOffset = (position * 8 + bit) * 4;
          table[tableOffset] ^= basis[basisOffset];
          table[tableOffset + 1] ^= basis[basisOffset + 1];
          table[tableOffset + 2] ^= basis[basisOffset + 2];
          table[tableOffset + 3] ^= basis[basisOffset + 3];
        }
      }
    }
    return table;
  }

  static Uint8List _initialCounter(Uint8List nonce) => Uint8List(_blockSize)
    ..setRange(0, _nonceSize, nonce)
    ..[15] = 1;

  static void _incrementCounter(Uint8List counter) {
    for (var index = 15; index >= 12; index--) {
      counter[index] = (counter[index] + 1) & 0xff;
      if (counter[index] != 0) return;
    }
  }

  static int _readWord(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static void _writeWord(Uint8List bytes, int offset, int value) {
    bytes[offset] = value >>> 24;
    bytes[offset + 1] = value >>> 16;
    bytes[offset + 2] = value >>> 8;
    bytes[offset + 3] = value;
  }

  static void _checkNonce(Uint8List nonce) {
    if (nonce.length != _nonceSize) {
      throw ArgumentError.value(nonce.length, 'nonce.length', _nonceSize);
    }
  }
}
