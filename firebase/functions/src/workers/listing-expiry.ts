import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { writeAudit } from '../shared/audit';
import { COLLECTIONS } from '../shared/collections';
import { REGION } from '../shared/config';

export const expirePublicListings = onSchedule(
  { schedule: 'every 60 minutes', region: REGION, timeZone: 'UTC' },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const expired = await db.collection(COLLECTIONS.publicListings)
      .where('status', '==', 'published')
      .where('expiresAt', '<=', now)
      .limit(100)
      .get();
    for (const candidate of expired.docs) {
      await db.runTransaction(async (tx) => {
        const publicRef = candidate.ref;
        const privateRef = db.collection(COLLECTIONS.privateListings).doc(candidate.id);
        const expiry = candidate.data().expiresAt as Timestamp;
        const guardId = `listingExpiry_${candidate.id}_${expiry.toMillis()}`;
        const guardRef = db.collection(COLLECTIONS.backendJobs).doc(guardId);
        const cleanupRef = db.collection(COLLECTIONS.backendJobs).doc(`${guardId}_cleanup`);
        const initialPrivate = await tx.get(privateRef);
        const landlordId = String(initialPrivate.data()?.landlordId ?? '');
        const accountRef = db.collection(COLLECTIONS.landlordAccounts).doc(landlordId);
        const unitRef = db.collection(COLLECTIONS.units).doc(String(initialPrivate.data()?.unitId ?? ''));
        const [guard, publicListing, privateListing, account, unit] = await Promise.all([
          tx.get(guardRef), tx.get(publicRef), tx.get(privateRef), tx.get(accountRef), tx.get(unitRef),
        ]);
        if (guard.exists) return;
        const currentExpiry = publicListing.data()?.expiresAt as Timestamp | undefined;
        if (publicListing.data()?.status !== 'published' || !currentExpiry || currentExpiry.toMillis() > now.toMillis()) return;
        tx.create(guardRef, {
          id: guardId, type: 'listingExpiryGuard', payload: { listingId: candidate.id }, state: 'succeeded',
          attemptCount: 0, nextAttemptAt: null, leaseUntil: null, createdAt: now, updatedAt: now, completedAt: now,
        });
        tx.update(publicRef, { status: 'expired', version: Number(publicListing.data()?.version) + 1, updatedAt: now });
        if (privateListing.exists) {
          tx.update(privateRef, { publicationState: 'expired', version: Number(privateListing.data()?.version) + 1, updatedAt: now });
        }
        if (unit.exists) {
          tx.update(unitRef, { activePublicListingId: null, version: Number(unit.data()?.version) + 1, updatedAt: now });
        }
        if (account.exists) {
          tx.update(accountRef, { activeListingCount: Math.max(0, Number(account.data()?.activeListingCount) - 1), version: Number(account.data()?.version) + 1, updatedAt: now });
        }
        tx.create(cleanupRef, {
          id: cleanupRef.id, type: 'cleanupListingMedia', payload: { listingId: candidate.id }, state: 'pending',
          attemptCount: 0, nextAttemptAt: now, leaseUntil: null, createdAt: now, updatedAt: now,
        });
        writeAudit(tx, db, now, {
          actor: { uid: 'system', platformAdmin: true, emailVerified: true, signInProvider: null },
          commandId: guardId,
          commandType: 'listing.expire',
          aggregateId: candidate.id,
          outcome: 'accepted',
          reasonCode: 'LISTING_LIFETIME_ELAPSED',
          changedFields: ['status', 'publicationState', 'activePublicListingId'],
        });
      });
    }
  },
);
