import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { fanoutBroadcast } from '../../src/workers/broadcast-fanout';

// The worker resolves getFirestore() on the default app.
const app = initializeApp({ projectId: 'demo-nyumba' });
const db = getFirestore(app);
const now = Timestamp.fromDate(new Date('2026-07-15T00:00:00.000Z'));

async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) throw new Error('FIRESTORE_EMULATOR_HOST is required.');
  await fetch(`http://${host}/emulator/v1/projects/demo-nyumba/databases/(default)/documents`, { method: 'DELETE' });
}

/** Seeds a user without an email so the courtesy-email path stays inert. */
async function seedUser(uid: string, role: string, roles?: string[]): Promise<void> {
  await db.doc(`users/${uid}`).set({
    id: uid, displayName: uid, email: null, role,
    ...(roles ? { roles } : {}),
    status: 'active', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
  });
}

beforeEach(clearFirestore);
afterAll(() => deleteApp(app));

describe('broadcast fanout worker', () => {
  it('reaches a role audience through the roles array and the legacy scalar exactly once', async () => {
    // A landlord who is also a tenant: findable only through the array.
    await seedUser('user_dual', 'landlord', ['landlord', 'tenant']);
    // A pre-array tenant account: findable only through the scalar.
    await seedUser('user_legacy_tenant', 'tenant');
    // A pure landlord must stay outside the tenants audience.
    await seedUser('user_pure_landlord', 'landlord', ['landlord']);
    // Scalar AND array both say tenant: the id-merge must not double-deliver.
    await seedUser('user_modern_tenant', 'tenant', ['tenant']);

    await db.doc('platformBroadcasts/broadcast_1').set({
      id: 'broadcast_1', title: 'Water maintenance', body: 'Water is off Saturday.',
      audience: 'tenants', audienceId: null, deliveryState: 'pending',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });

    await fanoutBroadcast({ broadcastId: 'broadcast_1' });

    const inboxItem = (uid: string) =>
      db.doc(`notificationInboxes/${uid}/items/broadcast_broadcast_1`).get();
    expect((await inboxItem('user_dual')).exists).toBe(true);
    expect((await inboxItem('user_legacy_tenant')).exists).toBe(true);
    expect((await inboxItem('user_modern_tenant')).exists).toBe(true);
    expect((await inboxItem('user_pure_landlord')).exists).toBe(false);
    expect((await db.doc('platformBroadcasts/broadcast_1').get()).data()).toMatchObject({
      deliveryState: 'sent', recipientCount: 3,
    });
  });
});
