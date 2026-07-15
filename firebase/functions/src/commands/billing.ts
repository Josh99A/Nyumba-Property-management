import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { requireActiveLandlord, requireOwnedByLandlord } from '../shared/accounts';
import { COLLECTIONS, TENANT_PORTAL_SECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import { createJob, idSchema, nonNegativeMoney, shortText, strictPayload, type CommandHandler } from '../shared/handlers';
import {
  tenantInvoiceProjection,
  tenantPaymentProjection,
  tenantReceiptProjection,
} from '../shared/projections';

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
    const invoice = requireAggregate<{ version: number; landlordId: string; balanceMinor: number; tenantUserUid?: string | null }>(invoiceSnap, undefined);
    requireOwnedByLandlord(invoice, landlord.landlordId);
    if (cmd.payload.amountMinor > invoice.balanceMinor) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'amountExceedsBalance' });
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
      tenantUserUid: invoice.tenantUserUid ?? null, receiptNumber, amountMinor: cmd.payload.amountMinor,
      currency: 'UGX', issuedAt: now, renderState: 'pending',
    };
    tx.create(paymentRef, payment);
    tx.create(db.collection(COLLECTIONS.receipts).doc(receiptId), receipt);
    tx.update(invoiceRef, { balanceMinor: nextBalance, status: nextStatus, ...bumpVersion(invoice, now) });
    tx.update(db.collection(COLLECTIONS.landlordAccounts).doc(landlord.landlordId), {
      receiptCounter: receiptNumber, ...bumpVersion(landlord.account, now),
    });
    if (invoice.tenantUserUid) {
      const portal = db.collection(COLLECTIONS.tenantPortals).doc(invoice.tenantUserUid);
      tx.set(portal.collection(TENANT_PORTAL_SECTIONS.payments).doc(cmd.aggregateId!), tenantPaymentProjection(payment));
      tx.set(portal.collection(TENANT_PORTAL_SECTIONS.receipts).doc(receiptId), tenantReceiptProjection(receipt));
      tx.set(portal.collection(TENANT_PORTAL_SECTIONS.invoices).doc(cmd.payload.invoiceId), tenantInvoiceProjection({
        ...invoice, balanceMinor: nextBalance, status: nextStatus, ...bumpVersion(invoice, now),
      }));
    }
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: 1, safeResult: { receiptId, receiptNumber }, changedFields: ['status', 'confirmedAt', 'allocations', 'receiptId'] };
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
