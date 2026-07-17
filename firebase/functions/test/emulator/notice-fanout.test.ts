import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { fanoutNotice } from '../../src/workers/notice-fanout';

// The worker resolves getFirestore() on the default app.
const app = initializeApp({ projectId: 'demo-nyumba' });
const db = getFirestore(app);
const now = Timestamp.fromDate(new Date('2026-07-15T00:00:00.000Z'));
const landlordId = 'landlord_1234';

async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) throw new Error('FIRESTORE_EMULATOR_HOST is required.');
  await fetch(`http://${host}/emulator/v1/projects/demo-nyumba/databases/(default)/documents`, { method: 'DELETE' });
}

async function seedLease(id: string, tenantUserUid: string, unitId: string): Promise<void> {
  await db.doc(`leases/${id}`).set({
    id, landlordId, unitId, tenantUserUid, status: 'active',
    version: 1, createdAt: now, updatedAt: now, isDeleted: false,
  });
}

async function seedNotice(id: string, audience: string, audienceId: string | null): Promise<void> {
  await db.doc(`notices/${id}`).set({
    id, landlordId, title: 'Water maintenance', body: 'Water will be off on Saturday morning.',
    audience, audienceId, publishState: 'pending', publishedAt: null,
    version: 1, createdAt: now, updatedAt: now, isDeleted: false,
  });
}

beforeEach(clearFirestore);
afterAll(() => deleteApp(app));

describe('notice fanout worker', () => {
  it('delivers a lease-scoped notice only to that lease tenant', async () => {
    await seedLease('lease_target', 'tenant_target', 'unit_a1');
    await seedLease('lease_other', 'tenant_other', 'unit_a2');
    await seedNotice('notice_lease', 'lease', 'lease_target');
    await fanoutNotice({ noticeId: 'notice_lease', landlordId });

    expect((await db.doc('tenantPortals/tenant_target/notices/notice_lease').get()).exists).toBe(true);
    expect((await db.doc('notificationInboxes/tenant_target/items/notice_notice_lease').get()).exists).toBe(true);
    expect((await db.doc('tenantPortals/tenant_other/notices/notice_lease').get()).exists).toBe(false);
    expect((await db.doc('notificationInboxes/tenant_other/items/notice_notice_lease').get()).exists).toBe(false);
    expect((await db.doc('notices/notice_lease').get()).data()?.publishState).toBe('published');
  });

  it('delivers a property-scoped notice to that property tenants only', async () => {
    await db.doc('units/unit_in').set({ id: 'unit_in', landlordId, propertyId: 'property_a1', version: 1 });
    await db.doc('units/unit_out').set({ id: 'unit_out', landlordId, propertyId: 'property_b1', version: 1 });
    await seedLease('lease_in', 'tenant_in', 'unit_in');
    await seedLease('lease_out', 'tenant_out', 'unit_out');
    await seedNotice('notice_prop', 'property', 'property_a1');
    await fanoutNotice({ noticeId: 'notice_prop', landlordId });

    expect((await db.doc('tenantPortals/tenant_in/notices/notice_prop').get()).exists).toBe(true);
    expect((await db.doc('notificationInboxes/tenant_in/items/notice_notice_prop').get()).exists).toBe(true);
    expect((await db.doc('tenantPortals/tenant_out/notices/notice_prop').get()).exists).toBe(false);
  });

  it('projects the published whitelist shape and stays idempotent on rerun', async () => {
    await seedLease('lease_target', 'tenant_target', 'unit_a1');
    await seedNotice('notice_all', 'all_active_tenants', null);
    await fanoutNotice({ noticeId: 'notice_all', landlordId });
    await fanoutNotice({ noticeId: 'notice_all', landlordId });

    const projection = (await db.doc('tenantPortals/tenant_target/notices/notice_all').get()).data()!;
    expect(projection.publishState).toBe('published');
    expect(projection).not.toHaveProperty('audience');
    expect(projection).not.toHaveProperty('audienceId');
    expect(projection).not.toHaveProperty('landlordId');
  });
});
