/// Server-truth view of one platform account, joined from the admin-readable
/// `users`, `landlordAccounts`, and `subscriptions` documents.
///
/// A [PlatformAccount] is keyed by the Firebase UID and can therefore address
/// the real account in audited admin commands (`landlord.approve` /
/// `landlord.suspend` / `landlord.reinstate` / `subscription.confirmPayment` /
/// `user.archive` / `user.restore` / `user.delete`).
library;

enum PlatformAccountStatus {
  active('Active'),
  pendingApproval('Pending approval'),

  /// An invited directory entry that does not yet have an active account.
  invited('Invited'),
  suspended('Suspended'),

  /// Super-admin archived: sign-in is disabled and the account waits either
  /// for restoration or permanent deletion.
  archived('Archived');

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
    this.userVersion,
    this.landlordAccountVersion,
    this.businessName,
    this.subscriptionTier,
    this.subscriptionRequestedTier,
    this.subscriptionStatus = PlatformSubscriptionStatus.none,
    this.subscriptionVersion,
  });

  /// Firebase UID for the server-backed account.
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

  /// Optional directory metadata; not every server account carries these.
  final String? location;
  final String? lastActiveLabel;

  /// Concurrency token for the `user.*` lifecycle commands, from the
  /// `users/{uid}` document. Null when the account has no server profile.
  final int? userVersion;

  /// Concurrency token for `landlord.*` admin commands. Null when the account
  /// has no landlord aggregate.
  final int? landlordAccountVersion;
  final String? businessName;

  final String? subscriptionTier;

  /// Tier the landlord asked to move to via `subscription.requestUpgrade`;
  /// entitlements stay on [subscriptionTier] until staff confirm payment.
  final String? subscriptionRequestedTier;

  final PlatformSubscriptionStatus subscriptionStatus;

  /// Concurrency token for `subscription.confirmPayment`.
  final int? subscriptionVersion;

  bool get isLandlord => roleLabel.toLowerCase() == 'landlord';

  /// An active subscription with a pending, different requested tier.
  bool get hasPendingUpgrade =>
      subscriptionStatus == PlatformSubscriptionStatus.active &&
      subscriptionRequestedTier != null &&
      subscriptionRequestedTier != subscriptionTier;
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

/// Readable label for a UID appearing in audit or activity context.
///
/// Server documents reference people by immutable Firebase UID — document
/// IDs and audit entries must never key on a name or email, which change and
/// are PII in every cross-reference. Presentation resolves the UID back to
/// the directory instead. Falls back to a shortened UID when the account is
/// unknown here (deleted, or an orphaned profile the directory collapsed).
String accountLabelFor(String? uid, Map<String, PlatformAccount> byUid) {
  if (uid == null || uid.isEmpty) return 'unknown account';
  final account = byUid[uid];
  if (account != null) {
    return account.displayName.isNotEmpty
        ? account.displayName
        : (account.email.isNotEmpty ? account.email : _shortUid(uid));
  }
  return _shortUid(uid);
}

String _shortUid(String uid) =>
    uid.length <= 10 ? uid : '${uid.substring(0, 8)}…';

/// Live read access to the admin-readable server documents. Implementations
/// stream from the server; there is deliberately no local mirror, because
/// every mutation against these aggregates is an online audited command.
abstract interface class AdminDirectoryRepository {
  Stream<List<PlatformAccount>> watchAccounts();

  Stream<List<AdminAuditEvent>> watchRecentAuditEvents({int limit});
}
