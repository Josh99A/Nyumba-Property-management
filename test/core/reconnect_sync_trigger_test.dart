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

  test('close waits for an in-flight sync pass before completing', () async {
    await _enqueueProperty(database, now);
    final gateway = _GatedGateway(now);
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

    networkStatus.goOnline();
    await gateway.started.future;

    var closed = false;
    final closing = trigger.close().then((_) => closed = true);
    await pumpEventQueue();
    expect(closed, isFalse, reason: 'close must wait for the sync pass');

    gateway.release();
    await closing;
    expect(await database.outboxCount(), 0);
  });

  test('close completes even when the in-flight sync pass fails', () async {
    await _enqueueProperty(database, now);
    final gateway = _GatedGateway(now, fail: true);
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

    networkStatus.goOnline();
    await gateway.started.future;

    final closing = trigger.close();
    gateway.release();
    await closing;

    final outbox = await database.readOutbox();
    expect(
      outbox.single.state,
      OutboxState.permanentlyFailed,
      reason: 'the failure is recorded, not rethrown out of close',
    );
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

/// Holds every push at [started] until [release], so tests can observe a
/// shutdown that races an in-flight sync pass.
final class _GatedGateway implements RemoteSyncGateway {
  _GatedGateway(this.now, {this.fail = false});

  final DateTime now;
  final bool fail;
  final Completer<void> started = Completer<void>();
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<RemoteWriteResult> push(RemoteMutation mutation) async {
    if (!started.isCompleted) started.complete();
    await _gate.future;
    if (fail) {
      throw const RemoteSyncException('server rejected', retryable: false);
    }
    return RemoteWriteResult(committedAt: now, serverRevision: 'revision-1');
  }
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
