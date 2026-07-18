import type { DocumentReference, Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';

import { bumpVersion, requireAggregate } from './aggregates';
import type { LandlordContext } from './accounts';
import { requireOwnedByLandlord } from './accounts';
import { COLLECTIONS } from './collections';
import { createJob } from './handlers';

interface UnitWithActiveListing {
  landlordId: string;
  activePublicListingId?: string | null;
}

interface PublishedListing {
  landlordId: string;
  publicationState: string;
  version: number;
}

/**
 * Everything needed to retire the listing attached to a unit.
 *
 * Loading and applying are deliberately separate: Firestore transactions
 * require all reads to finish before the first write, while occupancy changes
 * also need to load their lease/property state.
 */
export interface ActiveListingRetirement {
  listingId: string;
  listing: PublishedListing;
  listingRef: DocumentReference;
  publicRef: DocumentReference;
  publicExists: boolean;
  publicVersion: number;
}

export async function loadActiveListingRetirement(
  tx: Transaction,
  db: Firestore,
  unit: UnitWithActiveListing,
): Promise<ActiveListingRetirement | null> {
  const listingId = unit.activePublicListingId;
  if (!listingId) return null;

  const listingRef = db.collection(COLLECTIONS.privateListings).doc(listingId);
  const publicRef = db.collection(COLLECTIONS.publicListings).doc(listingId);
  const [listingSnapshot, publicSnapshot] = await Promise.all([
    tx.get(listingRef),
    tx.get(publicRef),
  ]);
  const listing = requireAggregate<PublishedListing>(listingSnapshot, undefined);
  requireOwnedByLandlord(listing, unit.landlordId);
  const publicVersion = publicSnapshot.data()?.version;

  return {
    listingId,
    listing,
    listingRef,
    publicRef,
    publicExists: publicSnapshot.exists,
    publicVersion:
        typeof publicVersion === 'number' && Number.isInteger(publicVersion)
          ? publicVersion
          : 0,
  };
}

/**
 * Retires a published advert in the same transaction that makes its unit
 * unavailable. The public query stops returning it immediately; media cleanup
 * remains asynchronous and idempotent.
 */
export function applyActiveListingRetirement(
  tx: Transaction,
  db: Firestore,
  landlord: LandlordContext,
  retirement: ActiveListingRetirement | null,
  commandId: string,
  now: Timestamp,
): boolean {
  if (!retirement || retirement.listing.publicationState !== 'published') {
    return false;
  }

  tx.update(retirement.listingRef, {
    publicationState: 'unpublished',
    ...bumpVersion(retirement.listing, now),
  });
  if (retirement.publicExists) {
    tx.update(retirement.publicRef, {
      status: 'unpublished',
      updatedAt: now,
      version: retirement.publicVersion + 1,
    });
  }
  tx.update(
    db.collection(COLLECTIONS.landlordAccounts).doc(landlord.landlordId),
    {
      activeListingCount: Math.max(
        0,
        landlord.account.activeListingCount - 1,
      ),
      ...bumpVersion(landlord.account, now),
    },
  );
  createJob(
    tx,
    db,
    `${commandId}_cleanup`,
    'cleanupListingMedia',
    { listingId: retirement.listingId },
    now,
  );
  return true;
}
