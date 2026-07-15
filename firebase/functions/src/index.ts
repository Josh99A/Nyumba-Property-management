import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import * as functionsV1 from 'firebase-functions/v1';
import { executeCommand } from './callable/execute-command';
import { COLLECTIONS } from './shared/collections';
import { REGION } from './shared/config';
import { expirePublicListings } from './workers/listing-expiry';
import { processBackendJob, sweepBackendJobs } from './workers/jobs';

initializeApp();

export { executeCommand, processBackendJob, sweepBackendJobs, expirePublicListings };

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
