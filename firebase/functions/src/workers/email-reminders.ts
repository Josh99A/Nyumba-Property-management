import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { COLLECTIONS } from '../shared/collections';
import { REGION } from '../shared/config';
import { EMAIL_SECRETS } from '../shared/email';

/** Days before an invoice due date that the upcoming-rent email goes out. */
const RENT_UPCOMING_DAYS = 3;
/** Days before a lease end date that both parties are told it ends soon. */
const LEASE_EXPIRY_DAYS = 30;
/** Days before a public listing expires that its landlord is warned. */
const LISTING_WARNING_DAYS = 3;

/**
 * Enqueues one email job under a deterministic ID. The job document is the
 * idempotency record: `create` refuses to overwrite, so every milestone
 * (this invoice's overdue notice, this lease's end date) emails exactly once
 * no matter how many daily sweeps observe it.
 */
async function enqueueOnce(
  db: Firestore,
  id: string,
  type: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const now = Timestamp.now();
  try {
    await db.collection(COLLECTIONS.backendJobs).doc(id).create({
      id,
      type,
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
    // ALREADY_EXISTS means an earlier sweep enqueued this milestone.
    if (code !== 6 && code !== 'already-exists') throw error;
  }
}

/** ISO date (YYYY-MM-DD) `days` from now; invoice/lease dates are ISO strings. */
function isoDaysFromNow(days: number): string {
  return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

/**
 * Daily sweep that turns approaching deadlines into email jobs: rent due
 * soon, rent overdue, leases ending, and listings about to expire. Runs in
 * the morning Kampala time so reminders land at the start of the day. The
 * email workers re-read every aggregate at send time, so a bill settled (or
 * lease ended) after enqueue results in no email, not a wrong one.
 */
export const sweepEmailReminders = onSchedule(
  {
    schedule: 'every day 07:00',
    region: REGION,
    timeZone: 'Africa/Kampala',
    secrets: EMAIL_SECRETS,
  },
  async () => {
    const db = getFirestore();
    const today = isoDaysFromNow(0);

    // Rent coming due: dueDate within the reminder window but not yet passed.
    const upcoming = await db.collection(COLLECTIONS.invoices)
      .where('status', 'in', ['due', 'part_paid'])
      .where('dueDate', '>=', today)
      .where('dueDate', '<=', `${isoDaysFromNow(RENT_UPCOMING_DAYS)}`)
      .limit(300)
      .get();
    for (const doc of upcoming.docs) {
      await enqueueOnce(db, `${doc.id}_email_upcoming`, 'sendRentReminderEmail', {
        invoiceId: doc.id,
        kind: 'upcoming',
      });
    }

    // Rent overdue: due date behind us with a balance still open.
    const overdue = await db.collection(COLLECTIONS.invoices)
      .where('status', 'in', ['due', 'part_paid'])
      .where('dueDate', '<', today)
      .limit(300)
      .get();
    for (const doc of overdue.docs) {
      await enqueueOnce(db, `${doc.id}_email_overdue`, 'sendRentReminderEmail', {
        invoiceId: doc.id,
        kind: 'overdue',
      });
    }

    // Active leases whose term ends within the notice window. The end date is
    // part of the job ID, so a renewed lease earns a fresh notice next time.
    const leases = await db.collection(COLLECTIONS.leases)
      .where('status', '==', 'active')
      .where('endDate', '<=', `${isoDaysFromNow(LEASE_EXPIRY_DAYS)}`)
      .limit(300)
      .get();
    for (const doc of leases.docs) {
      const endDate = String(doc.data().endDate ?? '').slice(0, 10);
      if (!endDate || endDate < today) continue;
      await enqueueOnce(
        db,
        `${doc.id}_email_leaseExpiry_${endDate}`,
        'sendLeaseExpiryEmail',
        { leaseId: doc.id },
      );
    }

    // Published listings the hourly expiry worker will take down soon.
    const horizon = Timestamp.fromMillis(Date.now() + LISTING_WARNING_DAYS * 86_400_000);
    const listings = await db.collection(COLLECTIONS.publicListings)
      .where('status', '==', 'published')
      .where('expiresAt', '<=', horizon)
      .limit(300)
      .get();
    for (const doc of listings.docs) {
      const expiresAt = doc.data().expiresAt as Timestamp | undefined;
      if (!expiresAt || expiresAt.toMillis() <= Date.now()) continue;
      await enqueueOnce(
        db,
        `${doc.id}_email_listingExpiry_${expiresAt.toMillis()}`,
        'sendListingExpiryWarningEmail',
        { listingId: doc.id, expiresAtMillis: expiresAt.toMillis() },
      );
    }
  },
);
