/**
 * Explicit per-actor projection whitelists. Canonical documents are never
 * copied wholesale into portals: every projected field is named here so a new
 * landlord-private field on a canonical record stays private by default.
 */

function pick(
  source: Record<string, unknown>,
  fields: readonly string[],
): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const field of fields) {
    if (source[field] !== undefined) result[field] = source[field];
  }
  return result;
}

const AGGREGATE_FIELDS = ['id', 'version', 'createdAt', 'updatedAt', 'isDeleted'] as const;

const TENANT_LEASE_FIELDS = [
  ...AGGREGATE_FIELDS,
  'unitId', 'startDate', 'endDate', 'monthlyRentMinor', 'depositMinor',
  'currency', 'status', 'activatedAt', 'endedAt',
] as const;

const TENANT_INVOICE_FIELDS = [
  ...AGGREGATE_FIELDS,
  'leaseId', 'dueDate', 'lineItems', 'memo', 'totalMinor', 'balanceMinor',
  'currency', 'status',
] as const;

const TENANT_PAYMENT_FIELDS = [
  ...AGGREGATE_FIELDS,
  'leaseId', 'invoiceId', 'amountMinor', 'currency', 'method', 'rail',
  'reference', 'status', 'confirmedAt', 'receiptId', 'allocations',
] as const;

const TENANT_RECEIPT_FIELDS = [
  ...AGGREGATE_FIELDS,
  'paymentId', 'receiptNumber', 'amountMinor', 'currency', 'issuedAt', 'renderState',
] as const;

const TENANT_MAINTENANCE_FIELDS = [
  ...AGGREGATE_FIELDS,
  'unitId', 'leaseId', 'title', 'description', 'category', 'priority',
  'status', 'statusNote', 'comments',
] as const;

const TENANT_NOTICE_FIELDS = [
  ...AGGREGATE_FIELDS,
  'title', 'body', 'publishState', 'publishedAt',
] as const;

const CLIENT_APPLICATION_FIELDS = [
  ...AGGREGATE_FIELDS,
  'listingId', 'displayName', 'email', 'phone', 'message', 'answers',
  'status', 'withdrawnAt',
] as const;

const CLIENT_CONTACT_FIELDS = [
  ...AGGREGATE_FIELDS,
  'listingId', 'displayName', 'email', 'phone', 'message', 'deliveryState',
] as const;

/**
 * Landlord read models.
 *
 * These differ in kind from the tenant/client projections above. Those exist to
 * *withhold* fields — the landlord's private data must not leak into a tenant's
 * portal, so they are strict whitelists over one canonical document.
 *
 * A landlord may already read every canonical document these are built from, so
 * these hide nothing. They exist because no single collection can reconstruct
 * what the client models: a Flutter `Tenancy` is a lease *joined with* its
 * tenant record, unit, and property, and a `RentPayment` carries the tenant and
 * property names that `payments` does not store. Joining four collections is
 * work the server must do once at write time, not work each client re-does on
 * every read while offline.
 *
 * Consequence: the field names below are the *client's*, not Firestore's, and
 * they are load-bearing. They must match the Dart mappers
 * (`TenancyMapper.fromJson`, `RentPaymentMapper.fromJson`) exactly — a rename on
 * either side breaks the read with a FormatException. `syncMetadata` is
 * deliberately absent: `OfflineDatabase.mergeRemoteEntity` supplies it.
 */
export interface LandlordTenancyView {
  leaseId: string;
  version: number;
  landlordId: string;
  tenantUserUid: string | null;
  propertyId: string;
  unitId: string;
  tenantName: string;
  email: string;
  phone: string;
  unitLabel: string;
  propertyName: string;
  monthlyRentMinor: number;
  balanceMinor: number;
  leaseStart: string;
  leaseEnd: string;
  status: 'active' | 'noticeGiven' | 'ended';
  createdAt: unknown;
  updatedAt: unknown;
}

export const landlordTenancyProjection = (view: LandlordTenancyView) => ({
  id: view.leaseId,
  version: view.version,
  landlordId: view.landlordId,
  tenantUserId: view.tenantUserUid,
  propertyId: view.propertyId,
  unitId: view.unitId,
  tenantName: view.tenantName,
  email: view.email,
  phone: view.phone,
  unitLabel: view.unitLabel,
  propertyName: view.propertyName,
  monthlyRentMinor: view.monthlyRentMinor,
  balanceMinor: view.balanceMinor,
  leaseStart: view.leaseStart,
  leaseEnd: view.leaseEnd,
  status: view.status,
  createdAt: view.createdAt,
  updatedAt: view.updatedAt,
});

export interface LandlordPaymentView {
  paymentId: string;
  version: number;
  landlordId: string;
  tenancyId: string;
  receiptNumber: string;
  tenantName: string;
  unitLabel: string;
  propertyName: string;
  amountMinor: number;
  method: string;
  period: string;
  paidOn: unknown;
  createdAt: unknown;
  updatedAt: unknown;
}

export const landlordPaymentProjection = (view: LandlordPaymentView) => ({
  id: view.paymentId,
  version: view.version,
  landlordId: view.landlordId,
  tenancyId: view.tenancyId,
  receiptNumber: view.receiptNumber,
  tenantName: view.tenantName,
  unitLabel: view.unitLabel,
  propertyName: view.propertyName,
  amountMinor: view.amountMinor,
  method: view.method,
  period: view.period,
  paidOn: view.paidOn,
  createdAt: view.createdAt,
  updatedAt: view.updatedAt,
});

export const tenantLeaseProjection = (lease: Record<string, unknown>) =>
  pick(lease, TENANT_LEASE_FIELDS);
export const tenantInvoiceProjection = (invoice: Record<string, unknown>) =>
  pick(invoice, TENANT_INVOICE_FIELDS);
export const tenantPaymentProjection = (payment: Record<string, unknown>) =>
  pick(payment, TENANT_PAYMENT_FIELDS);
export const tenantReceiptProjection = (receipt: Record<string, unknown>) =>
  pick(receipt, TENANT_RECEIPT_FIELDS);
export const tenantMaintenanceProjection = (request: Record<string, unknown>) =>
  pick(request, TENANT_MAINTENANCE_FIELDS);
export const tenantNoticeProjection = (notice: Record<string, unknown>) =>
  pick(notice, TENANT_NOTICE_FIELDS);
export const clientApplicationProjection = (application: Record<string, unknown>) =>
  pick(application, CLIENT_APPLICATION_FIELDS);
export const clientContactProjection = (contact: Record<string, unknown>) =>
  pick(contact, CLIENT_CONTACT_FIELDS);
