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
final class IsolateAesGcmJsonCodec extends AsyncContentCodecBase {
  IsolateAesGcmJsonCodec(Uint8List key)
    : assert(key.length == 32),
      _key = Uint8List.fromList(key);

  final Uint8List _key;

  @override
  Future<Object?> decodeAsync(String encoded) {
    final key = Uint8List.fromList(_key);
    return Isolate.run(() => AesGcmJsonCodec(key).decoder.convert(encoded));
  }

  @override
  Future<String> encodeAsync(Object? input) {
    final key = Uint8List.fromList(_key);
    return Isolate.run(() => AesGcmJsonCodec(key).encoder.convert(input));
  }
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
