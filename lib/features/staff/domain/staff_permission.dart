/// A capability a landlord can grant to a staff member. The ids match the
/// backend `StaffPermission` set (`firebase/functions/src/shared/accounts.ts`),
/// one per operational command group, and are the values stored on a staff
/// invite/membership and enforced by `requireWorkspace`.
enum StaffPermission {
  manageProperties('manageProperties'),
  manageTenants('manageTenants'),
  manageBilling('manageBilling'),
  manageMaintenance('manageMaintenance'),
  manageListings('manageListings'),
  manageCommunication('manageCommunication'),
  manageDocuments('manageDocuments'),
  viewReports('viewReports');

  const StaffPermission(this.id);

  /// The wire id persisted on the invite/membership and sent in command payloads.
  final String id;

  String get label => switch (this) {
    StaffPermission.manageProperties => 'Properties and units',
    StaffPermission.manageTenants => 'Tenants and leases',
    StaffPermission.manageBilling => 'Payments and invoices',
    StaffPermission.manageMaintenance => 'Maintenance',
    StaffPermission.manageListings => 'Listings',
    StaffPermission.manageCommunication => 'Notices',
    StaffPermission.manageDocuments => 'Documents',
    StaffPermission.viewReports => 'Reports',
  };

  String get description => switch (this) {
    StaffPermission.manageProperties =>
      'Add and edit properties and rental spaces.',
    StaffPermission.manageTenants =>
      'Invite tenants and manage their leases.',
    StaffPermission.manageBilling =>
      'Record payments, generate invoices, and issue receipts.',
    StaffPermission.manageMaintenance =>
      'Log and update maintenance requests.',
    StaffPermission.manageListings => 'Publish and manage public listings.',
    StaffPermission.manageCommunication => 'Send notices to tenants.',
    StaffPermission.manageDocuments => 'Upload and manage documents.',
    StaffPermission.viewReports => 'Generate operational reports.',
  };

  static StaffPermission? fromId(String id) {
    for (final permission in values) {
      if (permission.id == id) return permission;
    }
    return null;
  }

  /// Recognised capabilities from a raw Firestore array; unknown ids drop.
  static Set<StaffPermission> parse(Object? raw) {
    if (raw is! Iterable) return const {};
    final result = <StaffPermission>{};
    for (final entry in raw) {
      final permission = entry is String ? fromId(entry) : null;
      if (permission != null) result.add(permission);
    }
    return result;
  }
}

/// The fixed preset a landlord on a tier without custom roles (Pro) grants —
/// the full operational set. Mirrors `STANDARD_STAFF_PERMISSIONS` on the server.
const Set<StaffPermission> standardStaffPermissions = {
  StaffPermission.manageProperties,
  StaffPermission.manageTenants,
  StaffPermission.manageBilling,
  StaffPermission.manageMaintenance,
  StaffPermission.manageListings,
  StaffPermission.manageCommunication,
  StaffPermission.manageDocuments,
  StaffPermission.viewReports,
};
