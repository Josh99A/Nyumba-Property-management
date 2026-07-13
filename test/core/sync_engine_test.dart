import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/remote_sync_gateway.dart';
import 'package:nyumba_property_management/core/offline/sync_engine.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late OfflineDatabase database;
  final now = DateTime.utc(2026, 7, 13, 8);

  setUp(() async {
    database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(
        'sync-${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await database.initialize();
  });

  tearDown(() => database.close());

  test('syncs dependencies in order and preserves idempotency keys', () async {
    await _enqueuePropertyAndUnit(database, now);
    final gateway = _RecordingGateway(now);
    final engine = SyncEngine(
      database: database,
      gateway: gateway,
      clock: FixedClock(now.add(const Duration(minutes: 1))),
    );

    final report = await engine.syncPending();

    expect(report.succeeded, 2);
    expect(
      gateway.mutations.map((item) => item.entityType),
      <OfflineEntityType>[OfflineEntityType.property, OfflineEntityType.unit],
    );
    expect(gateway.mutations.map((item) => item.idempotencyKey), <String>[
      'property-create',
      'unit-create',
    ]);
    expect(await database.outboxCount(), 0);
  });

  test('permanent failure blocks dependent mutations', () async {
    await _enqueuePropertyAndUnit(database, now);
    final engine = SyncEngine(
      database: database,
      gateway: _RejectingGateway(),
      clock: FixedClock(now.add(const Duration(minutes: 1))),
    );

    final report = await engine.syncPending();
    final outbox = await database.readOutbox();

    expect(report.permanentlyFailed, 1);
    expect(
      outbox.singleWhere((item) => item.id == 'property-create').state,
      OutboxState.permanentlyFailed,
    );
    expect(
      outbox.singleWhere((item) => item.id == 'unit-create').state,
      OutboxState.blocked,
    );
  });
}

Future<void> _enqueuePropertyAndUnit(
  OfflineDatabase database,
  DateTime now,
) async {
  await database.putEntityAndEnqueue(
    entityType: OfflineEntityType.property,
    entityId: 'property-1',
    entity: _entityJson('property-1'),
    mutationId: 'property-create',
    operation: OutboxOperation.create,
    createdAt: now,
  );
  await database.putEntityAndEnqueue(
    entityType: OfflineEntityType.unit,
    entityId: 'unit-1',
    entity: _entityJson('unit-1'),
    mutationId: 'unit-create',
    operation: OutboxOperation.create,
    createdAt: now.add(const Duration(seconds: 1)),
    dependsOn: const <AggregateReference>[
      AggregateReference(type: OfflineEntityType.property, id: 'property-1'),
    ],
  );
}

Map<String, Object?> _entityJson(String id) => <String, Object?>{
  'id': id,
  'syncMetadata': SyncMetadataMapper.toJson(const SyncMetadata.pending()),
};

final class _RecordingGateway implements RemoteSyncGateway {
  _RecordingGateway(this.now);

  final DateTime now;
  final List<RemoteMutation> mutations = <RemoteMutation>[];

  @override
  Future<RemoteWriteResult> push(RemoteMutation mutation) async {
    mutations.add(mutation);
    return RemoteWriteResult(
      committedAt: now,
      serverRevision: 'revision-${mutations.length}',
    );
  }
}

final class _RejectingGateway implements RemoteSyncGateway {
  @override
  Future<RemoteWriteResult> push(RemoteMutation mutation) async {
    throw const RemoteSyncException('permission denied', retryable: false);
  }
}
