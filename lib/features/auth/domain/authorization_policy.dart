import 'user_session.dart';
import '../../staff/domain/staff_permission.dart';

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

  /// Capability-aware check for a concrete signed-in session. Staff never
  /// inherit the landlord matrix by role alone: the membership capability for
  /// the resource must also be present.
  static bool allowsSession(
    UserSession session,
    AppResource resource,
    CrudOperation operation,
  ) {
    if (session.role != AppRole.staff) {
      return allows(session.role, resource, operation);
    }
    // Personal profile access and the public catalogue belong to every signed-
    // in person; they are not landlord-workspace capabilities. Requiring a
    // staff grant for either would lock a teammate out of their own settings
    // and make public homes less accessible than they are to anonymous users.
    if (resource == AppResource.profile) {
      return _readUpdate.contains(operation);
    }
    if (resource == AppResource.publicListing) {
      return operation == CrudOperation.read;
    }
    final permission = _staffPermissionFor(resource);
    return permission != null &&
        session.can(permission) &&
        operationsFor(AppRole.landlord, resource).contains(operation);
  }

  static Set<CrudOperation> operationsFor(AppRole role, AppResource resource) {
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
        AppResource.adminAccount || AppResource.auditLog => _read,
        AppResource.landlordApproval ||
        AppResource.platformConfiguration => _readUpdate,
        _ => _all,
      },
      AppRole.landlord => switch (resource) {
        AppResource.profile || AppResource.subscription => _readUpdate,
        AppResource.landlordAccount => _read,
        AppResource.property ||
        AppResource.unit ||
        AppResource.tenantRecord ||
        AppResource.notice ||
        AppResource.document ||
        AppResource.privateListing => _all,
        AppResource.lease ||
        AppResource.payment ||
        AppResource.maintenanceRequest => _createReadUpdate,
        AppResource.application || AppResource.contactRequest => _readUpdate,
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
      // Staff authorization requires a concrete UserSession and is resolved by
      // allowsSession, never by role alone.
      AppRole.staff => const <CrudOperation>{},
      AppRole.superAdmin => throw StateError('Handled above.'),
    };
  }

  static StaffPermission? _staffPermissionFor(AppResource resource) =>
      switch (resource) {
        AppResource.property ||
        AppResource.unit => StaffPermission.manageProperties,
        AppResource.tenantRecord ||
        AppResource.lease => StaffPermission.manageTenants,
        AppResource.invoice ||
        AppResource.payment ||
        AppResource.receipt => StaffPermission.manageBilling,
        AppResource.maintenanceRequest => StaffPermission.manageMaintenance,
        AppResource.privateListing ||
        AppResource.publicListing ||
        AppResource.application ||
        AppResource.contactRequest => StaffPermission.manageListings,
        AppResource.notice => StaffPermission.manageCommunication,
        AppResource.document => StaffPermission.manageDocuments,
        AppResource.report => StaffPermission.viewReports,
        _ => null,
      };

  static bool canManageAccountRole(AppRole actorRole, String targetRole) {
    final normalized = targetRole.trim().toLowerCase().replaceAll(
      RegExp(r'[ _-]+'),
      '',
    );
    if (actorRole == AppRole.superAdmin) return true;
    if (actorRole != AppRole.admin) return false;
    return const {
      'client',
      'prospectiveclient',
      'tenant',
      'landlord',
    }.contains(normalized);
  }

  static List<String> assignableAccountRoles(AppRole actorRole) =>
      switch (actorRole) {
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
