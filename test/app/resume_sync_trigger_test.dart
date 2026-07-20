import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/resume_sync_trigger.dart';
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
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineDatabase database;
  final now = DateTime.utc(2026, 7, 20, 9);

  setUp(() async {
    database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(
        'resume-${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await database.initialize();
  });

  tearDown(() => database.close());

  test('returning to the foreground flushes the outbox', () async {
    await _enqueueProperty(database, now);
    final gateway = _RecordingGateway(now);
    final trigger = ResumeSyncTrigger(
      syncEngine: SyncEngine(
        database: database,
        gateway: gateway,
        clock: FixedClock(now.add(const Duration(minutes: 1))),
      ),
    );
    addTearDown(trigger.dispose);

    _cycleToBackgroundAndBack(binding);
    await pumpEventQueue();

    expect(gateway.mutations.map((item) => item.idempotencyKey), <String>[
      'property-create',
    ]);
    expect(await database.outboxCount(), 0);
  });

  test('dispose stops reacting to later resumes', () async {
    await _enqueueProperty(database, now);
    final gateway = _RecordingGateway(now);
    final trigger = ResumeSyncTrigger(
      syncEngine: SyncEngine(
        database: database,
        gateway: gateway,
        clock: FixedClock(now.add(const Duration(minutes: 1))),
      ),
    );

    trigger.dispose();
    _cycleToBackgroundAndBack(binding);
    await pumpEventQueue();

    expect(gateway.mutations, isEmpty);
    expect(await database.outboxCount(), 1);
  });
}

/// Dispatches each intermediate state explicitly: unlike the engine channel,
/// [TestWidgetsFlutterBinding.handleAppLifecycleStateChanged] does not
/// synthesize the transitions in between, and [AppLifecycleListener] only
/// fires `onResume` on the inactive-to-resumed step.
void _cycleToBackgroundAndBack(TestWidgetsFlutterBinding binding) {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    binding.handleAppLifecycleStateChanged(state);
  }
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
