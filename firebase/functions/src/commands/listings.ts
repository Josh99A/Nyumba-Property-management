import { Timestamp, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import {
  loadActiveLandlordContext,
  requireActiveLandlord,
  requireOwnedByLandlord,
  requireWorkspace,
} from '../shared/accounts';
import { landlordPublicToken } from '../shared/canonical';
import { COLLECTIONS } from '../shared/collections';
import {
  CURRENCY,
  LISTING_LIFETIME_DAYS,
  MAX_LISTING_PHOTOS,
  MIN_LISTING_PHOTOS,
} from '../shared/config';
import { DomainError } from '../shared/errors';
import { ratingBadge, readTotals } from '../shared/ratings';
import {
  coordinateSchema,
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
  // Nullable so a pin can be taken back, not only set. `listingSaveDraft`
  // spreads the payload onto the draft, so an absent key leaves the stored pin
  // untouched while an explicit null clears it.
  approximateLocation: coordinateSchema.nullable().optional(),
  stagedImagePaths: z.array(z.string().min(1).max(1_024)).max(MAX_LISTING_PHOTOS).optional(),
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
    const unitListingsQuery = db.collection(COLLECTIONS.privateListings)
      .where('unitId', '==', cmd.payload.unitId)
      .limit(2);
    const [listingSnap, unitSnap, unitListingsSnap] = await Promise.all([
      tx.get(listingRef),
      tx.get(unitRef),
      tx.get(unitListingsQuery),
    ]);
    const unit = requireAggregate<Record<string, unknown> & {
      version: number;
      landlordId: string;
      propertyId: string;
    }>(unitSnap, undefined);
    const landlord = isStaff
      ? await loadActiveLandlordContext(tx, db, unit.landlordId)
      : await requireWorkspace(tx, db, actor, 'manageListings');
    requireOwnedByLandlord(unit, landlord.landlordId);
    // A unit holds at most one private listing aggregate. `unitListingsSnap`
    // is the listings already on the *payload's* unit, so this rejects both a
    // second draft for a unit and an edit that tries to move an existing draft
    // onto a unit someone already advertised.
    const requireUnitIsFree = (): void => {
      const existingListing = unitListingsSnap.docs.find(
        (snapshot) => snapshot.id !== cmd.aggregateId,
      );
      if (existingListing) {
        throw new DomainError('ALREADY_EXISTS', {
          reason: 'unitAlreadyHasListing',
          listingId: existingListing.id,
        });
      }
    };
    if (cmd.expectedVersion === 0) {
      requireAbsent(listingSnap);
      requireUnitIsFree();
      tx.create(listingRef, {
        ...newAggregate(cmd.aggregateId!, now),
        landlordId: landlord.landlordId,
        propertyId: unit.propertyId,
        currency: CURRENCY,
        publicationState: 'draft',
        mediaState: 'staged',
        ...cmd.payload,
        stagedImagePaths: cmd.payload.stagedImagePaths ?? [],
      });
      return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: Object.keys(cmd.payload) };
    }
    const current = requireAggregate<Record<string, unknown> & { version: number; publicationState: string; unitId: string }>(listingSnap, cmd.expectedVersion);
    requireOwnedByLandlord(current, landlord.landlordId);
    if (current.publicationState === 'published') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'publishedListingIsImmutable' });
    }
    // `unitId` is on every saveDraft payload, including edits, and is spread
    // onto the aggregate below — so an edit can move a draft to another unit.
    // Only a move needs rechecking; an ordinary edit resends the unit it is
    // already on, and re-running the check for that would reject the listing
    // for colliding with itself if the query ever widened.
    if (cmd.payload.unitId !== current.unitId) requireUnitIsFree();
    const mediaChanges = cmd.payload.stagedImagePaths
      ? { mediaState: 'staged' }
      : {};
    tx.update(listingRef, {
      ...cmd.payload,
      propertyId: unit.propertyId,
      currency: CURRENCY,
      ...mediaChanges,
      ...bumpVersion(current, now),
    });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: current.version + 1, changedFields: [...Object.keys(cmd.payload), ...Object.keys(mediaChanges)] };
  },
};

const emptySchema = strictPayload({});

/**
 * The private pin on the property a unit belongs to, or null when there is not
 * one to inherit.
 *
 * Ownership is rechecked rather than assumed. The unit was already proven to
 * belong to the landlord, but `propertyId` is a field on that document, and a
 * cross-workspace value there must not be able to pull another landlord's
 * coordinate into a public projection.
 */
async function propertyLocation(
  tx: Transaction,
  db: Firestore,
  propertyId: string | undefined,
  landlordId: string,
): Promise<{ lat: number; lng: number } | null> {
  if (!propertyId) return null;
  const snap = await tx.get(db.collection(COLLECTIONS.properties).doc(propertyId));
  const data = snap.data();
  if (!snap.exists || !data || data.isDeleted === true) return null;
  if (data.landlordId !== landlordId) return null;
  const parsed = coordinateSchema.safeParse(data.location);
  return parsed.success ? parsed.data : null;
}

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
      amenities?: string[]; approximateLocation?: { lat: number; lng: number } | null; stagedImagePaths?: string[];
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
    const unit = requireAggregate<{ version: number; landlordId: string; propertyId?: string; occupancyStatus: string; activePublicListingId?: string | null }>(unitSnap, undefined);
    requireOwnedByLandlord(unit, landlord.landlordId);
    if (unit.occupancyStatus !== 'vacant' || unit.activePublicListingId) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'unitUnavailable' });
    }
    const required: Array<keyof typeof listing> = ['title', 'description', 'monthlyRentMinor', 'unitType', 'city', 'neighborhood'];
    if (required.some((field) => listing[field] === undefined || listing[field] === '')) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'listingMissingPublicFields' });
    }
    // The authoritative half of the photo rule. The client refuses to publish a
    // photoless advert too, but that check is a courtesy — this one is what
    // actually keeps empty grey tiles out of the public catalogue, whatever the
    // caller. Staged paths are the right thing to count: unpublishing sweeps the
    // delivered copies, so a republish re-renders from these.
    if ((listing.stagedImagePaths ?? []).length < MIN_LISTING_PHOTOS) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'listingMissingPhotos' });
    }
    // A listing with no pin of its own inherits the property's. The client
    // seeds new drafts from the property, but that is a convenience the server
    // cannot rely on: a draft written before it existed, or by any other
    // caller, reaches here with no location and used to publish an advert that
    // could never appear on the map — silently, because nothing about the
    // publish fails. Inheriting here is what makes republishing an affected
    // listing actually repair it. A pin the landlord placed on the listing
    // still wins; this only fills an absence.
    const inheritedLocation = listing.approximateLocation
      ? null
      : await propertyLocation(tx, db, unit.propertyId, landlord.landlordId);
    // The public map location is intentionally approximate: coordinates are
    // coarsened to ~110 m so the exact address can never be recovered from
    // the public projection.
    const sourceLocation = listing.approximateLocation ?? inheritedLocation;
    const approximateLocation = sourceLocation
      ? {
          lat: Math.round(sourceLocation.lat * 1_000) / 1_000,
          lng: Math.round(sourceLocation.lng * 1_000) / 1_000,
        }
      : null;
    const expiresAt = Timestamp.fromMillis(now.toMillis() + LISTING_LIFETIME_DAYS * 24 * 60 * 60 * 1000);
    const landlordToken = landlordPublicToken(landlord.landlordId);
    const publicRef = db.collection(COLLECTIONS.publicListings).doc(cmd.aggregateId!);
    // Stamp the landlord's current rating at publish time. Without this a new
    // listing shows no badge until the next review happens to trigger the
    // refresh fan-out, so an established landlord's reputation would silently
    // fail to carry over to their newest listing — the one they most want it on.
    const [existingPublic, ratingSnap] = await Promise.all([
      tx.get(publicRef),
      tx.get(db.collection(COLLECTIONS.landlordRatings).doc(landlord.landlordId)),
    ]);
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
      ...ratingBadge(readTotals(ratingSnap.data())),
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
      // Written back at full precision, not coarsened: this is the private
      // aggregate, and the landlord's own screens are entitled to the point
      // they placed. Persisting it makes the inheritance a one-time repair
      // rather than something recomputed on every publish, and means the
      // landlord can see and move the pin the advert will actually use.
      ...(inheritedLocation ? { approximateLocation: inheritedLocation } : {}),
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
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: listing.version + 1, safeResult: { expiresAt: expiresAt.toDate().toISOString() }, changedFields: ['publicationState', 'publishedAt', 'expiresAt', 'mediaState', ...(inheritedLocation ? ['approximateLocation'] : [])] };
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

/**
 * A landlord removing their own off-market advert, private and public copies
 * together. This is the owner's counterpart to the super-admin `listing.delete`
 * purge in `purge.ts`: no audit reason is required because this path always
 * loads the actor's own active landlord workspace and verifies ownership, even
 * when that actor also holds the super-admin claim. Cross-landlord removals
 * must use the reasoned `listing.delete` command. This command also refuses a
 * published advert so the ordinary unpublish path (which clears the unit
 * pointer and the plan counter) always runs first. An off-market listing holds
 * neither pointer nor counter, so there is nothing here to unwind.
 */
export const listingDiscard: CommandHandler<Record<string, never>> = {
  payloadSchema: emptySchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const privateRef = db.collection(COLLECTIONS.privateListings).doc(cmd.aggregateId!);
    const publicRef = db.collection(COLLECTIONS.publicListings).doc(cmd.aggregateId!);
    const [listingSnap, publicSnap] = await Promise.all([tx.get(privateRef), tx.get(publicRef)]);
    const listing = requireAggregate<{ version: number; landlordId: string; publicationState: string }>(
      listingSnap,
      cmd.expectedVersion,
    );
    const landlord = await requireActiveLandlord(tx, db, actor);
    requireOwnedByLandlord(listing, landlord.landlordId);
    if (listing.publicationState === 'published') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'listingStillPublished' });
    }
    tx.delete(privateRef);
    if (publicSnap.exists) tx.delete(publicRef);
    createJob(tx, db, `${cmd.commandId}_cleanup`, 'cleanupListingMedia', { listingId: cmd.aggregateId! }, now);
    return {
      status: 'accepted',
      aggregateId: cmd.aggregateId!,
      serverVersion: listing.version,
      changedFields: [],
    };
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
