import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/network_status.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/offline/reconnect_sync_trigger.dart';
import 'package:nyumba_property_management/core/offline/remote_sync_gateway.dart';
import 'package:nyumba_property_management/core/offline/sync_engine.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late OfflineDatabase database;
  final now = DateTime.utc(2026, 7, 20, 8);

  setUp(() async {
    database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(
        'reconnect-${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await database.initialize();
  });

  tearDown(() => database.close());

  test('offline run skips without claiming, reconnect flushes outbox', () async {
    await _enqueueProperty(database, now);
    final gateway = _RecordingGateway(now);
    final networkStatus = _ScriptedNetworkStatus();
    final engine = SyncEngine(
      database: database,
      gateway: gateway,
      clock: FixedClock(now.add(const Duration(minutes: 1))),
      networkStatus: networkStatus,
    );
    final trigger = ReconnectSyncTrigger(
      syncEngine: engine,
      networkStatus: networkStatus,
    );
    addTearDown(trigger.close);

    final offlineReport = await engine.syncPending();
    expect(offlineReport.skippedOffline, isTrue);
    expect(offlineReport.claimed, 0);
    expect(gateway.mutations, isEmpty);
    expect(await database.outboxCount(), 1);

    networkStatus.goOnline();
    await pumpEventQueue();

    expect(gateway.mutations.map((item) => item.idempotencyKey), <String>[
      'property-create',
    ]);
    expect(await database.outboxCount(), 0);
  });

  test('close stops reacting to later connectivity changes', () async {
    await _enqueueProperty(database, now);
    final gateway = _RecordingGateway(now);
    final networkStatus = _ScriptedNetworkStatus();
    final engine = SyncEngine(
      database: database,
      gateway: gateway,
      clock: FixedClock(now.add(const Duration(minutes: 1))),
      networkStatus: networkStatus,
    );
    final trigger = ReconnectSyncTrigger(
      syncEngine: engine,
      networkStatus: networkStatus,
    );

    await trigger.close();
    networkStatus.goOnline();
    await pumpEventQueue();

    expect(gateway.mutations, isEmpty);
    expect(await database.outboxCount(), 1);
  });
}

Future<void> _enqueueProperty(OfflineDatabase database, DateTime now) {
  return database.putEntityAndEnqueue(
    entityType: OfflineEntityType.property,
    entityId: 'property-1',
    entity: <String, Object?>{
      'id': 'property-1',
      'syncMetadata': SyncMetadataMapper.toJson(const SyncMetadata.pending()),
    },
    mutationId: 'property-create',
    operation: OutboxOperation.create,
    createdAt: now,
  );
}

final class _ScriptedNetworkStatus implements NetworkStatus {
  bool _online = false;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  void goOnline() {
    _online = true;
    _changes.add(true);
  }

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get changes => _changes.stream;
}

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
