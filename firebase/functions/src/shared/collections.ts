/** Firestore collection names shared across handlers, workers, and tests. */
export const COLLECTIONS = {
  users: 'users',
  landlordAccounts: 'landlordAccounts',
  staffInvites: 'staffInvites',
  staffMemberships: 'staffMemberships',
  subscriptions: 'subscriptions',
  planCatalog: 'planCatalog',
  properties: 'properties',
  units: 'units',
  tenantRecords: 'tenantRecords',
  leases: 'leases',
  invoices: 'invoices',
  payments: 'payments',
  receipts: 'receipts',
  maintenanceRequests: 'maintenanceRequests',
  notices: 'notices',
  documents: 'documents',
  privateListings: 'privateListings',
  publicListings: 'publicListings',
  applications: 'applications',
  contactRequests: 'contactRequests',
  reportSnapshots: 'reportSnapshots',
  commandReceipts: 'commandReceipts',
  auditLogs: 'auditLogs',
  backendJobs: 'backendJobs',
  backendJobDedupe: 'backendJobDedupe',
  providerEvents: 'providerEvents',
  backendConfig: 'backendConfig',
  platformBroadcasts: 'platformBroadcasts',
  deviceTokenOwners: 'deviceTokenOwners',
  notificationInboxes: 'notificationInboxes',
  tenantPortals: 'tenantPortals',
  clientPortals: 'clientPortals',
  landlordPortals: 'landlordPortals',
  // Reputation. `landlordReviews` is canonical and carries the reviewer's UID,
  // so it is admin-only; everything a browser sees comes from the two `public*`
  // mirrors, which are keyed by the same opaque `landlordToken` the public
  // listing exposes rather than by the landlord's UID.
  landlordReviews: 'landlordReviews',
  landlordRatings: 'landlordRatings',
  publicReviews: 'publicReviews',
  publicLandlordRatings: 'publicLandlordRatings',
  /** Landlord-to-Nyumba product feedback. Never public, never reciprocal. */
  platformFeedback: 'platformFeedback',
  /**
   * Landlord ↔ Nyumba support conversations. Unlike `platformFeedback`, the
   * landlord reads these back: a support thread is their own record of a
   * conversation, with a status and a reply they are waiting on.
   */
  supportTickets: 'supportTickets',
} as const;

export const TENANT_PORTAL_SECTIONS = {
  leases: 'leases',
  invoices: 'invoices',
  payments: 'payments',
  receipts: 'receipts',
  maintenance: 'maintenance',
  notices: 'notices',
  documents: 'documents',
  reviews: 'reviews',
} as const;

export const CLIENT_PORTAL_SECTIONS = {
  applications: 'applications',
  contactRequests: 'contactRequests',
} as const;

export const LANDLORD_PORTAL_SECTIONS = {
  tenancies: 'tenancies',
  payments: 'payments',
  reviews: 'reviews',
} as const;
