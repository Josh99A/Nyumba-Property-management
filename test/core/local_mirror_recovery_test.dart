import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/aes_gcm_json_codec.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:pointycastle/export.dart';
// The in-memory factory keeps live objects and never encodes them, so it
// cannot reproduce a codec mismatch. These tests use the file factory.
import 'package:sembast/sembast_io.dart';

SembastCodec _codecWith(int seed) => SembastCodec(
  signature: 'nyumba-aes-256-gcm-v1',
  codec: AesGcmJsonCodec(Uint8List.fromList(List.filled(32, seed))),
);

Map<String, Object?> _entityJson(String id) => <String, Object?>{
  'id': id,
  'landlordId': 'landlord-1',
  'name': 'Sunset Apartments',
  'syncMetadata': SyncMetadataMapper.toJson(SyncMetadata.pending()),
};

Future<void> _seedOne(OfflineDatabase database, String id) =>
    database.putEntityAndEnqueue(
      entityType: OfflineEntityType.property,
      entityId: id,
      entity: _entityJson(id),
      mutationId: 'mutation-$id',
      operation: OutboxOperation.create,
      createdAt: DateTime.utc(2026, 7, 15),
    );

void main() {
  group('unreadable local mirror recovery', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('nyumba_mirror_');
    });

    tearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    String pathFor(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';

    test(
      'plaintext mirror reopened with a codec is rebuilt, not fatal',
      () async {
        final path = pathFor('recovery-plaintext.db');
        final plaintext = await OfflineDatabase.open(
          factory: databaseFactoryIo,
          path: path,
        );
        await _seedOne(plaintext, 'property-1');
        await plaintext.close();

        // Reproduces the reported failure: sembast rejects the mismatched codec.
        await expectLater(
          OfflineDatabase.open(
            factory: databaseFactoryIo,
            path: path,
            codec: _codecWith(1),
          ),
          throwsA(
            isA<DatabaseException>().having(
              (error) => error.code,
              'code',
              DatabaseException.errInvalidCodec,
            ),
          ),
        );

        final recovered = await OfflineDatabase.openRecovering(
          factory: databaseFactoryIo,
          path: path,
          codec: _codecWith(1),
        );
        addTearDown(recovered.close);
        expect(
          await recovered.readEntities(OfflineEntityType.property),
          isEmpty,
        );

        // The rebuilt mirror must be a working, writable database.
        await _seedOne(recovered, 'property-2');
        expect(
          await recovered.readEntities(OfflineEntityType.property),
          hasLength(1),
        );
      },
    );

    test('encrypted mirror reopened without its codec is rebuilt', () async {
      final path = pathFor('recovery-encrypted.db');
      final encrypted = await OfflineDatabase.open(
        factory: databaseFactoryIo,
        path: path,
        codec: _codecWith(2),
      );
      await _seedOne(encrypted, 'property-1');
      await encrypted.close();

      final recovered = await OfflineDatabase.openRecovering(
        factory: databaseFactoryIo,
        path: path,
      );
      addTearDown(recovered.close);
      expect(await recovered.readEntities(OfflineEntityType.property), isEmpty);
    });

    test('a readable mirror is never discarded', () async {
      final path = pathFor('recovery-intact.db');
      final first = await OfflineDatabase.open(
        factory: databaseFactoryIo,
        path: path,
        codec: _codecWith(3),
      );
      await _seedOne(first, 'property-1');
      await first.close();

      final reopened = await OfflineDatabase.openRecovering(
        factory: databaseFactoryIo,
        path: path,
        codec: _codecWith(3),
      );
      addTearDown(reopened.close);
      expect(
        await reopened.readEntities(OfflineEntityType.property),
        hasLength(1),
        reason: 'Recovery must not delete a mirror that opens correctly.',
      );
      expect(await reopened.readOutbox(), hasLength(1));
    });

    test('classifies only undecodable failures as unreadable', () {
      expect(
        OfflineDatabase.isUnreadableMirror(
          DatabaseException.invalidCodec('Invalid codec signature'),
        ),
        isTrue,
      );
      expect(
        OfflineDatabase.isUnreadableMirror(const FormatException('bad')),
        isTrue,
      );
      expect(
        OfflineDatabase.isUnreadableMirror(DatabaseException.closed()),
        isFalse,
        reason: 'A closed database is a fault, not an unreadable mirror.',
      );
      expect(OfflineDatabase.isUnreadableMirror(StateError('x')), isFalse);
    });
  });

  test('AES codec round-trips and rejects a foreign key', () {
    final codec = AesGcmJsonCodec(Uint8List.fromList(List.filled(32, 7)));
    final encoded = codec.encoder.convert(<String, Object?>{'a': 1});
    expect(codec.decoder.convert(encoded), <String, Object?>{'a': 1});

    final foreign = AesGcmJsonCodec(Uint8List.fromList(List.filled(32, 8)));
    expect(
      () => foreign.decoder.convert(encoded),
      throwsA(isA<FormatException>()),
      reason:
          'A wrong workspace key must fail authentication, not return data.',
    );
    expect(encoded, isNot(contains(jsonEncode(<String, Object?>{'a': 1}))));
  });

  test('optimized AES codec reads records written by the legacy cipher', () {
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (index) => 200 + index),
    );
    final value = <String, Object?>{
      'name': 'large offline record',
      'photo': List.filled(4097, 'x').join(),
    };
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    final legacy = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final sealed = legacy.process(plaintext);
    final encoded = base64UrlEncode(
      Uint8List(nonce.length + sealed.length)
        ..setRange(0, nonce.length, nonce)
        ..setRange(nonce.length, nonce.length + sealed.length, sealed),
    );

    expect(AesGcmJsonCodec(key).decoder.convert(encoded), value);
  });

  test('legacy AES cipher reads records written by the optimized codec', () {
    final key = Uint8List.fromList(
      List<int>.generate(32, (index) => 255 - index),
    );
    final value = <String, Object?>{
      'items': List<String>.generate(257, (index) => 'item-$index'),
    };
    final encoded = AesGcmJsonCodec(key).encoder.convert(value);
    final bytes = base64Url.decode(encoded);
    final nonce = Uint8List.sublistView(bytes, 0, 12);
    final sealed = Uint8List.sublistView(bytes, 12);
    final legacy = GCMBlockCipher(
      AESEngine(),
    )..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));

    expect(jsonDecode(utf8.decode(legacy.process(sealed))), value);
  });

  test('isolate AES codec preserves Sembast records across reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nyumba_isolate_codec_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}isolate.db';
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
    SembastCodec codec() => SembastCodec(
      signature: 'nyumba-aes-256-gcm-v1',
      codec: IsolateAesGcmJsonCodec(key),
    );
    final first = await OfflineDatabase.open(
      factory: databaseFactoryIo,
      path: path,
      codec: codec(),
    );
    await _seedOne(first, 'property-isolate');
    await first.close();

    final reopened = await OfflineDatabase.open(
      factory: databaseFactoryIo,
      path: path,
      codec: codec(),
    );
    addTearDown(reopened.close);
    final properties = await reopened.readEntities(OfflineEntityType.property);
    expect(properties, hasLength(1));
    expect(properties.single['id'], 'property-isolate');
    expect(properties.single['name'], 'Sunset Apartments');
    expect(await reopened.readOutbox(), hasLength(1));
  });
}
