/// Mutations. Every one of these requires a live server request.
///
/// There is no queue behind this file, and that absence is the point. A command
/// either reaches the server and comes back with an answer, or it does not
/// happen. Nothing is stored for later delivery, nothing is retried behind the
/// user's back, and no local write is ever treated as the outcome.
library;

/// The aggregate a command acts on.
///
/// This is the old `OfflineEntityType` with the local store names removed. It
/// survives because the callable command router keys off aggregate identity,
/// not because anything is mirrored locally.
enum CommandAggregate {
  userProfile('user_profile'),
  property('property'),
  unit('unit'),
  tenancy('tenancy'),
  listing('listing'),
  publicListing('public_listing'),
  application('application'),
  invoice('invoice'),
  payment('payment'),
  maintenanceRequest('maintenance_request'),
  document('document'),
  leaseDocument('lease_document'),
  notice('notice'),
  notification('notification'),
  managedUser('managed_user'),
  staffInvite('staff_invite'),
  subscriptionPlan('subscription_plan'),
  planCatalog('plan_catalog'),
  adminAction('admin_action'),
  landlordReview('landlord_review'),
  publicReview('public_review'),
  platformFeedback('platform_feedback'),
  supportTicket('support_ticket');

  const CommandAggregate(this.cacheNamespace);

  /// Prefix for this aggregate's cache keys, so a confirmed mutation can
  /// invalidate the whole family in one call.
  final String cacheNamespace;
}

enum CommandOperation { create, update, publish, apply, delete }

/// One mutation, built at the moment the user asks for it and sent immediately.
///
/// [commandId] is the server's idempotency key. It is generated once per user
/// intent and **reused verbatim** across a reconciliation attempt — that reuse
/// is what lets the server recognise a command it already applied and answer
/// with the original outcome instead of doing the work twice.
final class CloudCommand {
  CloudCommand({
    required this.commandId,
    required this.type,
    required this.aggregate,
    required this.aggregateId,
    required this.operation,
    required Map<String, Object?> payload,
    required this.issuedAt,
    this.expectedVersion,
  }) : payload = Map.unmodifiable(payload);

  final String commandId;

  /// The router's command name, e.g. `property.create`.
  ///
  /// Named by the repository that issues it rather than derived from
  /// `(aggregate, operation)` by a central switch. The old central mapping had
  /// to invent pseudo-operations to express commands that did not fit five
  /// verbs — reviews needed six, support three — and smuggled the real intent
  /// through a `pendingAction` field on the payload. Naming the command where
  /// it is built removes that indirection entirely.
  final String type;

  final CommandAggregate aggregate;
  final String aggregateId;
  final CommandOperation operation;
  final Map<String, Object?> payload;
  final DateTime issuedAt;

  /// The server version this edit was composed against, for optimistic
  /// concurrency. Null for creates.
  final int? expectedVersion;

  CloudCommand withPayload(Map<String, Object?> payload) => CloudCommand(
    commandId: commandId,
    type: type,
    aggregate: aggregate,
    aggregateId: aggregateId,
    operation: operation,
    payload: payload,
    issuedAt: issuedAt,
    expectedVersion: expectedVersion,
  );
}

/// A server-confirmed mutation. Constructing one of these means the server
/// said yes — nothing else does.
final class CommandOutcome {
  const CommandOutcome({
    required this.committedAt,
    this.serverVersion,
    this.wasAlreadyApplied = false,
  });

  /// The server's commit time. Present only on success.
  final DateTime committedAt;

  final String? serverVersion;

  /// True when the server recognised [CloudCommand.commandId] from an earlier
  /// request. Still a success, and the honest answer to "did my first attempt
  /// go through?" — it did.
  final bool wasAlreadyApplied;
}

/// What a repository returns from a confirmed mutation.
///
/// Deliberately not the mutated aggregate. The server owns the record, and the
/// copy that lands on screen arrives on the live listener a moment later —
/// returning a client-built object here would be exactly the "local write
/// presented as server state" this architecture exists to prevent. What a
/// caller legitimately needs is the id it can navigate to and proof the server
/// said yes.
final class MutationResult {
  const MutationResult({required this.aggregateId, required this.outcome});

  final String aggregateId;
  final CommandOutcome outcome;

  /// True when this confirmation came from server idempotency recognising an
  /// earlier attempt rather than fresh work. The action still succeeded.
  bool get wasAlreadyApplied => outcome.wasAlreadyApplied;
}

/// How a command failed. The four cases need four different sentences to a
/// user, and conflating any two of them misinforms them about whether their
/// work happened.
enum CommandFailureKind {
  /// The request never left, or never arrived. It certainly did not apply.
  /// Safe to offer an immediate retry.
  connection,

  /// The server refused this actor.
  permissionDenied,

  /// The server received it, understood it, and said no. Retrying unchanged
  /// will fail identically.
  rejected,

  /// Submitted, but the connection dropped before the answer arrived. **It may
  /// have applied.** Never present this as failure, and never let a plain retry
  /// through — reconcile with the server first, reusing the same command id.
  uncertain,
}

final class CommandException implements Exception {
  const CommandException({
    required this.kind,
    required this.code,
    this.details,
    this.cause,
  });

  const CommandException.connection({
    String code = 'unavailable',
    Object? cause,
  }) : this(kind: CommandFailureKind.connection, code: code, cause: cause);

  const CommandException.uncertain({required String code, Object? cause})
    : this(kind: CommandFailureKind.uncertain, code: code, cause: cause);

  final CommandFailureKind kind;

  /// The stable domain code (`VALIDATION_FAILED`, `PERMISSION_DENIED`, …) or a
  /// transport code. Branch on this, never on a plugin's status string.
  final String code;

  /// Safe remediation data the server attached. Never another actor's record.
  final Map<String, Object?>? details;

  final Object? cause;

  /// The server's machine-readable explanation, when it sent one. The
  /// difference between "validation failed" and "this space is not vacant".
  String? get reason => details?['reason']?.toString();

  /// Payload fields the server's schema rejected, when it named them.
  List<String> get rejectedFields => switch (details?['fields']) {
    final List<Object?> fields => [
      for (final field in fields)
        if (field != null) field.toString(),
    ],
    _ => const <String>[],
  };

  /// Whether the user may simply be offered "try again". False for [uncertain],
  /// which must be reconciled, and for [rejected]/[permissionDenied], which
  /// will not change on their own.
  bool get isPlainRetryable => kind == CommandFailureKind.connection;

  @override
  String toString() => 'CommandException(${kind.name}, $code)';
}

/// Sends one command and waits for the server's answer. Implemented by
/// infrastructure; feature repositories depend on this interface, never on
/// Firebase types.
abstract interface class CloudCommandGateway {
  Future<CommandOutcome> send(CloudCommand command);
}
