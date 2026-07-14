import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import type { Actor } from '../../src/shared/actor';
import { DomainError } from '../../src/shared/errors';
import { executeCommandCore } from '../../src/shared/router';

const app = initializeApp({ projectId: 'demo-nyumba' }, 'router-tests');
const db = getFirestore(app);
const now = Timestamp.fromDate(new Date('2026-07-15T00:00:00.000Z'));
const landlord: Actor = { uid: 'landlord_1234', platformAdmin: false, emailVerified: true, signInProvider: 'password' };
const admin: Actor = { uid: 'admin_123456', platformAdmin: true, emailVerified: true, signInProvider: 'password' };

function envelope(
  commandId: string,
  type: string,
  aggregateId: string,
  expectedVersion: number,
  payload: Record<string, unknown>,
) {
  return {
    commandId, type, schemaVersion: 1 as const, aggregateId, expectedVersion, payload,
    client: { installationId: 'install_1234', appVersion: '1.0.0', platform: 'web' as const },
  };
}

async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) throw new Error('FIRESTORE_EMULATOR_HOST is required.');
  await fetch(`http://${host}/emulator/v1/projects/demo-nyumba/databases/(default)/documents`, { method: 'DELETE' });
}

async function seedLandlord(options: { approval?: string; subscription?: string; limit?: number; advertising?: boolean; config?: boolean } = {}): Promise<void> {
  const approval = options.approval ?? 'approved';
  const subscription = options.subscription ?? 'active';
  const batch = db.batch();
  batch.set(db.doc(`landlordAccounts/${landlord.uid}`), {
    id: landlord.uid, ownerUid: landlord.uid, approvalStatus: approval,
    activeUnitCount: 0, activeListingCount: 0, receiptCounter: 0,
    version: 1, createdAt: now, updatedAt: now, isDeleted: false,
  });
  if (subscription !== 'missing') {
    batch.set(db.doc(`subscriptions/${landlord.uid}`), {
      id: landlord.uid, tier: 'Starter', status: subscription,
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
  }
  if (options.config !== false) {
    batch.set(db.doc('backendConfig/entitlements'), {
      version: 1,
      plans: { Starter: { unitLimit: options.limit ?? 2, activeListingLimit: 2, advertising: options.advertising ?? true } },
    });
  }
  batch.set(db.doc('properties/property_1234'), {
    id: 'property_1234', landlordId: landlord.uid, name: 'Home', version: 1,
    createdAt: now, updatedAt: now, isDeleted: false,
  });
  await batch.commit();
}

function unitPayload(label = 'A1') {
  return { propertyId: 'property_1234', label, type: 'apartment', monthlyRentMinor: 100_000, bedrooms: 1, bathrooms: 1, amenities: [] };
}

beforeEach(clearFirestore);
afterAll(() => deleteApp(app));

describe('command router', () => {
  it('absorbs identical retries and rejects actor/hash reuse', async () => {
    await seedLandlord();
    const cmd = envelope('command_unit_01', 'unit.create', 'unit_123456', 0, unitPayload());
    const first = await executeCommandCore(db, landlord, cmd, now);
    const replay = await executeCommandCore(db, landlord, { ...cmd, client: { ...cmd.client, appVersion: '2.0.0' } }, now);
    expect(replay).toEqual(first);
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()?.activeUnitCount).toBe(1);

    await expect(executeCommandCore(db, landlord, { ...cmd, payload: unitPayload('A2') }, now)).rejects.toMatchObject({ code: 'IDEMPOTENCY_KEY_REUSED' });
    await expect(executeCommandCore(db, { ...landlord, uid: 'other_uid_1234' }, cmd, now)).rejects.toMatchObject({ code: 'IDEMPOTENCY_KEY_REUSED' });
  });

  it('persists and replays deterministic version conflicts', async () => {
    await seedLandlord();
    await db.doc('units/unit_123456').set({
      id: 'unit_123456', landlordId: landlord.uid, version: 3, isDeleted: false,
      createdAt: now, updatedAt: now, occupancyStatus: 'vacant',
    });
    const cmd = envelope('command_unit_02', 'unit.update', 'unit_123456', 2, { label: 'A2' });
    const first = await executeCommandCore(db, landlord, cmd, now);
    expect(first).toMatchObject({ status: 'rejected', error: { code: 'VERSION_CONFLICT', details: { currentVersion: 3 } } });
    expect(await executeCommandCore(db, landlord, cmd, now)).toEqual(first);
  });

  it.each([
    ['pending', 'active', true, 'ACCOUNT_NOT_APPROVED'],
    ['suspended', 'active', true, 'ACCOUNT_SUSPENDED'],
    ['approved', 'missing', true, 'SUBSCRIPTION_INACTIVE'],
    ['approved', 'active', false, 'ENTITLEMENT_MISSING'],
  ])('rejects landlord state approval=%s subscription=%s config=%s', async (approval, subscription, config, code) => {
    await seedLandlord({ approval, subscription, config });
    const result = await executeCommandCore(db, landlord, envelope('command_auth_01', 'unit.create', 'unit_123456', 0, unitPayload()), now);
    expect(result).toMatchObject({ status: 'rejected', error: { code } });
  });

  it('enforces admin claim and prevents self approval', async () => {
    await seedLandlord({ approval: 'pending' });
    const cmd = envelope('command_admin_1', 'landlord.approve', landlord.uid, 1, { reasonCode: 'IDENTITY_VERIFIED' });
    expect(await executeCommandCore(db, landlord, cmd, now)).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });
    const self = envelope('command_admin_2', 'landlord.approve', admin.uid, 1, { reasonCode: 'IDENTITY_VERIFIED' });
    await db.doc(`landlordAccounts/${admin.uid}`).set({ id: admin.uid, approvalStatus: 'pending', version: 1, isDeleted: false });
    expect(await executeCommandCore(db, admin, self, now)).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });
  });

  it('enforces unit limits and keeps archive/restore counters stable under replay', async () => {
    await seedLandlord({ limit: 1 });
    await executeCommandCore(db, landlord, envelope('command_limit_1', 'unit.create', 'unit_123456', 0, unitPayload()), now);
    expect(await executeCommandCore(db, landlord, envelope('command_limit_2', 'unit.create', 'unit_654321', 0, unitPayload('A2')), now)).toMatchObject({ status: 'rejected', error: { code: 'UNIT_LIMIT_REACHED' } });
    const archive = envelope('command_archive', 'unit.archive', 'unit_123456', 1, {});
    await executeCommandCore(db, landlord, archive, now);
    await executeCommandCore(db, landlord, archive, now);
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()?.activeUnitCount).toBe(0);
    const restore = envelope('command_restore', 'unit.restore', 'unit_123456', 2, {});
    await executeCommandCore(db, landlord, restore, now);
    await executeCommandCore(db, landlord, restore, now);
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()?.activeUnitCount).toBe(1);
  });

  it('publishes an allowlisted projection and rejects occupied/unentitled units', async () => {
    await seedLandlord();
    await db.doc('units/unit_123456').set({
      id: 'unit_123456', landlordId: landlord.uid, propertyId: 'property_1234', label: 'PRIVATE A1',
      exactAddress: 'PRIVATE ROAD', contactPhone: '+256700000000', occupancyStatus: 'vacant',
      activePublicListingId: null, version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('privateListings/listing_1234').set({
      id: 'listing_1234', landlordId: landlord.uid, unitId: 'unit_123456', publicationState: 'draft',
      title: 'Sunny apartment', description: 'A good home', monthlyRentMinor: 100_000,
      unitType: 'apartment', city: 'Kampala', neighborhood: 'Ntinda', district: 'Kampala',
      bedrooms: 1, bathrooms: 1, amenities: [], stagedImagePaths: [],
      exactAddress: 'PRIVATE ROAD', contactPhone: '+256700000000',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const result = await executeCommandCore(db, landlord, envelope('command_publish', 'listing.publish', 'listing_1234', 1, {}), now);
    expect(result.status).toBe('accepted');
    const publicData = (await db.doc('publicListings/listing_1234').get()).data()!;
    expect(publicData).not.toHaveProperty('exactAddress');
    expect(publicData).not.toHaveProperty('label');
    expect(publicData).not.toHaveProperty('contactPhone');
    expect((publicData.expiresAt as Timestamp).toMillis() - now.toMillis()).toBe(30 * 24 * 60 * 60 * 1000);
  });

  it('rejects publication for an occupied unit', async () => {
    await seedLandlord();
    await db.doc('units/unit_occupied').set({
      id: 'unit_occupied', landlordId: landlord.uid, occupancyStatus: 'occupied',
      activePublicListingId: null, version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('privateListings/listing_occupied').set({
      id: 'listing_occupied', landlordId: landlord.uid, unitId: 'unit_occupied', publicationState: 'draft',
      title: 'Occupied home', description: 'Not available', monthlyRentMinor: 100_000,
      unitType: 'apartment', city: 'Kampala', neighborhood: 'Ntinda', district: 'Kampala',
      stagedImagePaths: [], version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const result = await executeCommandCore(
      db,
      landlord,
      envelope('command_occupied', 'listing.publish', 'listing_occupied', 1, {}),
      now,
    );
    expect(result).toMatchObject({ status: 'rejected', error: { code: 'VALIDATION_FAILED' } });
  });

  it('rejects publication without the advertising entitlement', async () => {
    await seedLandlord({ advertising: false });
    const result = await executeCommandCore(
      db,
      landlord,
      envelope('command_no_ads', 'listing.publish', 'listing_missing', 1, {}),
      now,
    );
    expect(result).toMatchObject({ status: 'rejected', error: { code: 'ENTITLEMENT_MISSING' } });
  });
});
