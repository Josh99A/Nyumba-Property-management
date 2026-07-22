import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/router.dart';
import 'package:nyumba_property_management/features/auth/domain/authorization_policy.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/staff/domain/staff_permission.dart';

UserSession _staff({
  LandlordSubscriptionStatus status = LandlordSubscriptionStatus.active,
  Set<StaffPermission> permissions = const {StaffPermission.manageProperties},
}) => UserSession(
  userId: 'staff-1',
  displayName: 'Staff Member',
  email: 'staff@nyumba.test',
  role: AppRole.staff,
  subscriptionStatus: status,
  subscriptionTier: 'pro',
  workspaceId: 'owner-1',
  permissions: permissions,
);

void main() {
  group('staff session', () {
    test('acts in the owner workspace and holds only granted capabilities', () {
      final staff = _staff(
        permissions: const {
          StaffPermission.manageProperties,
          StaffPermission.manageMaintenance,
        },
      );
      expect(staff.effectiveWorkspaceId, 'owner-1');
      expect(staff.isWorkspaceOwner, isFalse);
      expect(staff.can(StaffPermission.manageProperties), isTrue);
      expect(staff.can(StaffPermission.manageMaintenance), isTrue);
      expect(staff.can(StaffPermission.manageBilling), isFalse);
    });

    test('an owner implicitly holds every capability', () {
      const owner = UserSession(
        userId: 'owner-1',
        displayName: 'Owner',
        email: 'owner@nyumba.test',
        role: AppRole.landlord,
        subscriptionStatus: LandlordSubscriptionStatus.active,
        subscriptionTier: 'pro',
      );
      expect(owner.effectiveWorkspaceId, 'owner-1');
      expect(owner.isWorkspaceOwner, isTrue);
      for (final permission in StaffPermission.values) {
        expect(owner.can(permission), isTrue, reason: permission.id);
      }
    });

    test('an active staff member lands on the dashboard', () {
      expect(_staff().workspacePath, '/dashboard');
      expect(_staff().hasConfirmedSubscription, isTrue);
    });

    test('a lapsed owner workspace leaves staff without a workspace home', () {
      final lapsed = _staff(status: LandlordSubscriptionStatus.expired);
      expect(lapsed.hasConfirmedSubscription, isFalse);
      expect(lapsed.workspacePath, isNull);
    });
  });

  group('staff routing', () {
    test('reaches the workspace but never owner-only surfaces', () {
      final staff = _staff();
      expect(redirectForSession(staff, '/dashboard'), isNull);
      expect(redirectForSession(staff, '/properties'), isNull);
      expect(redirectForSession(staff, '/finances'), '/dashboard');
      expect(redirectForSession(staff, '/explore'), isNull);
      // Team management and the payment gate are the owner's alone.
      expect(redirectForSession(staff, '/team'), '/dashboard');
      expect(redirectForSession(staff, '/subscription'), '/dashboard');
    });

    test('is sent home rather than to the payment gate when the plan lapses', () {
      final lapsed = _staff(status: LandlordSubscriptionStatus.expired);
      // Owners are pushed to /subscription; staff cannot pay, so they go to the
      // public explore page instead.
      expect(redirectForSession(lapsed, '/dashboard'), '/explore');
    });

    test('hides resources that have no staff-readable local projection', () {
      final staff = _staff(
        permissions: const {
          StaffPermission.manageMaintenance,
          StaffPermission.manageDocuments,
        },
      );
      expect(redirectForSession(staff, '/maintenance'), '/dashboard');
      expect(redirectForSession(staff, '/documents'), '/dashboard');
      expect(
        AuthorizationPolicy.allowsSession(
          staff,
          AppResource.maintenanceRequest,
          CrudOperation.read,
        ),
        isFalse,
      );
      expect(
        AuthorizationPolicy.allowsSession(
          staff,
          AppResource.document,
          CrudOperation.read,
        ),
        isFalse,
      );
    });
  });

  test('staff operations require the matching session capability', () {
    final staff = _staff();
    expect(
      AuthorizationPolicy.allows(
        AppRole.staff,
        AppResource.property,
        CrudOperation.read,
      ),
      isFalse,
    );
    expect(
      AuthorizationPolicy.allowsSession(
        staff,
        AppResource.property,
        CrudOperation.read,
      ),
      isTrue,
    );
    expect(
      AuthorizationPolicy.allowsSession(
        staff,
        AppResource.payment,
        CrudOperation.read,
      ),
      isFalse,
    );
    expect(
      AuthorizationPolicy.allows(
        AppRole.staff,
        AppResource.auditLog,
        CrudOperation.read,
      ),
      isFalse,
    );
  });

  test('staff can manage their own profile and read public listings', () {
    final staff = _staff(permissions: const {});
    for (final operation in const [CrudOperation.read, CrudOperation.update]) {
      expect(
        AuthorizationPolicy.allowsSession(
          staff,
          AppResource.profile,
          operation,
        ),
        isTrue,
        reason: 'profile.${operation.name}',
      );
    }
    expect(
      AuthorizationPolicy.allowsSession(
        staff,
        AppResource.profile,
        CrudOperation.delete,
      ),
      isFalse,
    );
    expect(
      AuthorizationPolicy.allowsSession(
        staff,
        AppResource.publicListing,
        CrudOperation.read,
      ),
      isTrue,
    );
  });
}
