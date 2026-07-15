import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { COLLECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import { optionalShortText, strictPayload, type CommandHandler } from '../shared/handlers';

const profileSchema = strictPayload({
  displayName: optionalShortText,
  phone: z.string().trim().max(32).optional(),
  locale: z.string().trim().max(16).optional(),
  notifications: z
    .object({ email: z.boolean(), push: z.boolean() })
    .strict()
    .optional(),
}).refine((value) => Object.values(value).some((field) => field !== undefined), {
  message: 'At least one profile field is required.',
});

export const profileUpdate: CommandHandler<z.infer<typeof profileSchema>> = {
  payloadSchema: profileSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    if (cmd.aggregateId !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.users).doc(actor.uid);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<Record<string, unknown> & { version: number }>(
      snapshot,
      cmd.expectedVersion,
    );
    const changes = Object.fromEntries(
      Object.entries(cmd.payload).filter(([, value]) => value !== undefined),
    );
    const next = { ...changes, ...bumpVersion(current, now) };
    tx.update(ref, next);
    return {
      status: 'applied',
      aggregateId: actor.uid,
      serverVersion: current.version + 1,
      changedFields: Object.keys(changes),
    };
  },
};

const onboardSchema = strictPayload({
  businessName: optionalShortText,
  phone: z.string().trim().min(7).max(32),
});

export const landlordOnboard: CommandHandler<z.infer<typeof onboardSchema>> = {
  payloadSchema: onboardSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    if (cmd.aggregateId !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    const accountRef = db.collection(COLLECTIONS.landlordAccounts).doc(actor.uid);
    const userRef = db.collection(COLLECTIONS.users).doc(actor.uid);
    const subscriptionRef = db.collection(COLLECTIONS.subscriptions).doc(actor.uid);
    const [account, user, subscription] = await Promise.all([
      tx.get(accountRef),
      tx.get(userRef),
      tx.get(subscriptionRef),
    ]);
    requireAbsent(account);
    const userData = requireAggregate<Record<string, unknown> & { version: number }>(user, undefined);

    tx.create(accountRef, {
      ...newAggregate(actor.uid, now),
      ownerUid: actor.uid,
      approvalStatus: 'pending',
      activeUnitCount: 0,
      activeListingCount: 0,
      receiptCounter: 0,
      businessName: cmd.payload.businessName ?? null,
      phone: cmd.payload.phone,
    });
    // Pre-billing placeholder: prices and the payment provider are TBD, so a
    // new landlord starts on a starter trial. A provider webhook owns this
    // document once billing exists; entitlement limits still apply.
    if (!subscription.exists) {
      tx.create(subscriptionRef, {
        ...newAggregate(actor.uid, now),
        tier: 'starter',
        status: 'trialing',
        trialStartedAt: now,
      });
    }
    tx.update(userRef, { role: 'landlord', ...bumpVersion(userData, now) });
    return {
      status: 'applied',
      aggregateId: actor.uid,
      serverVersion: 1,
      changedFields: ['role', 'approvalStatus', 'businessName', 'phone'],
    };
  },
};
