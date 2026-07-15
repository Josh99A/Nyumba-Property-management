import 'user_session.dart';

enum CrudOperation { create, read, update, delete }

enum AppResource {
  superAdminAccount,
  adminAccount,
  userAccount,
  profile,
  landlordAccount,
  landlordApproval,
  subscription,
  planCatalog,
  property,
  unit,
  tenantRecord,
  lease,
  invoice,
  payment,
  receipt,
  maintenanceRequest,
  notice,
  document,
  privateListing,
  publicListing,
  application,
  contactRequest,
  report,
  auditLog,
  platformConfiguration,
  backendOperation,
}

/// Presentation/application authorization policy.
///
/// This policy determines which controls and routes are exposed. It is never a
/// substitute for the ownership, relationship, account-state, entitlement,
/// and payload checks repeated by Firestore Rules and callable Functions.
abstract final class AuthorizationPolicy {
  static const _all = <CrudOperation>{
    CrudOperation.create,
    CrudOperation.read,
    CrudOperation.update,
    CrudOperation.delete,
  };
  static const _createRead = <CrudOperation>{
    CrudOperation.create,
    CrudOperation.read,
  };
  static const _createReadUpdate = <CrudOperation>{
    CrudOperation.create,
    CrudOperation.read,
    CrudOperation.update,
  };
  static const _read = <CrudOperation>{CrudOperation.read};
  static const _readUpdate = <CrudOperation>{
    CrudOperation.read,
    CrudOperation.update,
  };

  static bool allows(
    AppRole role,
    AppResource resource,
    CrudOperation operation,
  ) => operationsFor(role, resource).contains(operation);

  static Set<CrudOperation> operationsFor(
    AppRole role,
    AppResource resource,
  ) {
    if (role == AppRole.superAdmin) {
      return switch (resource) {
        AppResource.auditLog => _read,
        AppResource.backendOperation => _readUpdate,
        _ => _all,
      };
    }

    return switch (role) {
      AppRole.admin => switch (resource) {
        AppResource.superAdminAccount ||
        AppResource.backendOperation => const <CrudOperation>{},
        AppResource.adminAccount ||
        AppResource.auditLog => _read,
        AppResource.landlordApproval ||
        AppResource.platformConfiguration => _readUpdate,
        _ => _all,
      },
      AppRole.landlord => switch (resource) {
        AppResource.profile ||
        AppResource.subscription ||
        AppResource.landlordAccount => _readUpdate,
        AppResource.property ||
        AppResource.unit ||
        AppResource.tenantRecord ||
        AppResource.notice ||
        AppResource.document ||
        AppResource.privateListing => _all,
        AppResource.lease ||
        AppResource.payment ||
        AppResource.maintenanceRequest ||
        AppResource.application ||
        AppResource.contactRequest => _createReadUpdate,
        AppResource.invoice || AppResource.report => _createRead,
        AppResource.receipt || AppResource.publicListing => _read,
        _ => const <CrudOperation>{},
      },
      AppRole.tenant => switch (resource) {
        AppResource.profile => _readUpdate,
        AppResource.payment ||
        AppResource.application ||
        AppResource.contactRequest => _createRead,
        AppResource.maintenanceRequest => _createReadUpdate,
        AppResource.lease ||
        AppResource.invoice ||
        AppResource.receipt ||
        AppResource.notice ||
        AppResource.document ||
        AppResource.publicListing => _read,
        _ => const <CrudOperation>{},
      },
      AppRole.client => switch (resource) {
        AppResource.profile => _all,
        AppResource.application => _createReadUpdate,
        AppResource.contactRequest => _createRead,
        AppResource.publicListing => _read,
        _ => const <CrudOperation>{},
      },
      AppRole.superAdmin => throw StateError('Handled above.'),
    };
  }

  static bool canManageAccountRole(AppRole actorRole, String targetRole) {
    final normalized = targetRole
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[ _-]+'), '');
    if (actorRole == AppRole.superAdmin) return true;
    if (actorRole != AppRole.admin) return false;
    return normalized != 'admin' && normalized != 'superadmin';
  }

  static List<String> assignableAccountRoles(AppRole actorRole) => switch (
    actorRole
  ) {
    AppRole.superAdmin => const [
      'Super Admin',
      'Admin',
      'Landlord',
      'Tenant',
      'Client',
    ],
    AppRole.admin => const ['Landlord', 'Tenant', 'Client'],
    _ => const <String>[],
  };
}
