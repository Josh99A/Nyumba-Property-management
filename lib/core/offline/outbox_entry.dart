import 'offline_entity.dart';

enum OutboxOperation { create, update, publish, apply, delete }

enum OutboxState {
  pending,
  processing,
  retryScheduled,
  permanentlyFailed,
  blocked,
}

/// A durable, idempotent description of a remote mutation.
final class OutboxEntry {
  OutboxEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required Map<String, Object?> payload,
    required this.createdAt,
    this.state = OutboxState.pending,
    this.attemptCount = 0,
    this.dependencyIds = const <String>[],
    String? idempotencyKey,
    this.nextAttemptAt,
    this.claimedAt,
    this.lastError,
  }) : payload = Map.unmodifiable(payload),
       idempotencyKey = idempotencyKey ?? id;

  final String id;
  final OfflineEntityType entityType;
  final String entityId;
  final OutboxOperation operation;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final OutboxState state;
  final int attemptCount;
  final List<String> dependencyIds;
  final String idempotencyKey;
  final DateTime? nextAttemptAt;
  final DateTime? claimedAt;
  final String? lastError;

  AggregateReference get aggregate =>
      AggregateReference(type: entityType, id: entityId);

  OutboxEntry copyWith({
    OutboxState? state,
    int? attemptCount,
    List<String>? dependencyIds,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    DateTime? claimedAt,
    bool clearClaimedAt = false,
    String? lastError,
    bool clearLastError = false,
  }) => OutboxEntry(
    id: id,
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    payload: payload,
    createdAt: createdAt,
    state: state ?? this.state,
    attemptCount: attemptCount ?? this.attemptCount,
    dependencyIds: dependencyIds ?? this.dependencyIds,
    idempotencyKey: idempotencyKey,
    nextAttemptAt: clearNextAttemptAt
        ? null
        : (nextAttemptAt ?? this.nextAttemptAt),
    claimedAt: clearClaimedAt ? null : (claimedAt ?? this.claimedAt),
    lastError: clearLastError ? null : (lastError ?? this.lastError),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'entityType': entityType.name,
    'entityId': entityId,
    'operation': operation.name,
    'payload': payload,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'state': state.name,
    'attemptCount': attemptCount,
    'dependencyIds': dependencyIds,
    'idempotencyKey': idempotencyKey,
    'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
    'claimedAt': claimedAt?.toUtc().toIso8601String(),
    'lastError': lastError,
  };

  factory OutboxEntry.fromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, String field) {
      final raw = json[field];
      if (raw is! String) throw FormatException('$field must be a string.');
      return values.firstWhere(
        (value) => value.name == raw,
        orElse: () => throw FormatException('Unknown $field "$raw".'),
      );
    }

    DateTime? optionalDate(String field) {
      final raw = json[field];
      if (raw == null) return null;
      if (raw is! String) throw FormatException('$field must be a string.');
      return DateTime.parse(raw).toUtc();
    }

    final payload = json['payload'];
    if (payload is! Map) throw const FormatException('payload must be a map.');
    final dependencies = json['dependencyIds'];
    if (dependencies is! List ||
        dependencies.any((value) => value is! String)) {
      throw const FormatException('dependencyIds must be a list of strings.');
    }

    return OutboxEntry(
      id: json['id'] as String,
      entityType: enumValue(OfflineEntityType.values, 'entityType'),
      entityId: json['entityId'] as String,
      operation: enumValue(OutboxOperation.values, 'operation'),
      payload: Map<String, Object?>.from(payload),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      state: enumValue(OutboxState.values, 'state'),
      attemptCount: json['attemptCount'] as int,
      dependencyIds: List<String>.from(dependencies),
      idempotencyKey: json['idempotencyKey'] as String,
      nextAttemptAt: optionalDate('nextAttemptAt'),
      claimedAt: optionalDate('claimedAt'),
      lastError: json['lastError'] as String?,
    );
  }
}
