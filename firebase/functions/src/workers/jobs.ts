import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { COLLECTIONS } from '../shared/collections';
import {
  JOB_BASE_BACKOFF_SECONDS,
  JOB_LEASE_SECONDS,
  JOB_MAX_ATTEMPTS,
  REGION,
} from '../shared/config';
import {
  cleanupListingMedia,
  movePrivateDocument,
  publishListingMedia,
  purgeDocument,
} from './media-publication';
import { fanoutNotice } from './notice-fanout';
import { deliverContactRequest, notifyLandlordApplication } from './notifications';
import { initiatePayment } from './payment-provider';
import { renderReceipt } from './receipt-render';
import { generateReport } from './report-generation';
import { unpublishLandlordListings } from './unpublish-landlord';
import { deleteAuthUser, setAuthUserDisabled } from './auth-lifecycle';

type JobProcessor = (payload: Record<string, unknown>) => Promise<void>;

/**
 * Every job type any command can enqueue must be registered here. An enqueued
 * type with no processor burns JOB_MAX_ATTEMPTS and dies in dead_letter without
 * ever surfacing to a user, so `commandEnqueuedJobTypes` in the tests asserts
 * this map covers the full set.
 */
const processors = new Map<string, JobProcessor>([
  ['publishListingMedia', publishListingMedia],
  ['cleanupListingMedia', cleanupListingMedia],
  ['movePrivateDocument', movePrivateDocument],
  ['purgeDocument', purgeDocument],
  ['noticeFanout', fanoutNotice],
  ['unpublishLandlordListings', unpublishLandlordListings],
  ['initiatePayment', initiatePayment],
  ['renderReceipt', renderReceipt],
  ['notifyLandlordApplication', notifyLandlordApplication],
  ['deliverContactRequest', deliverContactRequest],
  ['generateReport', generateReport],
  ['setAuthUserDisabled', setAuthUserDisabled],
  ['deleteAuthUser', deleteAuthUser],
]);

/** Visible for tests, which assert no command enqueues an unregistered type. */
export const registeredJobTypes: ReadonlySet<string> = new Set(processors.keys());

async function claimJob(jobId: string): Promise<Record<string, unknown> | null> {
  const db = getFirestore();
  const ref = db.collection(COLLECTIONS.backendJobs).doc(jobId);
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) return null;
    const job = snapshot.data()!;
    const now = Timestamp.now();
    const nextAttemptAt = job.nextAttemptAt as Timestamp | null | undefined;
    const leaseUntil = job.leaseUntil as Timestamp | null | undefined;
    const claimablePending = job.state === 'pending' && (!nextAttemptAt || nextAttemptAt.toMillis() <= now.toMillis());
    const claimableOrphan = job.state === 'processing' && (!leaseUntil || leaseUntil.toMillis() <= now.toMillis());
    if (!claimablePending && !claimableOrphan) return null;
    tx.update(ref, {
      state: 'processing',
      leaseUntil: Timestamp.fromMillis(now.toMillis() + JOB_LEASE_SECONDS * 1_000),
      updatedAt: now,
    });
    return { ...job, id: jobId };
  });
}

export async function processJobById(jobId: string): Promise<void> {
  const job = await claimJob(jobId);
  if (!job) return;
  const ref = getFirestore().collection(COLLECTIONS.backendJobs).doc(jobId);
  try {
    const processor = processors.get(String(job.type));
    if (!processor) throw new Error(`No processor registered for ${String(job.type)}.`);
    const payload = typeof job.payload === 'object' && job.payload !== null
      ? job.payload as Record<string, unknown>
      : {};
    await processor(payload);
    await ref.update({
      state: 'succeeded',
      leaseUntil: null,
      completedAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  } catch (error) {
    const attemptCount = Number(job.attemptCount ?? 0) + 1;
    const dead = attemptCount >= JOB_MAX_ATTEMPTS;
    const delaySeconds = JOB_BASE_BACKOFF_SECONDS * 2 ** Math.min(attemptCount - 1, 10);
    const now = Timestamp.now();
    await ref.update({
      state: dead ? 'dead_letter' : 'pending',
      attemptCount,
      nextAttemptAt: dead ? null : Timestamp.fromMillis(now.toMillis() + delaySeconds * 1_000),
      leaseUntil: null,
      lastError: error instanceof Error ? error.message.slice(0, 500) : 'Unknown worker failure.',
      updatedAt: now,
    });
  }
}

export const processBackendJob = onDocumentCreated(
  { document: `${COLLECTIONS.backendJobs}/{jobId}`, region: REGION },
  async (event) => processJobById(event.params.jobId),
);

export const sweepBackendJobs = onSchedule(
  { schedule: 'every 5 minutes', region: REGION, timeZone: 'UTC' },
  async () => {
    const now = Timestamp.now();
    const [pending, orphaned] = await Promise.all([
      getFirestore().collection(COLLECTIONS.backendJobs)
        .where('state', '==', 'pending')
        .where('nextAttemptAt', '<=', now)
        .limit(100)
        .get(),
      getFirestore().collection(COLLECTIONS.backendJobs)
        .where('state', '==', 'processing')
        .where('leaseUntil', '<=', now)
        .limit(100)
        .get(),
    ]);
    const ids = new Set([...pending.docs, ...orphaned.docs].map((doc) => doc.id));
    for (const id of ids) await processJobById(id);
  },
);
