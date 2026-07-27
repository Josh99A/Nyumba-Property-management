import { Timestamp } from 'firebase-admin/firestore';
import { z } from 'zod';
import { newAggregate, requireAbsent } from '../shared/aggregates';
import { requireActiveLandlord, type LandlordAccount } from '../shared/accounts';
import { COLLECTIONS } from '../shared/collections';
import {
  FEEDBACK_NPS_COOLDOWN_DAYS,
  FEEDBACK_SUBMIT_COOLDOWN_SECONDS,
} from '../shared/config';
import { DomainError } from '../shared/errors';
import { longText, shortText, strictPayload, type CommandHandler } from '../shared/handlers';

/**
 * The two feedback-cadence timestamps live on `landlordAccounts`, but neither
 * is part of that document's modelled shape — this command is the only
 * reader and writer of both. A local extension keeps that scoping visible
 * instead of widening the shared `LandlordAccount` type for a concern nothing
 * else touches.
 */
interface FeedbackCadence {
  lastFeedbackSubmittedAt?: Timestamp;
  lastNpsSubmittedAt?: Timestamp;
}

function rejectIfWithin(
  last: Timestamp | undefined,
  cooldownMs: number,
  now: Timestamp,
): void {
  if (!(last instanceof Timestamp)) return;
  const elapsed = now.toMillis() - last.toMillis();
  if (elapsed < cooldownMs) {
    throw new DomainError('RATE_LIMITED', {
      retryAfterSeconds: Math.ceil((cooldownMs - elapsed) / 1000),
    });
  }
}

/**
 * Landlord-to-Nyumba product feedback.
 *
 * Deliberately unrelated to `reviews.ts`. That system is public, adversarial,
 * and needs eligibility proof, aggregates, and moderation; this one is private
 * telemetry from a paying customer with no adversary and no reader but us.
 * Sharing machinery between them would drag moderation and rate-limit
 * complexity into a form whose entire job is to be frictionless.
 */
const feedbackSchema = strictPayload({
  kind: z.enum(['nps', 'freeform']),
  /** 0–10 recommendation score. Required for `nps`, rejected for `freeform`. */
  score: z.number().int().min(0).max(10).optional(),
  comment: longText.optional(),
  category: z
    .enum(['easeOfUse', 'valueForMoney', 'support', 'bug', 'featureRequest'])
    .optional(),
  appVersion: shortText,
  platform: z.enum(['android', 'ios', 'web']),
}).superRefine((payload, context) => {
  if (payload.kind === 'nps' && payload.score === undefined) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['score'], message: 'npsScoreRequired' });
  }
  if (payload.kind === 'freeform') {
    if (payload.score !== undefined) {
      context.addIssue({ code: z.ZodIssueCode.custom, path: ['score'], message: 'scoreNotAllowed' });
    }
    if (payload.comment === undefined) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['comment'],
        message: 'commentRequired',
      });
    }
  }
});

export const feedbackSubmit: CommandHandler<z.infer<typeof feedbackSchema>> = {
  payloadSchema: feedbackSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.platformFeedback).doc(cmd.aggregateId!);
    // Reads must precede the writes below within the transaction; order
    // between these two doesn't matter, only that both land first.
    const [snapshot, landlord] = await Promise.all([
      tx.get(ref),
      requireActiveLandlord(tx, db, actor),
    ]);
    requireAbsent(snapshot);
    const account = landlord.account as LandlordAccount & FeedbackCadence;

    // Every kind shares one floor against double-submits and scripted abuse;
    // NPS additionally keeps its own much longer "don't ask again yet" cadence.
    rejectIfWithin(
      account.lastFeedbackSubmittedAt,
      FEEDBACK_SUBMIT_COOLDOWN_SECONDS * 1000,
      now,
    );
    if (cmd.payload.kind === 'nps') {
      rejectIfWithin(
        account.lastNpsSubmittedAt,
        FEEDBACK_NPS_COOLDOWN_DAYS * 24 * 60 * 60 * 1000,
        now,
      );
    }

    tx.create(ref, {
      ...newAggregate(cmd.aggregateId!, now),
      actorUid: actor.uid,
      kind: cmd.payload.kind,
      score: cmd.payload.score ?? null,
      comment: cmd.payload.comment ?? null,
      category: cmd.payload.category ?? null,
      appVersion: cmd.payload.appVersion,
      platform: cmd.payload.platform,
      // The whole point of denormalizing the tier at write time: a detractor
      // on the top tier is a churn alert worth acting on today. Joining this
      // against `subscriptions` weeks later reads whatever tier they churned
      // *to*, which is precisely the information that would be misleading.
      planTier: landlord.subscription.tier,
      subscriptionStatus: landlord.subscription.status,
      submittedAt: now,
    });

    // Server-owned prompt schedule. A cadence tracked only on the device resets
    // on reinstall and on every new device, so the same landlord gets asked
    // again and again — the fastest way to make people resent the prompt.
    tx.update(db.collection(COLLECTIONS.landlordAccounts).doc(actor.uid), {
      lastFeedbackSubmittedAt: now,
      ...(cmd.payload.kind === 'nps' ? { lastNpsSubmittedAt: now } : {}),
    });

    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: 1,
      changedFields: ['kind', 'score', 'comment'],
    };
  },
};

// A `feedback.dismissPrompt` command was considered here and deliberately left
// out. The cadence that actually matters — how often a landlord may be *asked*
// again after answering — is already enforced above by the 90-day check against
// `lastNpsSubmittedAt`, which no client can bypass. A separate command whose
// only job was to record "shown and declined" would have cost a Firestore write
// per dismissal to shorten a snooze the client tracks on-device perfectly well.
// See FeedbackPromptStore on the Flutter side.
