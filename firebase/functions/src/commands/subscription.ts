import { z } from 'zod';
import { bumpVersion, requireAggregate } from '../shared/aggregates';
import { requirePlatformAdmin, requireSuperAdmin } from '../shared/actor';
import { COLLECTIONS } from '../shared/collections';
import { loadEntitlements, planForTier } from '../shared/config';
import { DomainError } from '../shared/errors';
import { nonNegativeMoney, shortText, strictPayload, type CommandHandler } from '../shared/handlers';

interface SubscriptionRecord {
  version: number;
  status: string;
  tier: string;
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

const confirmPaymentSchema = strictPayload({
  reference: shortText,
  tier: z.string().trim().min(1).max(40).optional(),
});

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
    if (subscription.status === 'active') {
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
    const tier = cmd.payload.tier ?? subscription.tier;
    planForTier(entitlements, tier);
    tx.update(ref, {
      tier,
      status: 'active',
      activatedAt: now,
      paymentReference: cmd.payload.reference,
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
      changedFields: ['status', 'tier', 'activatedAt', 'paymentReference'],
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
  tier: z.string().trim().min(1).max(40),
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
 * Super-admin editing of one plan's commercial terms: prices, yearly price,
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
    requireSuperAdmin(actor);
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
