import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late OfflineDatabase database;
  final now = DateTime.utc(2026, 7, 13, 8);

  setUp(() async {
    database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(
        'nyumba-${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await database.initialize();
  });

  tearDown(() => database.close());

  test('entity and mutation are committed atomically', () async {
    await database.putEntityAndEnqueue(
      entityType: OfflineEntityType.property,
      entityId: 'property-1',
      entity: _entityJson(id: 'property-1', name: 'Garden Court'),
      mutationId: 'mutation-1',
      operation: OutboxOperation.create,
      createdAt: now,
      createOnly: true,
    );

    expect(
      await database.readEntity(OfflineEntityType.property, 'property-1'),
      containsPair('name', 'Garden Court'),
    );
    final outbox = await database.readOutbox();
    expect(outbox, hasLength(1));
    expect(outbox.single.entityId, 'property-1');
    expect(outbox.single.idempotencyKey, 'mutation-1');

    await expectLater(
      database.putEntityAndEnqueue(
        entityType: OfflineEntityType.property,
        entityId: 'property-1',
        entity: _entityJson(id: 'property-1', name: 'Overwritten'),
        mutationId: 'mutation-2',
        operation: OutboxOperation.create,
        createdAt: now,
        createOnly: true,
      ),
      throwsA(isA<EntityAlreadyExistsException>()),
    );

    expect(
      await database.readEntity(OfflineEntityType.property, 'property-1'),
      containsPair('name', 'Garden Court'),
    );
    expect(await database.outboxCount(), 1);
  });

  test(
    'cross-aggregate dependencies are durable and claimed in order',
    () async {
      await database.putEntityAndEnqueue(
        entityType: OfflineEntityType.property,
        entityId: 'property-1',
        entity: _entityJson(id: 'property-1', name: 'Garden Court'),
        mutationId: 'property-create',
        operation: OutboxOperation.create,
        createdAt: now,
      );
      await database.putEntityAndEnqueue(
        entityType: OfflineEntityType.unit,
        entityId: 'unit-1',
        entity: _entityJson(id: 'unit-1', name: 'A1'),
        mutationId: 'unit-create',
        operation: OutboxOperation.create,
        createdAt: now.add(const Duration(seconds: 1)),
        dependsOn: const <AggregateReference>[
          AggregateReference(
            type: OfflineEntityType.property,
            id: 'property-1',
          ),
        ],
      );

      final entries = await database.readOutbox();
      final unitMutation = entries.singleWhere(
        (item) => item.id == 'unit-create',
      );
      expect(unitMutation.dependencyIds, contains('property-create'));

      final first = await database.claimNextMutation(now: now);
      expect(first?.id, 'property-create');
      await database.acknowledgeMutation(
        mutationId: first!.id,
        syncedAt: now,
        serverRevision: 'revision-1',
      );

      final second = await database.claimNextMutation(
        now: now.add(const Duration(seconds: 1)),
      );
      expect(second?.id, 'unit-create');
    },
  );

  test('acknowledging an older edit leaves a newer edit pending', () async {
    await database.putEntityAndEnqueue(
      entityType: OfflineEntityType.property,
      entityId: 'property-1',
      entity: _entityJson(id: 'property-1', name: 'First'),
      mutationId: 'create',
      operation: OutboxOperation.create,
      createdAt: now,
    );
    await database.putEntityAndEnqueue(
      entityType: OfflineEntityType.property,
      entityId: 'property-1',
      entity: _entityJson(id: 'property-1', name: 'Second'),
      mutationId: 'update',
      operation: OutboxOperation.update,
      createdAt: now.add(const Duration(seconds: 1)),
    );

    await database.acknowledgeMutation(
      mutationId: 'create',
      syncedAt: now,
      serverRevision: 'revision-1',
    );
    final entity = await database.readEntity(
      OfflineEntityType.property,
      'property-1',
    );
    final sync = SyncMetadataMapper.fromJson(entity!['syncMetadata']);

    expect(sync.state, EntitySyncState.pending);
    expect(sync.serverRevision, 'revision-1');
    expect(await database.outboxCount(), 1);
  });

  test('remote merge marks a pending divergent edit as conflicted', () async {
    await database.mergeRemoteEntity(
      entityType: OfflineEntityType.property,
      entityId: 'property-1',
      entity: <String, Object?>{
        'id': 'property-1',
        'name': 'Server v1',
        'version': 1,
      },
    );
    await database.putEntityAndEnqueue(
      entityType: OfflineEntityType.property,
      entityId: 'property-1',
      entity: _entityJson(id: 'property-1', name: 'Local edit'),
      mutationId: 'property-update',
      operation: OutboxOperation.update,
      createdAt: now,
    );

    final result = await database.mergeRemoteEntity(
      entityType: OfflineEntityType.property,
      entityId: 'property-1',
      entity: <String, Object?>{
        'id': 'property-1',
        'name': 'Server v2',
        'version': 2,
      },
    );

    expect(result, RemoteMergeResult.conflicted);
    final local = await database.readEntity(
      OfflineEntityType.property,
      'property-1',
    );
    expect(local?['name'], 'Local edit');
    expect(
      SyncMetadataMapper.fromJson(local?['syncMetadata']).state,
      EntitySyncState.conflicted,
    );
  });

  test(
    'separate account database paths never expose each other records',
    () async {
      final first = await OfflineDatabase.open(
        factory: databaseFactoryMemory,
        path: 'account-one.db',
      );
      final second = await OfflineDatabase.open(
        factory: databaseFactoryMemory,
        path: 'account-two.db',
      );
      addTearDown(first.close);
      addTearDown(second.close);
      await first.putEntityAndEnqueue(
        entityType: OfflineEntityType.property,
        entityId: 'private-property',
        entity: _entityJson(id: 'private-property', name: 'Private'),
        mutationId: 'private-mutation',
        operation: OutboxOperation.create,
        createdAt: now,
      );

      expect(
        await second.readEntity(OfflineEntityType.property, 'private-property'),
        isNull,
      );
      expect(await second.outboxCount(), 0);
    },
  );
}

Map<String, Object?> _entityJson({required String id, required String name}) =>
    <String, Object?>{
      'id': id,
      'name': name,
      'syncMetadata': SyncMetadataMapper.toJson(const SyncMetadata.pending()),
    };
