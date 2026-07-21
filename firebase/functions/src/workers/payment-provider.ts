import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { COLLECTIONS, TENANT_PORTAL_SECTIONS } from '../shared/collections';
import { tenantPaymentProjection } from '../shared/projections';

export interface PaymentInitiationRequest {
  paymentId: string;
  amountMinor: number;
  currency: string;
  rail: 'mtn_momo' | 'airtel_money';
  payerPhone: string;
}

export interface PaymentInitiationResult {
  /** The provider's own reference, stored for reconciliation. */
  providerReference: string;
  /** Provider-side state right after initiation; terminal states arrive by webhook. */
  state: 'pending' | 'failed';
  failureReason?: string;
}

/**
 * A mobile-money aggregator. Implementations own their HTTP contract, retries,
 * and signature verification, and must be idempotent on `paymentId`: this
 * worker is at-least-once, so a duplicate initiate must not charge twice.
 */
export interface PaymentProviderAdapter {
  readonly key: string;
  initiate(request: PaymentInitiationRequest): Promise<PaymentInitiationResult>;
}

const adapters = new Map<string, PaymentProviderAdapter>();

/**
 * Registers a provider adapter at module load.
 *
 * No adapter ships today: the aggregator choice, fee model, reconciliation
 * policy, and webhook contract are all still TBD (docs/architecture/README.md).
 * Committing a speculative integration would mean untested code holding real
 * money, so the registry is deliberately empty and initiation fails closed
 * until a real adapter is registered here.
 *
 * Whatever is registered here collects **rent**, which is the landlord's money.
 * It must land in a landlord-owned destination (a provider subaccount or
 * equivalent), not in Nyumba's merchant balance to be forwarded later — Nyumba
 * only ever collects subscription payments. An adapter that pools rent
 * centrally is wrong even if it reconciles correctly.
 */
export function registerPaymentProvider(adapter: PaymentProviderAdapter): void {
  adapters.set(adapter.key, adapter);
}

/** Visible for tests; production registration happens at module load. */
export function clearPaymentProviders(): void {
  adapters.clear();
}

/**
 * Initiates a tenant-pushed mobile-money collection.
 *
 * Deliberately does not throw when no adapter is configured. Throwing would
 * burn eight retries and land in dead_letter, leaving the tenant staring at a
 * payment stuck on `pending` forever with nothing explaining why. Instead the
 * payment is moved to a terminal `failed` state with a reason the UI can render,
 * because a retry cannot conjure a provider that was never configured.
 */
export async function initiatePayment(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const paymentId = String(payload.paymentId);
  const providerKey = typeof payload.providerKey === 'string' ? payload.providerKey : '';
  const paymentRef = db.collection(COLLECTIONS.payments).doc(paymentId);
  const snapshot = await paymentRef.get();
  if (!snapshot.exists) return;
  const payment = snapshot.data()!;

  // The command already created the payment as pending; a replay after a lost
  // response must not re-initiate a collection that is already underway.
  if (payment.status !== 'pending') return;

  const adapter = adapters.get(providerKey);
  if (!adapter) {
    await failPayment(paymentId, payment, 'providerNotConfigured');
    return;
  }

  let result: PaymentInitiationResult;
  try {
    result = await adapter.initiate({
      paymentId,
      amountMinor: Number(payment.amountMinor),
      currency: String(payment.currency ?? 'UGX'),
      rail: payment.rail as 'mtn_momo' | 'airtel_money',
      payerPhone: String(payment.payerPhone),
    });
  } catch (error) {
    // A provider outage is genuinely transient: let the job retry with backoff
    // rather than failing a payment the tenant may still be able to make.
    throw error instanceof Error ? error : new Error('Payment provider call failed.');
  }

  if (result.state === 'failed') {
    await failPayment(paymentId, payment, result.failureReason ?? 'providerRejected');
    return;
  }
  await update(paymentId, payment, {
    providerReference: result.providerReference,
    providerKey,
    initiatedAt: Timestamp.now(),
  });
}

async function failPayment(
  paymentId: string,
  payment: FirebaseFirestore.DocumentData,
  reasonCode: string,
): Promise<void> {
  await update(paymentId, payment, {
    status: 'failed',
    failureReasonCode: reasonCode,
    failedAt: Timestamp.now(),
  });
}

/**
 * Writes the canonical payment and mirrors it to the tenant's portal in one
 * batch, so a retry after a partial failure can never leave the two views of
 * the payment disagreeing.
 */
async function update(
  paymentId: string,
  payment: FirebaseFirestore.DocumentData,
  changes: Record<string, unknown>,
): Promise<void> {
  const db = getFirestore();
  const now = Timestamp.now();
  const next = { ...payment, ...changes, version: Number(payment.version ?? 1) + 1, updatedAt: now };
  const batch = db.batch();
  batch.update(db.collection(COLLECTIONS.payments).doc(paymentId), {
    ...changes,
    version: next.version,
    updatedAt: now,
  });
  if (typeof payment.tenantUserUid === 'string') {
    batch.set(
      db
        .collection(COLLECTIONS.tenantPortals)
        .doc(payment.tenantUserUid)
        .collection(TENANT_PORTAL_SECTIONS.payments)
        .doc(paymentId),
      tenantPaymentProjection(next),
    );
  }
  await batch.commit();
}
