import { createHash } from 'node:crypto';
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

const registerDeviceSchema = strictPayload({
  // FCM tokens are long and opaque; bound the length rather than the alphabet.
  token: z.string().trim().min(32).max(4_096),
  platform: z.enum(['web', 'android', 'ios', 'macos', 'windows', 'linux']),
});

/** Beyond this, the oldest registration is dropped. */
const MAX_DEVICE_TOKENS = 10;

/**
 * Registers this device's FCM token against the signed-in user.
 *
 * A callable rather than a direct write because `users/{uid}` denies all client
 * writes: the document also carries `role`, so letting a client touch it at all
 * would hand it a lever on its own authorization.
 *
 * Idempotent on the token, which matters because the client re-registers on
 * every launch and FCM hands back the same token until it rotates.
 *
 * A token identifies a physical device, so it may belong to at most one
 * account at a time: `deviceTokenOwners/{sha256(token)}` records the current
 * owner, and registering here transactionally revokes the token from the
 * previous account. Without that, a shared device would keep delivering user
 * A's notifications after user B signs in on it.
 */
export const profileRegisterDevice: CommandHandler<z.infer<typeof registerDeviceSchema>> = {
  payloadSchema: registerDeviceSchema,
  aggregateIdMode: 'forbidden',
  expectedVersionMode: 'none',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.users).doc(actor.uid);
    const ownerRef = db.collection(COLLECTIONS.deviceTokenOwners)
      .doc(createHash('sha256').update(cmd.payload.token).digest('hex'));
    const [snapshot, ownerSnap] = await Promise.all([tx.get(ref), tx.get(ownerRef)]);
    const current = requireAggregate<Record<string, unknown> & { version: number }>(snapshot, undefined);

    // Reads must precede the first write, so the previous owner's document is
    // loaded here even though its update is buffered below.
    const previousOwnerUid = ownerSnap.data()?.uid;
    let previousOwner: { ref: FirebaseFirestore.DocumentReference; kept: unknown[]; version: number } | null = null;
    if (typeof previousOwnerUid === 'string' && previousOwnerUid !== actor.uid) {
      const previousRef = db.collection(COLLECTIONS.users).doc(previousOwnerUid);
      const previousSnap = await tx.get(previousRef);
      const previousData = previousSnap.data();
      if (previousSnap.exists && previousData && Array.isArray(previousData.deviceTokens)) {
        const kept = (previousData.deviceTokens as { token?: unknown }[]).filter(
          (entry) => !(typeof entry === 'object' && entry !== null && entry.token === cmd.payload.token),
        );
        if (kept.length !== previousData.deviceTokens.length) {
          previousOwner = { ref: previousRef, kept, version: Number(previousData.version ?? 1) };
        }
      }
    }

    const existing = Array.isArray(current.deviceTokens)
      ? (current.deviceTokens as { token?: unknown }[]).filter(
        (entry): entry is { token: string; platform: string; updatedAt: unknown } =>
          typeof entry === 'object' && entry !== null && typeof entry.token === 'string',
      )
      : [];
    // Re-registering moves the token to the newest slot rather than duplicating
    // it, so the cap evicts genuinely stale devices instead of this one.
    const others = existing.filter((entry) => entry.token !== cmd.payload.token);
    const next = [...others, { token: cmd.payload.token, platform: cmd.payload.platform, updatedAt: now }]
      .slice(-MAX_DEVICE_TOKENS);

    if (previousOwner) {
      tx.update(previousOwner.ref, {
        deviceTokens: previousOwner.kept,
        ...bumpVersion({ version: previousOwner.version }, now),
      });
    }
    tx.set(ownerRef, { uid: actor.uid, platform: cmd.payload.platform, updatedAt: now });
    tx.update(ref, { deviceTokens: next, ...bumpVersion(current, now) });
    return {
      status: 'applied',
      aggregateId: actor.uid,
      serverVersion: current.version + 1,
      safeResult: { deviceCount: next.length },
      changedFields: ['deviceTokens'],
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
