enum EntitySyncState { synced, pending, conflicted, failed }

/// Sync information carried by every offline aggregate.
///
/// This type is deliberately persistence-agnostic and therefore remains usable
/// in pure Dart domain tests.
final class SyncMetadata {
  const SyncMetadata({
    required this.state,
    this.serverRevision,
    this.lastSyncedAt,
    this.lastError,
  });

  const SyncMetadata.synced({this.serverRevision, this.lastSyncedAt})
    : state = EntitySyncState.synced,
      lastError = null;

  const SyncMetadata.pending({
    this.serverRevision,
    this.lastSyncedAt,
    this.lastError,
  }) : state = EntitySyncState.pending;

  final EntitySyncState state;
  final String? serverRevision;
  final DateTime? lastSyncedAt;
  final String? lastError;

  bool get needsSync => state != EntitySyncState.synced;

  SyncMetadata markPending() => SyncMetadata.pending(
    serverRevision: serverRevision,
    lastSyncedAt: lastSyncedAt,
  );

  SyncMetadata markSynced({required DateTime at, String? revision}) =>
      SyncMetadata.synced(
        serverRevision: revision ?? serverRevision,
        lastSyncedAt: at.toUtc(),
      );

  SyncMetadata markFailed(String error) => SyncMetadata(
    state: EntitySyncState.failed,
    serverRevision: serverRevision,
    lastSyncedAt: lastSyncedAt,
    lastError: error,
  );

  SyncMetadata markConflicted(String error, {String? remoteRevision}) =>
      SyncMetadata(
        state: EntitySyncState.conflicted,
        serverRevision: remoteRevision ?? serverRevision,
        lastSyncedAt: lastSyncedAt,
        lastError: error,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncMetadata &&
      other.state == state &&
      other.serverRevision == serverRevision &&
      other.lastSyncedAt == lastSyncedAt &&
      other.lastError == lastError;

  @override
  int get hashCode =>
      Object.hash(state, serverRevision, lastSyncedAt, lastError);
}
