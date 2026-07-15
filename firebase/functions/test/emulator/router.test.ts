import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import type { Actor } from '../../src/shared/actor';
import { DomainError } from '../../src/shared/errors';
import { executeCommandCore } from '../../src/shared/router';

const app = initializeApp({ projectId: 'demo-nyumba' }, 'router-tests');
const db = getFirestore(app);
const now = Timestamp.fromDate(new Date('2026-07-15T00:00:00.000Z'));
const landlord: Actor = { uid: 'landlord_1234', email: 'landlord@nyumba.test', platformAdmin: false, superAdmin: false, emailVerified: true, signInProvider: 'password' };
const admin: Actor = { uid: 'admin_123456', email: 'admin@nyumba.test', platformAdmin: true, superAdmin: false, emailVerified: true, signInProvider: 'password' };
const superAdmin: Actor = { uid: 'super_admin_123', email: 'superadmin@nyumba.test', platformAdmin: false, superAdmin: true, emailVerified: true, signInProvider: 'password' };

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
    const superAdminApproval = envelope('command_admin_3', 'landlord.approve', landlord.uid, 1, { reasonCode: 'IDENTITY_VERIFIED' });
    expect(await executeCommandCore(db, superAdmin, superAdminApproval, now)).toMatchObject({ status: 'applied' });
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
      approximateLocation: { lat: 0.3162345, lng: 32.5811789 },
      exactAddress: 'PRIVATE ROAD', contactPhone: '+256700000000',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const result = await executeCommandCore(db, landlord, envelope('command_publish', 'listing.publish', 'listing_1234', 1, {}), now);
    expect(result.status).toBe('accepted');
    const publicData = (await db.doc('publicListings/listing_1234').get()).data()!;
    expect(publicData).not.toHaveProperty('exactAddress');
    expect(publicData).not.toHaveProperty('label');
    expect(publicData).not.toHaveProperty('contactPhone');
    expect(publicData.approximateLocation).toEqual({ lat: 0.316, lng: 32.581 });
    expect((publicData.expiresAt as Timestamp).toMillis() - now.toMillis()).toBe(30 * 24 * 60 * 60 * 1000);
  });

  it('writes report snapshots with the owner fields the read rules authorize', async () => {
    await seedLandlord();
    const result = await executeCommandCore(db, landlord, envelope('command_report_1', 'report.request', 'report_123456', 0, {
      reportType: 'occupancy', from: '2026-01-01T00:00:00.000Z', to: '2026-06-30T00:00:00.000Z', format: 'pdf',
    }), now);
    expect(result.status).toBe('accepted');
    const report = (await db.doc('reportSnapshots/report_123456').get()).data()!;
    expect(report.ownerType).toBe('landlord');
    expect(report.ownerId).toBe(landlord.uid);
  });

  it('keeps the landlord UID out of client portal projections', async () => {
    await seedLandlord();
    const client: Actor = { uid: 'client_123456', email: 'client@nyumba.test', platformAdmin: false, superAdmin: false, emailVerified: true, signInProvider: 'password' };
    const expiresAt = Timestamp.fromMillis(now.toMillis() + 7 * 24 * 60 * 60 * 1000);
    await db.doc('publicListings/listing_1234').set({ id: 'listing_1234', status: 'published', expiresAt });
    await db.doc('privateListings/listing_1234').set({
      id: 'listing_1234', landlordId: landlord.uid, publicationState: 'published',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const contact = await executeCommandCore(db, client, envelope('command_contact', 'contact.submit', 'contact_12345', 0, {
      listingId: 'listing_1234', displayName: 'Prospect', email: 'prospect@example.com', message: 'Is this rental still available?',
    }), now);
    expect(contact.status).toBe('accepted');
    expect((await db.doc('contactRequests/contact_12345').get()).data()!.landlordId).toBe(landlord.uid);
    const projection = (await db.doc(`clientPortals/${client.uid}/contactRequests/contact_12345`).get()).data()!;
    expect(projection).not.toHaveProperty('landlordId');

    const application = await executeCommandCore(db, client, envelope('command_apply_1', 'application.submit', 'apply_123456', 0, {
      listingId: 'listing_1234', displayName: 'Prospect', email: 'prospect@example.com',
      phone: '+256700000001', message: 'I would like to apply for this rental.',
    }), now);
    expect(application.status).toBe('accepted');
    const applicationProjection = (await db.doc(`clientPortals/${client.uid}/applications/apply_123456`).get()).data()!;
    expect(applicationProjection).not.toHaveProperty('landlordId');
    expect(applicationProjection).not.toHaveProperty('landlordNotes');

    const withdrawn = await executeCommandCore(db, client, envelope('command_apply_2', 'application.withdraw', 'apply_123456', 1, {}), now);
    expect(withdrawn.status).toBe('applied');
    const reapplied = await executeCommandCore(db, client, envelope('command_apply_3', 'application.submit', 'apply_654321', 0, {
      listingId: 'listing_1234', displayName: 'Prospect', email: 'prospect@example.com',
      phone: '+256700000001', message: 'Applying again after withdrawing earlier.',
    }), now);
    expect(reapplied.status).toBe('accepted');
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

  it('bootstraps a pending landlord account with a starter trial on onboarding', async () => {
    await db.doc(`users/${landlord.uid}`).set({
      id: landlord.uid, displayName: 'Landlord', email: 'landlord@nyumba.test', role: 'client',
      status: 'active', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const result = await executeCommandCore(db, landlord, envelope('command_onboard', 'landlord.onboard', landlord.uid, 0, {
      businessName: 'Mugisha Rentals', phone: '+256772000100',
    }), now);
    expect(result.status).toBe('applied');
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()).toMatchObject({ approvalStatus: 'pending' });
    expect((await db.doc(`subscriptions/${landlord.uid}`).get()).data()).toMatchObject({ tier: 'starter', status: 'trialing' });
    expect((await db.doc(`users/${landlord.uid}`).get()).data()).toMatchObject({ role: 'landlord' });
  });

  it('links pending invites to a verified tenant account and provisions the portal', async () => {
    await seedLandlord();
    const tenant: Actor = { uid: 'tenant_123456', email: 'brian.okello@example.com', platformAdmin: false, superAdmin: false, emailVerified: true, signInProvider: 'google.com' };
    await db.doc(`users/${tenant.uid}`).set({
      id: tenant.uid, displayName: 'Brian Okello', email: tenant.email, role: 'client',
      status: 'active', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    // Landlord invites with a mixed-case email; storage must normalize it.
    const invite = await executeCommandCore(db, landlord, envelope('command_invite_1', 'tenant.invite', 'tenantrec_123', 0, {
      displayName: 'Brian Okello', email: 'Brian.Okello@Example.com', phone: '+256772345678',
    }), now);
    expect(invite.status).toBe('applied');
    expect((await db.doc('tenantRecords/tenantrec_123').get()).data()).toMatchObject({ email: 'brian.okello@example.com', inviteState: 'pending' });
    await db.doc('leases/lease_1234567').set({
      id: 'lease_1234567', landlordId: landlord.uid, unitId: 'unit_123456', tenantRecordId: 'tenantrec_123',
      status: 'active', tenantUserUid: null, monthlyRentMinor: 100_000, depositMinor: 0, currency: 'UGX',
      startDate: '2026-07-01T00:00:00.000Z', endDate: '2027-06-30T00:00:00.000Z',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });

    const claim = { commandId: 'command_claim_1', type: 'tenant.claimInvite', schemaVersion: 1 as const, payload: {}, client: { installationId: 'install_1234', appVersion: '1.0.0', platform: 'web' as const } };
    const result = await executeCommandCore(db, tenant, claim, now);
    expect(result.status).toBe('applied');
    expect(result.result).toMatchObject({ linkedRecords: 1, linkedLeases: 1 });
    expect((await db.doc('tenantRecords/tenantrec_123').get()).data()).toMatchObject({ tenantUserUid: tenant.uid, inviteState: 'accepted' });
    expect((await db.doc('leases/lease_1234567').get()).data()).toMatchObject({ tenantUserUid: tenant.uid });
    expect((await db.doc(`users/${tenant.uid}`).get()).data()).toMatchObject({ role: 'tenant' });
    expect((await db.doc(`tenantPortals/${tenant.uid}/leases/lease_1234567`).get()).exists).toBe(true);

    // Re-claiming is idempotent under a fresh command id and links nothing new.
    const again = await executeCommandCore(db, tenant, { ...claim, commandId: 'command_claim_2' }, now);
    expect(again.result).toMatchObject({ linkedRecords: 0 });
  });

  it('rejects invite claims without a verified email', async () => {
    const unverified: Actor = { uid: 'tenant_654321', email: 'new.tenant@example.com', platformAdmin: false, superAdmin: false, emailVerified: false, signInProvider: 'password' };
    const claim = { commandId: 'command_claim_3', type: 'tenant.claimInvite', schemaVersion: 1 as const, payload: {}, client: { installationId: 'install_1234', appVersion: '1.0.0', platform: 'web' as const } };
    const result = await executeCommandCore(db, unverified, claim, now);
    expect(result).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });
  });
});
