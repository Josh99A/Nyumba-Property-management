import type { Firestore, Transaction } from 'firebase-admin/firestore';
import type { Actor } from './actor';
import { COLLECTIONS } from './collections';
import { DomainError } from './errors';
import { loadEntitlements, planForTier, type PlanEntitlements } from './config';

export type ApprovalStatus = 'pending' | 'approved' | 'suspended';
export type SubscriptionStatus =
  | 'pending_payment'
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
  activeStaffSeatCount: number;
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
 * Grantable staff capabilities — one per operational command group. The owner
 * implicitly holds all of them; a staff member holds whatever subset their
 * invite was granted. Owner-level surfaces (subscription, plan, staff
 * management, account lifecycle) are deliberately absent: they stay owner-only.
 */
export const STAFF_PERMISSIONS = [
  'manageProperties',
  'manageTenants',
  'manageBilling',
  'manageMaintenance',
  'manageListings',
  'manageCommunication',
  'manageDocuments',
  'viewReports',
] as const;

export type StaffPermission = (typeof STAFF_PERMISSIONS)[number];

/** The fixed preset granted on tiers without custom-role entitlement (Pro). */
export const STANDARD_STAFF_PERMISSIONS: readonly StaffPermission[] = STAFF_PERMISSIONS;

const STAFF_PERMISSION_SET: ReadonlySet<string> = new Set(STAFF_PERMISSIONS);

export function isStaffPermission(value: unknown): value is StaffPermission {
  return typeof value === 'string' && STAFF_PERMISSION_SET.has(value);
}

/** Keeps only recognised capabilities; unknown strings are dropped, not trusted. */
export function sanitizeStaffPermissions(value: unknown): StaffPermission[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<StaffPermission>();
  for (const entry of value) {
    if (isStaffPermission(entry)) seen.add(entry);
  }
  return [...seen];
}

/**
 * Deterministic membership doc id so Firestore Rules can authorize a staff
 * member's workspace reads with a single O(1) `exists()` on a known path.
 */
export function staffMembershipId(landlordId: string, memberUid: string): string {
  return `${landlordId}__${memberUid}`;
}

export interface WorkspaceContext extends LandlordContext {
  /** The signed-in actor performing the command (owner or staff uid). */
  actingUid: string;
  isOwner: boolean;
  permissions: readonly StaffPermission[];
}

/** Rejects a claimed role when the actor's mutable account is no longer active. */
export async function requireActiveAccount(
  tx: Transaction,
  db: Firestore,
  actor: Actor,
): Promise<void> {
  const snapshot = await tx.get(db.collection(COLLECTIONS.users).doc(actor.uid));
  const account = snapshot.data();
  if (
    !snapshot.exists
    || !account
    || account.status !== 'active'
    || account.isDeleted === true
  ) {
    throw new DomainError('PERMISSION_DENIED');
  }
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
  if (subscription.status !== 'active') {
    throw new DomainError('SUBSCRIPTION_INACTIVE', { status: subscription.status });
  }

  return {
    landlordId,
    account,
    subscription,
    entitlements: planForTier(entitlementsConfig, subscription.tier),
  };
}

/**
 * Resolves the actor to the workspace they may act in and authorizes the
 * requested capability. The workspace is the owner's aggregate in both cases:
 *
 *  - Owner path: `landlordAccounts/{actor.uid}` exists — the actor holds every
 *    capability.
 *  - Staff path: an active `staffMemberships` doc links this actor to an
 *    owner's `landlordId`; the granted permission set must include `capability`.
 *
 * Either way the returned context carries the OWNER's landlordId, account,
 * subscription and entitlements, so unit counts, the receipt counter and
 * ownership checks are unchanged — a staff command mutates the owner's
 * workspace exactly as the owner's would. Staff inherit the owner's approval
 * and subscription gating because `loadActiveLandlordContext` runs on the
 * owner's landlordId.
 *
 * v1 assumes a staff member belongs to a single workspace; commands carry no
 * target workspace, so the first active membership wins.
 */
export async function requireWorkspace(
  tx: Transaction,
  db: Firestore,
  actor: Actor,
  capability: StaffPermission,
): Promise<WorkspaceContext> {
  const ownerAccountSnap = await tx.get(
    db.collection(COLLECTIONS.landlordAccounts).doc(actor.uid),
  );
  const ownerAccount = ownerAccountSnap.data() as LandlordAccount | undefined;
  if (ownerAccountSnap.exists && ownerAccount?.ownerUid === actor.uid) {
    const context = await loadActiveLandlordContext(tx, db, actor.uid);
    return { ...context, actingUid: actor.uid, isOwner: true, permissions: STANDARD_STAFF_PERMISSIONS };
  }

  const membershipSnap = await tx.get(
    db
      .collection(COLLECTIONS.staffMemberships)
      .where('memberUid', '==', actor.uid)
      .where('active', '==', true)
      .limit(2),
  );
  if (membershipSnap.size > 1) {
    throw new DomainError('PERMISSION_DENIED', { reason: 'multipleWorkspaceMemberships' });
  }
  const membershipDoc = membershipSnap.docs[0];
  if (!membershipDoc) throw new DomainError('PERMISSION_DENIED');
  const membership = membershipDoc.data() as {
    landlordId?: unknown;
    permissions?: unknown;
  };
  if (typeof membership.landlordId !== 'string') throw new DomainError('PERMISSION_DENIED');
  const permissions = sanitizeStaffPermissions(membership.permissions);
  if (!permissions.includes(capability)) throw new DomainError('PERMISSION_DENIED');

  const context = await loadActiveLandlordContext(tx, db, membership.landlordId);
  return { ...context, actingUid: actor.uid, isOwner: false, permissions };
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
