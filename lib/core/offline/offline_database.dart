import 'package:sembast/sembast.dart';

import '../domain/domain_exception.dart';
import '../domain/sync_metadata.dart';
import 'offline_entity.dart';
import 'outbox_entry.dart';
import 'sync_metadata_mapper.dart';

/// Sembast-backed local source of truth shared by feature repositories.
///
/// Entity writes and their outbox records are committed in the same database
/// transaction. A process crash can therefore never leave an optimistic local
/// write without a durable remote-sync intent.
final class OfflineDatabase {
  OfflineDatabase(this.database);

  static const int schemaVersion = 1;
  static const String _outboxStoreName = '_outbox';
  static const String _metadataStoreName = '_metadata';

  final Database database;

  static final StoreRef<String, Map<String, Object?>> _outboxStore =
      stringMapStoreFactory.store(_outboxStoreName);
  static final StoreRef<String, Map<String, Object?>> _metadataStore =
      stringMapStoreFactory.store(_metadataStoreName);

  static Future<OfflineDatabase> open({
    required DatabaseFactory factory,
    required String path,
    SembastCodec? codec,
  }) async {
    final database = await factory.openDatabase(path, codec: codec);
    final result = OfflineDatabase(database);
    await result.initialize();
    return result;
  }

  Future<void> initialize() async {
    await database.transaction((transaction) async {
      final current = await _metadataStore.record('schema').get(transaction);
      final storedVersion = current?['version'];
      if (storedVersion is int && storedVersion > schemaVersion) {
        throw StateError(
          'Local database schema $storedVersion is newer than supported '
          'schema $schemaVersion.',
        );
      }
      await _metadataStore.record('schema').put(transaction, <String, Object?>{
        'version': schemaVersion,
      });
    });
  }

  StoreRef<String, Map<String, Object?>> _entityStore(OfflineEntityType type) =>
      stringMapStoreFactory.store(type.storeName);

  Future<Map<String, Object?>?> readEntity(
    OfflineEntityType type,
    String id,
  ) async {
    final value = await _entityStore(type).record(id).get(database);
    return value == null ? null : Map<String, Object?>.from(value);
  }

  Future<List<Map<String, Object?>>> readEntities(
    OfflineEntityType type,
  ) async {
    final snapshots = await _entityStore(type).find(database);
    return snapshots
        .map((snapshot) => Map<String, Object?>.from(snapshot.value))
        .toList(growable: false);
  }

  Stream<Map<String, Object?>?> watchEntity(
    OfflineEntityType type,
    String id,
  ) => _entityStore(type)
      .record(id)
      .onSnapshot(database)
      .map(
        (snapshot) =>
            snapshot == null ? null : Map<String, Object?>.from(snapshot.value),
      );

  Stream<List<Map<String, Object?>>> watchEntities(OfflineEntityType type) =>
      _entityStore(type)
          .query()
          .onSnapshots(database)
          .map(
            (snapshots) => snapshots
                .map((snapshot) => Map<String, Object?>.from(snapshot.value))
                .toList(growable: false),
          );

  /// Atomically persists an entity and enqueues the corresponding mutation.
  ///
  /// Outstanding mutations for this aggregate are automatic dependencies,
  /// preserving create-before-update ordering. [dependsOn] adds cross-aggregate
  /// ordering such as property -> unit -> listing -> application.
  Future<OutboxEntry> putEntityAndEnqueue({
    required OfflineEntityType entityType,
    required String entityId,
    required Map<String, Object?> entity,
    required String mutationId,
    required OutboxOperation operation,
    required DateTime createdAt,
    List<AggregateReference> dependsOn = const <AggregateReference>[],
    bool createOnly = false,
  }) => database.transaction((transaction) async {
    final entityRecord = _entityStore(entityType).record(entityId);
    if (createOnly && await entityRecord.exists(transaction)) {
      throw EntityAlreadyExistsException(entityType.name, entityId);
    }
    if (await _outboxStore.record(mutationId).exists(transaction)) {
      throw EntityAlreadyExistsException('outbox mutation', mutationId);
    }

    final existingSnapshots = await _outboxStore.find(transaction);
    final existingEntries = existingSnapshots
        .map((snapshot) => OutboxEntry.fromJson(snapshot.value))
        .toList(growable: false);
    final dependencyAggregates = dependsOn.toSet();
    final dependencyEntries = existingEntries.where(
      (entry) =>
          (entry.entityType == entityType && entry.entityId == entityId) ||
          dependencyAggregates.contains(entry.aggregate),
    );
    final dependencyIds =
        dependencyEntries
            .map((entry) => entry.id)
            .toSet()
            .toList(growable: false)
          ..sort();

    final outboxEntry = OutboxEntry(
      id: mutationId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: entity,
      createdAt: createdAt.toUtc(),
      dependencyIds: dependencyIds,
    );

    await entityRecord.put(transaction, Map<String, Object?>.from(entity));
    await _outboxStore
        .record(mutationId)
        .put(transaction, outboxEntry.toJson());
    return outboxEntry;
  });

  /// Applies server/bootstrap data only when there is no unsynced local edit.
  /// This keeps the local database authoritative while preventing remote pulls
  /// from overwriting optimistic user changes.
  Future<bool> putRemoteEntityIfUnmodified({
    required OfflineEntityType entityType,
    required String entityId,
    required Map<String, Object?> entity,
  }) => database.transaction((transaction) async {
    final outbox = await _outboxStore.find(transaction);
    final hasLocalMutation = outbox.any((snapshot) {
      final entry = OutboxEntry.fromJson(snapshot.value);
      return entry.entityType == entityType && entry.entityId == entityId;
    });
    if (hasLocalMutation) return false;
    await _entityStore(
      entityType,
    ).record(entityId).put(transaction, Map<String, Object?>.from(entity));
    return true;
  });

  /// Merges a listener record without ever overwriting an optimistic edit.
  /// Listener replays at or below the locally known server version are ignored.
  Future<RemoteMergeResult> mergeRemoteEntity({
    required OfflineEntityType entityType,
    required String entityId,
    required Map<String, Object?> entity,
  }) => database.transaction((transaction) async {
    final outbox = await _outboxStore.find(transaction);
    final hasLocalMutation = outbox.any((snapshot) {
      final entry = OutboxEntry.fromJson(snapshot.value);
      return entry.entityType == entityType && entry.entityId == entityId;
    });
    final entityRecord = _entityStore(entityType).record(entityId);
    final local = await entityRecord.get(transaction);
    final remoteVersion = _remoteVersion(entity);
    if (hasLocalMutation) {
      if (local != null) {
        final sync = SyncMetadataMapper.fromJson(local['syncMetadata']);
        final localVersion = int.tryParse(sync.serverRevision ?? '');
        if (remoteVersion != null && remoteVersion != localVersion) {
          await entityRecord.put(transaction, <String, Object?>{
            ...local,
            'syncMetadata': SyncMetadataMapper.toJson(
              sync.markConflicted(
                'Remote version changed while local edits are pending.',
                remoteRevision: remoteVersion.toString(),
              ),
            ),
          });
          return RemoteMergeResult.conflicted;
        }
      }
      return RemoteMergeResult.ignored;
    }
    if (local != null && remoteVersion != null) {
      final sync = SyncMetadataMapper.fromJson(local['syncMetadata']);
      final localVersion = int.tryParse(sync.serverRevision ?? '');
      if (localVersion != null && remoteVersion <= localVersion) {
        return RemoteMergeResult.ignored;
      }
    }
    final merged = Map<String, Object?>.from(entity);
    merged['syncMetadata'] = SyncMetadataMapper.toJson(
      SyncMetadata.synced(
        serverRevision: remoteVersion?.toString(),
        lastSyncedAt: DateTime.now().toUtc(),
      ),
    );
    await _entityStore(entityType).record(entityId).put(transaction, merged);
    return RemoteMergeResult.applied;
  });

  static int? _remoteVersion(Map<String, Object?> entity) {
    final value = entity['version'] ?? entity['projectionVersion'];
    return value is int ? value : int.tryParse(value?.toString() ?? '');
  }

  Future<List<OutboxEntry>> readOutbox() async {
    final snapshots = await _outboxStore.find(database);
    final entries = snapshots
        .map((snapshot) => OutboxEntry.fromJson(snapshot.value))
        .toList(growable: false);
    entries.sort(_compareEntries);
    return entries;
  }

  Stream<List<OutboxEntry>> watchOutbox() =>
      _outboxStore.query().onSnapshots(database).map((snapshots) {
        final entries = snapshots
            .map((snapshot) => OutboxEntry.fromJson(snapshot.value))
            .toList(growable: false);
        entries.sort(_compareEntries);
        return entries;
      });

  Future<int> outboxCount() => _outboxStore.count(database);

  /// Claims one dependency-ready mutation using a durable processing lease.
  Future<OutboxEntry?> claimNextMutation({
    required DateTime now,
    Duration processingLease = const Duration(minutes: 2),
  }) => database.transaction((transaction) async {
    final snapshots = await _outboxStore.find(transaction);
    final entries = <String, OutboxEntry>{
      for (final snapshot in snapshots)
        snapshot.key: OutboxEntry.fromJson(snapshot.value),
    };

    final staleBefore = now.toUtc().subtract(processingLease);
    for (final mapEntry in entries.entries.toList(growable: false)) {
      final entry = mapEntry.value;
      if (entry.state == OutboxState.processing &&
          (entry.claimedAt == null || entry.claimedAt!.isBefore(staleBefore))) {
        final recovered = entry.copyWith(
          state: OutboxState.retryScheduled,
          nextAttemptAt: now.toUtc(),
          clearClaimedAt: true,
          lastError: 'Recovered an expired processing lease.',
        );
        entries[entry.id] = recovered;
        await _outboxStore
            .record(entry.id)
            .put(transaction, recovered.toJson());
      }
    }

    final ordered = entries.values.toList(growable: false)
      ..sort(_compareEntries);
    for (var entry in ordered) {
      if (entry.state == OutboxState.blocked) {
        final remainingDependencies = entry.dependencyIds
            .where(entries.containsKey)
            .toList(growable: false);
        if (remainingDependencies.isEmpty) {
          entry = entry.copyWith(
            state: OutboxState.pending,
            clearLastError: true,
          );
          entries[entry.id] = entry;
          await _outboxStore.record(entry.id).put(transaction, entry.toJson());
        }
      }

      if (entry.state != OutboxState.pending &&
          entry.state != OutboxState.retryScheduled) {
        continue;
      }
      if (entry.nextAttemptAt != null &&
          entry.nextAttemptAt!.isAfter(now.toUtc())) {
        continue;
      }

      final remainingDependencies = entry.dependencyIds
          .map((dependencyId) => entries[dependencyId])
          .whereType<OutboxEntry>()
          .toList(growable: false);
      final failedDependency = remainingDependencies.any(
        (dependency) =>
            dependency.state == OutboxState.permanentlyFailed ||
            dependency.state == OutboxState.blocked,
      );
      if (failedDependency) {
        final blocked = entry.copyWith(
          state: OutboxState.blocked,
          lastError: 'Blocked by a failed dependency.',
          clearClaimedAt: true,
        );
        entries[entry.id] = blocked;
        await _outboxStore.record(entry.id).put(transaction, blocked.toJson());
        continue;
      }
      if (remainingDependencies.isNotEmpty) continue;

      final payload = Map<String, Object?>.from(entry.payload);
      if (!payload.containsKey('_expectedVersion')) {
        if (entry.operation == OutboxOperation.create ||
            entry.operation == OutboxOperation.apply) {
          payload['_expectedVersion'] = 0;
        } else {
          final entity = await _entityStore(
            entry.entityType,
          ).record(entry.entityId).get(transaction);
          if (entity != null) {
            final sync = SyncMetadataMapper.fromJson(entity['syncMetadata']);
            final revision = int.tryParse(sync.serverRevision ?? '');
            if (revision != null) payload['_expectedVersion'] = revision;
          }
        }
      }
      final claimed = entry.copyWith(
        payload: payload,
        state: OutboxState.processing,
        claimedAt: now.toUtc(),
        clearNextAttemptAt: true,
      );
      await _outboxStore.record(entry.id).put(transaction, claimed.toJson());
      return claimed;
    }
    return null;
  });

  /// Atomically removes a delivered mutation and updates the aggregate's sync
  /// metadata. If a newer edit exists, the entity correctly remains pending.
  Future<void> acknowledgeMutation({
    required String mutationId,
    required DateTime syncedAt,
    String? serverRevision,
  }) => database.transaction((transaction) async {
    final record = _outboxStore.record(mutationId);
    final raw = await record.get(transaction);
    if (raw == null) return;
    final delivered = OutboxEntry.fromJson(raw);
    await record.delete(transaction);

    final remainingSnapshots = await _outboxStore.find(transaction);
    final hasNewerMutation = remainingSnapshots.any((snapshot) {
      final candidate = OutboxEntry.fromJson(snapshot.value);
      return candidate.entityType == delivered.entityType &&
          candidate.entityId == delivered.entityId;
    });
    final entityRecord = _entityStore(
      delivered.entityType,
    ).record(delivered.entityId);
    final entity = await entityRecord.get(transaction);
    if (entity == null) return;
    final currentSync = SyncMetadataMapper.fromJson(entity['syncMetadata']);
    final nextSync = hasNewerMutation
        ? SyncMetadata.pending(
            serverRevision: serverRevision ?? currentSync.serverRevision,
            lastSyncedAt: syncedAt.toUtc(),
          )
        : currentSync.markSynced(at: syncedAt, revision: serverRevision);
    await entityRecord.put(transaction, <String, Object?>{
      ...entity,
      'syncMetadata': SyncMetadataMapper.toJson(nextSync),
    });
  });

  Future<OutboxEntry?> failMutation({
    required String mutationId,
    required String error,
    required bool permanent,
    required DateTime failedAt,
    DateTime? retryAt,
  }) => database.transaction((transaction) async {
    final record = _outboxStore.record(mutationId);
    final raw = await record.get(transaction);
    if (raw == null) return null;
    final current = OutboxEntry.fromJson(raw);
    final failed = current.copyWith(
      state: permanent
          ? OutboxState.permanentlyFailed
          : OutboxState.retryScheduled,
      attemptCount: current.attemptCount + 1,
      nextAttemptAt: permanent ? null : (retryAt ?? failedAt.toUtc()),
      clearNextAttemptAt: permanent,
      clearClaimedAt: true,
      lastError: error,
    );
    await record.put(transaction, failed.toJson());

    final entityRecord = _entityStore(
      current.entityType,
    ).record(current.entityId);
    final entity = await entityRecord.get(transaction);
    if (entity != null) {
      final currentSync = SyncMetadataMapper.fromJson(entity['syncMetadata']);
      final nextSync = permanent
          ? currentSync.markFailed(error)
          : SyncMetadata.pending(
              serverRevision: currentSync.serverRevision,
              lastSyncedAt: currentSync.lastSyncedAt,
              lastError: error,
            );
      await entityRecord.put(transaction, <String, Object?>{
        ...entity,
        'syncMetadata': SyncMetadataMapper.toJson(nextSync),
      });
    }
    return failed;
  });

  Future<bool> retryMutation(String mutationId) =>
      database.transaction((transaction) async {
        final record = _outboxStore.record(mutationId);
        final raw = await record.get(transaction);
        if (raw == null) return false;
        final current = OutboxEntry.fromJson(raw);
        final retried = current.copyWith(
          state: OutboxState.pending,
          attemptCount: 0,
          clearNextAttemptAt: true,
          clearClaimedAt: true,
          clearLastError: true,
        );
        await record.put(transaction, retried.toJson());

        final entityRecord = _entityStore(
          current.entityType,
        ).record(current.entityId);
        final entity = await entityRecord.get(transaction);
        if (entity != null) {
          final sync = SyncMetadataMapper.fromJson(entity['syncMetadata']);
          await entityRecord.put(transaction, <String, Object?>{
            ...entity,
            'syncMetadata': SyncMetadataMapper.toJson(sync.markPending()),
          });
        }
        return true;
      });

  Future<void> close() => database.close();

  static int _compareEntries(OutboxEntry left, OutboxEntry right) {
    final priority = left.entityType.syncPriority.compareTo(
      right.entityType.syncPriority,
    );
    if (priority != 0) return priority;
    final created = left.createdAt.compareTo(right.createdAt);
    if (created != 0) return created;
    return left.id.compareTo(right.id);
  }
}

enum RemoteMergeResult { applied, ignored, conflicted }
