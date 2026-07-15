import { Timestamp } from 'firebase-admin/firestore';
import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { COLLECTIONS, CLIENT_PORTAL_SECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import { createJob, idSchema, longText, shortText, strictPayload, type CommandHandler } from '../shared/handlers';
import { clientApplicationProjection, clientContactProjection } from '../shared/projections';

const applicationSchema = strictPayload({
  listingId: idSchema,
  displayName: shortText,
  email: z.string().email().max(320),
  phone: z.string().trim().min(7).max(32),
  message: longText,
  answers: z.record(z.string().max(1_000)).default({}),
});

export const applicationSubmit: CommandHandler<z.infer<typeof applicationSchema>> = {
  payloadSchema: applicationSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const appRef = db.collection(COLLECTIONS.applications).doc(cmd.aggregateId!);
    const publicRef = db.collection(COLLECTIONS.publicListings).doc(cmd.payload.listingId);
    const privateRef = db.collection(COLLECTIONS.privateListings).doc(cmd.payload.listingId);
    // Fetch a handful and filter in code so a withdrawn application does not
    // permanently block re-applying (avoids an extra composite index).
    const duplicateQuery = db.collection(COLLECTIONS.applications)
      .where('listingId', '==', cmd.payload.listingId)
      .where('applicantUid', '==', actor.uid)
      .limit(10);
    const [appSnap, publicSnap, privateSnap, duplicates] = await Promise.all([
      tx.get(appRef), tx.get(publicRef), tx.get(privateRef), tx.get(duplicateQuery),
    ]);
    requireAbsent(appSnap);
    const publicListing = publicSnap.data();
    const privateListing = privateSnap.data();
    if (!publicSnap.exists || publicListing?.status !== 'published' || !(publicListing.expiresAt instanceof Timestamp) || publicListing.expiresAt.toMillis() <= now.toMillis()) {
      throw new DomainError('NOT_FOUND');
    }
    if (!privateSnap.exists || typeof privateListing?.landlordId !== 'string') throw new DomainError('NOT_FOUND');
    const hasOpenApplication = duplicates.docs.some(
      (document) => document.data().status !== 'withdrawn',
    );
    if (hasOpenApplication) throw new DomainError('ALREADY_EXISTS');
    const canonical = {
      ...newAggregate(cmd.aggregateId!, now), listingId: cmd.payload.listingId,
      landlordId: privateListing.landlordId, applicantUid: actor.uid,
      displayName: cmd.payload.displayName, email: cmd.payload.email, phone: cmd.payload.phone,
      message: cmd.payload.message, answers: cmd.payload.answers, status: 'submitted', landlordNotes: null,
    };
    tx.create(appRef, canonical);
    tx.set(db.collection(COLLECTIONS.clientPortals).doc(actor.uid).collection(CLIENT_PORTAL_SECTIONS.applications).doc(cmd.aggregateId!), clientApplicationProjection(canonical));
    createJob(tx, db, `${cmd.commandId}_notify`, 'notifyLandlordApplication', { applicationId: cmd.aggregateId!, landlordId: privateListing.landlordId }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: ['status'] };
  },
};

export const applicationWithdraw: CommandHandler<Record<string, never>> = {
  payloadSchema: strictPayload({}),
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.applications).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const application = requireAggregate<Record<string, unknown> & { version: number; applicantUid: string; status: string }>(snapshot, cmd.expectedVersion);
    if (application.applicantUid !== actor.uid) throw new DomainError('PERMISSION_DENIED');
    if (application.status !== 'submitted') throw new DomainError('VALIDATION_FAILED', { reason: 'applicationNotWithdrawable' });
    const changes = { status: 'withdrawn', withdrawnAt: now, ...bumpVersion(application, now) };
    tx.update(ref, changes);
    tx.set(db.collection(COLLECTIONS.clientPortals).doc(actor.uid).collection(CLIENT_PORTAL_SECTIONS.applications).doc(cmd.aggregateId!), clientApplicationProjection({ ...application, ...changes }));
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: application.version + 1, changedFields: ['status', 'withdrawnAt'] };
  },
};

const contactSchema = strictPayload({
  listingId: idSchema,
  displayName: shortText,
  email: z.string().email().max(320),
  phone: z.string().trim().min(7).max(32).optional(),
  message: longText,
});

export const contactSubmit: CommandHandler<z.infer<typeof contactSchema>> = {
  payloadSchema: contactSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.contactRequests).doc(cmd.aggregateId!);
    const listingRef = db.collection(COLLECTIONS.publicListings).doc(cmd.payload.listingId);
    const privateRef = db.collection(COLLECTIONS.privateListings).doc(cmd.payload.listingId);
    const cutoff = Timestamp.fromMillis(now.toMillis() - 60 * 60 * 1000);
    const recentQuery = db.collection(COLLECTIONS.contactRequests)
      .where('requesterUid', '==', actor.uid)
      .where('createdAt', '>=', cutoff)
      .limit(6);
    const [snapshot, listingSnap, privateSnap, recent] = await Promise.all([
      tx.get(ref), tx.get(listingRef), tx.get(privateRef), tx.get(recentQuery),
    ]);
    requireAbsent(snapshot);
    const listing = listingSnap.data();
    const privateListing = privateSnap.data();
    if (!listingSnap.exists || listing?.status !== 'published' || !privateSnap.exists) throw new DomainError('NOT_FOUND');
    if (recent.size >= 5) throw new DomainError('RATE_LIMITED', { retryAfterSeconds: 3600 });
    const contact = {
      ...newAggregate(cmd.aggregateId!, now), listingId: cmd.payload.listingId,
      landlordId: privateListing?.landlordId, requesterUid: actor.uid,
      displayName: cmd.payload.displayName, email: cmd.payload.email, phone: cmd.payload.phone ?? null,
      message: cmd.payload.message, deliveryState: 'pending',
    };
    tx.create(ref, contact);
    // The requester projection must not reveal the landlord's UID; the public
    // listing only exposes an opaque contact token.
    tx.set(db.collection(COLLECTIONS.clientPortals).doc(actor.uid).collection(CLIENT_PORTAL_SECTIONS.contactRequests).doc(cmd.aggregateId!), clientContactProjection(contact));
    createJob(tx, db, `${cmd.commandId}_notify`, 'deliverContactRequest', { contactRequestId: cmd.aggregateId!, landlordId: privateListing?.landlordId }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: ['deliveryState'] };
  },
};
