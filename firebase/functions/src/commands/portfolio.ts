import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { loadActiveLandlordContext, requireActiveLandlord, requireOwnedByLandlord } from '../shared/accounts';
import { COLLECTIONS } from '../shared/collections';
import { COUNTRY, CURRENCY } from '../shared/config';
import { DomainError } from '../shared/errors';
import {
  idSchema,
  longText,
  nonNegativeMoney,
  optionalShortText,
  shortText,
  strictPayload,
  type CommandHandler,
} from '../shared/handlers';
import {
  applyActiveListingRetirement,
  loadActiveListingRetirement,
} from '../shared/listing-retirement';

const propertyCreateSchema = strictPayload({
  targetLandlordId: idSchema.optional(),
  name: shortText,
  addressLine: shortText,
  city: shortText,
  district: optionalShortText,
  description: longText.optional(),
  stagedImagePaths: z.array(z.string().min(1).max(1_024)).max(5).optional(),
});

function validateStagedPaths(uid: string, paths: string[]): void {
  if (paths.some((path) => !path.startsWith(`uploads/${uid}/`))) {
    throw new DomainError('VALIDATION_FAILED', { fields: ['stagedImagePaths'] });
  }
}

export const propertyCreate: CommandHandler<z.infer<typeof propertyCreateSchema>> = {
  payloadSchema: propertyCreateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    validateStagedPaths(actor.uid, cmd.payload.stagedImagePaths ?? []);
    const isStaff = actor.platformAdmin || actor.superAdmin;
    if (isStaff && !cmd.payload.targetLandlordId) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'targetLandlordRequired' });
    }
    const landlord = isStaff
      ? await loadActiveLandlordContext(tx, db, cmd.payload.targetLandlordId!)
      : await requireActiveLandlord(tx, db, actor);
    const ref = db.collection(COLLECTIONS.properties).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    requireAbsent(snapshot);
    const { targetLandlordId: _targetLandlordId, ...propertyFields } = cmd.payload;
    tx.create(ref, {
      ...newAggregate(cmd.aggregateId!, now),
      landlordId: landlord.landlordId,
      country: COUNTRY,
      ...propertyFields,
    });
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: 1,
      changedFields: Object.keys(propertyFields),
    };
  },
};

const propertyUpdateSchema = strictPayload({
  name: shortText.optional(),
  addressLine: shortText.optional(),
  city: shortText.optional(),
  district: optionalShortText,
  description: z.string().trim().max(5_000).optional(),
  stagedImagePaths: z.array(z.string().min(1).max(1_024)).max(5).optional(),
}).refine((value) => Object.values(value).some((field) => field !== undefined));

export const propertyUpdate: CommandHandler<z.infer<typeof propertyUpdateSchema>> = {
  payloadSchema: propertyUpdateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    if (cmd.payload.stagedImagePaths) {
      validateStagedPaths(actor.uid, cmd.payload.stagedImagePaths);
    }
    const ref = db.collection(COLLECTIONS.properties).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<Record<string, unknown> & { version: number }>(snapshot, cmd.expectedVersion);
    if (!actor.platformAdmin && !actor.superAdmin) {
      const landlord = await requireActiveLandlord(tx, db, actor);
      requireOwnedByLandlord(current, landlord.landlordId);
    }
    const changes = Object.fromEntries(Object.entries(cmd.payload).filter(([, value]) => value !== undefined));
    tx.update(ref, { ...changes, ...bumpVersion(current, now) });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: current.version + 1, changedFields: Object.keys(changes) };
  },
};

export const propertyArchive: CommandHandler<Record<string, never>> = {
  payloadSchema: strictPayload({}),
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.properties).doc(cmd.aggregateId!);
    const unitsQuery = db.collection(COLLECTIONS.units)
      .where('propertyId', '==', cmd.aggregateId!)
      .where('isDeleted', '==', false)
      .limit(1);
    const [snapshot, activeUnits] = await Promise.all([tx.get(ref), tx.get(unitsQuery)]);
    const current = requireAggregate<Record<string, unknown> & { version: number }>(snapshot, cmd.expectedVersion);
    if (!actor.platformAdmin && !actor.superAdmin) {
      const landlord = await requireActiveLandlord(tx, db, actor);
      requireOwnedByLandlord(current, landlord.landlordId);
    }
    if (!activeUnits.empty) throw new DomainError('VALIDATION_FAILED', { reason: 'propertyHasActiveUnits' });
    tx.update(ref, { isDeleted: true, deletedAt: now, ...bumpVersion(current, now) });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: current.version + 1, changedFields: ['isDeleted', 'deletedAt'] };
  },
};

const unitFields = {
  label: shortText,
  type: z.enum(['apartment', 'house', 'shop', 'office', 'bedsitter', 'room', 'other']),
  monthlyRentMinor: nonNegativeMoney,
  bedrooms: z.number().int().min(0).max(100),
  bathrooms: z.number().int().min(0).max(100),
  amenities: z.array(z.string().trim().min(1).max(100)).max(50),
};
const occupancyStatusSchema = z.enum(['vacant', 'occupied', 'reserved', 'maintenance', 'inactive']);
const initialAvailabilitySchema = z.enum(['vacant', 'reserved', 'maintenance', 'inactive']);
const unitCreateSchema = strictPayload({
  propertyId: idSchema,
  occupancyStatus: initialAvailabilitySchema.optional(),
  ...unitFields,
});

export const unitCreate: CommandHandler<z.infer<typeof unitCreateSchema>> = {
  payloadSchema: unitCreateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const propertyRef = db.collection(COLLECTIONS.properties).doc(cmd.payload.propertyId);
    const unitRef = db.collection(COLLECTIONS.units).doc(cmd.aggregateId!);
    const [propertySnap, unitSnap] = await Promise.all([tx.get(propertyRef), tx.get(unitRef)]);
    const property = requireAggregate<Record<string, unknown> & { version: number; landlordId: string }>(propertySnap, undefined);
    const isStaff = actor.platformAdmin || actor.superAdmin;
    const landlord = isStaff
      ? await loadActiveLandlordContext(tx, db, property.landlordId)
      : await requireActiveLandlord(tx, db, actor);
    if (!isStaff) requireOwnedByLandlord(property, landlord.landlordId);
    requireAbsent(unitSnap);
    if (landlord.account.activeUnitCount >= landlord.entitlements.unitLimit) {
      throw new DomainError('UNIT_LIMIT_REACHED', { unitLimit: landlord.entitlements.unitLimit });
    }
    const accountRef = db.collection(COLLECTIONS.landlordAccounts).doc(landlord.landlordId);
    const { occupancyStatus, ...createFields } = cmd.payload;
    tx.create(unitRef, {
      ...newAggregate(cmd.aggregateId!, now),
      landlordId: landlord.landlordId,
      ...createFields,
      occupancyStatus: occupancyStatus ?? 'vacant',
      currency: CURRENCY,
      activePublicListingId: null,
    });
    tx.update(accountRef, {
      activeUnitCount: landlord.account.activeUnitCount + 1,
      ...bumpVersion(landlord.account, now),
    });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: [...Object.keys(createFields), 'occupancyStatus', 'currency'] };
  },
};

const unitUpdateSchema = strictPayload({
  label: unitFields.label.optional(),
  type: unitFields.type.optional(),
  monthlyRentMinor: unitFields.monthlyRentMinor.optional(),
  bedrooms: unitFields.bedrooms.optional(),
  bathrooms: unitFields.bathrooms.optional(),
  amenities: unitFields.amenities.optional(),
  occupancyStatus: occupancyStatusSchema.optional(),
}).refine((value) => Object.values(value).some((field) => field !== undefined));

export const unitUpdate: CommandHandler<z.infer<typeof unitUpdateSchema>> = {
  payloadSchema: unitUpdateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.units).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<Record<string, unknown> & {
      version: number; landlordId: string; occupancyStatus?: string;
      activeLeaseId?: string | null; activePublicListingId?: string | null;
    }>(snapshot, cmd.expectedVersion);
    const isStaff = actor.platformAdmin || actor.superAdmin;
    const occupancyChanged =
      cmd.payload.occupancyStatus !== undefined &&
      cmd.payload.occupancyStatus !== (current.occupancyStatus ?? 'vacant');
    // Occupied is always established by the tenancy command. Availability can
    // be managed directly only while no active lease owns the unit.
    if (
      occupancyChanged &&
      (current.activeLeaseId || cmd.payload.occupancyStatus === 'occupied')
    ) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'unitOccupancyLeaseManaged' });
    }
    const unpublishListingId =
      occupancyChanged && cmd.payload.occupancyStatus !== 'vacant' && current.activePublicListingId
        ? current.activePublicListingId
        : null;
    const landlord = isStaff
      ? unpublishListingId
        ? await loadActiveLandlordContext(tx, db, current.landlordId)
        : null
      : await requireActiveLandlord(tx, db, actor);
    if (!isStaff) requireOwnedByLandlord(current, landlord!.landlordId);

    const retirement = unpublishListingId
      ? await loadActiveListingRetirement(tx, db, current)
      : null;

    // A space that stops being vacant cannot stay advertised: retire the
    // public projection in the same transaction so browsers never see an
    // unavailable space as available.
    applyActiveListingRetirement(
      tx,
      db,
      landlord!,
      retirement,
      cmd.commandId,
      now,
    );

    const changes = Object.fromEntries(Object.entries(cmd.payload).filter(([, value]) => value !== undefined));
    tx.update(ref, {
      ...changes,
      ...(unpublishListingId ? { activePublicListingId: null } : {}),
      ...bumpVersion(current, now),
    });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: current.version + 1, changedFields: Object.keys(changes) };
  },
};

export const unitArchive: CommandHandler<Record<string, never>> = {
  payloadSchema: strictPayload({}),
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.units).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<{ version: number; landlordId: string; occupancyStatus: string; activePublicListingId?: string | null }>(snapshot, cmd.expectedVersion);
    const isStaff = actor.platformAdmin || actor.superAdmin;
    const landlord = isStaff
      ? await loadActiveLandlordContext(tx, db, current.landlordId)
      : await requireActiveLandlord(tx, db, actor);
    if (!isStaff) requireOwnedByLandlord(current, landlord.landlordId);
    if (current.occupancyStatus !== 'vacant' || current.activePublicListingId) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'unitNotArchivable' });
    }
    tx.update(ref, { isDeleted: true, deletedAt: now, ...bumpVersion(current, now) });
    tx.update(db.collection(COLLECTIONS.landlordAccounts).doc(landlord.landlordId), {
      activeUnitCount: Math.max(0, landlord.account.activeUnitCount - 1),
      ...bumpVersion(landlord.account, now),
    });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: current.version + 1, changedFields: ['isDeleted', 'deletedAt'] };
  },
};

export const unitRestore: CommandHandler<Record<string, never>> = {
  payloadSchema: strictPayload({}),
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.units).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<{ version: number; landlordId: string; isDeleted: boolean }>(snapshot, cmd.expectedVersion, { allowDeleted: true });
    const isStaff = actor.platformAdmin || actor.superAdmin;
    const landlord = isStaff
      ? await loadActiveLandlordContext(tx, db, current.landlordId)
      : await requireActiveLandlord(tx, db, actor);
    if (!isStaff) requireOwnedByLandlord(current, landlord.landlordId);
    if (!current.isDeleted) throw new DomainError('VALIDATION_FAILED', { reason: 'unitNotArchived' });
    if (landlord.account.activeUnitCount >= landlord.entitlements.unitLimit) {
      throw new DomainError('UNIT_LIMIT_REACHED', { unitLimit: landlord.entitlements.unitLimit });
    }
    tx.update(ref, { isDeleted: false, deletedAt: null, ...bumpVersion(current, now) });
    tx.update(db.collection(COLLECTIONS.landlordAccounts).doc(landlord.landlordId), {
      activeUnitCount: landlord.account.activeUnitCount + 1,
      ...bumpVersion(landlord.account, now),
    });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: current.version + 1, changedFields: ['isDeleted', 'deletedAt'] };
  },
};
