import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { requireActiveLandlord, requireOwnedByLandlord } from '../shared/accounts';
import { COLLECTIONS, LANDLORD_PORTAL_SECTIONS, TENANT_PORTAL_SECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import { createJob, idSchema, nonNegativeMoney, shortText, strictPayload, type CommandHandler } from '../shared/handlers';
import {
  landlordPaymentProjection,
  landlordTenancyProjection,
  tenantInvoiceProjection,
  tenantPaymentProjection,
  tenantReceiptProjection,
} from '../shared/projections';

/** Denormalized names every landlord payment projection carries. */
interface TenancyLabels {
  tenantName: string;
  unitLabel: string;
  propertyName: string;
}

/**
 * Rebuilds the names (and identifiers) a landlord read model needs by joining
 * the canonical records, for leases whose tenancy view was never written
 * (lease.create predates the view; tenancy.establish always writes one).
 *
 * Must run before the caller's first buffered write: a transaction cannot
 * read after it writes.
 */
async function reconstructTenancyLabels(
  tx: Transaction,
  db: Firestore,
  lease: { tenantRecordId?: unknown; unitId?: unknown },
): Promise<TenancyLabels & { propertyId: string; email: string; phone: string }> {
  const tenantRecordId = typeof lease.tenantRecordId === 'string' ? lease.tenantRecordId : null;
  const unitId = typeof lease.unitId === 'string' ? lease.unitId : null;
  const [tenantSnap, unitSnap] = await Promise.all([
    tenantRecordId ? tx.get(db.collection(COLLECTIONS.tenantRecords).doc(tenantRecordId)) : null,
    unitId ? tx.get(db.collection(COLLECTIONS.units).doc(unitId)) : null,
  ]);
  const tenant = tenantSnap?.data();
  const unit = unitSnap?.data();
  const propertyId = typeof unit?.propertyId === 'string' ? unit.propertyId : null;
  const propertySnap = propertyId
    ? await tx.get(db.collection(COLLECTIONS.properties).doc(propertyId))
    : null;
  return {
    tenantName: String(tenant?.displayName ?? 'Tenant'),
    email: String(tenant?.email ?? ''),
    phone: String(tenant?.phone ?? ''),
    unitLabel: String(unit?.label ?? 'Unit'),
    propertyName: String(propertySnap?.data()?.name ?? 'Property'),
    propertyId: propertyId ?? '',
  };
}

/**
 * Human label for the billing period a manual payment settles. The client
 * requires a non-empty period; invoices carry either an explicit one (opening
 * balances) or a due date to derive a month from.
 */
function invoicePeriodLabel(invoice: { period?: unknown; dueDate?: unknown }): string {
  if (typeof invoice.period === 'string' && invoice.period) return invoice.period;
  const month = typeof invoice.dueDate === 'string' ? invoice.dueDate.slice(0, 7) : '';
  return month || 'Unscheduled';
}

const lineItemSchema = z.object({ description: shortText, amountMinor: nonNegativeMoney }).strict();
const invoiceSchema = strictPayload({
  leaseId: idSchema,
  dueDate: z.string().datetime(),
  lineItems: z.array(lineItemSchema).min(1).max(50),
  memo: z.string().trim().max(1_000).optional(),
});

export const invoiceGenerate: CommandHandler<z.infer<typeof invoiceSchema>> = {
  payloadSchema: invoiceSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const invoiceRef = db.collection(COLLECTIONS.invoices).doc(cmd.aggregateId!);
    const leaseRef = db.collection(COLLECTIONS.leases).doc(cmd.payload.leaseId);
    const [invoiceSnap, leaseSnap] = await Promise.all([tx.get(invoiceRef), tx.get(leaseRef)]);
    requireAbsent(invoiceSnap);
    const lease = requireAggregate<{ version: number; landlordId: string; tenantUserUid?: string | null; status: string }>(leaseSnap, undefined);
    requireOwnedByLandlord(lease, landlord.landlordId);
    if (lease.status !== 'active') throw new DomainError('VALIDATION_FAILED', { reason: 'leaseNotActive' });
    const totalMinor = cmd.payload.lineItems.reduce((sum, line) => sum + line.amountMinor, 0);
    if (!Number.isSafeInteger(totalMinor)) throw new DomainError('VALIDATION_FAILED', { fields: ['lineItems'] });
    const invoice = {
      ...newAggregate(cmd.aggregateId!, now), landlordId: landlord.landlordId, leaseId: cmd.payload.leaseId,
      tenantUserUid: lease.tenantUserUid ?? null, dueDate: cmd.payload.dueDate, lineItems: cmd.payload.lineItems,
      memo: cmd.payload.memo ?? null, totalMinor, balanceMinor: totalMinor, currency: 'UGX', status: 'due',
    };
    tx.create(invoiceRef, invoice);
    if (lease.tenantUserUid) {
      tx.set(db.collection(COLLECTIONS.tenantPortals).doc(lease.tenantUserUid).collection(TENANT_PORTAL_SECTIONS.invoices).doc(cmd.aggregateId!), tenantInvoiceProjection(invoice));
    }
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: 1, safeResult: { totalMinor }, changedFields: ['lineItems', 'totalMinor', 'balanceMinor', 'status'] };
  },
};

const manualPaymentSchema = strictPayload({
  invoiceId: idSchema,
  amountMinor: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
  method: z.enum(['cash', 'bank_transfer', 'mtn_momo', 'airtel_money']),
  reference: z.string().trim().max(200).optional(),
});

export const paymentRecordManual: CommandHandler<z.infer<typeof manualPaymentSchema>> = {
  payloadSchema: manualPaymentSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const paymentRef = db.collection(COLLECTIONS.payments).doc(cmd.aggregateId!);
    const invoiceRef = db.collection(COLLECTIONS.invoices).doc(cmd.payload.invoiceId);
    const [paymentSnap, invoiceSnap] = await Promise.all([tx.get(paymentRef), tx.get(invoiceRef)]);
    requireAbsent(paymentSnap);
    const invoice = requireAggregate<{ version: number; landlordId: string; balanceMinor: number; tenantUserUid?: string | null; leaseId?: string; period?: string; dueDate?: string }>(invoiceSnap, undefined);
    requireOwnedByLandlord(invoice, landlord.landlordId);
    if (cmd.payload.amountMinor > invoice.balanceMinor) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'amountExceedsBalance' });
    }
    // Reads must precede the first buffered write. The invoice's lease keys the
    // tenancy view carrying the names the landlord payment projection needs;
    // when the view is missing the canonical records rebuild them, so an
    // accepted payment never commits without its landlord read model.
    const leaseId = typeof invoice.leaseId === 'string' ? invoice.leaseId : null;
    let labels: TenancyLabels | null = null;
    if (leaseId) {
      const tenancyView = (await tx.get(
        db.collection(COLLECTIONS.landlordPortals).doc(landlord.landlordId)
          .collection(LANDLORD_PORTAL_SECTIONS.tenancies).doc(leaseId),
      )).data();
      if (tenancyView) {
        labels = {
          tenantName: String(tenancyView.tenantName ?? ''),
          unitLabel: String(tenancyView.unitLabel ?? ''),
          propertyName: String(tenancyView.propertyName ?? ''),
        };
      } else {
        const lease = (await tx.get(db.collection(COLLECTIONS.leases).doc(leaseId))).data();
        if (lease) labels = await reconstructTenancyLabels(tx, db, lease);
      }
    }
    const receiptNumber = landlord.account.receiptCounter + 1;
    const receiptId = `${cmd.aggregateId!}_receipt`;
    const nextBalance = invoice.balanceMinor - cmd.payload.amountMinor;
    const nextStatus = nextBalance === 0 ? 'paid' : 'part_paid';
    const payment = {
      ...newAggregate(cmd.aggregateId!, now), landlordId: landlord.landlordId, invoiceId: cmd.payload.invoiceId,
      tenantUserUid: invoice.tenantUserUid ?? null, amountMinor: cmd.payload.amountMinor, currency: 'UGX',
      method: cmd.payload.method, reference: cmd.payload.reference ?? null, status: 'confirmed', confirmedAt: now,
      allocations: [{ invoiceId: cmd.payload.invoiceId, amountMinor: cmd.payload.amountMinor }], receiptId,
    };
    const receipt = {
      ...newAggregate(receiptId, now), landlordId: landlord.landlordId, paymentId: cmd.aggregateId!,
      tenantUserUid: invoice.tenantUserUid ?? null, receiptNumber: formatReceiptNumber(receiptNumber),
      amountMinor: cmd.payload.amountMinor, currency: 'UGX', issuedAt: now, renderState: 'pending',
    };
    tx.create(paymentRef, payment);
    tx.create(db.collection(COLLECTIONS.receipts).doc(receiptId), receipt);
    tx.update(invoiceRef, { balanceMinor: nextBalance, status: nextStatus, ...bumpVersion(invoice, now) });
    tx.update(db.collection(COLLECTIONS.landlordAccounts).doc(landlord.landlordId), {
      receiptCounter: receiptNumber, ...bumpVersion(landlord.account, now),
    });
    createJob(tx, db, `${cmd.commandId}_render`, 'renderReceipt', { receiptId }, now);
    createJob(tx, db, `${cmd.commandId}_receipt_email`, 'sendPaymentReceiptEmail', { receiptId }, now);
    if (invoice.tenantUserUid) {
      const portal = db.collection(COLLECTIONS.tenantPortals).doc(invoice.tenantUserUid);
      tx.set(portal.collection(TENANT_PORTAL_SECTIONS.payments).doc(cmd.aggregateId!), tenantPaymentProjection(payment));
      tx.set(portal.collection(TENANT_PORTAL_SECTIONS.receipts).doc(receiptId), tenantReceiptProjection(receipt));
      tx.set(portal.collection(TENANT_PORTAL_SECTIONS.invoices).doc(cmd.payload.invoiceId), tenantInvoiceProjection({
        ...invoice, balanceMinor: nextBalance, status: nextStatus, ...bumpVersion(invoice, now),
      }));
    }
    // The landlord read model mirrors what payment.recordAgainstTenancy
    // writes, so a manually recorded payment also survives a second-device
    // pull instead of existing only in the canonical collection.
    if (leaseId && labels) {
      tx.set(
        db.collection(COLLECTIONS.landlordPortals).doc(landlord.landlordId)
          .collection(LANDLORD_PORTAL_SECTIONS.payments).doc(cmd.aggregateId!),
        landlordPaymentProjection({
          paymentId: cmd.aggregateId!,
          version: 1,
          landlordId: landlord.landlordId,
          tenancyId: leaseId,
          receiptNumber: formatReceiptNumber(receiptNumber),
          tenantName: labels.tenantName,
          unitLabel: labels.unitLabel,
          propertyName: labels.propertyName,
          amountMinor: cmd.payload.amountMinor,
          method: cmd.payload.method,
          period: invoicePeriodLabel(invoice),
          paidOn: now,
          createdAt: now,
          updatedAt: now,
        }),
      );
    }
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: 1, safeResult: { receiptId, receiptNumber: formatReceiptNumber(receiptNumber) }, changedFields: ['status', 'confirmedAt', 'allocations', 'receiptId'] };
  },
};

const recordAgainstTenancySchema = strictPayload({
  tenancyId: idSchema,
  amountMinor: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
  method: z.enum(['cash', 'bank_transfer', 'mtn_momo', 'airtel_money']),
  period: shortText,
  reference: z.string().trim().max(200).optional(),
});

interface OpenInvoice {
  id: string;
  version: number;
  balanceMinor: number;
  dueDate: string;
  status: string;
  isDeleted?: boolean;
}

/**
 * Records rent received against a tenancy, without the landlord ever issuing an
 * invoice by hand.
 *
 * Nyumba's product model is a running tenancy balance, not an invoice ledger:
 * landlords record cash/MoMo as it arrives. Invoices remain the server's
 * internal accounting unit (they are what makes a balance settleable and
 * auditable), so this command allocates the payment across the tenancy's open
 * invoices oldest-first.
 *
 * Nothing in the product accrues rent into new invoices, so once the opening
 * balance is settled a payment has nothing to settle and is retained in full as
 * `creditMinor`. That is deliberate: the money was genuinely received but is not
 * owed against anything, and the client floors its tenancy balance at zero, so
 * both sides agree the balance is nil. Introducing periodic rent invoices is a
 * product decision, not something this command should invent.
 *
 * The receipt number comes from the landlord's server-side counter. A client
 * cannot author one: two offline devices would mint the same number.
 */
/**
 * Facts a settlement needs, whichever command is settling.
 *
 * `existing` marks the confirmation of a payment the tenant already declared:
 * that document is updated in place rather than created, and the declaration
 * is preserved on it.
 */
interface SettleTenancyPaymentParams {
  paymentId: string;
  tenancyId: string;
  amountMinor: number;
  method: string;
  period: string;
  reference: string | null;
  commandId: string;
  existing?: { version: number; declaredByUid: string | null };
}

interface SettlementOutcome {
  receiptId: string;
  receiptNumber: string;
  creditMinor: number;
  serverVersion: number;
}

/**
 * Allocates money across a tenancy's open invoices, issues the receipt, and
 * refreshes both portals.
 *
 * Shared by the landlord recording a payment directly and by the landlord
 * confirming one their tenant declared, so the two can never settle the same
 * money differently — a drift between them would show up as a wrong balance
 * or a missing receipt, which is the worst class of bug this product can have.
 *
 * Callers must have read (and validated) the payment document already; every
 * remaining read happens here before the first buffered write.
 */
async function settleTenancyPayment(
  tx: Transaction,
  db: Firestore,
  landlord: Awaited<ReturnType<typeof requireActiveLandlord>>,
  params: SettleTenancyPaymentParams,
  now: FirebaseFirestore.Timestamp,
): Promise<SettlementOutcome> {
  const paymentRef = db.collection(COLLECTIONS.payments).doc(params.paymentId);
  const leaseRef = db.collection(COLLECTIONS.leases).doc(params.tenancyId);
  const tenancyViewRef = db.collection(COLLECTIONS.landlordPortals).doc(landlord.landlordId)
    .collection(LANDLORD_PORTAL_SECTIONS.tenancies).doc(params.tenancyId);

  // Every read must precede the first buffered write in a transaction.
  const [leaseSnap, invoiceSnap, tenancyViewSnap] = await Promise.all([
    tx.get(leaseRef),
    tx.get(db.collection(COLLECTIONS.invoices).where('leaseId', '==', params.tenancyId).limit(50)),
    tx.get(tenancyViewRef),
  ]);
  const lease = requireAggregate<{ version: number; landlordId: string; status: string; tenantUserUid?: string | null; tenantRecordId?: string; unitId?: string; startDate?: string; endDate?: string; monthlyRentMinor?: number }>(leaseSnap, undefined);
  requireOwnedByLandlord(lease, landlord.landlordId);
  if (lease.status !== 'active') throw new DomainError('VALIDATION_FAILED', { reason: 'leaseNotActive' });
  // limit(50) bounds the transaction, and nothing in the product accrues
  // invoices per tenancy, so a saturated window means data this command does
  // not understand. Allocating oldest-first over a truncated set could settle
  // the wrong invoices; reject deterministically instead of guessing.
  if (invoiceSnap.size >= 50) {
    throw new DomainError('VALIDATION_FAILED', { reason: 'openInvoiceWindowExceeded' });
  }
  const tenancyView = tenancyViewSnap.data();
  // Also a read, so it too must precede the allocation writes below. A lease
  // whose view was never written (lease.create) is rebuilt rather than
  // skipped: the projection written further down is the only record of this
  // payment a second device can pull.
  const rebuilt = tenancyView ? null : await reconstructTenancyLabels(tx, db, lease);
  const labels: TenancyLabels = tenancyView
    ? {
      tenantName: String(tenancyView.tenantName ?? ''),
      unitLabel: String(tenancyView.unitLabel ?? ''),
      propertyName: String(tenancyView.propertyName ?? ''),
    }
    : rebuilt!;

  const openInvoices = invoiceSnap.docs
    .map((doc) => doc.data() as OpenInvoice)
    .filter((invoice) => invoice.isDeleted !== true && invoice.balanceMinor > 0)
    .sort((left, right) => left.dueDate.localeCompare(right.dueDate));
  const outstandingBeforeMinor = openInvoices.reduce(
    (total, invoice) => total + invoice.balanceMinor,
    0,
  );

  // Allocate oldest-first. Money that is genuinely in hand must never be
  // rejected for exceeding the outstanding balance, so any surplus is retained
  // as an explicit credit rather than refused. This mirrors the client, which
  // already floors a tenancy balance at zero.
  const allocations: { invoiceId: string; amountMinor: number }[] = [];
  let unallocatedMinor = params.amountMinor;
  for (const invoice of openInvoices) {
    if (unallocatedMinor <= 0) break;
    const applied = Math.min(unallocatedMinor, invoice.balanceMinor);
    const nextBalance = invoice.balanceMinor - applied;
    allocations.push({ invoiceId: invoice.id, amountMinor: applied });
    unallocatedMinor -= applied;
    tx.update(db.collection(COLLECTIONS.invoices).doc(invoice.id), {
      balanceMinor: nextBalance,
      status: nextBalance === 0 ? 'paid' : 'part_paid',
      ...bumpVersion(invoice, now),
    });
    if (lease.tenantUserUid) {
      tx.set(
        db.collection(COLLECTIONS.tenantPortals).doc(lease.tenantUserUid)
          .collection(TENANT_PORTAL_SECTIONS.invoices).doc(invoice.id),
        tenantInvoiceProjection({ ...invoice, balanceMinor: nextBalance, status: nextBalance === 0 ? 'paid' : 'part_paid', ...bumpVersion(invoice, now) }),
      );
    }
  }

  const receiptNumber = landlord.account.receiptCounter + 1;
  const receiptId = `${params.paymentId}_receipt`;
  const serverVersion = params.existing ? params.existing.version + 1 : 1;
  const settled = {
    landlordId: landlord.landlordId,
    leaseId: params.tenancyId,
    invoiceId: allocations[0]?.invoiceId ?? null,
    tenantUserUid: lease.tenantUserUid ?? null,
    amountMinor: params.amountMinor,
    currency: 'UGX',
    method: params.method,
    period: params.period,
    reference: params.reference,
    status: 'confirmed',
    confirmedAt: now,
    allocations,
    creditMinor: unallocatedMinor,
    receiptId,
  };
  const payment = params.existing
    ? {
      ...settled,
      id: params.paymentId,
      declaredByUid: params.existing.declaredByUid,
      version: serverVersion,
      updatedAt: now,
      isDeleted: false,
    }
    : { ...newAggregate(params.paymentId, now), ...settled };
  const receipt = {
    ...newAggregate(receiptId, now),
    landlordId: landlord.landlordId,
    paymentId: params.paymentId,
    tenantUserUid: lease.tenantUserUid ?? null,
    receiptNumber: formatReceiptNumber(receiptNumber),
    amountMinor: params.amountMinor,
    currency: 'UGX',
    issuedAt: now,
    renderState: 'pending',
  };
  if (params.existing) {
    tx.update(paymentRef, {
      ...settled,
      version: serverVersion,
      updatedAt: now,
    });
  } else {
    tx.create(paymentRef, payment);
  }
  tx.create(db.collection(COLLECTIONS.receipts).doc(receiptId), receipt);
  tx.update(db.collection(COLLECTIONS.landlordAccounts).doc(landlord.landlordId), {
    receiptCounter: receiptNumber,
    ...bumpVersion(landlord.account, now),
  });
  createJob(tx, db, `${params.commandId}_render`, 'renderReceipt', { receiptId }, now);
  createJob(tx, db, `${params.commandId}_receipt_email`, 'sendPaymentReceiptEmail', { receiptId }, now);
  if (lease.tenantUserUid) {
    const portal = db.collection(COLLECTIONS.tenantPortals).doc(lease.tenantUserUid);
    tx.set(portal.collection(TENANT_PORTAL_SECTIONS.payments).doc(params.paymentId), tenantPaymentProjection(payment));
    tx.set(portal.collection(TENANT_PORTAL_SECTIONS.receipts).doc(receiptId), tenantReceiptProjection(receipt));
  }

  // Landlord read models. The tenancy view carries the names this payment
  // needs, and is also where the landlord's balance is corrected: the device
  // decremented its own copy optimistically, and this is the value that
  // overwrites it. An accepted payment always commits with its projection.
  const landlordPortal = db.collection(COLLECTIONS.landlordPortals).doc(landlord.landlordId);
  // Surplus beyond what was owed is a credit, not a negative balance, so
  // only the allocated part reduces the outstanding total.
  const allocatedMinor = params.amountMinor - unallocatedMinor;
  const remainingBalanceMinor = outstandingBeforeMinor - allocatedMinor;
  tx.set(
    landlordPortal.collection(LANDLORD_PORTAL_SECTIONS.payments).doc(params.paymentId),
    landlordPaymentProjection({
      paymentId: params.paymentId,
      version: serverVersion,
      landlordId: landlord.landlordId,
      tenancyId: params.tenancyId,
      receiptNumber: formatReceiptNumber(receiptNumber),
      tenantName: labels.tenantName,
      unitLabel: labels.unitLabel,
      propertyName: labels.propertyName,
      amountMinor: params.amountMinor,
      method: params.method,
      period: params.period,
      paidOn: now,
      createdAt: now,
      updatedAt: now,
    }),
  );
  if (tenancyView) {
    tx.update(tenancyViewRef, {
      balanceMinor: remainingBalanceMinor,
      version: Number(tenancyView.version ?? 1) + 1,
      updatedAt: now,
    });
  } else {
    // Repair the missing view while the joined records are at hand, so the
    // next payment (and the landlord's next pull) finds it in place.
    tx.set(tenancyViewRef, landlordTenancyProjection({
      leaseId: params.tenancyId,
      version: 1,
      landlordId: landlord.landlordId,
      tenantUserUid: lease.tenantUserUid ?? null,
      propertyId: rebuilt!.propertyId,
      unitId: String(lease.unitId ?? ''),
      tenantName: rebuilt!.tenantName,
      email: rebuilt!.email,
      phone: rebuilt!.phone,
      unitLabel: rebuilt!.unitLabel,
      propertyName: rebuilt!.propertyName,
      monthlyRentMinor: Number(lease.monthlyRentMinor ?? 0),
      balanceMinor: remainingBalanceMinor,
      leaseStart: String(lease.startDate ?? ''),
      leaseEnd: String(lease.endDate ?? ''),
      status: 'active',
      createdAt: now,
      updatedAt: now,
    }));
  }
  return {
    receiptId,
    receiptNumber: formatReceiptNumber(receiptNumber),
    creditMinor: unallocatedMinor,
    serverVersion,
  };
}

export const paymentRecordAgainstTenancy: CommandHandler<z.infer<typeof recordAgainstTenancySchema>> = {
  payloadSchema: recordAgainstTenancySchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const paymentRef = db.collection(COLLECTIONS.payments).doc(cmd.aggregateId!);
    requireAbsent(await tx.get(paymentRef));
    const outcome = await settleTenancyPayment(tx, db, landlord, {
      paymentId: cmd.aggregateId!,
      tenancyId: cmd.payload.tenancyId,
      amountMinor: cmd.payload.amountMinor,
      method: cmd.payload.method,
      period: cmd.payload.period,
      reference: cmd.payload.reference ?? null,
      commandId: cmd.commandId,
    }, now);
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: outcome.serverVersion,
      safeResult: {
        receiptId: outcome.receiptId,
        receiptNumber: outcome.receiptNumber,
        creditMinor: outcome.creditMinor,
      },
      changedFields: ['status', 'confirmedAt', 'allocations', 'receiptId'],
    };
  },
};


/** Stable, landlord-scoped receipt reference, e.g. `NYB-RCP-00842`. */
export function formatReceiptNumber(counter: number): string {
  return `NYB-RCP-${String(counter).padStart(5, '0')}`;
}

const declarePaymentSchema = strictPayload({
  tenancyId: idSchema,
  amountMinor: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
  method: z.enum(['cash', 'bank_transfer', 'mtn_momo', 'airtel_money']),
  period: shortText,
  /**
   * Proof of payment. Required — the landlord is being asked to accept money
   * on this evidence alone, so a declaration with nothing to check would just
   * move the guesswork onto them.
   */
  reference: shortText,
  note: z.string().trim().max(500).optional(),
});

interface DeclaredPaymentRecord {
  version: number;
  landlordId: string;
  leaseId: string;
  status: string;
  amountMinor: number;
  method: string;
  period: string;
  reference?: string | null;
  declaredByUid?: string | null;
}

/**
 * A tenant reports rent they have already paid, with proof.
 *
 * Nyumba cannot collect money yet, so rent is settled outside the app and
 * somebody has to tell it what happened. Until now only the landlord could,
 * which left a tenant who paid on the 1st invisible until the landlord got
 * around to recording it — and the tenant portal's own "Record payment" button
 * enqueued a landlord-only command that the server always rejected.
 *
 * A declaration is a claim, not a payment: it deliberately allocates nothing,
 * settles no invoice, moves no balance and issues no receipt. Otherwise a
 * tenant could clear their own arrears by asserting them away. The landlord
 * confirms it (which settles it through the same path as money they recorded
 * themselves) or rejects it with a reason.
 */
export const paymentDeclare: CommandHandler<z.infer<typeof declarePaymentSchema>> = {
  payloadSchema: declarePaymentSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const paymentRef = db.collection(COLLECTIONS.payments).doc(cmd.aggregateId!);
    const leaseRef = db.collection(COLLECTIONS.leases).doc(cmd.payload.tenancyId);
    const [paymentSnap, leaseSnap] = await Promise.all([tx.get(paymentRef), tx.get(leaseRef)]);
    requireAbsent(paymentSnap);
    const lease = requireAggregate<{
      version: number;
      landlordId: string;
      status: string;
      tenantUserUid?: string | null;
    }>(leaseSnap, undefined);
    // Only the tenant on the tenancy may declare against it, and only while
    // it is live: the lease is the authority, never a payload field.
    if (lease.tenantUserUid !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    if (lease.status !== 'active') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'leaseNotActive' });
    }
    const payment = {
      ...newAggregate(cmd.aggregateId!, now),
      landlordId: lease.landlordId,
      leaseId: cmd.payload.tenancyId,
      invoiceId: null,
      tenantUserUid: actor.uid,
      declaredByUid: actor.uid,
      amountMinor: cmd.payload.amountMinor,
      currency: 'UGX',
      method: cmd.payload.method,
      period: cmd.payload.period,
      reference: cmd.payload.reference,
      note: cmd.payload.note ?? null,
      // Never 'confirmed': nothing is settled until the landlord accepts it.
      status: 'declared',
      declaredAt: now,
      confirmedAt: null,
      allocations: [],
      receiptId: null,
    };
    tx.create(paymentRef, payment);
    tx.set(
      db.collection(COLLECTIONS.tenantPortals).doc(actor.uid)
        .collection(TENANT_PORTAL_SECTIONS.payments).doc(cmd.aggregateId!),
      tenantPaymentProjection(payment),
    );
    createJob(tx, db, `${cmd.commandId}_notify`, 'notifyLandlordPaymentDeclared', {
      paymentId: cmd.aggregateId!,
      landlordId: lease.landlordId,
    }, now);
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: 1,
      changedFields: ['status', 'declaredAt', 'reference'],
    };
  },
};

const confirmDeclaredSchema = strictPayload({});

/**
 * The landlord accepts a payment their tenant declared.
 *
 * Settles through the same helper as money the landlord recorded directly, so
 * a confirmed declaration produces exactly the same allocations, receipt and
 * balances — the tenant's proof is preserved on the payment as its reference.
 */
export const paymentConfirmDeclared: CommandHandler<Record<string, never>> = {
  payloadSchema: confirmDeclaredSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const paymentRef = db.collection(COLLECTIONS.payments).doc(cmd.aggregateId!);
    const snapshot = await tx.get(paymentRef);
    const declared = requireAggregate<DeclaredPaymentRecord>(snapshot, cmd.expectedVersion);
    requireOwnedByLandlord(declared, landlord.landlordId);
    if (declared.status !== 'declared') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'paymentNotAwaitingReview' });
    }
    const outcome = await settleTenancyPayment(tx, db, landlord, {
      paymentId: cmd.aggregateId!,
      tenancyId: declared.leaseId,
      amountMinor: declared.amountMinor,
      method: declared.method,
      period: declared.period,
      reference: declared.reference ?? null,
      commandId: cmd.commandId,
      existing: {
        version: declared.version,
        declaredByUid: declared.declaredByUid ?? null,
      },
    }, now);
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: outcome.serverVersion,
      safeResult: {
        receiptId: outcome.receiptId,
        receiptNumber: outcome.receiptNumber,
        creditMinor: outcome.creditMinor,
      },
      changedFields: ['status', 'confirmedAt', 'allocations', 'receiptId'],
    };
  },
};

const rejectDeclaredSchema = strictPayload({
  reasonCode: z.enum([
    'PAYMENT_NOT_RECEIVED',
    'AMOUNT_INCORRECT',
    'REFERENCE_INVALID',
    'DUPLICATE_DECLARATION',
    'LANDLORD_CORRECTION',
  ]),
  note: z.string().trim().max(500).optional(),
});

/**
 * The landlord rejects a payment their tenant declared.
 *
 * Nothing financial unwinds, because a declaration never settled anything —
 * only the claim is closed, with a reason the tenant can see and act on. The
 * record is kept rather than deleted: a disputed payment is exactly the thing
 * both sides need a history of.
 */
export const paymentRejectDeclared: CommandHandler<z.infer<typeof rejectDeclaredSchema>> = {
  payloadSchema: rejectDeclaredSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const paymentRef = db.collection(COLLECTIONS.payments).doc(cmd.aggregateId!);
    const snapshot = await tx.get(paymentRef);
    const declared = requireAggregate<DeclaredPaymentRecord>(snapshot, cmd.expectedVersion);
    requireOwnedByLandlord(declared, landlord.landlordId);
    if (declared.status !== 'declared') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'paymentNotAwaitingReview' });
    }
    const rejected = {
      status: 'rejected',
      rejectedAt: now,
      rejectionReasonCode: cmd.payload.reasonCode,
      rejectionNote: cmd.payload.note ?? null,
      ...bumpVersion(declared, now),
    };
    tx.update(paymentRef, rejected);
    if (declared.declaredByUid) {
      tx.set(
        db.collection(COLLECTIONS.tenantPortals).doc(declared.declaredByUid)
          .collection(TENANT_PORTAL_SECTIONS.payments).doc(cmd.aggregateId!),
        tenantPaymentProjection({ ...declared, ...rejected, id: cmd.aggregateId! }),
      );
    }
    createJob(tx, db, `${cmd.commandId}_notify`, 'notifyTenantPaymentRejected', {
      paymentId: cmd.aggregateId!,
      tenantUserUid: declared.declaredByUid ?? null,
    }, now);
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: declared.version + 1,
      changedFields: ['status', 'rejectedAt', 'rejectionReasonCode'],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

const initiateSchema = strictPayload({
  leaseId: idSchema,
  invoiceId: idSchema,
  amountMinor: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
  rail: z.enum(['mtn_momo', 'airtel_money']),
  payerPhone: z.string().regex(/^\+256\d{9}$/),
});

export const paymentInitiate: CommandHandler<z.infer<typeof initiateSchema>> = {
  payloadSchema: initiateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const paymentRef = db.collection(COLLECTIONS.payments).doc(cmd.aggregateId!);
    const leaseRef = db.collection(COLLECTIONS.leases).doc(cmd.payload.leaseId);
    const invoiceRef = db.collection(COLLECTIONS.invoices).doc(cmd.payload.invoiceId);
    const providerRef = db.collection(COLLECTIONS.backendConfig).doc('paymentProvider');
    const [paymentSnap, leaseSnap, invoiceSnap, providerSnap] = await Promise.all([
      tx.get(paymentRef), tx.get(leaseRef), tx.get(invoiceRef), tx.get(providerRef),
    ]);
    requireAbsent(paymentSnap);
    const lease = requireAggregate<{ version: number; tenantUserUid?: string | null; landlordId: string; status: string }>(leaseSnap, undefined);
    const invoice = requireAggregate<{ version: number; leaseId: string; landlordId: string; balanceMinor: number }>(invoiceSnap, undefined);
    if (lease.tenantUserUid !== actor.uid || lease.status !== 'active' || invoice.leaseId !== cmd.payload.leaseId) {
      throw new DomainError('PERMISSION_DENIED');
    }
    if (cmd.payload.amountMinor > invoice.balanceMinor) throw new DomainError('VALIDATION_FAILED', { reason: 'amountExceedsBalance' });
    if (!providerSnap.exists || providerSnap.data()?.enabled !== true) {
      throw new DomainError('PAYMENT_PROVIDER_UNAVAILABLE');
    }
    const payment = {
      ...newAggregate(cmd.aggregateId!, now), landlordId: lease.landlordId, leaseId: cmd.payload.leaseId,
      invoiceId: cmd.payload.invoiceId, tenantUserUid: actor.uid, amountMinor: cmd.payload.amountMinor,
      currency: 'UGX', rail: cmd.payload.rail, payerPhone: cmd.payload.payerPhone, status: 'pending',
    };
    tx.create(paymentRef, payment);
    createJob(tx, db, `${cmd.commandId}_provider`, 'initiatePayment', { paymentId: cmd.aggregateId!, providerKey: providerSnap.data()?.providerKey }, now);
    tx.set(db.collection(COLLECTIONS.tenantPortals).doc(actor.uid).collection(TENANT_PORTAL_SECTIONS.payments).doc(cmd.aggregateId!), tenantPaymentProjection(payment));
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: ['status'] };
  },
};

export const receiptRegenerate: CommandHandler<Record<string, never>> = {
  payloadSchema: strictPayload({}),
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const ref = db.collection(COLLECTIONS.receipts).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const receipt = requireAggregate<{ version: number; landlordId: string }>(snapshot, cmd.expectedVersion);
    requireOwnedByLandlord(receipt, landlord.landlordId);
    tx.update(ref, { renderState: 'pending', ...bumpVersion(receipt, now) });
    createJob(tx, db, `${cmd.commandId}_render`, 'renderReceipt', { receiptId: cmd.aggregateId! }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: receipt.version + 1, changedFields: ['renderState'] };
  },
};
