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
}
