import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { COLLECTIONS, CLIENT_PORTAL_SECTIONS } from '../shared/collections';
import { clientContactProjection } from '../shared/projections';
import { deliverUserNotification } from '../shared/messaging';

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
  // The canonical record names the recipient; the job payload carries the same
  // value but is never treated as the authority on who owns the application.
  if (typeof application.landlordId !== 'string' || !application.landlordId) return;

  await deliverUserNotification(application.landlordId, {
    id: `application_${applicationId}`,
    kind: 'application',
    templateKey: 'new_application',
    relatedEntityId: applicationId,
    data: { route: '/listings', applicationId, listingId: String(application.listingId ?? '') },
  });
}

/** Rent amount as a readable UGX string for a notification body. */
function ugx(amountMinor: unknown): string {
  const minor = typeof amountMinor === 'number' ? amountMinor : 0;
  return `UGX ${(minor / 100).toLocaleString('en-UG', { maximumFractionDigits: 0 })}`;
}

/**
 * Tells a landlord their tenant reported a payment that needs reviewing.
 *
 * A declaration settles nothing until the landlord acts on it, so this nudge
 * is the difference between money being confirmed today and sitting unnoticed
 * for a month.
 */
export async function notifyLandlordPaymentDeclared(
  payload: Record<string, unknown>,
): Promise<void> {
  const db = getFirestore();
  const paymentId = String(payload.paymentId);
  const snapshot = await db.collection(COLLECTIONS.payments).doc(paymentId).get();
  const payment = snapshot.data();
  // Re-read rather than trust the payload: a landlord who already reviewed it
  // must not be pinged about a decision they have made.
  if (!payment || payment.status !== 'declared') return;
  const landlordId = typeof payment.landlordId === 'string' ? payment.landlordId : null;
  if (!landlordId) return;

  await deliverUserNotification(landlordId, {
    id: `payment_declared_${paymentId}`,
    kind: 'system',
    custom: {
      title: 'A tenant reported a payment',
      body: `${ugx(payment.amountMinor)} for ${String(payment.period ?? 'rent')} `
        + `is waiting for you to confirm or reject.`,
    },
    relatedEntityId: paymentId,
    data: { route: '/finances', paymentId },
  });
}

/**
 * Tells a tenant their reported payment was not accepted, and why, so a
 * rejection is never silent.
 */
export async function notifyTenantPaymentRejected(
  payload: Record<string, unknown>,
): Promise<void> {
  const db = getFirestore();
  const paymentId = String(payload.paymentId);
  const snapshot = await db.collection(COLLECTIONS.payments).doc(paymentId).get();
  const payment = snapshot.data();
  if (!payment || payment.status !== 'rejected') return;
  const tenantUid = typeof payment.declaredByUid === 'string'
    ? payment.declaredByUid
    : typeof payment.tenantUserUid === 'string'
      ? payment.tenantUserUid
      : null;
  if (!tenantUid) return;

  const note = typeof payment.rejectionNote === 'string' && payment.rejectionNote
    ? ` ${payment.rejectionNote}`
    : '';
  await deliverUserNotification(tenantUid, {
    id: `payment_rejected_${paymentId}`,
    kind: 'system',
    custom: {
      title: 'Your reported payment was not confirmed',
      body: `${ugx(payment.amountMinor)} for ${String(payment.period ?? 'rent')} `
        + `could not be confirmed by your landlord.${note} Your balance is unchanged.`,
    },
    relatedEntityId: paymentId,
    data: { route: '/tenant/payments', paymentId },
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

  // The canonical record, not the job payload, says who owns the listing.
  const landlordId = typeof contact.landlordId === 'string' ? contact.landlordId : null;
  const deliveryState = landlordId ? 'delivered' : 'undeliverable';
  const now = Timestamp.now();
  const next = {
    ...contact,
    deliveryState,
    deliveredAt: landlordId ? now : null,
    version: Number(contact.version ?? 1) + 1,
    updatedAt: now,
  };
  // One batch, so a retry after a partial failure can never leave the
  // canonical delivery state and the prospect's portal disagreeing.
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

  await deliverUserNotification(landlordId, {
    id: `enquiry_${contactRequestId}`,
    kind: 'enquiry',
    templateKey: 'new_enquiry',
    relatedEntityId: contactRequestId,
    data: { route: '/listings', contactRequestId, listingId: String(contact.listingId ?? '') },
  });
}
