import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/local_database_opener_io.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/aes_gcm_json_codec.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:sembast/sembast_io.dart';

void main() {
  test(
    'background compaction preserves the latest entity and outbox',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nyumba_background_compaction_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final databasePath = '${directory.path}${Platform.pathSeparator}large.db';
      final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
      final codec = SembastCodec(
        signature: 'nyumba-aes-256-gcm-v1',
        codec: AesGcmJsonCodec(key),
      );
      final database = await OfflineDatabase.open(
        factory: databaseFactoryIo,
        path: databasePath,
        codec: codec,
      );
      final photo =
          'data:image/jpeg;base64,${List.filled(256 * 1024, 'a').join()}';
      Map<String, Object?> entity(String name) => <String, Object?>{
        'id': 'property-1',
        'landlordId': 'landlord-1',
        'name': name,
        'imageUrls': [photo],
        'syncMetadata': SyncMetadataMapper.toJson(const SyncMetadata.pending()),
      };

      await database.putEntityAndEnqueue(
        entityType: OfflineEntityType.property,
        entityId: 'property-1',
        entity: entity('First'),
        mutationId: 'mutation-1',
        operation: OutboxOperation.create,
        createdAt: DateTime.utc(2026, 7, 22),
      );
      await database.acknowledgeMutation(
        mutationId: 'mutation-1',
        syncedAt: DateTime.utc(2026, 7, 22, 1),
        serverRevision: '1',
      );
      await database.putEntityAndEnqueue(
        entityType: OfflineEntityType.property,
        entityId: 'property-1',
        entity: entity('Latest'),
        mutationId: 'mutation-2',
        operation: OutboxOperation.update,
        createdAt: DateTime.utc(2026, 7, 22, 2),
      );
      await database.close();
      final sizeBefore = await File(databasePath).length();

      await compactLargeDatabaseInBackground(
        databasePath,
        key,
        thresholdBytes: 0,
      );

      final sizeAfter = await File(databasePath).length();
      expect(sizeAfter, lessThan(sizeBefore));
      final reopened = await OfflineDatabase.open(
        factory: databaseFactoryIo,
        path: databasePath,
        codec: codec,
      );
      addTearDown(reopened.close);
      final properties = await reopened.readEntities(
        OfflineEntityType.property,
      );
      expect(properties, hasLength(1));
      expect(properties.single['name'], 'Latest');
      expect(properties.single['imageUrls'], [photo]);
      final outbox = await reopened.readOutbox();
      expect(outbox, hasLength(1));
      expect(outbox.single.id, 'mutation-2');
    },
  );

  test('background compaction leaves a foreign-key mirror untouched', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nyumba_foreign_key_compaction_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final databasePath = '${directory.path}${Platform.pathSeparator}large.db';
    final key = Uint8List.fromList(List.filled(32, 7));
    final codec = SembastCodec(
      signature: 'nyumba-aes-256-gcm-v1',
      codec: AesGcmJsonCodec(key),
    );
    final database = await OfflineDatabase.open(
      factory: databaseFactoryIo,
      path: databasePath,
      codec: codec,
    );
    await database.putLocalEntity(
      entityType: OfflineEntityType.property,
      entityId: 'property-1',
      entity: <String, Object?>{
        'id': 'property-1',
        'payload': List.filled(16 * 1024, 'x').join(),
      },
      reason: LocalOnlyReason.localWorkspaceOnly,
    );
    await database.close();
    final bytesBefore = await File(databasePath).readAsBytes();

    await compactLargeDatabaseInBackground(
      databasePath,
      Uint8List.fromList(List.filled(32, 8)),
      thresholdBytes: 0,
    );

    expect(await File(databasePath).readAsBytes(), bytesBefore);
    final reopened = await OfflineDatabase.open(
      factory: databaseFactoryIo,
      path: databasePath,
      codec: codec,
    );
    addTearDown(reopened.close);
    expect(
      await reopened.readEntity(OfflineEntityType.property, 'property-1'),
      isNotNull,
    );
  });
}
