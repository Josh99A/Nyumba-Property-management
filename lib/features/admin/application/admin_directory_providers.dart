import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/authorization_policy.dart';
import '../../auth/domain/user_session.dart';
import '../data/firestore_admin_directory.dart';
import '../domain/managed_user.dart';
import '../domain/platform_account.dart';

/// Where the admin account directory comes from in this session.
enum AdminDirectorySource {
  /// Real server documents, streamed live. Actions run audited commands.
  live,

  /// Seeded local fixtures in an explicit demo session. Actions stay local.
  demo,

  /// Not an admin session, or no Firebase app is configured.
  unavailable,
}

final adminDirectorySourceProvider = Provider<AdminDirectorySource>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session == null ||
      (session.role != AppRole.admin && session.role != AppRole.superAdmin)) {
    return AdminDirectorySource.unavailable;
  }
  if (session.isDemo) return AdminDirectorySource.demo;
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
/// join; demo sessions map the seeded local directory into the same shape so
/// the screens have exactly one honest data path each.
final platformAccountsProvider = StreamProvider<List<PlatformAccount>>((
  ref,
) async* {
  switch (ref.watch(adminDirectorySourceProvider)) {
    case AdminDirectorySource.live:
      yield* ref.watch(adminDirectoryRepositoryProvider).watchAccounts();
    case AdminDirectorySource.demo:
      final deps = await ref.watch(appDependenciesProvider.future);
      yield* deps.managedUsers.watchAll().map(
        (users) => users
            .map(
              (user) => PlatformAccount(
                uid: user.id,
                displayName: user.name,
                email: user.email,
                roleLabel: user.role,
                status: switch (user.status) {
                  ManagedUserStatus.active => PlatformAccountStatus.active,
                  ManagedUserStatus.invited => PlatformAccountStatus.invited,
                  ManagedUserStatus.suspended =>
                    PlatformAccountStatus.suspended,
                },
                joinedLabel: user.joinedLabel,
                location: user.location,
                lastActiveLabel: user.lastActiveLabel,
                isLocalOnly: true,
              ),
            )
            .toList(growable: false),
      );
    case AdminDirectorySource.unavailable:
      yield const <PlatformAccount>[];
  }
});

/// Recent entries of the server-owned audit log. Empty outside live sessions:
/// the demo workspace shows its local action history instead, and inventing
/// audit events would defeat the point of an audit log.
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

/// Server-owned ordinary roles `user.changeRole` accepts. Administrator
/// privileges are Auth custom claims granted only by the audited ops script,
/// never from inside the app.
const assignableServerRoles = ['landlord', 'tenant', 'client'];

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

  /// Archives any account: sign-in is disabled server-side and the profile is
  /// marked archived. Super-admin only, like every `user.*` lifecycle command.
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
  /// this unless the account is already archived.
  Future<void> deleteUser({
    required PlatformAccount account,
    required String reasonCode,
  }) => _userLifecycle('user.delete', account, reasonCode);

  /// Changes an account's ordinary role (`landlord`/`tenant`/`client`).
  /// Administrator privileges cannot be granted here by design.
  Future<void> changeUserRole({
    required PlatformAccount account,
    required String role,
    required String reasonCode,
  }) async {
    final version = _requireSuperAdminTarget(account);
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
    String reasonCode,
  ) async {
    final version = _requireSuperAdminTarget(account);
    final gateway = await _ref.read(authCommandGatewayProvider.future);
    await gateway.sendCommand(
      type: type,
      aggregateId: account.uid,
      expectedVersion: version,
      payload: <String, Object?>{'reasonCode': reasonCode},
    );
  }

  /// Shared gate for the super-admin-only `user.*` commands; returns the
  /// `users/{uid}` concurrency token.
  int _requireSuperAdminTarget(PlatformAccount account) {
    _requireManageable(account);
    final session = _ref.read(sessionControllerProvider);
    if (session?.role != AppRole.superAdmin) {
      throw StateError(
        'Only a super administrator can perform this account action.',
      );
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
    if (session.isDemo) {
      throw StateError('Demo sessions cannot act on real accounts.');
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
