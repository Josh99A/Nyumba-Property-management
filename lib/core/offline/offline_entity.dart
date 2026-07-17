enum OfflineEntityType {
  userProfile('user_profiles', 5),
  property('properties', 10),
  unit('units', 20),
  tenancy('tenancies', 25),
  listing('listings', 30),
  application('applications', 40),
  invoice('invoices', 45),
  payment('payments', 50),
  maintenanceRequest('maintenance_requests', 60),

  /// Uploaded files: the server's `documents` collection, whose records carry a
  /// storage path, checksum, and byte size.
  document('documents', 70),

  /// The landlord's Documents screen index — invoice/receipt/lease/notice rows
  /// rendered to PDF on the device from data already held in other aggregates.
  ///
  /// Separate from [document] because they are unrelated things that merely
  /// share a name. They previously shared the `documents` store, so a pulled
  /// uploaded-file record and a locally rendered index row landed together and
  /// whichever mapper read second threw on the other's shape.
  leaseDocument('lease_documents', 75),

  notice('notices', 80),
  notification('app_notifications', 82),
  // `managedUser` is the admin-facing account directory. It is deliberately a
  // separate store from `userProfile`: both once shared `user_profiles`, so an
  // admin who saved their own settings wrote a UserSettings record that the
  // admin directory then tried to read back as a ManagedUser.
  managedUser('managed_users', 85),
  subscriptionPlan('subscription_plans', 90),
  adminAction('admin_actions', 95);

  const OfflineEntityType(this.storeName, this.syncPriority);

  final String storeName;
  final int syncPriority;
}

/// Why a local write carries no outbox intent. See [OfflineDatabase.putLocalEntity].
enum LocalOnlyReason {
  /// The server owns and recomputes this value; a remote pull replaces it.
  /// Some other mutation's outbox entry is the real sync intent.
  serverDerived,

  /// Working state with no canonical collection behind it, so no command
  /// could accept it. It lives and dies on this device.
  localWorkspaceOnly,
}

final class AggregateReference {
  const AggregateReference({required this.type, required this.id});

  final OfflineEntityType type;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is AggregateReference && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}
