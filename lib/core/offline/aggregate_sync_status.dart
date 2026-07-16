import '../domain/sync_metadata.dart';
import 'offline_entity.dart';
import 'outbox_entry.dart';

/// Honest, user-facing synchronization state of one aggregate, derived from
/// its durable outbox entries plus the entity's own [SyncMetadata].
///
/// Connectivity is only a hint: a local write is never presented as accepted
/// until the server acknowledgement clears its outbox entry.
enum AggregateSyncStatus {
  /// Every mutation has been acknowledged by the server.
  synced,

  /// A durable mutation is waiting for delivery.
  pending,

  /// A mutation is currently claimed by the sync runner.
  syncing,

  /// The server permanently rejected a mutation; explicit recovery is needed.
  rejected,

  /// A mutation cannot be sent until a failed dependency is resolved.
  blocked,

  /// A remote change could not be applied over an unsynced local edit.
  conflicted,

  /// Held on this device only, and not waiting to be sent. Distinct from
  /// [synced], which asserts the server has this record.
  localOnly,
}

/// Resolves the status for the aggregate identified by [entityType]/[entityId]
/// against the current [outbox] snapshot.
AggregateSyncStatus resolveAggregateSyncStatus({
  required OfflineEntityType entityType,
  required String entityId,
  required List<OutboxEntry> outbox,
  required SyncMetadata syncMetadata,
}) {
  final entries = outbox.where(
    (entry) => entry.entityType == entityType && entry.entityId == entityId,
  );
  var hasAny = false;
  var hasProcessing = false;
  var hasBlocked = false;
  var hasRejected = false;
  for (final entry in entries) {
    hasAny = true;
    switch (entry.state) {
      case OutboxState.processing:
        hasProcessing = true;
      case OutboxState.blocked:
        hasBlocked = true;
      case OutboxState.permanentlyFailed:
        hasRejected = true;
      case OutboxState.pending:
      case OutboxState.retryScheduled:
        break;
    }
  }
  if (hasRejected) return AggregateSyncStatus.rejected;
  if (hasBlocked) return AggregateSyncStatus.blocked;
  if (hasProcessing) return AggregateSyncStatus.syncing;
  if (hasAny) return AggregateSyncStatus.pending;
  if (syncMetadata.state == EntitySyncState.failed) {
    return AggregateSyncStatus.rejected;
  }
  if (syncMetadata.state == EntitySyncState.conflicted) {
    return AggregateSyncStatus.conflicted;
  }
  // Checked before the synced fallback: a local-only record has no outbox entry
  // and no failure, so it would otherwise land on `synced` and claim the server
  // holds a record that was never sent anywhere.
  if (syncMetadata.state == EntitySyncState.localOnly) {
    return AggregateSyncStatus.localOnly;
  }
  return AggregateSyncStatus.synced;
}
