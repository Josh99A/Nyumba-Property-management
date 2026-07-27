enum OfflineEntityType {
  userProfile('user_profiles', 5),
  property('properties', 10),
  unit('units', 20),
  tenancy('tenancies', 25),
  listing('listings', 30),
  // Server-owned public catalogue. Keep this separate from `listing`: the
  // private and public Firestore projections share document IDs and versions
  // but deliberately have different shapes, so merging them into one store
  // lets whichever listener arrives first overwrite the other.
  publicListing('public_listings', 31),
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
  staffInvite('staff_invites', 87),
  subscriptionPlan('subscription_plans', 90),
  planCatalog('plan_catalog', 92),
  adminAction('admin_actions', 95),

  /// A tenant's review of a landlord, keyed by the lease it describes.
  ///
  /// One store serves both the author's copy (`tenantPortals/{uid}/reviews`) and
  /// the reviewed landlord's (`landlordPortals/{uid}/reviews`). They are the same
  /// shape and a given account is only ever one of the two parties for a given
  /// lease, so they cannot collide — and the workspace is already scoped per
  /// account *and* active role.
  landlordReview('landlord_reviews', 96),

  /// The anonymous mirror browsed from the marketplace.
  ///
  /// Separate from [landlordReview] for the same reason [publicListing] is
  /// separate from [listing]: the two projections share document IDs but
  /// deliberately differ — the public copy carries no reviewer identity and no
  /// unit label — so merging them lets whichever listener arrives last erase the
  /// other's fields.
  publicReview('public_reviews', 97),

  /// Landlord-to-Nyumba product feedback. Write-only; nothing pulls it back.
  platformFeedback('platform_feedback', 98);

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
