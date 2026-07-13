import 'offline_entity.dart';
import 'outbox_entry.dart';

/// Transport-neutral mutation sent by the sync engine.
final class RemoteMutation {
  RemoteMutation({
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required Map<String, Object?> payload,
    required this.idempotencyKey,
    required this.clientCreatedAt,
  }) : payload = Map.unmodifiable(payload);

  factory RemoteMutation.fromOutbox(OutboxEntry entry) => RemoteMutation(
    mutationId: entry.id,
    entityType: entry.entityType,
    entityId: entry.entityId,
    operation: entry.operation,
    payload: entry.payload,
    idempotencyKey: entry.idempotencyKey,
    clientCreatedAt: entry.createdAt,
  );

  final String mutationId;
  final OfflineEntityType entityType;
  final String entityId;
  final OutboxOperation operation;
  final Map<String, Object?> payload;
  final String idempotencyKey;
  final DateTime clientCreatedAt;
}

final class RemoteWriteResult {
  const RemoteWriteResult({
    required this.committedAt,
    this.serverRevision,
    this.wasAlreadyApplied = false,
  });

  final DateTime committedAt;
  final String? serverRevision;

  /// True when the backend recognized the idempotency key from an earlier
  /// request. This is still a successful delivery.
  final bool wasAlreadyApplied;
}

/// Implemented by Firebase/backend infrastructure, not feature repositories.
/// The backend must persist [RemoteMutation.idempotencyKey] and return success
/// for duplicates, making retries safe after ambiguous network failures.
abstract interface class RemoteSyncGateway {
  Future<RemoteWriteResult> push(RemoteMutation mutation);
}

final class RemoteSyncException implements Exception {
  const RemoteSyncException(this.message, {this.retryable = true, this.cause});

  final String message;
  final bool retryable;
  final Object? cause;

  @override
  String toString() => 'RemoteSyncException: $message';
}
