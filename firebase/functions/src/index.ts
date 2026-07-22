import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import * as functionsV1 from 'firebase-functions/v1';
import { executeCommand } from './callable/execute-command';
import { COLLECTIONS } from './shared/collections';
import { REGION } from './shared/config';
import { expirePublicListings } from './workers/listing-expiry';
import { processBackendJob, sweepBackendJobs } from './workers/jobs';
import { sweepEmailReminders } from './workers/email-reminders';
import { sweepSubscriptionRenewals } from './workers/subscription-renewal';

initializeApp();

export {
  executeCommand,
  processBackendJob,
  sweepBackendJobs,
  expirePublicListings,
  sweepEmailReminders,
  sweepSubscriptionRenewals,
};

/**
 * Marks the profile of a deleted Auth account. Without this, deleting an
 * account strands its `users/{uid}` document forever: the admin directory
 * would keep listing a person who can no longer sign in, and a
 * re-registration of the same email would appear as a duplicate.
 */
export const onUserDeleted = functionsV1
  .region(REGION)
  .auth.user()
  .onDelete(async (user) => {
    const now = Timestamp.now();
    const ref = getFirestore().collection(COLLECTIONS.users).doc(user.uid);
    await getFirestore().runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (!existing.exists) return;
      tx.update(ref, {
        isDeleted: true,
        updatedAt: now,
        version: Number(existing.data()?.version ?? 0) + 1,
      });
    });
  });

export const onUserCreated = functionsV1
  .region(REGION)
  .auth.user()
  .onCreate(async (user) => {
    const now = Timestamp.now();
    const ref = getFirestore().collection(COLLECTIONS.users).doc(user.uid);
    // Auth triggers deliver at least once; an existing profile means an
    // earlier attempt already succeeded and must not be overwritten.
    await getFirestore().runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      if (existing.exists) return;
      tx.create(ref, {
        id: user.uid,
        // This trigger runs the instant the account exists, which for an
        // email/password sign-up is before the client sets a display name.
        // Store null rather than '': an empty string reads as a real value and
        // shadows the name Auth later holds.
        displayName: user.displayName || null,
        email: user.email ?? null,
        role: 'client',
        status: 'active',
        version: 1,
        createdAt: now,
        updatedAt: now,
        isDeleted: false,
      });
    });
  });
