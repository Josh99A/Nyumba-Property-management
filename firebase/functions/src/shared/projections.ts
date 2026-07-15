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
