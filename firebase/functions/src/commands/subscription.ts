import { Timestamp, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { z } from 'zod';
import { bumpVersion, requireAggregate } from '../shared/aggregates';
import { requireActiveAccount } from '../shared/accounts';
import { requirePlatformAdmin } from '../shared/actor';
import { COLLECTIONS } from '../shared/collections';
import { loadEntitlements, planForTier } from '../shared/config';
import { DomainError } from '../shared/errors';
import { createJob, nonNegativeMoney, shortText, strictPayload, type CommandHandler } from '../shared/handlers';

interface SubscriptionRecord {
  version: number;
  status: string;
  tier: string;
  requestedTier?: string | null;
  upgradeBillingChannel?: string | null;
  upgradeState?: string | null;
  billingInterval?: string | null;
}

/**
 * How a landlord intends to pay for a plan change.
 *
 * `cash` is the manual path: an administrator verifies the physical money and
 * activates the upgrade. `mobile_money`/`card` are the electronic path: a real
 * aggregator collects the money and its signed webhook auto-activates the
 * upgrade with no administrator in the loop. Electronic collection fails
 * closed until an aggregator is configured (see `loadSubscriptionBilling`), so
 * a plan can never be upgraded without money actually moving.
 */
const BILLING_CHANNELS = ['mobile_money', 'card', 'cash'] as const;

/**
 * Server-owned electronic-billing configuration. Absent or `enabled !== true`
 * means no aggregator is wired, so electronic subscription payments fail
 * closed — mirroring `backendConfig/paymentProvider` for tenant rent.
 */
async function loadSubscriptionBilling(
  tx: Transaction,
  db: Firestore,
): Promise<{ enabled: boolean }> {
  const snapshot = await tx.get(db.collection(COLLECTIONS.backendConfig).doc('subscriptionBilling'));
  return { enabled: snapshot.data()?.enabled === true };
}

const selectPlanSchema = strictPayload({
  tier: z.string().trim().min(1).max(40),
});

/**
 * Records which plan a landlord intends to pay for.
 *
 * Self-service only while no payment is confirmed: once a subscription is
 * `active`, a tier change is a billing event with money attached, and it
 * belongs to `subscription.confirmPayment` (or the future provider webhook) —
 * never to the client. Status is deliberately untouchable here, so this
 * command can never open a workspace.
 */
export const subscriptionSelectPlan: CommandHandler<z.infer<typeof selectPlanSchema>> = {
  payloadSchema: selectPlanSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    if (cmd.aggregateId !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.subscriptions).doc(actor.uid);
    const [snapshot, entitlements] = await Promise.all([tx.get(ref), loadEntitlements(tx, db)]);
    const subscription = requireAggregate<SubscriptionRecord>(snapshot, cmd.expectedVersion);
    if (subscription.status === 'active') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'subscriptionAlreadyActive' });
    }
    // Unknown tiers fail closed exactly like every entitlement check.
    planForTier(entitlements, cmd.payload.tier);
    tx.update(ref, { tier: cmd.payload.tier, ...bumpVersion(subscription, now) });
    return {
      status: 'applied',
      aggregateId: actor.uid,
      serverVersion: subscription.version + 1,
      changedFields: ['tier'],
    };
  },
};

const requestUpgradeSchema = strictPayload({
  tier: z.string().trim().min(1).max(40),
  billingChannel: z.enum(BILLING_CHANNELS),
});

/**
 * Records which tier an active landlord wants to move to, and how they intend
 * to pay for it.
 *
 * The mirror of `subscription.selectPlan` for the paid side of the gate:
 * self-service, and deliberately powerless over entitlements. The current
 * tier, status, and every entitlement stay exactly as paid for until the
 * matching confirmation applies the change — so this command can never open
 * capacity nobody paid for. Re-requesting overwrites the previous request;
 * requesting the current tier is rejected rather than treated as a hidden
 * cancel.
 *
 * The chosen `billingChannel` decides how the upgrade is confirmed:
 *
 * - `cash`: the manual path. The request is parked as `awaiting_admin`, and an
 *   administrator activates it through `subscription.confirmPayment` once the
 *   physical money is verified.
 * - `mobile_money` / `card`: the electronic path. A real aggregator collects
 *   the money and its signed webhook activates the upgrade automatically, with
 *   no administrator in the loop. This fails closed with
 *   `PAYMENT_PROVIDER_UNAVAILABLE` until an aggregator is configured
 *   (`backendConfig/subscriptionBilling.enabled`), because simulating an
 *   electronic payment would activate a plan against money that never moved.
 */
export const subscriptionRequestUpgrade: CommandHandler<z.infer<typeof requestUpgradeSchema>> = {
  payloadSchema: requestUpgradeSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    if (cmd.aggregateId !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.subscriptions).doc(actor.uid);
    const [snapshot, entitlements, billing] = await Promise.all([
      tx.get(ref),
      loadEntitlements(tx, db),
      loadSubscriptionBilling(tx, db),
    ]);
    const subscription = requireAggregate<SubscriptionRecord>(snapshot, cmd.expectedVersion);
    // An unpaid subscription changes tier through selectPlan; a plan-change
    // request only means something once there is an active plan to keep.
    if (subscription.status !== 'active') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'subscriptionNotActive' });
    }
    if (cmd.payload.tier === subscription.tier) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'tierUnchanged' });
    }
    planForTier(entitlements, cmd.payload.tier);

    const channel = cmd.payload.billingChannel;
    // Electronic collection has no configured aggregator yet, so it fails
    // closed rather than parking an upgrade that nothing could ever confirm.
    if (channel !== 'cash' && !billing.enabled) {
      throw new DomainError('PAYMENT_PROVIDER_UNAVAILABLE');
    }
    const upgradeState = channel === 'cash' ? 'awaiting_admin' : 'awaiting_payment';
    tx.update(ref, {
      requestedTier: cmd.payload.tier,
      upgradeBillingChannel: channel,
      upgradeState,
      upgradeRequestedAt: now,
      ...bumpVersion(subscription, now),
    });
    return {
      status: 'applied',
      aggregateId: actor.uid,
      serverVersion: subscription.version + 1,
      changedFields: ['requestedTier', 'upgradeBillingChannel', 'upgradeState', 'upgradeRequestedAt'],
    };
  },
};

const confirmPaymentSchema = strictPayload({
  reference: shortText,
  tier: z.string().trim().min(1).max(40).optional(),
  billingInterval: z.enum(['monthly', 'yearly']).optional(),
});

/**
 * End of a paid period. Calendar-aware rather than a fixed day count, so a
 * monthly subscription confirmed on the 31st lands on the last day of a
 * shorter month instead of skipping it.
 */
function periodEnd(from: Timestamp, interval: 'monthly' | 'yearly'): Timestamp {
  const date = from.toDate();
  const target = new Date(date);
  if (interval === 'yearly') {
    target.setUTCFullYear(target.getUTCFullYear() + 1);
  } else {
    const day = target.getUTCDate();
    target.setUTCMonth(target.getUTCMonth() + 1);
    // Rolled into the following month (e.g. 31 Jan + 1 month): step back to
    // the last day of the intended month.
    if (target.getUTCDate() !== day) target.setUTCDate(0);
  }
  return Timestamp.fromDate(target);
}

/**
 * Marks a landlord subscription as paid and opens the workspace.
 *
 * Platform staff only, through the same audited command path as
 * `landlord.approve`; the signed billing webhook will call this exact
 * transition once provider integration exists. A landlord can never confirm
 * their own payment. A non-blank `reference` (the provider transaction ID, or
 * the manual payment reference an operator holds) is required, so every
 * activation carries an audit trail of what money justified it. `tier` records
 * what was actually paid for when it differs from what the landlord selected,
 * and is validated against the server-owned entitlement config so an
 * activation can never point at a plan the backend would then refuse to serve.
 *
 * Confirming payment is also the account activation: a still-`pending`
 * landlord account is approved in the same transaction, so one confirmed
 * payment opens the workspace without a separate `landlord.approve` step. A
 * `suspended` account rejects instead — payment must never silently undo a
 * compliance suspension; `landlord.reinstate` is the only path back.
 *
 * On an already-`active` subscription this same command applies a paid plan
 * change: the target tier comes from the explicit `tier` payload or the
 * landlord's `requestedTier` (subscription.requestUpgrade), and confirming
 * clears the request and its billing channel. An active subscription with no
 * tier change to apply still rejects — there is no such thing as re-confirming
 * the same plan.
 *
 * This is the administrator (cash) path. The electronic aggregator's signed
 * webhook will call this same transition to auto-activate a
 * `mobile_money`/`card` upgrade without an administrator — but an
 * administrator may not stand in for it: a pending upgrade left
 * `awaiting_payment` is rejected rather than adopted, so a plan can never open
 * on a checkout the provider never confirmed. Passing `tier` explicitly
 * remains available as a deliberate, audited override when a provider
 * callback has to be rescued by hand.
 */
export const subscriptionConfirmPayment: CommandHandler<z.infer<typeof confirmPaymentSchema>> = {
  payloadSchema: confirmPaymentSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requirePlatformAdmin(actor);
    const landlordId = cmd.aggregateId!;
    if (landlordId === actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.subscriptions).doc(landlordId);
    const accountRef = db.collection(COLLECTIONS.landlordAccounts).doc(landlordId);
    const [snapshot, accountSnapshot, entitlements] = await Promise.all([
      tx.get(ref),
      tx.get(accountRef),
      loadEntitlements(tx, db),
    ]);
    const subscription = requireAggregate<SubscriptionRecord>(snapshot, cmd.expectedVersion);
    const wasActive = subscription.status === 'active';
    // An electronic upgrade belongs to the aggregator: its signed webhook
    // calls this transition once money actually moved. An administrator must
    // not adopt one implicitly, or a plan opens on a checkout nobody
    // completed. Passing `tier` explicitly stays allowed — that is a
    // deliberate, audited override for rescuing a failed provider callback,
    // not an accident.
    if (
      wasActive
      && cmd.payload.tier === undefined
      && subscription.upgradeState === 'awaiting_payment'
    ) {
      throw new DomainError('VALIDATION_FAILED', {
        reason: 'electronicUpgradeAwaitingProvider',
      });
    }
    const tier =
      cmd.payload.tier
      ?? (wasActive ? subscription.requestedTier ?? undefined : undefined)
      ?? subscription.tier;
    if (wasActive && tier === subscription.tier) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'subscriptionAlreadyActive' });
    }
    const account = accountSnapshot.data() as
      | { version: number; approvalStatus?: string }
      | undefined;
    if (!accountSnapshot.exists || !account) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'landlordAccountMissing' });
    }
    if (account.approvalStatus === 'suspended') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'accountSuspended' });
    }
    if (account.approvalStatus !== 'pending' && account.approvalStatus !== 'approved') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'accountApprovalStatusInvalid' });
    }
    planForTier(entitlements, tier);
    // A confirmed payment always buys a fresh period and wipes any overdue
    // state, so paying inside the grace window restores a clean subscription
    // rather than leaving a stale deadline that would expire it anyway.
    const interval = cmd.payload.billingInterval
      ?? (subscription.billingInterval === 'yearly' ? 'yearly' : 'monthly');
    tx.update(ref, {
      tier,
      status: 'active',
      requestedTier: null,
      upgradeBillingChannel: null,
      upgradeState: null,
      paymentReference: cmd.payload.reference,
      billingInterval: interval,
      renewalDueAt: periodEnd(now, interval),
      graceEndsAt: null,
      paymentOverdueSince: null,
      ...(wasActive ? { planChangedAt: now } : { activatedAt: now }),
      ...bumpVersion(subscription, now),
    });
    if (account.approvalStatus === 'pending') {
      tx.update(accountRef, {
        approvalStatus: 'approved',
        approvalReasonCode: 'PAYMENT_CONFIRMED',
        approvedAt: now,
        ...bumpVersion(account, now),
      });
    }
    return {
      status: 'applied',
      aggregateId: landlordId,
      serverVersion: subscription.version + 1,
      changedFields: [
        'status',
        'tier',
        'requestedTier',
        'upgradeBillingChannel',
        'upgradeState',
        'paymentReference',
        'billingInterval',
        'renewalDueAt',
        'graceEndsAt',
        wasActive ? 'planChangedAt' : 'activatedAt',
      ],
    };
  },
};

const rejectPaymentSchema = strictPayload({
  reasonCode: z.enum([
    'PAYMENT_NOT_RECEIVED',
    'AMOUNT_INCORRECT',
    'REFERENCE_INVALID',
    'DUPLICATE_REQUEST',
    'ADMIN_CORRECTION',
  ]),
  note: z.string().trim().max(500).optional(),
});

/**
 * Rejects a payment a landlord claimed to have made.
 *
 * The counterpart to `subscription.confirmPayment`: staff who checked and
 * found no money must be able to say so, instead of leaving the request
 * sitting in the queue forever with the landlord assuming it is in progress.
 *
 * Deliberately never punitive — it clears the pending request and records why,
 * leaving the subscription exactly as it was. An unpaid account stays
 * `pending_payment` (still able to select a plan and try again) and a paid one
 * keeps the plan and period it already has; only the rejected *request* goes
 * away. The landlord is told, so a rejection is never silent.
 */
export const subscriptionRejectPayment: CommandHandler<z.infer<typeof rejectPaymentSchema>> = {
  payloadSchema: rejectPaymentSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requirePlatformAdmin(actor);
    const landlordId = cmd.aggregateId!;
    if (landlordId === actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.subscriptions).doc(landlordId);
    const snapshot = await tx.get(ref);
    const subscription = requireAggregate<SubscriptionRecord>(snapshot, cmd.expectedVersion);
    // Rejecting needs something outstanding to reject: either a landlord's
    // pending upgrade request, or an account still awaiting its first payment.
    const hasPendingUpgrade = typeof subscription.requestedTier === 'string'
      && subscription.requestedTier !== subscription.tier;
    if (!hasPendingUpgrade && subscription.status === 'active') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'noPaymentAwaitingReview' });
    }
    tx.update(ref, {
      requestedTier: null,
      upgradeBillingChannel: null,
      upgradeState: null,
      paymentRejectedAt: now,
      paymentRejectionReasonCode: cmd.payload.reasonCode,
      paymentRejectionNote: cmd.payload.note ?? null,
      ...bumpVersion(subscription, now),
    });
    createJob(tx, db, `${cmd.commandId}_notice`, 'sendSubscriptionNoticeEmail', {
      landlordId,
      kind: 'payment_rejected',
      reasonCode: cmd.payload.reasonCode,
      note: cmd.payload.note ?? null,
    }, now);
    return {
      status: 'accepted',
      aggregateId: landlordId,
      serverVersion: subscription.version + 1,
      changedFields: ['requestedTier', 'paymentRejectedAt', 'paymentRejectionReasonCode'],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

const downgradeSchema = strictPayload({
  tier: z.string().trim().min(1).max(40),
  reasonCode: z.enum([
    'LANDLORD_REQUESTED',
    'PAYMENT_SHORTFALL',
    'ADMIN_CORRECTION',
  ]),
});

/**
 * Moves an active subscription to a smaller plan, without a payment.
 *
 * Downward only. Letting this command raise a tier would hand any admin
 * session a way to grant paid capacity for free; upgrades keep going through
 * `confirmPayment` against a verified payment. "Smaller" is judged by the
 * server-owned unit limit rather than a hard-coded tier order, so it stays
 * correct when super admins re-price or re-scope plans via `plan.update`.
 *
 * Downgrade safety (docs/architecture/subscription-tiers.md) is preserved: the
 * subscription stays active, nothing is deleted, tenants are untouched, and an
 * over-limit landlord simply cannot create more units or publish more listings
 * until they are back within the new plan. The paid period is left alone —
 * money already paid is not shortened by moving to a cheaper plan.
 */
export const subscriptionDowngrade: CommandHandler<z.infer<typeof downgradeSchema>> = {
  payloadSchema: downgradeSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requirePlatformAdmin(actor);
    const landlordId = cmd.aggregateId!;
    if (landlordId === actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.subscriptions).doc(landlordId);
    const [snapshot, entitlements] = await Promise.all([tx.get(ref), loadEntitlements(tx, db)]);
    const subscription = requireAggregate<SubscriptionRecord>(snapshot, cmd.expectedVersion);
    if (cmd.payload.tier === subscription.tier) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'tierUnchanged' });
    }
    const current = planForTier(entitlements, subscription.tier);
    const target = planForTier(entitlements, cmd.payload.tier);
    if (target.unitLimit > current.unitLimit) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'notADowngrade' });
    }
    tx.update(ref, {
      tier: cmd.payload.tier,
      // A pending upgrade cannot survive a downgrade: it would re-raise the
      // tier the moment anyone confirmed it.
      requestedTier: null,
      upgradeBillingChannel: null,
      upgradeState: null,
      planChangedAt: now,
      downgradeReasonCode: cmd.payload.reasonCode,
      ...bumpVersion(subscription, now),
    });
    createJob(tx, db, `${cmd.commandId}_notice`, 'sendSubscriptionNoticeEmail', {
      landlordId,
      kind: 'downgraded',
      tier: cmd.payload.tier,
      reasonCode: cmd.payload.reasonCode,
    }, now);
    return {
      status: 'accepted',
      aggregateId: landlordId,
      serverVersion: subscription.version + 1,
      changedFields: ['tier', 'requestedTier', 'planChangedAt', 'downgradeReasonCode'],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

const deactivateSchema = strictPayload({
  reasonCode: z.enum([
    'NON_PAYMENT',
    'LANDLORD_REQUESTED',
    'DUPLICATE_ACCOUNT',
    'ADMIN_CORRECTION',
  ]),
});

/**
 * Ends a landlord's subscription, closing their workspace.
 *
 * The manual counterpart to the grace-period sweep. Because every landlord
 * command requires an `active` subscription, `canceled` is what actually locks
 * the workspace — and that is the whole effect. Nothing is deleted, listings
 * are left as they are, and tenants keep their portal, their lease, their
 * balances and their documents: a landlord who stopped paying must never cost
 * their tenants access to their own records. Reversal is `confirmPayment`,
 * which restores the workspace and starts a fresh paid period.
 *
 * This is not a compliance tool. Suspending an account for abuse is
 * `landlord.suspend`, which also takes their adverts down.
 */
export const subscriptionDeactivate: CommandHandler<z.infer<typeof deactivateSchema>> = {
  payloadSchema: deactivateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requirePlatformAdmin(actor);
    const landlordId = cmd.aggregateId!;
    if (landlordId === actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.subscriptions).doc(landlordId);
    const snapshot = await tx.get(ref);
    const subscription = requireAggregate<SubscriptionRecord>(snapshot, cmd.expectedVersion);
    if (subscription.status === 'canceled' || subscription.status === 'expired') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'subscriptionAlreadyEnded' });
    }
    tx.update(ref, {
      status: 'canceled',
      requestedTier: null,
      upgradeBillingChannel: null,
      upgradeState: null,
      graceEndsAt: null,
      canceledAt: now,
      cancelReasonCode: cmd.payload.reasonCode,
      ...bumpVersion(subscription, now),
    });
    createJob(tx, db, `${cmd.commandId}_notice`, 'sendSubscriptionNoticeEmail', {
      landlordId,
      kind: 'deactivated',
      reasonCode: cmd.payload.reasonCode,
    }, now);
    return {
      status: 'accepted',
      aggregateId: landlordId,
      serverVersion: subscription.version + 1,
      changedFields: ['status', 'canceledAt', 'cancelReasonCode'],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

const planFeatureSchema = z
  .object({
    id: z.string().trim().min(1).max(60).regex(/^[a-z0-9-]+$/),
    label: z.string().trim().min(1).max(120),
    implemented: z.boolean(),
  })
  .strict();

/**
 * Tier IDs like `pro` are shorter than the envelope's aggregateId pattern
 * allows, so the tier travels in the payload and the catalog document's own
 * `version` is checked through `expectedCatalogVersion` instead of the
 * envelope's optimistic-concurrency field.
 */
const updatePlanSchema = strictPayload({
  // Lowercase alphanumeric-hyphen only: the value addresses both a document
  // ID and the `plans.${tier}` field path, so path-reserved characters
  // (dots especially) must never validate even though unknown tiers already
  // fail closed before any write.
  tier: z.string().trim().min(1).max(40).regex(/^[a-z0-9-]+$/),
  expectedCatalogVersion: z.number().int().min(1),
  displayName: shortText.optional(),
  tagline: z.string().trim().min(1).max(200).optional(),
  capacityLabel: z.string().trim().min(1).max(200).nullable().optional(),
  monthlyPriceMinor: nonNegativeMoney.optional(),
  yearlyPriceMinor: nonNegativeMoney.optional(),
  unitLimit: z.number().int().min(0).max(1_000_000).optional(),
  activeListingLimit: z.number().int().min(0).max(1_000_000).optional(),
  isPublic: z.boolean().optional(),
  features: z.array(planFeatureSchema).max(40).optional(),
});

const EDITABLE_PLAN_FIELDS = [
  'displayName',
  'tagline',
  'capacityLabel',
  'monthlyPriceMinor',
  'yearlyPriceMinor',
  'unitLimit',
  'activeListingLimit',
  'isPublic',
  'features',
] as const;

interface PlanCatalogRecord {
  version: number;
  monthlyPriceMinor?: number;
  yearlyPriceMinor?: number;
}

/**
 * Administrator editing of one plan's commercial terms: prices, yearly price,
 * capacity limits, presentation copy, visibility, and the feature list with
 * its `implemented` flags. Writes `planCatalog/{tier}` (what clients render)
 * and, when a limit changes, the same values into
 * `backendConfig/entitlements` (what commands enforce) in one transaction so
 * the two can never advertise different capacity. Existing tiers only — the
 * four-tier structure is normative (docs/architecture/subscription-tiers.md),
 * and an unknown tier fails closed like every other entitlement path.
 */
export const planUpdate: CommandHandler<z.infer<typeof updatePlanSchema>> = {
  payloadSchema: updatePlanSchema,
  aggregateIdMode: 'forbidden',
  expectedVersionMode: 'none',
  async apply({ tx, db, actor, cmd, now }) {
    requirePlatformAdmin(actor);
    await requireActiveAccount(tx, db, actor);
    const { tier, expectedCatalogVersion, ...edits } = cmd.payload;
    const changedFields = EDITABLE_PLAN_FIELDS.filter((field) => edits[field] !== undefined);
    if (changedFields.length === 0) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'noFieldsToUpdate' });
    }
    const catalogRef = db.collection(COLLECTIONS.planCatalog).doc(tier);
    const entitlementsRef = db.collection(COLLECTIONS.backendConfig).doc('entitlements');
    const [catalogSnap, entitlements] = await Promise.all([
      tx.get(catalogRef),
      loadEntitlements(tx, db),
    ]);
    const catalog = requireAggregate<PlanCatalogRecord>(catalogSnap, expectedCatalogVersion);
    const plan = planForTier(entitlements, tier);

    // A yearly price above twelve months of the monthly price would render as
    // a negative "saving"; reject the pair rather than advertising it.
    const monthly = edits.monthlyPriceMinor ?? catalog.monthlyPriceMinor;
    const yearly = edits.yearlyPriceMinor ?? catalog.yearlyPriceMinor;
    if (
      typeof monthly === 'number' && typeof yearly === 'number'
      && monthly > 0 && yearly > monthly * 12
    ) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'yearlyPriceExceedsMonthlyTimesTwelve' });
    }

    const catalogUpdate: Record<string, unknown> = { ...bumpVersion(catalog, now) };
    for (const field of changedFields) catalogUpdate[field] = edits[field];
    tx.update(catalogRef, catalogUpdate);

    // Limits are enforced from the entitlements config, not the catalog;
    // mirror them so display and enforcement cannot drift apart.
    const unitLimit = edits.unitLimit ?? plan.unitLimit;
    const activeListingLimit = edits.activeListingLimit ?? plan.activeListingLimit;
    if (edits.unitLimit !== undefined || edits.activeListingLimit !== undefined) {
      tx.update(entitlementsRef, {
        version: entitlements.version + 1,
        [`plans.${tier}`]: { ...plan, unitLimit, activeListingLimit },
        updatedAt: now,
      });
    }

    return {
      status: 'applied',
      aggregateId: tier,
      serverVersion: catalog.version + 1,
      changedFields: [...changedFields],
    };
  },
};
