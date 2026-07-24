import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/staff/domain/staff_permission.dart';

void main() {
  const landlordProfile = SessionProfile(
    role: AppRole.landlord,
    workspaceId: 'owner-1',
    subscriptionStatus: LandlordSubscriptionStatus.active,
    subscriptionTier: 'starter',
  );
  const tenantProfile = SessionProfile(role: AppRole.tenant);
  const staffProfile = SessionProfile(
    role: AppRole.staff,
    workspaceId: 'other-owner',
    permissions: {StaffPermission.manageProperties},
    subscriptionStatus: LandlordSubscriptionStatus.active,
  );

  UserSession landlordTenantSession({List<SessionProfile>? profiles}) =>
      UserSession(
        userId: 'owner-1',
        displayName: 'Dual Role',
        email: 'dual@nyumba.test',
        role: AppRole.landlord,
        subscriptionStatus: LandlordSubscriptionStatus.active,
        subscriptionTier: 'starter',
        workspaceId: 'owner-1',
        profiles: profiles ?? const [landlordProfile, tenantProfile],
      );

  group('UserSession profiles', () {
    test('a session without collected profiles synthesizes its active one', () {
      const single = UserSession(
        userId: 't-1',
        displayName: 'Tenant',
        email: 't@nyumba.test',
        role: AppRole.tenant,
      );
      expect(single.profiles, isEmpty);
      expect(single.hasMultipleProfiles, isFalse);
      expect(single.activeProfile.role, AppRole.tenant);
      expect(single.activeProfile.workspaceId, isNull);
    });

    test('the active profile is matched by role and workspace', () {
      final session = landlordTenantSession();
      expect(session.hasMultipleProfiles, isTrue);
      expect(session.activeProfile, same(session.profiles.first));
      expect(session.activeProfile.subscriptionTier, 'starter');
    });

    test('withActiveProfile swaps every scalar the UI branches on', () {
      final session = landlordTenantSession();
      final asTenant = session.withActiveProfile(tenantProfile);

      expect(asTenant.role, AppRole.tenant);
      expect(asTenant.workspaceId, isNull);
      expect(asTenant.isWorkspaceOwner, isFalse);
      expect(
        asTenant.subscriptionStatus,
        LandlordSubscriptionStatus.notApplicable,
      );
      expect(asTenant.workspacePath, '/tenant');
      // Identity and the profile set survive the swap.
      expect(asTenant.userId, session.userId);
      expect(asTenant.profiles, session.profiles);

      final backAgain = asTenant.withActiveProfile(landlordProfile);
      expect(backAgain.role, AppRole.landlord);
      expect(backAgain.isWorkspaceOwner, isTrue);
      expect(backAgain.subscriptionStatus, LandlordSubscriptionStatus.active);
      expect(backAgain.workspacePath, '/dashboard');
    });

    test('a staff profile carries its granted permissions across a switch', () {
      final session = landlordTenantSession(
        profiles: const [landlordProfile, staffProfile],
      );
      final asStaff = session.withActiveProfile(staffProfile);
      expect(asStaff.role, AppRole.staff);
      expect(asStaff.effectiveWorkspaceId, 'other-owner');
      expect(asStaff.can(StaffPermission.manageProperties), isTrue);
      expect(asStaff.can(StaffPermission.manageBilling), isFalse);
    });

    test('withSubscription updates the active profile entry too', () {
      final session = landlordTenantSession();
      final lapsed = session.withSubscription(
        status: LandlordSubscriptionStatus.pastDue,
        tier: 'starter',
      );
      expect(lapsed.subscriptionStatus, LandlordSubscriptionStatus.pastDue);

      // Switching away and back must not resurrect the stale snapshot.
      final roundTripped = lapsed
          .withActiveProfile(tenantProfile)
          .withActiveProfile(lapsed.activeProfile);
      expect(
        roundTripped.subscriptionStatus,
        LandlordSubscriptionStatus.pastDue,
      );
      // The untouched tenant entry stays as it was.
      expect(
        lapsed.profiles.last.subscriptionStatus,
        LandlordSubscriptionStatus.notApplicable,
      );
    });

    test('profile keys distinguish staff workspaces', () {
      expect(landlordProfile.key, 'landlord:owner-1');
      expect(tenantProfile.key, 'tenant');
      expect(staffProfile.key, 'staff:other-owner');
    });
  });

  group('selectActiveProfile', () {
    const admin = SessionProfile(role: AppRole.admin);

    test('prefers the persisted choice when it still exists', () {
      expect(
        selectActiveProfile(const [landlordProfile, tenantProfile], 'tenant'),
        same(tenantProfile),
      );
    });

    test('falls back to privilege order when nothing is persisted', () {
      expect(
        selectActiveProfile(const [tenantProfile, landlordProfile], null),
        same(landlordProfile),
      );
      expect(
        selectActiveProfile(const [
          tenantProfile,
          landlordProfile,
          admin,
        ], null),
        same(admin),
      );
      expect(
        selectActiveProfile(const [tenantProfile, staffProfile], null),
        same(staffProfile),
      );
    });

    test('ignores a stale persisted key', () {
      expect(
        selectActiveProfile(const [
          landlordProfile,
          tenantProfile,
        ], 'staff:gone-workspace'),
        same(landlordProfile),
      );
    });
  });

  group('workspaceScopeFor', () {
    test('keys the offline mirror by account and active role', () {
      expect(workspaceScopeFor(null), 'anonymous');
      final session = landlordTenantSession();
      expect(workspaceScopeFor(session), 'account-owner-1--landlord');
      expect(
        workspaceScopeFor(session.withActiveProfile(staffProfile)),
        'account-owner-1--staff--workspace-other-owner',
      );
      const secondStaffWorkspace = SessionProfile(
        role: AppRole.staff,
        workspaceId: 'second-owner',
      );
      expect(
        workspaceScopeFor(session.withActiveProfile(secondStaffWorkspace)),
        'account-owner-1--staff--workspace-second-owner',
      );
      // Tenants keep the legacy unsuffixed scope: their locally recorded data
      // has no server pull to rebuild it from.
      expect(
        workspaceScopeFor(session.withActiveProfile(tenantProfile)),
        'account-owner-1',
      );
    });
  });

  group('loadWorkspaceState', () {
    test('preserves successful server mapping', () async {
      final result = await loadWorkspaceState(
        fallbackStatus: AccountStatus.active,
        readAccount: () async => {'approvalStatus': 'pending'},
        readSubscription: () async => {
          'status': 'active',
          'tier': ' starter ',
          'requestedTier': ' pro ',
        },
      );

      expect(result.accountStatus, AccountStatus.pendingApproval);
      expect(result.subscriptionStatus, LandlordSubscriptionStatus.active);
      expect(result.tier, 'starter');
      expect(result.requestedTier, 'pro');
    });

    test('locks an unavailable workspace without throwing', () async {
      final result = await loadWorkspaceState(
        fallbackStatus: AccountStatus.active,
        readAccount: () async => {'approvalStatus': 'suspended'},
        readSubscription: () async => throw StateError('server unavailable'),
      );

      expect(result.accountStatus, AccountStatus.suspended);
      expect(result.subscriptionStatus, LandlordSubscriptionStatus.unavailable);
      expect(result.tier, isNull);
      expect(result.requestedTier, isNull);

      var subscriptionRead = false;
      final accountFailure = await loadWorkspaceState(
        fallbackStatus: AccountStatus.pendingApproval,
        readAccount: () async => throw StateError('server unavailable'),
        readSubscription: () async {
          subscriptionRead = true;
          return {'status': 'active'};
        },
      );
      expect(accountFailure.accountStatus, AccountStatus.pendingApproval);
      expect(
        accountFailure.subscriptionStatus,
        LandlordSubscriptionStatus.unavailable,
      );
      expect(subscriptionRead, isFalse);
    });
  });
}
