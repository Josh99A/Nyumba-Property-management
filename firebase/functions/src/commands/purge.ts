import { z } from 'zod';
import { requireAggregate } from '../shared/aggregates';
import { requireSuperAdmin } from '../shared/actor';
import { COLLECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import { createJob, strictPayload, type CommandHandler } from '../shared/handlers';

/**
 * Permanent removal of records that are already out of circulation.
 *
 * Every command here is super-admin only and destroys the canonical document
 * rather than tombstoning it — the archive is the reversible state, and this
 * is the deliberate second step out of it. Ordinary administrators archive;
 * only a super admin purges.
 *
 * None of these load a landlord context. The workspace gates
 * (`loadActiveLandlordContext`) reject suspended and unsubscribed accounts,
 * and cleaning up after exactly those accounts is the point of this file.
 * Authorization here is the super-admin claim plus the archived precondition.
 */
const purgeReasonSchema = strictPayload({
  reasonCode: z.enum([
    'POLICY_VIOLATION',
    'FRAUD_RISK',
    'USER_REQUESTED',
    'DATA_RETENTION',
    'ADMIN_CORRECTION',
  ]),
});

type PurgeReason = z.infer<typeof purgeReasonSchema>;

interface ArchivableAggregate {
  version: number;
  isDeleted?: boolean;
  landlordId?: string;
}

/**
 * Handler writes available to the cascade.
 *
 * Firestore caps a transaction at 500 writes. The command router always adds
 * the command receipt and audit entry after the handler returns, so the
 * cascade must leave two writes free for them.
 */
const MAX_CASCADE_HANDLER_WRITES = 498;

/** Firestore `in` filters accept at most 30 values. */
const IN_QUERY_LIMIT = 30;

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

/**
 * Destroys an archived property and everything under it: its rental spaces and
 * their listings, private and public copies together. Tenancy, lease, payment,
 * document, maintenance and notice history is deliberately kept — this is a
 * portfolio cleanup, not an accounting erasure.
 *
 * The cascade only ever reaches records that are already out of circulation. A
 * property can only be archived once every unit is archived, and a unit can
 * only be archived while vacant and unadvertised, so a cascade never destroys
 * an occupied space or a live advert and never has to touch a plan counter (the
 * archive that preceded it already did). Those invariants are still re-checked
 * here and the whole command refuses if any of them fail to hold. Storage
 * objects are removed by follow-up jobs because Storage cannot join the
 * Firestore transaction.
 */
export const propertyDelete: CommandHandler<PurgeReason> = {
  payloadSchema: purgeReasonSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requireSuperAdmin(actor);
    const ref = db.collection(COLLECTIONS.properties).doc(cmd.aggregateId!);
    const unitsSnap = await tx.get(
      db.collection(COLLECTIONS.units).where('propertyId', '==', cmd.aggregateId!),
    );
    const snapshot = await tx.get(ref);
    const current = requireAggregate<ArchivableAggregate & { stagedImagePaths?: unknown }>(
      snapshot,
      cmd.expectedVersion,
      { allowDeleted: true },
    );
    if (current.isDeleted !== true) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'notArchived' });
    }

    const units = unitsSnap.docs.map((doc) => ({
      id: doc.id,
      ...(doc.data() as { activeLeaseId?: string | null }),
    }));
    // Defensive: an archived property should never still own an active or
    // occupied space, but refuse rather than silently erase one if it does.
    if (units.some((unit) => unit.activeLeaseId)) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'propertyHasActiveUnits' });
    }

    const unitIds = units.map((unit) => unit.id);
    const listingSnaps = await Promise.all(
      chunk(unitIds, IN_QUERY_LIMIT).map((ids) =>
        tx.get(db.collection(COLLECTIONS.privateListings).where('unitId', 'in', ids)),
      ),
    );
    const listings = listingSnaps.flatMap((snap) =>
      snap.docs.map((doc) => ({
        id: doc.id,
        ...(doc.data() as { publicationState?: string }),
      })),
    );
    if (listings.some((listing) => listing.publicationState === 'published')) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'listingStillPublished' });
    }

    const publicSnaps = await Promise.all(
      listings.map((listing) =>
        tx.get(db.collection(COLLECTIONS.publicListings).doc(listing.id)),
      ),
    );

    const propertyPaths = Array.isArray(current.stagedImagePaths)
      ? current.stagedImagePaths.filter((path): path is string => typeof path === 'string')
      : [];
    const listingCleanupJobs = listings.length;
    const propertyMediaJob = propertyPaths.length > 0 ? 1 : 0;
    const totalWrites =
      1 + units.length + listings.length + publicSnaps.filter((snap) => snap.exists).length +
      listingCleanupJobs + propertyMediaJob;
    if (totalWrites > MAX_CASCADE_HANDLER_WRITES) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'portfolioTooLargeToCascade' });
    }

    for (const unit of units) {
      tx.delete(db.collection(COLLECTIONS.units).doc(unit.id));
    }
    listings.forEach((listing, index) => {
      tx.delete(db.collection(COLLECTIONS.privateListings).doc(listing.id));
      if (publicSnaps[index]?.exists) {
        tx.delete(db.collection(COLLECTIONS.publicListings).doc(listing.id));
      }
      createJob(tx, db, `${cmd.commandId}_listing_${index}`, 'cleanupListingMedia', {
        listingId: listing.id,
      }, now);
    });
    tx.delete(ref);
    if (propertyPaths.length > 0) {
      createJob(tx, db, `${cmd.commandId}_media`, 'purgeStorageObjects', { paths: propertyPaths }, now);
    }
    return {
      status: listingCleanupJobs > 0 || propertyMediaJob > 0 ? 'accepted' : 'applied',
      aggregateId: cmd.aggregateId!,
      // The document is gone; the last version it held is the honest answer.
      serverVersion: current.version,
      changedFields: [],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

/**
 * Destroys an archived unit. `unit.archive` already refuses while the space is
 * occupied or advertised and already decremented `activeUnitCount`, so this
 * only re-checks the pointers and must NOT touch the counter again.
 */
export const unitDelete: CommandHandler<PurgeReason> = {
  payloadSchema: purgeReasonSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requireSuperAdmin(actor);
    const ref = db.collection(COLLECTIONS.units).doc(cmd.aggregateId!);
    const listingsSnap = await tx.get(
      db.collection(COLLECTIONS.privateListings).where('unitId', '==', cmd.aggregateId!),
    );
    const snapshot = await tx.get(ref);
    const current = requireAggregate<
      ArchivableAggregate & { activeLeaseId?: string | null; activePublicListingId?: string | null }
    >(snapshot, cmd.expectedVersion, { allowDeleted: true });
    if (current.isDeleted !== true) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'notArchived' });
    }
    if (current.activeLeaseId || current.activePublicListingId) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'unitStillLinked' });
    }

    const listings = listingsSnap.docs.map((doc) => ({
      id: doc.id,
      ...(doc.data() as { publicationState?: string }),
    }));
    if (listings.some((listing) => listing.publicationState === 'published')) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'listingStillPublished' });
    }
    const publicSnaps = await Promise.all(
      listings.map((listing) =>
        tx.get(db.collection(COLLECTIONS.publicListings).doc(listing.id)),
      ),
    );
    const totalWrites =
      1 + listings.length + publicSnaps.filter((snap) => snap.exists).length +
      listings.length;
    if (totalWrites > MAX_CASCADE_HANDLER_WRITES) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'portfolioTooLargeToCascade' });
    }

    listings.forEach((listing, index) => {
      tx.delete(db.collection(COLLECTIONS.privateListings).doc(listing.id));
      if (publicSnaps[index]?.exists) {
        tx.delete(db.collection(COLLECTIONS.publicListings).doc(listing.id));
      }
      createJob(tx, db, `${cmd.commandId}_listing_${index}`, 'cleanupListingMedia', {
        listingId: listing.id,
      }, now);
    });
    tx.delete(ref);
    return {
      status: listings.length > 0 ? 'accepted' : 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: current.version,
      changedFields: [],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

/**
 * Destroys a listing that is off the market, private projection and public
 * projection together. A published listing must be unpublished first so the
 * ordinary retirement path clears `unit.activePublicListingId` and decrements
 * `activeListingCount` — by the time a listing is unpublished, expired, or
 * still a draft, neither of those points at it.
 */
export const listingDelete: CommandHandler<PurgeReason> = {
  payloadSchema: purgeReasonSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requireSuperAdmin(actor);
    const privateRef = db.collection(COLLECTIONS.privateListings).doc(cmd.aggregateId!);
    const publicRef = db.collection(COLLECTIONS.publicListings).doc(cmd.aggregateId!);
    const [privateSnap, publicSnap] = await Promise.all([tx.get(privateRef), tx.get(publicRef)]);
    const current = requireAggregate<ArchivableAggregate & { publicationState?: string }>(
      privateSnap,
      cmd.expectedVersion,
      { allowDeleted: true },
    );
    if (current.publicationState === 'published') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'listingStillPublished' });
    }
    tx.delete(privateRef);
    if (publicSnap.exists) tx.delete(publicRef);
    createJob(tx, db, `${cmd.commandId}_cleanup`, 'cleanupListingMedia', { listingId: cmd.aggregateId! }, now);
    return {
      status: 'accepted',
      aggregateId: cmd.aggregateId!,
      serverVersion: current.version,
      changedFields: [],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

/**
 * Purges a soft-deleted document immediately instead of waiting out the
 * 90-day retention window `document.delete` schedules. The existing
 * `purgeDocument` worker does the work — it deletes the private object and
 * then the record — so this only has to enqueue it without a `runAt`.
 */
export const documentPurge: CommandHandler<PurgeReason> = {
  payloadSchema: purgeReasonSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requireSuperAdmin(actor);
    const ref = db.collection(COLLECTIONS.documents).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<ArchivableAggregate>(snapshot, cmd.expectedVersion, {
      allowDeleted: true,
    });
    if (current.isDeleted !== true) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'notDeleted' });
    }
    createJob(tx, db, `${cmd.commandId}_purge`, 'purgeDocument', { documentId: cmd.aggregateId! }, now);
    return {
      status: 'accepted',
      aggregateId: cmd.aggregateId!,
      serverVersion: current.version,
      changedFields: [],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};
