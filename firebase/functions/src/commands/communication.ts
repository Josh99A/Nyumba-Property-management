import { z } from 'zod';
import { newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { requireOwnedByLandlord, requireWorkspace } from '../shared/accounts';
import { requirePlatformAdmin } from '../shared/actor';
import { COLLECTIONS } from '../shared/collections';
import { loadEntitlements, planForTier } from '../shared/config';
import { DomainError } from '../shared/errors';
import { createJob, longText, shortText, strictPayload, type CommandHandler } from '../shared/handlers';

const noticeSchema = strictPayload({
  title: shortText,
  body: longText,
  audience: z.enum(['all_active_tenants', 'property', 'lease']),
  audienceId: z.string().regex(/^[A-Za-z0-9_-]{8,128}$/).optional(),
}).superRefine((value, context) => {
  if (value.audience !== 'all_active_tenants' && !value.audienceId) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['audienceId'], message: 'audienceId is required.' });
  }
});

export const noticePublish: CommandHandler<z.infer<typeof noticeSchema>> = {
  payloadSchema: noticeSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireWorkspace(tx, db, actor, 'manageCommunication');
    const ref = db.collection(COLLECTIONS.notices).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    requireAbsent(snapshot);
    // A scoped audience must reference an aggregate this landlord owns; the
    // fanout worker then narrows delivery to exactly that scope.
    if (cmd.payload.audience === 'property' || cmd.payload.audience === 'lease') {
      const targetCollection =
        cmd.payload.audience === 'property' ? COLLECTIONS.properties : COLLECTIONS.leases;
      const targetSnap = await tx.get(db.collection(targetCollection).doc(cmd.payload.audienceId!));
      const target = requireAggregate<{ version: number; landlordId: string }>(targetSnap, undefined);
      requireOwnedByLandlord(target, landlord.landlordId);
    }
    tx.create(ref, {
      ...newAggregate(cmd.aggregateId!, now), landlordId: landlord.landlordId,
      ...cmd.payload, audienceId: cmd.payload.audienceId ?? null, publishState: 'pending', publishedAt: null,
    });
    createJob(tx, db, `${cmd.commandId}_fanout`, 'noticeFanout', { noticeId: cmd.aggregateId!, landlordId: landlord.landlordId }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: ['publishState'] };
  },
};

const broadcastSchema = strictPayload({
  title: shortText,
  body: longText,
  audience: z.enum(['all_users', 'landlords', 'tenants', 'clients', 'tier', 'user']),
  /** Tier ID for `tier`, target UID for `user`; forbidden otherwise. */
  audienceId: z.string().trim().min(1).max(128).optional(),
}).superRefine((value, context) => {
  const scoped = value.audience === 'tier' || value.audience === 'user';
  if (scoped && !value.audienceId) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['audienceId'], message: 'audienceId is required.' });
  }
  if (!scoped && value.audienceId) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['audienceId'], message: 'audienceId is only valid for tier or user audiences.' });
  }
});

/**
 * Platform announcement to every user, a target group (role or subscription
 * tier), or one individual — the operational channel for incidents,
 * maintenance windows, and commercial notices. Open to any administrator,
 * since running that channel is ordinary platform duty. The command
 * records the canonical broadcast document and hands delivery (in-app inbox,
 * push, and email) to the durable `broadcastFanout` job, so a large audience
 * never runs inside the command transaction.
 */
export const platformBroadcast: CommandHandler<z.infer<typeof broadcastSchema>> = {
  payloadSchema: broadcastSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    requirePlatformAdmin(actor);
    const ref = db.collection(COLLECTIONS.platformBroadcasts).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    requireAbsent(snapshot);
    // Scoped audiences must reference something real before anything is
    // enqueued: an unknown tier fails closed like every entitlement check, and
    // a broadcast to a missing or deleted account is a mistake worth surfacing.
    if (cmd.payload.audience === 'tier') {
      const entitlements = await loadEntitlements(tx, db);
      planForTier(entitlements, cmd.payload.audienceId!);
    } else if (cmd.payload.audience === 'user') {
      const target = await tx.get(db.collection(COLLECTIONS.users).doc(cmd.payload.audienceId!));
      const user = target.data();
      if (!target.exists || !user || user.isDeleted === true) {
        throw new DomainError('NOT_FOUND');
      }
    }
    tx.create(ref, {
      ...newAggregate(cmd.aggregateId!, now),
      title: cmd.payload.title,
      body: cmd.payload.body,
      audience: cmd.payload.audience,
      audienceId: cmd.payload.audienceId ?? null,
      requestedByUid: actor.uid,
      deliveryState: 'pending',
      recipientCount: null,
      completedAt: null,
    });
    createJob(tx, db, `${cmd.commandId}_broadcast`, 'broadcastFanout', { broadcastId: cmd.aggregateId! }, now);
    return {
      status: 'accepted',
      aggregateId: cmd.aggregateId!,
      serverVersion: 1,
      changedFields: ['deliveryState'],
    };
  },
};
