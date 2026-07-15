import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/auth/domain/authorization_policy.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';

void main() {
  group('super admin', () {
    test('has full business access but cannot mutate audit history', () {
      for (final resource in AppResource.values) {
        for (final operation in CrudOperation.values) {
          final expected =
              resource != AppResource.auditLog ||
              operation == CrudOperation.read;
          if (resource == AppResource.backendOperation) {
            expect(
              AuthorizationPolicy.allows(
                AppRole.superAdmin,
                resource,
                operation,
              ),
              operation == CrudOperation.read ||
                  operation == CrudOperation.update,
            );
          } else {
            expect(
              AuthorizationPolicy.allows(
                AppRole.superAdmin,
                resource,
                operation,
              ),
              expected,
              reason: '${resource.name}.${operation.name}',
            );
          }
        }
      }
    });

    test('may assign protected administrator roles', () {
      expect(
        AuthorizationPolicy.canManageAccountRole(
          AppRole.superAdmin,
          'Super Admin',
        ),
        isTrue,
      );
      expect(
        AuthorizationPolicy.assignableAccountRoles(AppRole.superAdmin),
        containsAll(<String>['Super Admin', 'Admin']),
      );
    });
  });

  group('admin', () {
    test('has broad business access without protected platform access', () {
      expect(
        AuthorizationPolicy.operationsFor(AppRole.admin, AppResource.property),
        containsAll(CrudOperation.values),
      );
      expect(
        AuthorizationPolicy.allows(
          AppRole.admin,
          AppResource.auditLog,
          CrudOperation.read,
        ),
        isTrue,
      );
      expect(
        AuthorizationPolicy.allows(
          AppRole.admin,
          AppResource.auditLog,
          CrudOperation.delete,
        ),
        isFalse,
      );
      expect(
        AuthorizationPolicy.operationsFor(
          AppRole.admin,
          AppResource.superAdminAccount,
        ),
        isEmpty,
      );
      expect(
        AuthorizationPolicy.canManageAccountRole(AppRole.admin, 'Admin'),
        isFalse,
      );
      expect(
        AuthorizationPolicy.canManageAccountRole(AppRole.admin, 'Landlord'),
        isTrue,
      );
      expect(
        AuthorizationPolicy.canManageAccountRole(AppRole.admin, 'Unknown'),
        isFalse,
      );
    });
  });

  test('landlord permissions stop at the owned portfolio boundary', () {
    expect(
      AuthorizationPolicy.allows(
        AppRole.landlord,
        AppResource.property,
        CrudOperation.delete,
      ),
      isTrue,
    );
    expect(
      AuthorizationPolicy.allows(
        AppRole.landlord,
        AppResource.auditLog,
        CrudOperation.read,
      ),
      isFalse,
    );
  });

  test('tenant can submit maintenance but cannot update invoices', () {
    expect(
      AuthorizationPolicy.allows(
        AppRole.tenant,
        AppResource.maintenanceRequest,
        CrudOperation.create,
      ),
      isTrue,
    );
    expect(
      AuthorizationPolicy.allows(
        AppRole.tenant,
        AppResource.invoice,
        CrudOperation.update,
      ),
      isFalse,
    );
  });

  test('prospective client is limited to public and self-service data', () {
    expect(
      AuthorizationPolicy.allows(
        AppRole.client,
        AppResource.publicListing,
        CrudOperation.read,
      ),
      isTrue,
    );
    expect(
      AuthorizationPolicy.allows(
        AppRole.client,
        AppResource.privateListing,
        CrudOperation.read,
      ),
      isFalse,
    );
  });
}
