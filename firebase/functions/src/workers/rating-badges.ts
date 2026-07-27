import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { landlordPublicToken } from '../shared/canonical';
import { COLLECTIONS } from '../shared/collections';
import { ratingBadge, readTotals } from '../shared/ratings';

/**
 * Copies a landlord's current rating onto every listing they have live.
 *
 * Firestore cannot join, so a marketplace card that shows a rating has to carry
 * one. But a landlord's live listing count is unbounded, which is exactly why
 * this is a job and not part of the review transaction: stamping N listings
 * inline would make one tenant's review cost scale with the size of the
 * landlord's portfolio and eventually exceed the transaction write limit,
 * failing the submission itself.
 *
 * Badges are therefore eventually consistent, by design. A card showing a
 * rating a few seconds stale is unnoticeable; a review that could not be
 * submitted because its landlord owns two hundred listings is not.
 *
 * The authoritative numbers always live in `landlordRatings` and
 * `publicLandlordRatings`, which the review transaction writes atomically. This
 * only refreshes the denormalized copies.
 */
export async function refreshLandlordRatingBadges(
  payload: Record<string, unknown>,
): Promise<void> {
  const db = getFirestore();
  const landlordId = String(payload.landlordId);
  if (!landlordId) return;

  const ratingSnap = await db.collection(COLLECTIONS.landlordRatings).doc(landlordId).get();
  // A missing rating document means every review was withdrawn or moderated
  // away; the correct badge then is the empty one, not a stale leftover.
  const badge = ratingBadge(readTotals(ratingSnap.data()));

  // Queried on the public collection by token rather than walking
  // `privateListings` and deriving IDs: it targets exactly the documents being
  // written, so there is no private listing whose public projection was already
  // retired and would be resurrected as a badge-only document.
  const published = await db.collection(COLLECTIONS.publicListings)
    .where('landlordToken', '==', landlordPublicToken(landlordId))
    .where('status', '==', 'published')
    .get();

  const now = Timestamp.now();
  for (let start = 0; start < published.docs.length; start += 400) {
    const batch = db.batch();
    for (const listing of published.docs.slice(start, start + 400)) {
      // `update` rather than a merged `set`: if a listing was unpublished
      // between the query and this commit, the right outcome is for the batch
      // to fail and the job to retry against a fresh query — not to write a
      // badge back onto a document that is no longer public.
      batch.update(listing.ref, { ...badge, updatedAt: now });
    }
    await batch.commit();
  }
}
