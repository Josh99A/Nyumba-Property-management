enum EntitySyncState {
  synced,
  pending,
  conflicted,
  failed,

  /// Never leaves the device, and is not waiting to. Distinct from [pending],
  /// which promises a sync that will eventually happen: showing "pending" on a
  /// record nothing will ever send is the same false promise as showing
  /// "synced" on one the server never accepted.
  localOnly,
}

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

  /// Working state with no canonical collection behind it. See
  /// [EntitySyncState.localOnly].
  const SyncMetadata.local()
    : state = EntitySyncState.localOnly,
      serverRevision = null,
      lastSyncedAt = null,
      lastError = null;

  final EntitySyncState state;
  final String? serverRevision;
  final DateTime? lastSyncedAt;
  final String? lastError;

  /// Whether this record is still owed a trip to the server. A local-only
  /// record is not: nothing will ever carry it, so counting it as unsynced
  /// would leave every "all changes saved" indicator permanently unsettled.
  bool get needsSync =>
      state != EntitySyncState.synced && state != EntitySyncState.localOnly;

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
