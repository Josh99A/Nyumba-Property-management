import { z } from 'zod';
import { bumpVersion, requireAggregate } from '../shared/aggregates';
import { requirePlatformAdmin } from '../shared/actor';
import { COLLECTIONS } from '../shared/collections';
import { loadEntitlements, planForTier } from '../shared/config';
import { DomainError } from '../shared/errors';
import { shortText, strictPayload, type CommandHandler } from '../shared/handlers';

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
    const [snapshot, entitlements] = await Promise.all([tx.get(ref), loadEntitlements(tx, db)]);
    const subscription = requireAggregate<SubscriptionRecord>(snapshot, cmd.expectedVersion);
    if (subscription.status === 'active') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'subscriptionAlreadyActive' });
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
    return {
      status: 'applied',
      aggregateId: landlordId,
      serverVersion: subscription.version + 1,
      changedFields: ['status', 'tier', 'activatedAt', 'paymentReference'],
    };
  },
};
