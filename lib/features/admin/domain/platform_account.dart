/// Server-truth view of one platform account, joined from the admin-readable
/// `users`, `landlordAccounts`, and `subscriptions` documents.
///
/// Unlike [ManagedUser], which is a local-only working directory keyed by
/// client UUIDs, a [PlatformAccount] is keyed by the Firebase UID and can
/// therefore address the real account in audited admin commands
/// (`landlord.approve` / `landlord.suspend` / `landlord.reinstate` /
/// `subscription.confirmPayment`).
library;

enum PlatformAccountStatus {
  active('Active'),
  pendingApproval('Pending approval'),

  /// Demo-only: a locally invited directory entry that has no server account.
  invited('Invited'),
  suspended('Suspended');

  const PlatformAccountStatus(this.label);

  final String label;
}

enum PlatformSubscriptionStatus {
  active('Active'),
  pendingPayment('Awaiting payment'),
  trialing('Trialing'),
  pastDue('Past due'),
  canceled('Canceled'),
  expired('Expired'),
  none('None');

  const PlatformSubscriptionStatus(this.label);

  final String label;

  static PlatformSubscriptionStatus fromServer(String? raw) => switch (raw) {
    'active' => active,
    'pending_payment' => pendingPayment,
    'trialing' => trialing,
    'past_due' => pastDue,
    'canceled' => canceled,
    'expired' => expired,
    _ => none,
  };
}

final class PlatformAccount {
  const PlatformAccount({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.roleLabel,
    required this.status,
    required this.joinedLabel,
    this.location,
    this.lastActiveLabel,
    this.landlordAccountVersion,
    this.businessName,
    this.subscriptionTier,
    this.subscriptionStatus = PlatformSubscriptionStatus.none,
    this.subscriptionVersion,
    this.isLocalOnly = false,
  });

  /// Firebase UID for server-backed accounts; a client UUID for demo entries.
  final String uid;
  final String displayName;

  /// May be empty: a server account is not guaranteed to carry an email.
  final String email;

  /// Presentation label, e.g. `Landlord`. Administrator privileges live in
  /// Firebase Auth custom claims and are not mirrored to the `users`
  /// collection, so admins appear here under their base role.
  final String roleLabel;
  final PlatformAccountStatus status;
  final String joinedLabel;

  /// Only demo entries record these; the server tracks neither.
  final String? location;
  final String? lastActiveLabel;

  /// Concurrency token for `landlord.*` admin commands. Null when the account
  /// has no landlord aggregate.
  final int? landlordAccountVersion;
  final String? businessName;

  final String? subscriptionTier;
  final PlatformSubscriptionStatus subscriptionStatus;

  /// Concurrency token for `subscription.confirmPayment`.
  final int? subscriptionVersion;

  /// True for demo directory entries that exist only on this device.
  final bool isLocalOnly;

  bool get isLandlord => roleLabel.toLowerCase() == 'landlord';
}

/// One redacted entry of the server-owned append-only audit log.
final class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.action,
    required this.actorUid,
    required this.actorIsAdmin,
    required this.outcome,
    required this.at,
    this.aggregateId,
    this.reasonCode,
  });

  final String id;

  /// The command type, e.g. `landlord.approve`.
  final String action;
  final String actorUid;
  final bool actorIsAdmin;

  /// `applied`, `accepted`, or `rejected`.
  final String outcome;
  final DateTime at;
  final String? aggregateId;
  final String? reasonCode;
}

/// Live read access to the admin-readable server documents. Implementations
/// stream from the server; there is deliberately no local mirror, because
/// every mutation against these aggregates is an online audited command.
abstract interface class AdminDirectoryRepository {
  Stream<List<PlatformAccount>> watchAccounts();

  Stream<List<AdminAuditEvent>> watchRecentAuditEvents({int limit});
}
