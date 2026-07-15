import type { Firestore, Transaction } from 'firebase-admin/firestore';
import type { Actor } from './actor';
import { COLLECTIONS } from './collections';
import { DomainError } from './errors';
import { loadEntitlements, planForTier, type PlanEntitlements } from './config';

export type ApprovalStatus = 'pending' | 'approved' | 'suspended';
export type SubscriptionStatus =
  | 'trialing'
  | 'active'
  | 'past_due'
  | 'canceled'
  | 'expired'
  | 'none';

export interface LandlordAccount {
  id: string;
  ownerUid: string;
  approvalStatus: ApprovalStatus;
  approvalReasonCode?: string;
  activeUnitCount: number;
  activeListingCount: number;
  receiptCounter: number;
  version: number;
}

export interface Subscription {
  tier: string;
  status: SubscriptionStatus;
  version: number;
}

export interface LandlordContext {
  landlordId: string;
  account: LandlordAccount;
  subscription: Subscription;
  entitlements: PlanEntitlements;
}

/**
 * Loads and authorizes the landlord acting on their own aggregate. The
 * landlord ID is always the actor UID — never a payload field. Approval and
 * subscription state are mutable server documents re-read on every command
 * so suspension or expiry applies without waiting for token refresh.
 */
export async function requireActiveLandlord(
  tx: Transaction,
  db: Firestore,
  actor: Actor,
): Promise<LandlordContext> {
  const landlordId = actor.uid;
  const context = await loadActiveLandlordContext(tx, db, landlordId);
  if (context.account.ownerUid !== actor.uid) {
    throw new DomainError('PERMISSION_DENIED');
  }
  return context;
}

/**
 * Loads mutable landlord state for an already-authorized staff workflow.
 * Callers must verify the actor has an Admin/Super Admin claim before using
 * this helper; the target landlord ID comes from a canonical aggregate or an
 * explicitly audited staff command.
 */
export async function loadActiveLandlordContext(
  tx: Transaction,
  db: Firestore,
  landlordId: string,
): Promise<LandlordContext> {
  const [accountSnap, subscriptionSnap, entitlementsConfig] = await Promise.all([
    tx.get(db.collection(COLLECTIONS.landlordAccounts).doc(landlordId)),
    tx.get(db.collection(COLLECTIONS.subscriptions).doc(landlordId)),
    loadEntitlements(tx, db),
  ]);

  const account = accountSnap.data() as LandlordAccount | undefined;
  if (!accountSnap.exists || !account) throw new DomainError('PERMISSION_DENIED');
  if (account.approvalStatus === 'suspended') throw new DomainError('ACCOUNT_SUSPENDED');
  if (account.approvalStatus !== 'approved') throw new DomainError('ACCOUNT_NOT_APPROVED');

  const subscription = subscriptionSnap.data() as Subscription | undefined;
  if (!subscriptionSnap.exists || !subscription) throw new DomainError('SUBSCRIPTION_INACTIVE');
  if (subscription.status !== 'active' && subscription.status !== 'trialing') {
    throw new DomainError('SUBSCRIPTION_INACTIVE', { status: subscription.status });
  }

  return {
    landlordId,
    account,
    subscription,
    entitlements: planForTier(entitlementsConfig, subscription.tier),
  };
}

/** Ownership check for canonical landlord documents already loaded in the transaction. */
export function requireOwnedByLandlord(
  record: object,
  landlordId: string,
): void {
  if ((record as { landlordId?: unknown }).landlordId !== landlordId) {
    throw new DomainError('PERMISSION_DENIED');
  }
}
