import {
  getFirestore,
  Timestamp,
  type QueryDocumentSnapshot,
} from 'firebase-admin/firestore';
import { landlordPublicToken } from '../shared/canonical';
import { COLLECTIONS } from '../shared/collections';
import { ratingBadge, readTotals } from '../shared/ratings';

/**
 * Listings stamped per page. Kept at the batched-write ceiling of 500 minus
 * headroom, so one page is exactly one commit.
 */
const BADGE_PAGE_SIZE = 400;

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
  //
  // Read a page at a time rather than the whole result set. The doc comment
  // above is explicit that a landlord's live listing count is unbounded, and a
  // single `.get()` pulls every one of those documents into this function's
  // memory before the first batch is written — the same unbounded cost the job
  // exists to keep out of the review transaction.
  //
  // `__name__` is the sort key because it is the one field guaranteed present,
  // unique, and immutable across the page loop; the deployed
  // (landlordToken, status) composite index already carries it as its implicit
  // tie-breaker, so this needs no new index.
  const query = db.collection(COLLECTIONS.publicListings)
    .where('landlordToken', '==', landlordPublicToken(landlordId))
    .where('status', '==', 'published')
    .orderBy('__name__')
    .limit(BADGE_PAGE_SIZE);

  const now = Timestamp.now();
  let cursor: QueryDocumentSnapshot | undefined;

  while (true) {
    const page = await (cursor === undefined ? query : query.startAfter(cursor)).get();
    if (page.empty) break;

    const batch = db.batch();
    for (const listing of page.docs) {
      // `update` rather than a merged `set`: if a listing was unpublished
      // between the query and this commit, the right outcome is for the batch
      // to fail and the job to retry against a fresh query — not to write a
      // badge back onto a document that is no longer public.
      batch.update(listing.ref, { ...badge, updatedAt: now });
    }
    await batch.commit();

    if (page.docs.length < BADGE_PAGE_SIZE) break;
    cursor = page.docs.at(-1);
  }
}
