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
 * Destroys an archived property. Refuses while any unit still references it —
 * including archived units, which a purge would orphan beyond recovery, so
 * the units must be purged first. Staged photos are removed by a follow-up
 * job because Storage deletion cannot join the Firestore transaction.
 */
export const propertyDelete: CommandHandler<PurgeReason> = {
  payloadSchema: purgeReasonSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requireSuperAdmin(actor);
    const ref = db.collection(COLLECTIONS.properties).doc(cmd.aggregateId!);
    const unitsQuery = db
      .collection(COLLECTIONS.units)
      .where('propertyId', '==', cmd.aggregateId!)
      .limit(1);
    const [snapshot, units] = await Promise.all([tx.get(ref), tx.get(unitsQuery)]);
    const current = requireAggregate<ArchivableAggregate & { stagedImagePaths?: unknown }>(
      snapshot,
      cmd.expectedVersion,
      { allowDeleted: true },
    );
    if (current.isDeleted !== true) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'notArchived' });
    }
    if (!units.empty) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'propertyHasUnits' });
    }
    const paths = Array.isArray(current.stagedImagePaths)
      ? current.stagedImagePaths.filter((path): path is string => typeof path === 'string')
      : [];
    tx.delete(ref);
    if (paths.length > 0) {
      createJob(tx, db, `${cmd.commandId}_media`, 'purgeStorageObjects', { paths }, now);
    }
    return {
      status: paths.length > 0 ? 'accepted' : 'applied',
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
  async apply({ tx, db, actor, cmd }) {
    requireSuperAdmin(actor);
    const ref = db.collection(COLLECTIONS.units).doc(cmd.aggregateId!);
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
    tx.delete(ref);
    return {
      status: 'applied',
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
