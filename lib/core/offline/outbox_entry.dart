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
    this.errorReason,
    this.errorFields = const <String>[],
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

  /// The stable domain error code of the last failure (`VALIDATION_FAILED`,
  /// `PERMISSION_DENIED`, …), or a transport description.
  final String? lastError;

  /// The server's machine-readable explanation of that code, when it sent one.
  ///
  /// Persisted alongside the code because the code alone cannot be turned into
  /// a useful sentence: every listing rejection is `VALIDATION_FAILED`, and
  /// only the reason distinguishes "add a photo" from "that space is not
  /// vacant". Dropping it here is what left the UI saying "validation failed".
  final String? errorReason;

  /// Payload fields the server's schema rejected, when it named them.
  final List<String> errorFields;

  AggregateReference get aggregate =>
      AggregateReference(type: entityType, id: entityId);

  OutboxEntry copyWith({
    Map<String, Object?>? payload,
    OutboxState? state,
    int? attemptCount,
    List<String>? dependencyIds,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    DateTime? claimedAt,
    bool clearClaimedAt = false,
    String? lastError,
    bool clearLastError = false,
    String? errorReason,
    List<String>? errorFields,
  }) => OutboxEntry(
    id: id,
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    payload: payload ?? this.payload,
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
    // The explanation belongs to the code it arrived with. A new code always
    // replaces it, so a stale reason can never be read against a later,
    // different failure.
    errorReason: clearLastError || lastError != null
        ? errorReason
        : (errorReason ?? this.errorReason),
    errorFields: clearLastError || lastError != null
        ? (errorFields ?? const <String>[])
        : (errorFields ?? this.errorFields),
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
    'errorReason': errorReason,
    'errorFields': errorFields,
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
      errorReason: json['errorReason'] as String?,
      // Absent on entries written before failures carried an explanation, and
      // an empty list is the honest reading of "no fields were named".
      errorFields: switch (json['errorFields']) {
        final List<Object?> fields => <String>[
          for (final field in fields)
            if (field != null) field.toString(),
        ],
        _ => const <String>[],
      },
    );
  }
}
