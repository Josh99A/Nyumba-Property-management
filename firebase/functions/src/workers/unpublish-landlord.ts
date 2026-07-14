import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { COLLECTIONS } from '../shared/collections';

export async function unpublishLandlordListings(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const landlordId = String(payload.landlordId);
  const listings = await db.collection(COLLECTIONS.privateListings)
    .where('landlordId', '==', landlordId)
    .where('publicationState', '==', 'published')
    .get();
  for (const listingDoc of listings.docs) {
    await db.runTransaction(async (tx) => {
      const listingRef = listingDoc.ref;
      const publicRef = db.collection(COLLECTIONS.publicListings).doc(listingDoc.id);
      const accountRef = db.collection(COLLECTIONS.landlordAccounts).doc(landlordId);
      const unitRef = db.collection(COLLECTIONS.units).doc(String(listingDoc.data().unitId));
      const [listing, publicListing, account, unit] = await Promise.all([
        tx.get(listingRef), tx.get(publicRef), tx.get(accountRef), tx.get(unitRef),
      ]);
      if (listing.data()?.publicationState !== 'published') return;
      const now = Timestamp.now();
      tx.update(listingRef, { publicationState: 'unpublished', updatedAt: now, version: Number(listing.data()?.version) + 1 });
      if (publicListing.exists) tx.update(publicRef, { status: 'unpublished', updatedAt: now, version: Number(publicListing.data()?.version) + 1 });
      if (unit.exists) tx.update(unitRef, { activePublicListingId: null, updatedAt: now, version: Number(unit.data()?.version) + 1 });
      if (account.exists) tx.update(accountRef, { activeListingCount: Math.max(0, Number(account.data()?.activeListingCount) - 1), updatedAt: now, version: Number(account.data()?.version) + 1 });
      tx.set(db.collection(COLLECTIONS.backendJobs).doc(`cleanup_suspended_${listingDoc.id}`), {
        id: `cleanup_suspended_${listingDoc.id}`, type: 'cleanupListingMedia', payload: { listingId: listingDoc.id },
        state: 'pending', attemptCount: 0, nextAttemptAt: now, leaseUntil: null, createdAt: now, updatedAt: now,
      }, { merge: true });
    });
  }
}
