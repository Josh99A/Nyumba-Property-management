import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/aes_gcm_json_codec.dart';

Uint8List _key(int fill) => Uint8List.fromList(List.filled(32, fill));

/// Sembast calls the codec once per record, so the cost that matters is what
/// each call adds on top of the cryptography. These pin the worker's reuse and
/// its error contract; correctness of the cipher itself lives in
/// local_mirror_recovery_test.dart.
void main() {
  test('many records share one worker isolate', () async {
    final codec = IsolateAesGcmJsonCodec(_key(11));
    addTearDown(codec.close);

    final encoded = <String>[];
    for (var record = 0; record < 40; record++) {
      encoded.add(await codec.encodeAsync(<String, Object?>{'n': record}));
    }
    for (var record = 0; record < encoded.length; record++) {
      expect(await codec.decodeAsync(encoded[record]), <String, Object?>{
        'n': record,
      });
    }

    expect(
      codec.workerSpawnCount,
      1,
      reason: '80 conversions must not cost 80 isolate spawns',
    );
  });

  test('overlapping conversions each get their own answer', () async {
    final codec = IsolateAesGcmJsonCodec(_key(12));
    addTearDown(codec.close);

    // Fired without awaiting in between, so replies can arrive interleaved and
    // the request ids are what keep them matched to the right caller.
    final pending = <Future<String>>[
      for (var record = 0; record < 16; record++)
        codec.encodeAsync(<String, Object?>{'n': record}),
    ];
    final encoded = await Future.wait(pending);

    final decoded = await Future.wait(encoded.map(codec.decodeAsync));
    expect(decoded, [
      for (var record = 0; record < 16; record++)
        <String, Object?>{'n': record},
    ]);
    expect(codec.workerSpawnCount, 1);
  });

  test('a foreign key fails as a FormatException across the port', () async {
    final written = IsolateAesGcmJsonCodec(_key(13));
    addTearDown(written.close);
    final foreign = IsolateAesGcmJsonCodec(_key(14));
    addTearDown(foreign.close);

    final encoded = await written.encodeAsync(<String, Object?>{'a': 1});

    // OfflineDatabase.openRecovering tests `is FormatException` to decide
    // whether a mirror is unreadable and should be rebuilt, so the type has to
    // survive the isolate boundary, not just the message.
    await expectLater(
      foreign.decodeAsync(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'closing releases the worker and the next record starts another',
    () async {
      final codec = IsolateAesGcmJsonCodec(_key(15));
      addTearDown(codec.close);

      final encoded = await codec.encodeAsync(<String, Object?>{'a': 1});
      expect(codec.workerSpawnCount, 1);

      await codec.close();

      expect(await codec.decodeAsync(encoded), <String, Object?>{'a': 1});
      expect(codec.workerSpawnCount, 2);
    },
  );
}
