import { createHash } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import {
  loadActiveLandlordContext,
  requireOwnedByLandlord,
  requireWorkspace,
} from '../shared/accounts';
import { COLLECTIONS } from '../shared/collections';
import { LISTING_LIFETIME_DAYS } from '../shared/config';
import { DomainError } from '../shared/errors';
import {
  createJob,
  idSchema,
  longText,
  nonNegativeMoney,
  shortText,
  strictPayload,
  type CommandHandler,
} from '../shared/handlers';

const draftSchema = strictPayload({
  unitId: idSchema,
  title: shortText,
  description: longText,
  monthlyRentMinor: nonNegativeMoney,
  unitType: z.enum(['apartment', 'house', 'shop', 'office', 'bedsitter', 'room', 'other']),
  city: shortText,
  neighborhood: shortText,
  district: shortText.optional(),
  bedrooms: z.number().int().min(0).max(100),
  bathrooms: z.number().int().min(0).max(100),
  amenities: z.array(z.string().trim().min(1).max(100)).max(50),
  approximateLocation: z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) }).strict().optional(),
  stagedImagePaths: z.array(z.string().min(1).max(1_024)).max(10).optional(),
});

function validateStagedPaths(uid: string, paths: string[]): void {
  if (paths.some((path) => !path.startsWith(`uploads/${uid}/`))) {
    throw new DomainError('VALIDATION_FAILED', { fields: ['stagedImagePaths'] });
  }
}

export const listingSaveDraft: CommandHandler<z.infer<typeof draftSchema>> = {
  payloadSchema: draftSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'createOrEdit',
  async apply({ tx, db, actor, cmd, now }) {
    const isStaff = actor.platformAdmin || actor.superAdmin;
    validateStagedPaths(actor.uid, cmd.payload.stagedImagePaths ?? []);
    const listingRef = db.collection(COLLECTIONS.privateListings).doc(cmd.aggregateId!);
    const unitRef = db.collection(COLLECTIONS.units).doc(cmd.payload.unitId);
    const [listingSnap, unitSnap] = await Promise.all([tx.get(listingRef), tx.get(unitRef)]);
    const unit = requireAggregate<Record<string, unknown> & { version: number; landlordId: string }>(unitSnap, undefined);
    const landlord = isStaff
      ? await loadActiveLandlordContext(tx, db, unit.landlordId)
      : await requireWorkspace(tx, db, actor, 'manageListings');
    requireOwnedByLandlord(unit, landlord.landlordId);
    if (cmd.expectedVersion === 0) {
      requireAbsent(listingSnap);
      tx.create(listingRef, {
        ...newAggregate(cmd.aggregateId!, now),
        landlordId: landlord.landlordId,
        publicationState: 'draft',
        mediaState: 'staged',
        ...cmd.payload,
        stagedImagePaths: cmd.payload.stagedImagePaths ?? [],
      });
      return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: Object.keys(cmd.payload) };
    }
    const current = requireAggregate<Record<string, unknown> & { version: number; publicationState: string }>(listingSnap, cmd.expectedVersion);
    requireOwnedByLandlord(current, landlord.landlordId);
    if (current.publicationState === 'published') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'publishedListingIsImmutable' });
    }
    const mediaChanges = cmd.payload.stagedImagePaths
      ? { mediaState: 'staged' }
      : {};
    tx.update(listingRef, { ...cmd.payload, ...mediaChanges, ...bumpVersion(current, now) });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: current.version + 1, changedFields: [...Object.keys(cmd.payload), ...Object.keys(mediaChanges)] };
  },
};

const emptySchema = strictPayload({});

export const listingPublish: CommandHandler<Record<string, never>> = {
  payloadSchema: emptySchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const isStaff = actor.platformAdmin || actor.superAdmin;
    const actorLandlord = isStaff
      ? null
      : await requireWorkspace(tx, db, actor, 'manageListings');
    if (actorLandlord && !actorLandlord.entitlements.advertising) {
      throw new DomainError('ENTITLEMENT_MISSING', { entitlement: 'advertising' });
    }
    const listingRef = db.collection(COLLECTIONS.privateListings).doc(cmd.aggregateId!);
    const listingSnap = await tx.get(listingRef);
    const listing = requireAggregate<Record<string, unknown> & {
      version: number; landlordId: string; unitId: string; publicationState: string;
      title?: string; description?: string; monthlyRentMinor?: number; unitType?: string;
      city?: string; neighborhood?: string; district?: string; bedrooms?: number; bathrooms?: number;
      amenities?: string[]; approximateLocation?: { lat: number; lng: number }; stagedImagePaths?: string[];
    }>(listingSnap, cmd.expectedVersion);
    const landlord = isStaff
      ? await loadActiveLandlordContext(tx, db, listing.landlordId)
      : actorLandlord!;
    requireOwnedByLandlord(listing, landlord.landlordId);
    if (!landlord.entitlements.advertising) throw new DomainError('ENTITLEMENT_MISSING', { entitlement: 'advertising' });
    if (landlord.account.activeListingCount >= landlord.entitlements.activeListingLimit) {
      throw new DomainError('UNIT_LIMIT_REACHED', { listingLimit: landlord.entitlements.activeListingLimit });
    }
    const unitRef = db.collection(COLLECTIONS.units).doc(listing.unitId);
    const unitSnap = await tx.get(unitRef);
    const unit = requireAggregate<{ version: number; landlordId: string; occupancyStatus: string; activePublicListingId?: string | null }>(unitSnap, undefined);
    requireOwnedByLandlord(unit, landlord.landlordId);
    if (unit.occupancyStatus !== 'vacant' || unit.activePublicListingId) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'unitUnavailable' });
    }
    const required: Array<keyof typeof listing> = ['title', 'description', 'monthlyRentMinor', 'unitType', 'city', 'neighborhood'];
    if (required.some((field) => listing[field] === undefined || listing[field] === '')) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'listingMissingPublicFields' });
    }
    // The public map location is intentionally approximate: coordinates are
    // coarsened to ~110 m so the exact address can never be recovered from
    // the public projection.
    const approximateLocation = listing.approximateLocation
      ? {
          lat: Math.round(listing.approximateLocation.lat * 1_000) / 1_000,
          lng: Math.round(listing.approximateLocation.lng * 1_000) / 1_000,
        }
      : null;
    const expiresAt = Timestamp.fromMillis(now.toMillis() + LISTING_LIFETIME_DAYS * 24 * 60 * 60 * 1000);
    const landlordToken = createHash('sha256').update(landlord.landlordId).digest('hex').slice(0, 24);
    const publicRef = db.collection(COLLECTIONS.publicListings).doc(cmd.aggregateId!);
    const existingPublic = await tx.get(publicRef);
    if (existingPublic.exists) {
      const state = existingPublic.data()?.status;
      if (state === 'published') throw new DomainError('ALREADY_EXISTS');
    }

    const publicProjection = {
      id: cmd.aggregateId!,
      version: listing.version + 1,
      title: listing.title,
      description: listing.description,
      monthlyRentMinor: listing.monthlyRentMinor,
      currency: 'UGX',
      unitType: listing.unitType,
      city: listing.city,
      neighborhood: listing.neighborhood,
      ...(listing.district ? { district: listing.district } : {}),
      bedrooms: listing.bedrooms ?? 0,
      bathrooms: listing.bathrooms ?? 0,
      amenities: listing.amenities ?? [],
      approximateLocation,
      landlordToken,
      imagePaths: [],
      status: 'published',
      publishedAt: now,
      expiresAt,
      createdAt: existingPublic.data()?.createdAt ?? now,
      updatedAt: now,
      isDeleted: false,
    };
    tx.set(publicRef, publicProjection);
    tx.update(listingRef, {
      publicationState: 'published',
      publishedAt: now,
      expiresAt,
      mediaState: 'pending',
      ...bumpVersion(listing, now),
    });
    tx.update(unitRef, { activePublicListingId: cmd.aggregateId!, ...bumpVersion(unit, now) });
    tx.update(db.collection(COLLECTIONS.landlordAccounts).doc(landlord.landlordId), {
      activeListingCount: landlord.account.activeListingCount + 1,
      ...bumpVersion(landlord.account, now),
    });
    createJob(tx, db, `${cmd.commandId}_media`, 'publishListingMedia', {
      listingId: cmd.aggregateId!, landlordId: landlord.landlordId, stagedImagePaths: listing.stagedImagePaths ?? [],
    }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: listing.version + 1, safeResult: { expiresAt: expiresAt.toDate().toISOString() }, changedFields: ['publicationState', 'publishedAt', 'expiresAt', 'mediaState'] };
  },
};

export const listingUnpublish: CommandHandler<Record<string, never>> = {
  payloadSchema: emptySchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const isStaff = actor.platformAdmin || actor.superAdmin;
    const listingRef = db.collection(COLLECTIONS.privateListings).doc(cmd.aggregateId!);
    const listingSnap = await tx.get(listingRef);
    const listing = requireAggregate<{ version: number; landlordId: string; unitId: string; publicationState: string }>(listingSnap, undefined);
    const landlord = isStaff
      ? await loadActiveLandlordContext(tx, db, listing.landlordId)
      : await requireWorkspace(tx, db, actor, 'manageListings');
    requireOwnedByLandlord(listing, landlord.landlordId);
    // Delivery is at least once and the unit.update occupancy path may retire
    // the listing first, so a listing that is already off the market is a
    // successful no-op rather than a permanent rejection.
    if (listing.publicationState === 'unpublished') {
      return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: listing.version, changedFields: [] };
    }
    // A real state transition still requires the client's expected version;
    // only the already-achieved idempotent state above may absorb a stale one.
    requireAggregate(listingSnap, cmd.expectedVersion);
    if (listing.publicationState !== 'published') throw new DomainError('VALIDATION_FAILED', { reason: 'listingNotPublished' });
    const unitRef = db.collection(COLLECTIONS.units).doc(listing.unitId);
    const publicRef = db.collection(COLLECTIONS.publicListings).doc(cmd.aggregateId!);
    const [unitSnap, publicSnap] = await Promise.all([tx.get(unitRef), tx.get(publicRef)]);
    const unit = requireAggregate<{ version: number; landlordId: string }>(unitSnap, undefined);
    if (!publicSnap.exists) throw new DomainError('NOT_FOUND');
    tx.update(publicRef, { status: 'unpublished', updatedAt: now, version: (publicSnap.data()?.version as number) + 1 });
    tx.update(listingRef, { publicationState: 'unpublished', ...bumpVersion(listing, now) });
    tx.update(unitRef, { activePublicListingId: null, ...bumpVersion(unit, now) });
    tx.update(db.collection(COLLECTIONS.landlordAccounts).doc(landlord.landlordId), {
      activeListingCount: Math.max(0, landlord.account.activeListingCount - 1),
      ...bumpVersion(landlord.account, now),
    });
    createJob(tx, db, `${cmd.commandId}_cleanup`, 'cleanupListingMedia', { listingId: cmd.aggregateId! }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: listing.version + 1, changedFields: ['publicationState'] };
  },
};

export const listingRenew: CommandHandler<Record<string, never>> = {
  payloadSchema: emptySchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const isStaff = actor.platformAdmin || actor.superAdmin;
    const listingRef = db.collection(COLLECTIONS.privateListings).doc(cmd.aggregateId!);
    const publicRef = db.collection(COLLECTIONS.publicListings).doc(cmd.aggregateId!);
    const [listingSnap, publicSnap] = await Promise.all([tx.get(listingRef), tx.get(publicRef)]);
    const listing = requireAggregate<{ version: number; landlordId: string; publicationState: string }>(listingSnap, cmd.expectedVersion);
    const landlord = isStaff
      ? await loadActiveLandlordContext(tx, db, listing.landlordId)
      : await requireWorkspace(tx, db, actor, 'manageListings');
    requireOwnedByLandlord(listing, landlord.landlordId);
    if (!landlord.entitlements.advertising) throw new DomainError('ENTITLEMENT_MISSING', { entitlement: 'advertising' });
    if (listing.publicationState !== 'published' || publicSnap.data()?.status !== 'published') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'listingNotPublished' });
    }
    const expiresAt = Timestamp.fromMillis(now.toMillis() + LISTING_LIFETIME_DAYS * 24 * 60 * 60 * 1000);
    tx.update(listingRef, { expiresAt, ...bumpVersion(listing, now) });
    tx.update(publicRef, { expiresAt, updatedAt: now, version: (publicSnap.data()?.version as number) + 1 });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: listing.version + 1, safeResult: { expiresAt: expiresAt.toDate().toISOString() }, changedFields: ['expiresAt'] };
  },
};
