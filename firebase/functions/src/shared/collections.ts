/** Firestore collection names shared across handlers, workers, and tests. */
export const COLLECTIONS = {
  users: 'users',
  landlordAccounts: 'landlordAccounts',
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
  deviceTokenOwners: 'deviceTokenOwners',
  tenantPortals: 'tenantPortals',
  clientPortals: 'clientPortals',
  landlordPortals: 'landlordPortals',
} as const;

export const TENANT_PORTAL_SECTIONS = {
  leases: 'leases',
  invoices: 'invoices',
  payments: 'payments',
  receipts: 'receipts',
  maintenance: 'maintenance',
  notices: 'notices',
  documents: 'documents',
} as const;

export const CLIENT_PORTAL_SECTIONS = {
  applications: 'applications',
  contactRequests: 'contactRequests',
} as const;

export const LANDLORD_PORTAL_SECTIONS = {
  tenancies: 'tenancies',
  payments: 'payments',
} as const;
