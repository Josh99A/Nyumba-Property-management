import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { COLLECTIONS } from '../shared/collections';
import {
  REGION,
  SUBSCRIPTION_GRACE_DAYS,
  SUBSCRIPTION_GRACE_WARNING_DAYS_LEFT,
  SUBSCRIPTION_RENEWAL_WARNING_DAYS,
} from '../shared/config';
import { EMAIL_SECRETS } from '../shared/email';

const DAY_MS = 86_400_000;

/**
 * Enqueues one notice job under a deterministic ID. The job document is the
 * idempotency record — `create` refuses to overwrite — so each milestone is
 * announced exactly once however many sweeps observe it.
 */
async function enqueueOnce(
  db: Firestore,
  id: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const now = Timestamp.now();
  try {
    await db.collection(COLLECTIONS.backendJobs).doc(id).create({
      id,
      type: 'sendSubscriptionNoticeEmail',
      payload,
      state: 'pending',
      attemptCount: 0,
      nextAttemptAt: now,
      leaseUntil: null,
      createdAt: now,
      updatedAt: now,
    });
  } catch (error) {
    const code = (error as { code?: number | string }).code;
    if (code !== 6 && code !== 'already-exists') throw error;
  }
}

/**
 * Daily subscription lifecycle sweep.
 *
 * Runs the whole unpaid path so nobody is ever locked out unannounced:
 *
 * 1. `SUBSCRIPTION_RENEWAL_WARNING_DAYS` before the renewal date, warn.
 * 2. On the renewal date, open a `SUBSCRIPTION_GRACE_DAYS` grace window. The
 *    subscription deliberately **stays active** through it — the landlord and
 *    their tenants keep working while the payment is settled — and the
 *    landlord is told the workspace will lock.
 * 3. With `SUBSCRIPTION_GRACE_WARNING_DAYS_LEFT` days of grace remaining,
 *    warn again.
 * 4. When grace runs out, expire the subscription. That locks the workspace
 *    (every landlord command requires an `active` subscription) and nothing
 *    more: no data is deleted, listings are left alone, and tenants keep their
 *    portal. Confirming a payment reopens everything.
 *
 * Each step re-reads state at send time via the notice worker, so a landlord
 * who pays midway is never warned about a deadline that no longer applies.
 */
export const sweepSubscriptionRenewals = onSchedule(
  {
    schedule: 'every day 08:00',
    region: REGION,
    timeZone: 'Africa/Kampala',
    secrets: EMAIL_SECRETS,
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const nowMs = now.toMillis();

    // 1. Renewal approaching.
    const warningHorizon = Timestamp.fromMillis(
      nowMs + SUBSCRIPTION_RENEWAL_WARNING_DAYS * DAY_MS,
    );
    const upcoming = await db
      .collection(COLLECTIONS.subscriptions)
      .where('status', '==', 'active')
      .where('renewalDueAt', '>', now)
      .where('renewalDueAt', '<=', warningHorizon)
      .limit(300)
      .get();
    for (const doc of upcoming.docs) {
      const dueAt = doc.data().renewalDueAt as Timestamp;
      await enqueueOnce(db, `sub_${doc.id}_renewal_${dueAt.toMillis()}`, {
        landlordId: doc.id,
        kind: 'renewal_due',
      });
    }

    // 2/3/4. Everything already past its renewal date.
    const lapsed = await db
      .collection(COLLECTIONS.subscriptions)
      .where('status', '==', 'active')
      .where('renewalDueAt', '<=', now)
      .limit(300)
      .get();
    for (const doc of lapsed.docs) {
      const data = doc.data();
      const dueAt = data.renewalDueAt as Timestamp;
      const existingGraceEnd = data.graceEndsAt;
      const graceEndsAt = existingGraceEnd instanceof Timestamp
        ? existingGraceEnd
        : Timestamp.fromMillis(dueAt.toMillis() + SUBSCRIPTION_GRACE_DAYS * DAY_MS);

      // 2. First sweep after the due date opens the grace window.
      if (!(existingGraceEnd instanceof Timestamp)) {
        await db.runTransaction(async (tx) => {
          const fresh = await tx.get(doc.ref);
          const current = fresh.data();
          // Re-check inside the transaction: a payment confirmed since the
          // query would have cleared the due date entirely.
          if (!current || current.status !== 'active') return;
          if (current.graceEndsAt instanceof Timestamp) return;
          const currentDue = current.renewalDueAt;
          if (!(currentDue instanceof Timestamp) || currentDue.toMillis() > nowMs) return;
          tx.update(doc.ref, {
            graceEndsAt,
            paymentOverdueSince: now,
            version: Number(current.version ?? 1) + 1,
            updatedAt: now,
          });
        });
        await enqueueOnce(db, `sub_${doc.id}_grace_${graceEndsAt.toMillis()}`, {
          landlordId: doc.id,
          kind: 'grace_started',
        });
        continue;
      }

      // 4. Grace exhausted: lock the workspace.
      if (graceEndsAt.toMillis() <= nowMs) {
        await db.runTransaction(async (tx) => {
          const fresh = await tx.get(doc.ref);
          const current = fresh.data();
          if (!current || current.status !== 'active') return;
          const currentGrace = current.graceEndsAt;
          if (!(currentGrace instanceof Timestamp) || currentGrace.toMillis() > nowMs) return;
          tx.update(doc.ref, {
            status: 'expired',
            expiredAt: now,
            version: Number(current.version ?? 1) + 1,
            updatedAt: now,
          });
        });
        await enqueueOnce(db, `sub_${doc.id}_expired_${graceEndsAt.toMillis()}`, {
          landlordId: doc.id,
          kind: 'expired',
        });
        continue;
      }

      // 3. Inside the grace window, with the final warning due.
      const daysLeft = (graceEndsAt.toMillis() - nowMs) / DAY_MS;
      if (daysLeft <= SUBSCRIPTION_GRACE_WARNING_DAYS_LEFT) {
        await enqueueOnce(db, `sub_${doc.id}_graceEnding_${graceEndsAt.toMillis()}`, {
          landlordId: doc.id,
          kind: 'grace_ending',
        });
      }
    }
  },
);
