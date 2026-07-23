import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../data/firestore_admin_directory.dart';
import '../domain/platform_account.dart';

/// Where the admin account directory comes from in this session.
enum AdminDirectorySource {
  /// Real server documents, streamed live. Actions run audited commands.
  live,

  /// Not an admin session, or no Firebase app is configured.
  unavailable,
}

final adminDirectorySourceProvider = Provider<AdminDirectorySource>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session == null ||
      (session.role != AppRole.admin && session.role != AppRole.superAdmin)) {
    return AdminDirectorySource.unavailable;
  }
  return Firebase.apps.isEmpty
      ? AdminDirectorySource.unavailable
      : AdminDirectorySource.live;
});

final adminDirectoryRepositoryProvider = Provider<AdminDirectoryRepository>(
  (ref) => FirestoreAdminDirectory(),
);

/// The account directory the admin screens render.
///
/// Live sessions stream the real `users`/`landlordAccounts`/`subscriptions`
/// join. Every other session has no directory to show.
final platformAccountsProvider = StreamProvider<List<PlatformAccount>>((
  ref,
) async* {
  switch (ref.watch(adminDirectorySourceProvider)) {
    case AdminDirectorySource.live:
      yield* ref.watch(adminDirectoryRepositoryProvider).watchAccounts();
    case AdminDirectorySource.unavailable:
      yield const <PlatformAccount>[];
  }
});

/// Recent entries of the server-owned audit log. Empty outside live sessions,
/// since inventing audit events would defeat the point of an audit log.
final adminAuditEventsProvider = StreamProvider<List<AdminAuditEvent>>((
  ref,
) async* {
  if (ref.watch(adminDirectorySourceProvider) != AdminDirectorySource.live) {
    yield const <AdminAuditEvent>[];
    return;
  }
  yield* ref
      .watch(adminDirectoryRepositoryProvider)
      .watchRecentAuditEvents(limit: 30);
});

/// Reason codes the server accepts per admin transition
/// (`firebase/functions/src/commands/admin.ts`).
const approveReasonCodes = ['IDENTITY_VERIFIED', 'COMPLIANCE_APPROVED'];
const suspendReasonCodes = [
  'POLICY_VIOLATION',
  'FRAUD_RISK',
  'ADMIN_CORRECTION',
];
const reinstateReasonCodes = ['APPEAL_APPROVED', 'ADMIN_CORRECTION'];
const archiveUserReasonCodes = [
  'POLICY_VIOLATION',
  'FRAUD_RISK',
  'USER_REQUESTED',
  'ADMIN_CORRECTION',
];
const restoreUserReasonCodes = ['APPEAL_APPROVED', 'ADMIN_CORRECTION'];
const deleteUserReasonCodes = [
  'USER_REQUESTED',
  'POLICY_VIOLATION',
  'ADMIN_CORRECTION',
];
const changeRoleReasonCodes = [
  'ADMIN_CORRECTION',
  'USER_REQUESTED',
  'IDENTITY_VERIFIED',
];

/// Why an archived record was destroyed for good
/// (`firebase/functions/src/commands/purge.ts`).
const purgeReasonCodes = [
  'DATA_RETENTION',
  'USER_REQUESTED',
  'POLICY_VIOLATION',
  'FRAUD_RISK',
  'ADMIN_CORRECTION',
];

/// Why staff could not confirm a payment a landlord reported
/// (`subscription.rejectPayment`).
const rejectPaymentReasonCodes = [
  'PAYMENT_NOT_RECEIVED',
  'AMOUNT_INCORRECT',
  'REFERENCE_INVALID',
  'DUPLICATE_REQUEST',
  'ADMIN_CORRECTION',
];

/// Why an active subscription was moved to a smaller plan
/// (`subscription.downgrade`).
const downgradeReasonCodes = [
  'LANDLORD_REQUESTED',
  'PAYMENT_SHORTFALL',
  'ADMIN_CORRECTION',
];

/// Why a subscription was ended, locking the workspace
/// (`subscription.deactivate`).
const deactivateSubscriptionReasonCodes = [
  'NON_PAYMENT',
  'LANDLORD_REQUESTED',
  'DUPLICATE_ACCOUNT',
  'ADMIN_CORRECTION',
];

/// Server-owned ordinary roles `user.changeRole` accepts. Administrator
/// privileges are Auth custom claims granted only by the audited ops script,
/// never from inside the app.
const assignableServerRoles = ['landlord', 'tenant', 'client'];

/// Audiences the `platform.broadcast` command accepts, in presentation order.
const broadcastAudiences = [
  'all_users',
  'landlords',
  'tenants',
  'clients',
  'tier',
  'user',
];

/// One sent (or sending) platform announcement, read from the server-owned
/// `platformBroadcasts` collection for the admin history panel.
final class PlatformBroadcast {
  const PlatformBroadcast({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.audienceId,
    required this.deliveryState,
    required this.recipientCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String audience;
  final String? audienceId;
  final String deliveryState;
  final int? recipientCount;
  final DateTime? createdAt;
}

/// Recent platform broadcasts, newest first. Empty outside live admin
/// sessions — the collection is server-owned and staff-read by rule.
final platformBroadcastsProvider = StreamProvider<List<PlatformBroadcast>>((
  ref,
) async* {
  if (ref.watch(adminDirectorySourceProvider) != AdminDirectorySource.live) {
    yield const <PlatformBroadcast>[];
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('platformBroadcasts')
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map(
        (snapshot) => [
          for (final document in snapshot.docs)
            PlatformBroadcast(
              id: document.id,
              title: document.data()['title'] as String? ?? '',
              body: document.data()['body'] as String? ?? '',
              audience: document.data()['audience'] as String? ?? 'all_users',
              audienceId: document.data()['audienceId'] as String?,
              deliveryState:
                  document.data()['deliveryState'] as String? ?? 'pending',
              recipientCount: (document.data()['recipientCount'] as num?)
                  ?.toInt(),
              createdAt: (document.data()['createdAt'] as Timestamp?)?.toDate(),
            ),
        ],
      );
});

final sendPlatformBroadcastProvider = Provider<SendPlatformBroadcast>(
  SendPlatformBroadcast.new,
);

/// Sends a platform announcement through the audited `platform.broadcast`
/// command. Open to any administrator: running the announcement channel is
/// ordinary platform duty. Delivery (inbox, push, email) is the server's
/// durable job — nothing is sent from the client.
class SendPlatformBroadcast {
  const SendPlatformBroadcast(this._ref);

  final Ref _ref;

  Future<void> call({
    required String title,
    required String body,
    required String audience,
    String? audienceId,
  }) async {
    final session = _ref.read(sessionControllerProvider);
    if (session == null ||
        (session.role != AppRole.admin && session.role != AppRole.superAdmin)) {
      throw StateError('Administrator permission is required.');
    }
    if (title.trim().isEmpty || body.trim().isEmpty) {
      throw StateError('A broadcast needs both a title and a message.');
    }
    if (!broadcastAudiences.contains(audience)) {
      throw StateError('That audience is not supported.');
    }
    final scoped = audience == 'tier' || audience == 'user';
    if (scoped && (audienceId == null || audienceId.trim().isEmpty)) {
      throw StateError('Choose who this broadcast targets.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'platform.broadcast',
      aggregateId: 'broadcast_${const Uuid().v7().replaceAll('-', '')}',
      expectedVersion: 0,
      payload: <String, Object?>{
        'title': title.trim(),
        'body': body.trim(),
        'audience': audience,
        if (scoped) 'audienceId': audienceId!.trim(),
      },
    );
  }
}

final adminAccountCommandsProvider = Provider<AdminAccountCommands>(
  AdminAccountCommands.new,
);

/// Audited, server-authoritative admin actions against real accounts.
///
/// Online by nature: each command needs the current server version of the
/// aggregate it edits, and the server writes the authoritative audit entry in
/// the same transaction. Nothing here touches the outbox — a queued
/// suspension that applies hours later is an operational hazard, not a
/// feature.
class AdminAccountCommands {
  const AdminAccountCommands(this._ref);

  final Ref _ref;

  Future<void> approveLandlord({
    required PlatformAccount account,
    required String reasonCode,
  }) => _landlordTransition('landlord.approve', account, reasonCode);

  Future<void> suspendLandlord({
    required PlatformAccount account,
    required String reasonCode,
  }) => _landlordTransition('landlord.suspend', account, reasonCode);

  Future<void> reinstateLandlord({
    required PlatformAccount account,
    required String reasonCode,
  }) => _landlordTransition('landlord.reinstate', account, reasonCode);

  /// Marks a landlord subscription paid against an explicit payment
  /// reference, through the same audited staff path as landlord approval.
  Future<void> confirmSubscriptionPayment({
    required PlatformAccount account,
    required String reference,
    String? tier,
  }) async {
    _requireManageable(account);
    final version = account.subscriptionVersion;
    if (version == null) {
      throw StateError('This account has no subscription record yet.');
    }
    if (reference.trim().isEmpty) {
      throw StateError('A payment reference is required.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'subscription.confirmPayment',
      aggregateId: account.uid,
      expectedVersion: version,
      payload: <String, Object?>{
        'reference': reference.trim(),
        if (tier != null && tier.trim().isNotEmpty) 'tier': tier.trim(),
      },
    );
  }

  /// Records that staff checked and could not confirm a payment the landlord
  /// reported. Clears the pending request and tells the landlord why; the
  /// plan and its entitlements are left exactly as they were.
  Future<void> rejectSubscriptionPayment({
    required PlatformAccount account,
    required String reasonCode,
    String? note,
  }) async {
    _requireManageable(account);
    final version = account.subscriptionVersion;
    if (version == null) {
      throw StateError('This account has no subscription record yet.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'subscription.rejectPayment',
      aggregateId: account.uid,
      expectedVersion: version,
      payload: <String, Object?>{
        'reasonCode': reasonCode,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  /// Moves an active subscription to a smaller plan without a payment. The
  /// server rejects anything that is not actually a downgrade, so this can
  /// never hand out paid capacity for free.
  Future<void> downgradeSubscription({
    required PlatformAccount account,
    required String tier,
    required String reasonCode,
  }) async {
    _requireManageable(account);
    final version = account.subscriptionVersion;
    if (version == null) {
      throw StateError('This account has no subscription record yet.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'subscription.downgrade',
      aggregateId: account.uid,
      expectedVersion: version,
      payload: <String, Object?>{'tier': tier, 'reasonCode': reasonCode},
    );
  }

  /// Ends a subscription, locking the landlord's workspace. Nothing is
  /// deleted and tenants keep their portal; confirming a payment reopens it.
  Future<void> deactivateSubscription({
    required PlatformAccount account,
    required String reasonCode,
  }) async {
    _requireManageable(account);
    final version = account.subscriptionVersion;
    if (version == null) {
      throw StateError('This account has no subscription record yet.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'subscription.deactivate',
      aggregateId: account.uid,
      expectedVersion: version,
      payload: <String, Object?>{'reasonCode': reasonCode},
    );
  }

  /// Archives any account: sign-in is disabled server-side and the profile is
  /// marked archived. Open to any administrator because [restoreUser] undoes
  /// it; only the permanent [deleteUser] is reserved for a super admin.
  Future<void> archiveUser({
    required PlatformAccount account,
    required String reasonCode,
  }) => _userLifecycle('user.archive', account, reasonCode);

  /// Returns an archived account to active and re-enables sign-in.
  Future<void> restoreUser({
    required PlatformAccount account,
    required String reasonCode,
  }) => _userLifecycle('user.restore', account, reasonCode);

  /// Permanently deletes an account out of the archive. The server refuses
  /// this unless the account is already archived, and unless the caller holds
  /// the super-admin claim.
  Future<void> deleteUser({
    required PlatformAccount account,
    required String reasonCode,
  }) => _userLifecycle(
    'user.delete',
    account,
    reasonCode,
    superAdminOnly: true,
  );

  /// Changes an account's ordinary role (`landlord`/`tenant`/`client`).
  /// Administrator privileges cannot be granted here by design.
  Future<void> changeUserRole({
    required PlatformAccount account,
    required String role,
    required String reasonCode,
  }) async {
    final version = _requireLifecycleTarget(account);
    if (!assignableServerRoles.contains(role)) {
      throw StateError('That role cannot be assigned from the app.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: 'user.changeRole',
      aggregateId: account.uid,
      expectedVersion: version,
      payload: <String, Object?>{'role': role, 'reasonCode': reasonCode},
    );
  }

  Future<void> _userLifecycle(
    String type,
    PlatformAccount account,
    String reasonCode, {
    bool superAdminOnly = false,
  }) async {
    final version = _requireLifecycleTarget(
      account,
      superAdminOnly: superAdminOnly,
    );
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: type,
      aggregateId: account.uid,
      expectedVersion: version,
      payload: <String, Object?>{'reasonCode': reasonCode},
    );
  }

  /// Shared gate for the `user.*` commands; returns the `users/{uid}`
  /// concurrency token. The reversible ones are open to any administrator;
  /// pass [superAdminOnly] for the irreversible ones. This mirrors the
  /// server's own gate — it is a UX guard, never the security boundary.
  int _requireLifecycleTarget(
    PlatformAccount account, {
    bool superAdminOnly = false,
  }) {
    _requireManageable(account);
    if (superAdminOnly) {
      final session = _ref.read(sessionControllerProvider);
      if (session?.role != AppRole.superAdmin) {
        throw StateError(
          'Only a super administrator can permanently delete an account.',
        );
      }
    }
    final version = account.userVersion;
    if (version == null) {
      throw StateError('This account has no server profile to act on.');
    }
    return version;
  }

  Future<void> _landlordTransition(
    String type,
    PlatformAccount account,
    String reasonCode,
  ) async {
    _requireManageable(account);
    final version = account.landlordAccountVersion;
    if (version == null) {
      throw StateError('This account has no landlord record to act on.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: type,
      aggregateId: account.uid,
      expectedVersion: version,
      payload: <String, Object?>{'reasonCode': reasonCode},
    );
  }

  void _requireManageable(PlatformAccount account) {
    final session = _ref.read(sessionControllerProvider);
    if (session == null ||
        (session.role != AppRole.admin && session.role != AppRole.superAdmin)) {
      throw StateError('Administrator permission is required.');
    }
    if (account.uid == session.userId) {
      throw StateError('You cannot act on your own account.');
    }
    if (!AuthorizationPolicy.canManageAccountRole(
      session.role,
      account.roleLabel,
    )) {
      throw StateError('You do not have permission to manage this account.');
    }
  }
}

final adminPurgeCommandsProvider = Provider<AdminPurgeCommands>(
  AdminPurgeCommands.new,
);

/// Permanent removal of archived portfolio records, across any landlord's
/// workspace.
///
/// Online and super-admin only, for the same reasons as [AdminAccountCommands]:
/// each command carries the aggregate's current server version, and a purge
/// queued offline could fire against a record that was restored in the
/// meantime. The role check here is a UX guard so the menu item never offers
/// what the server would refuse — `requireSuperAdmin` in
/// `firebase/functions/src/commands/purge.ts` is the real boundary.
class AdminPurgeCommands {
  const AdminPurgeCommands(this._ref);

  final Ref _ref;

  /// Destroys an archived property. The server refuses while any unit still
  /// references it, so units are purged first.
  Future<void> deleteProperty({
    required String propertyId,
    required int expectedVersion,
    required String reasonCode,
  }) => _purge('property.delete', propertyId, expectedVersion, reasonCode);

  /// Destroys an archived rental space.
  Future<void> deleteUnit({
    required String unitId,
    required int expectedVersion,
    required String reasonCode,
  }) => _purge('unit.delete', unitId, expectedVersion, reasonCode);

  /// Destroys a listing that is off the market, private and public copies
  /// together. The server refuses while it is still published.
  Future<void> deleteListing({
    required String listingId,
    required int expectedVersion,
    required String reasonCode,
  }) => _purge('listing.delete', listingId, expectedVersion, reasonCode);

  /// Purges a soft-deleted document now instead of at the end of its
  /// retention window.
  Future<void> purgeDocument({
    required String documentId,
    required int expectedVersion,
    required String reasonCode,
  }) => _purge('document.purge', documentId, expectedVersion, reasonCode);

  Future<void> _purge(
    String type,
    String aggregateId,
    int expectedVersion,
    String reasonCode,
  ) async {
    final session = _ref.read(sessionControllerProvider);
    if (session?.role != AppRole.superAdmin) {
      throw StateError(
        'Only a super administrator can permanently delete a record.',
      );
    }
    if (!purgeReasonCodes.contains(reasonCode)) {
      throw StateError('That reason code is not accepted for a purge.');
    }
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: type,
      aggregateId: aggregateId,
      expectedVersion: expectedVersion,
      payload: <String, Object?>{'reasonCode': reasonCode},
    );
  }
}
