import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { COLLECTIONS, CLIENT_PORTAL_SECTIONS } from '../shared/collections';
import { clientContactProjection } from '../shared/projections';
import { notifyUser } from '../shared/messaging';

/**
 * Tells a landlord a prospect applied to one of their listings.
 *
 * The application document is already canonical and landlord-readable by the
 * time this runs, so the push is a nudge, not the delivery mechanism. A landlord
 * with notifications off still sees the application in their app.
 */
export async function notifyLandlordApplication(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const applicationId = String(payload.applicationId);
  const snapshot = await db.collection(COLLECTIONS.applications).doc(applicationId).get();
  if (!snapshot.exists) return;
  const application = snapshot.data()!;
  if (application.isDeleted === true || application.status === 'withdrawn') return;
  const landlordId = String(application.landlordId);

  await notifyUser(landlordId, {
    title: 'New application',
    body: `${String(application.displayName ?? 'A prospect')} applied to one of your listings.`,
    data: { route: '/listings', applicationId, listingId: String(application.listingId ?? '') },
  });
}

/**
 * Delivers a prospect's contact request to the landlord and records the
 * delivery state on both the canonical record and the prospect's portal, so the
 * sender can tell whether their message actually went anywhere.
 *
 * A contact request with no landlord (the listing was unpublished or removed
 * between submission and delivery) is terminal, not retryable.
 */
export async function deliverContactRequest(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const contactRequestId = String(payload.contactRequestId);
  const ref = db.collection(COLLECTIONS.contactRequests).doc(contactRequestId);
  const snapshot = await ref.get();
  if (!snapshot.exists) return;
  const contact = snapshot.data()!;
  if (contact.deliveryState === 'delivered' || contact.deliveryState === 'undeliverable') return;

  const landlordId = typeof payload.landlordId === 'string' ? payload.landlordId : null;
  const deliveryState = landlordId ? 'delivered' : 'undeliverable';
  const now = Timestamp.now();
  const next = {
    ...contact,
    deliveryState,
    deliveredAt: landlordId ? now : null,
    version: Number(contact.version ?? 1) + 1,
    updatedAt: now,
  };
  const batch = db.batch();
  batch.update(ref, {
    deliveryState,
    deliveredAt: landlordId ? now : null,
    version: next.version,
    updatedAt: now,
  });

  // `requesterUid` is what contact.submit writes and what keys the prospect's
  // portal; there is no `clientUid` field on a contact request.
  if (typeof contact.requesterUid === 'string') {
    batch.set(
      db
        .collection(COLLECTIONS.clientPortals)
        .doc(contact.requesterUid)
        .collection(CLIENT_PORTAL_SECTIONS.contactRequests)
        .doc(contactRequestId),
      clientContactProjection(next),
    );
  }
  await batch.commit();
  if (!landlordId) return;

  await notifyUser(landlordId, {
    title: 'New enquiry',
    body: `${String(contact.displayName ?? 'Someone')} asked about one of your listings.`,
    data: { route: '/listings', contactRequestId, listingId: String(contact.listingId ?? '') },
  });
}
