import { deleteApp, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import type { Actor } from '../../src/shared/actor';
import { STAFF_PERMISSIONS } from '../../src/shared/accounts';
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

async function seedLandlord(options: { approval?: string; subscription?: string; limit?: number; advertising?: boolean; config?: boolean; tier?: string; staffSeatLimit?: number; customStaffRoles?: boolean } = {}): Promise<void> {
  const approval = options.approval ?? 'approved';
  const subscription = options.subscription ?? 'active';
  const tier = options.tier ?? 'starter';
  const batch = db.batch();
  batch.set(db.doc(`landlordAccounts/${landlord.uid}`), {
    id: landlord.uid, ownerUid: landlord.uid, approvalStatus: approval,
    activeUnitCount: 0, activeListingCount: 0, activeStaffSeatCount: 0, receiptCounter: 0,
    version: 1, createdAt: now, updatedAt: now, isDeleted: false,
  });
  if (subscription !== 'missing') {
    batch.set(db.doc(`subscriptions/${landlord.uid}`), {
      id: landlord.uid, tier, status: subscription,
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
  }
  if (options.config !== false) {
    batch.set(db.doc('backendConfig/entitlements'), {
      version: 1,
      plans: {
        starter: { unitLimit: options.limit ?? 2, activeListingLimit: 2, advertising: options.advertising ?? true, staffSeatLimit: options.staffSeatLimit ?? 0, customStaffRoles: options.customStaffRoles ?? false },
        pro: { unitLimit: 50, activeListingLimit: 25, advertising: true, staffSeatLimit: options.staffSeatLimit ?? 2, customStaffRoles: options.customStaffRoles ?? false },
        premium: { unitLimit: 200, activeListingLimit: 200, advertising: true, staffSeatLimit: options.staffSeatLimit ?? 9, customStaffRoles: options.customStaffRoles ?? true },
      },
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

  it('updates profile preferences without a local version and marks only the actor inbox read', async () => {
    await db.doc(`users/${landlord.uid}`).set({
      id: landlord.uid, displayName: 'Landlord', role: 'landlord', status: 'active',
      notifications: {
        email: true,
        push: false,
        rentReminders: false,
        maintenanceUpdates: true,
      },
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc(`notificationInboxes/${landlord.uid}/items/inbox_1234`).set({
      id: 'inbox_1234', recipientUid: landlord.uid, kind: 'system',
      title: 'Update', body: 'Something changed.', route: '/listings',
      isRead: false, readAt: null, version: 1, createdAt: now, updatedAt: now,
      isDeleted: false,
    });

    const profileBase = envelope(
      'command_profile_1',
      'profile.update',
      landlord.uid,
      1,
      { locale: 'sw', notifications: { email: false, push: true } },
    );
    const { expectedVersion: _profileVersion, ...profileCommand } = profileBase;
    expect(await executeCommandCore(db, landlord, profileCommand, now)).toMatchObject({
      status: 'applied', serverVersion: 2,
    });
    expect((await db.doc(`users/${landlord.uid}`).get()).data()).toMatchObject({
      locale: 'sw',
      notifications: {
        email: false,
        push: true,
        rentReminders: false,
        maintenanceUpdates: true,
      },
    });

    const unsupportedLocaleBase = envelope(
      'command_profile_bad_locale',
      'profile.update',
      landlord.uid,
      2,
      { locale: 'fr' },
    );
    const { expectedVersion: _unsupportedVersion, ...unsupportedLocale } = unsupportedLocaleBase;
    expect(await executeCommandCore(db, landlord, unsupportedLocale, now)).toMatchObject({
      status: 'rejected', error: { code: 'VALIDATION_FAILED' },
    });

    const read = envelope(
      'command_inbox_01',
      'notification.markRead',
      'inbox_1234',
      1,
      {},
    );
    expect(await executeCommandCore(db, landlord, read, now)).toMatchObject({
      status: 'applied', serverVersion: 2,
    });
    expect((await db.doc(
      `notificationInboxes/${landlord.uid}/items/inbox_1234`,
    ).get()).data()?.isRead).toBe(true);

    const other = { ...landlord, uid: 'other_user_1234' };
    const otherRead = envelope(
      'command_inbox_02',
      'notification.markRead',
      'inbox_1234',
      1,
      {},
    );
    expect(await executeCommandCore(db, other, otherRead, now)).toMatchObject({
      status: 'rejected', error: { code: 'NOT_FOUND' },
    });
  });

  it('removes the current device token before sign-out', async () => {
    await db.doc(`users/${landlord.uid}`).set({
      id: landlord.uid, displayName: 'Landlord', role: 'landlord', status: 'active',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const token = 'fcm_device_token_123456789012345678901234567890';
    const registerBase = envelope(
      'command_device_register',
      'profile.registerDevice',
      landlord.uid,
      1,
      { token, platform: 'web' },
    );
    const {
      aggregateId: _registerAggregate,
      expectedVersion: _registerVersion,
      ...register
    } = registerBase;
    expect(await executeCommandCore(db, landlord, register, now)).toMatchObject({
      status: 'applied', result: { deviceCount: 1 },
    });

    const unregisterBase = envelope(
      'command_device_unregister',
      'profile.unregisterDevice',
      landlord.uid,
      2,
      { token },
    );
    const {
      aggregateId: _unregisterAggregate,
      expectedVersion: _unregisterVersion,
      ...unregister
    } = unregisterBase;
    expect(await executeCommandCore(db, landlord, unregister, now)).toMatchObject({
      status: 'applied', result: { deviceCount: 0 },
    });
    expect((await db.doc(`users/${landlord.uid}`).get()).data()?.deviceTokens).toEqual([]);
    expect((await db.collection('deviceTokenOwners').get()).empty).toBe(true);
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
    ['approved', 'pending_payment', true, 'SUBSCRIPTION_INACTIVE'],
    ['approved', 'trialing', true, 'SUBSCRIPTION_INACTIVE'],
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

  it('lets any administrator archive and restore, but reserves permanent deletion for a Super Admin', async () => {
    await seedLandlord();
    await db.doc(`users/${landlord.uid}`).set({
      id: landlord.uid, displayName: 'Landlord', email: 'landlord@nyumba.test', role: 'landlord',
      status: 'active', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });

    // No administrator may act on their own account, whatever the claim.
    await db.doc(`users/${admin.uid}`).set({ id: admin.uid, role: 'client', status: 'active', version: 1, isDeleted: false });
    const selfAttempt = envelope('command_user_arch_1', 'user.archive', admin.uid, 1, { reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, admin, selfAttempt, now)).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });

    // Delete is only allowed out of the archive.
    const premature = envelope('command_user_del_0', 'user.delete', landlord.uid, 1, { reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, superAdmin, premature, now)).toMatchObject({
      status: 'rejected', error: { code: 'VALIDATION_FAILED', details: { reason: 'notArchived' } },
    });

    // Archiving is reversible, so a platform admin may do it: the profile is
    // marked, sign-in is disabled, and listings come down.
    const archive = envelope('command_user_arch_2', 'user.archive', landlord.uid, 1, { reasonCode: 'POLICY_VIOLATION' });
    expect(await executeCommandCore(db, admin, archive, now)).toMatchObject({ status: 'accepted' });
    expect((await db.doc(`users/${landlord.uid}`).get()).data()).toMatchObject({ status: 'archived', archiveReasonCode: 'POLICY_VIOLATION', version: 2 });
    expect((await db.doc('backendJobs/command_user_arch_2_disable').get()).data()).toMatchObject({
      type: 'setAuthUserDisabled',
      payload: {
        uid: landlord.uid,
        disabled: true,
        expectedUserVersion: 2,
        expectedUserStatus: 'archived',
      },
    });
    expect((await db.doc('backendJobs/command_user_arch_2_unpublish').get()).data()).toMatchObject({ type: 'unpublishLandlordListings' });
    const again = envelope('command_user_arch_3', 'user.archive', landlord.uid, 2, { reasonCode: 'POLICY_VIOLATION' });
    expect(await executeCommandCore(db, admin, again, now)).toMatchObject({
      status: 'rejected', error: { code: 'VALIDATION_FAILED', details: { reason: 'alreadyArchived' } },
    });

    // Restore returns the account to active and re-enables sign-in.
    const restore = envelope('command_user_rest_1', 'user.restore', landlord.uid, 2, { reasonCode: 'APPEAL_APPROVED' });
    expect(await executeCommandCore(db, admin, restore, now)).toMatchObject({ status: 'accepted' });
    expect((await db.doc(`users/${landlord.uid}`).get()).data()).toMatchObject({ status: 'active', archiveReasonCode: null, version: 3 });
    expect((await db.doc('backendJobs/command_user_rest_1_enable').get()).data()).toMatchObject({
      type: 'setAuthUserDisabled',
      payload: {
        uid: landlord.uid,
        disabled: false,
        expectedUserVersion: 3,
        expectedUserStatus: 'active',
      },
    });

    // Permanent deletion is where the claims diverge: the same archived
    // account an admin created cannot be destroyed by that admin.
    const rearchive = envelope('command_user_arch_4', 'user.archive', landlord.uid, 3, { reasonCode: 'USER_REQUESTED' });
    expect(await executeCommandCore(db, admin, rearchive, now)).toMatchObject({ status: 'accepted' });
    const adminDelete = envelope('command_user_del_2', 'user.delete', landlord.uid, 4, { reasonCode: 'USER_REQUESTED' });
    expect(await executeCommandCore(db, admin, adminDelete, now)).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });

    // Delete from the archive tombstones the profile and enqueues Auth deletion.
    const remove = envelope('command_user_del_1', 'user.delete', landlord.uid, 4, { reasonCode: 'USER_REQUESTED' });
    expect(await executeCommandCore(db, superAdmin, remove, now)).toMatchObject({ status: 'accepted' });
    expect((await db.doc(`users/${landlord.uid}`).get()).data()).toMatchObject({ isDeleted: true, deleteReasonCode: 'USER_REQUESTED', version: 5 });
    expect((await db.doc('backendJobs/command_user_del_1_delete').get()).data()).toMatchObject({ type: 'deleteAuthUser', payload: { uid: landlord.uid } });
  });

  it('purges archived portfolio records only for a Super Admin, and only bottom-up', async () => {
    await seedLandlord();
    await executeCommandCore(db, landlord, envelope('command_purge_seed', 'unit.create', 'unit_123456', 0, unitPayload()), now);

    // A live record is never purgeable: the archive is the required first step.
    const live = envelope('command_purge_0', 'property.delete', 'property_1234', 1, { reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, superAdmin, live, now)).toMatchObject({
      status: 'rejected', error: { code: 'VALIDATION_FAILED', details: { reason: 'notArchived' } },
    });

    await executeCommandCore(db, landlord, envelope('command_purge_1', 'unit.archive', 'unit_123456', 1, {}), now);
    await executeCommandCore(db, landlord, envelope('command_purge_2', 'property.archive', 'property_1234', 1, {}), now);

    // An archived unit still references the property, and purging the parent
    // would orphan it past recovery — the child has to go first.
    const parentFirst = envelope('command_purge_3', 'property.delete', 'property_1234', 2, { reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, superAdmin, parentFirst, now)).toMatchObject({
      status: 'rejected', error: { code: 'VALIDATION_FAILED', details: { reason: 'propertyHasUnits' } },
    });

    // Permanent deletion is closed to an ordinary platform admin.
    const adminAttempt = envelope('command_purge_4', 'unit.delete', 'unit_123456', 2, { reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, admin, adminAttempt, now)).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });

    const removeUnit = envelope('command_purge_5', 'unit.delete', 'unit_123456', 2, { reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, superAdmin, removeUnit, now)).toMatchObject({ status: 'applied' });
    expect((await db.doc('units/unit_123456').get()).exists).toBe(false);
    // The archive already decremented the counter; the purge must not repeat it.
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()?.activeUnitCount).toBe(0);

    // Staged photos never reach a server-owned prefix, so they are swept by an
    // explicit path list rather than by prefix.
    await db.doc('properties/property_1234').update({ stagedImagePaths: ['uploads/landlord_1234/cmd/a.jpg'] });
    const removeProperty = envelope('command_purge_6', 'property.delete', 'property_1234', 2, { reasonCode: 'DATA_RETENTION' });
    expect(await executeCommandCore(db, superAdmin, removeProperty, now)).toMatchObject({ status: 'accepted' });
    expect((await db.doc('properties/property_1234').get()).exists).toBe(false);
    expect((await db.doc('backendJobs/command_purge_6_media').get()).data()).toMatchObject({
      type: 'purgeStorageObjects', payload: { paths: ['uploads/landlord_1234/cmd/a.jpg'] },
    });
  });

  it('purges listings and documents that are already out of circulation', async () => {
    await seedLandlord();
    await db.doc('privateListings/listing_1234').set({
      id: 'listing_1234', landlordId: landlord.uid, unitId: 'unit_123456', publicationState: 'published',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('publicListings/listing_1234').set({
      id: 'listing_1234', status: 'published', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });

    // A live advert must be unpublished first, so the ordinary retirement path
    // clears the unit pointer and the account's listing counter.
    const published = envelope('command_lpurge_0', 'listing.delete', 'listing_1234', 1, { reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, superAdmin, published, now)).toMatchObject({
      status: 'rejected', error: { code: 'VALIDATION_FAILED', details: { reason: 'listingStillPublished' } },
    });

    await db.doc('privateListings/listing_1234').update({ publicationState: 'expired' });
    const adminAttempt = envelope('command_lpurge_1', 'listing.delete', 'listing_1234', 1, { reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, admin, adminAttempt, now)).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });

    // Both projections go together — a surviving public row would advertise a
    // listing with no private record behind it.
    const remove = envelope('command_lpurge_2', 'listing.delete', 'listing_1234', 1, { reasonCode: 'POLICY_VIOLATION' });
    expect(await executeCommandCore(db, superAdmin, remove, now)).toMatchObject({ status: 'accepted' });
    expect((await db.doc('privateListings/listing_1234').get()).exists).toBe(false);
    expect((await db.doc('publicListings/listing_1234').get()).exists).toBe(false);
    expect((await db.doc('backendJobs/command_lpurge_2_cleanup').get()).data()).toMatchObject({
      type: 'cleanupListingMedia', payload: { listingId: 'listing_1234' },
    });

    // A document must already be soft-deleted; purge only skips the wait.
    await db.doc('documents/document_1234').set({
      id: 'document_1234', landlordId: landlord.uid, uploadedByUid: landlord.uid, state: 'available',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const live = envelope('command_dpurge_0', 'document.purge', 'document_1234', 1, { reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, superAdmin, live, now)).toMatchObject({
      status: 'rejected', error: { code: 'VALIDATION_FAILED', details: { reason: 'notDeleted' } },
    });

    await db.doc('documents/document_1234').update({ isDeleted: true, state: 'deleted' });
    const purge = envelope('command_dpurge_1', 'document.purge', 'document_1234', 1, { reasonCode: 'USER_REQUESTED' });
    expect(await executeCommandCore(db, superAdmin, purge, now)).toMatchObject({ status: 'accepted' });
    expect((await db.doc('backendJobs/command_dpurge_1_purge').get()).data()).toMatchObject({
      type: 'purgeDocument', payload: { documentId: 'document_1234' },
    });
  });

  it('defers the scheduled document purge to the end of the retention window', async () => {
    await seedLandlord();
    await db.doc('documents/document_5678').set({
      id: 'document_5678', landlordId: landlord.uid, uploadedByUid: landlord.uid, state: 'available',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const remove = envelope('command_ddel_1', 'document.delete', 'document_5678', 1, {});
    expect(await executeCommandCore(db, landlord, remove, now)).toMatchObject({ status: 'accepted' });

    // Soft deletion is only honest if the file survives the window: the job
    // must not become claimable until purgeAt.
    const job = (await db.doc('backendJobs/command_ddel_1_purge').get()).data();
    const purgeAt = (await db.doc('documents/document_5678').get()).data()?.purgeAt as Timestamp;
    expect(purgeAt.toMillis()).toBe(now.toMillis() + 90 * 24 * 60 * 60 * 1000);
    expect((job?.nextAttemptAt as Timestamp).toMillis()).toBe(purgeAt.toMillis());
  });

  it('lets any administrator change ordinary roles, provisioning landlord aggregates on promotion', async () => {
    await db.doc('users/tenant_roleup_1').set({
      id: 'tenant_roleup_1', displayName: 'Tenant', role: 'tenant',
      status: 'active', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });

    await db.doc(`users/${superAdmin.uid}`).set({ id: superAdmin.uid, role: 'client', status: 'active', version: 1, isDeleted: false });
    const selfAttempt = envelope('command_role_1', 'user.changeRole', superAdmin.uid, 1, { role: 'landlord', reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, superAdmin, selfAttempt, now)).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });

    const unchanged = envelope('command_role_2', 'user.changeRole', 'tenant_roleup_1', 1, { role: 'tenant', reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, superAdmin, unchanged, now)).toMatchObject({
      status: 'rejected', error: { code: 'VALIDATION_FAILED', details: { reason: 'roleUnchanged' } },
    });

    // Promotion provisions the landlord aggregates in the fail-closed states.
    // A platform admin is enough: the payload enum cannot name an admin role,
    // so this can never escalate anyone into the administrator claims.
    const promote = envelope('command_role_3', 'user.changeRole', 'tenant_roleup_1', 1, { role: 'landlord', reasonCode: 'IDENTITY_VERIFIED' });
    expect(await executeCommandCore(db, admin, promote, now)).toMatchObject({ status: 'applied' });
    expect((await db.doc('users/tenant_roleup_1').get()).data()).toMatchObject({ role: 'landlord', roleChangeReasonCode: 'IDENTITY_VERIFIED', version: 2 });
    expect((await db.doc('landlordAccounts/tenant_roleup_1').get()).data()).toMatchObject({ ownerUid: 'tenant_roleup_1', approvalStatus: 'pending' });
    expect((await db.doc('subscriptions/tenant_roleup_1').get()).data()).toMatchObject({ status: 'pending_payment' });

    // Demotion changes only the role; landlord aggregates stay as the record.
    const demote = envelope('command_role_4', 'user.changeRole', 'tenant_roleup_1', 2, { role: 'client', reasonCode: 'USER_REQUESTED' });
    expect(await executeCommandCore(db, superAdmin, demote, now)).toMatchObject({ status: 'applied' });
    expect((await db.doc('users/tenant_roleup_1').get()).data()).toMatchObject({ role: 'client', version: 3 });
    expect((await db.doc('landlordAccounts/tenant_roleup_1').get()).exists).toBe(true);

    // An archived account must be restored before its role can change.
    await db.doc('users/tenant_roleup_1').update({ status: 'archived' });
    const archivedAttempt = envelope('command_role_5', 'user.changeRole', 'tenant_roleup_1', 3, { role: 'tenant', reasonCode: 'ADMIN_CORRECTION' });
    expect(await executeCommandCore(db, superAdmin, archivedAttempt, now)).toMatchObject({
      status: 'rejected', error: { code: 'VALIDATION_FAILED', details: { reason: 'accountArchived' } },
    });
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

  it('allows audited staff property archives and still blocks active units', async () => {
    await seedLandlord();
    const archive = envelope('command_property_archive_1', 'property.archive', 'property_1234', 1, {});
    expect(await executeCommandCore(db, admin, archive, now)).toMatchObject({ status: 'applied' });
    expect((await db.doc('properties/property_1234').get()).data()?.isDeleted).toBe(true);

    await db.doc('properties/property_1234').update({ isDeleted: false, deletedAt: null, version: 2 });
    await db.doc('units/unit_active_1234').set({
      id: 'unit_active_1234', propertyId: 'property_1234', landlordId: landlord.uid,
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const blocked = envelope('command_property_archive_2', 'property.archive', 'property_1234', 2, {});
    expect(await executeCommandCore(db, superAdmin, blocked, now)).toMatchObject({
      status: 'rejected',
      error: { code: 'VALIDATION_FAILED', details: { reason: 'propertyHasActiveUnits' } },
    });
  });

  it('allows Admin and Super Admin to manage a landlord portfolio lifecycle', async () => {
    await seedLandlord();
    const propertyId = 'property_staff_1234';
    const unitId = 'unit_staff_123456';
    const listingId = 'listing_staff_1234';

    expect(await executeCommandCore(db, admin, envelope(
      'command_staff_property_create',
      'property.create',
      propertyId,
      0,
      {
        targetLandlordId: landlord.uid,
        name: 'Staff Managed Court',
        addressLine: '12 Admin Road',
        city: 'Kampala',
        stagedImagePaths: [],
      },
    ), now)).toMatchObject({ status: 'applied' });
    const property = (await db.doc(`properties/${propertyId}`).get()).data()!;
    expect(property.landlordId).toBe(landlord.uid);
    expect(property).not.toHaveProperty('targetLandlordId');

    expect(await executeCommandCore(db, admin, envelope(
      'command_staff_property_update',
      'property.update',
      propertyId,
      1,
      { name: 'Staff Managed Homes' },
    ), now)).toMatchObject({ status: 'applied', serverVersion: 2 });
    expect(await executeCommandCore(db, admin, envelope(
      'command_staff_unit_create',
      'unit.create',
      unitId,
      0,
      { ...unitPayload('S1'), propertyId },
    ), now)).toMatchObject({ status: 'applied' });
    expect(await executeCommandCore(db, admin, envelope(
      'command_staff_unit_update',
      'unit.update',
      unitId,
      1,
      { label: 'S2' },
    ), now)).toMatchObject({ status: 'applied', serverVersion: 2 });

    expect(await executeCommandCore(db, superAdmin, envelope(
      'command_staff_listing_create',
      'listing.saveDraft',
      listingId,
      0,
      {
        unitId,
        title: 'Staff managed apartment',
        description: 'A well maintained apartment in Kampala.',
        monthlyRentMinor: 100_000,
        unitType: 'apartment',
        city: 'Kampala',
        neighborhood: 'Ntinda',
        district: 'Kampala',
        bedrooms: 1,
        bathrooms: 1,
        amenities: [],
        stagedImagePaths: [],
      },
    ), now)).toMatchObject({ status: 'applied' });
    expect(await executeCommandCore(db, superAdmin, envelope(
      'command_staff_listing_update',
      'listing.saveDraft',
      listingId,
      1,
      {
        unitId,
        title: 'Updated staff managed apartment',
        description: 'An updated, well maintained apartment in Kampala.',
        monthlyRentMinor: 120_000,
        unitType: 'apartment',
        city: 'Kampala',
        neighborhood: 'Ntinda',
        district: 'Kampala',
        bedrooms: 1,
        bathrooms: 1,
        amenities: [],
        stagedImagePaths: [],
      },
    ), now)).toMatchObject({ status: 'applied', serverVersion: 2 });
    expect(await executeCommandCore(db, superAdmin, envelope(
      'command_staff_listing_publish',
      'listing.publish',
      listingId,
      2,
      {},
    ), now)).toMatchObject({ status: 'accepted' });
    expect(await executeCommandCore(db, superAdmin, envelope(
      'command_staff_listing_unpublish',
      'listing.unpublish',
      listingId,
      3,
      {},
    ), now)).toMatchObject({ status: 'accepted' });
    expect((await db.doc(`publicListings/${listingId}`).get()).data()?.status).toBe('unpublished');

    expect(await executeCommandCore(db, superAdmin, envelope(
      'command_staff_unit_archive',
      'unit.archive',
      unitId,
      4,
      {},
    ), now)).toMatchObject({ status: 'applied' });
    expect(await executeCommandCore(db, superAdmin, envelope(
      'command_staff_property_archive',
      'property.archive',
      propertyId,
      2,
      {},
    ), now)).toMatchObject({ status: 'applied' });
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()).toMatchObject({
      activeUnitCount: 0,
      activeListingCount: 0,
    });
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

  it('retires a public listing when a landlord makes its unit unavailable', async () => {
    await seedLandlord();
    await db.doc(`landlordAccounts/${landlord.uid}`).update({ activeListingCount: 1 });
    await db.doc('units/unit_available_1').set({
      id: 'unit_available_1', landlordId: landlord.uid, propertyId: 'property_1234',
      occupancyStatus: 'vacant', activeLeaseId: null, activePublicListingId: 'listing_available_1',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('privateListings/listing_available_1').set({
      id: 'listing_available_1', landlordId: landlord.uid, unitId: 'unit_available_1',
      publicationState: 'published', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('publicListings/listing_available_1').set({
      id: 'listing_available_1', status: 'published', version: 1,
      expiresAt: Timestamp.fromMillis(now.toMillis() + 7 * 24 * 60 * 60 * 1000),
      createdAt: now, updatedAt: now,
    });

    const command = envelope(
      'command_availability_1',
      'unit.update',
      'unit_available_1',
      1,
      { occupancyStatus: 'maintenance' },
    );
    expect(await executeCommandCore(db, landlord, command, now)).toMatchObject({
      status: 'applied', serverVersion: 2,
    });
    // Replaying the same command must not decrement the listing count twice.
    expect(await executeCommandCore(db, landlord, command, now)).toMatchObject({
      status: 'applied', serverVersion: 2,
    });
    expect((await db.doc('units/unit_available_1').get()).data()).toMatchObject({
      occupancyStatus: 'maintenance', activePublicListingId: null,
    });
    expect((await db.doc('privateListings/listing_available_1').get()).data()?.publicationState).toBe('unpublished');
    expect((await db.doc('publicListings/listing_available_1').get()).data()?.status).toBe('unpublished');
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()?.activeListingCount).toBe(0);
    expect((await db.doc('backendJobs/command_availability_1_cleanup').get()).data()).toMatchObject({
      type: 'cleanupListingMedia', payload: { listingId: 'listing_available_1' },
    });
    // The local outbox may still deliver its earlier listing.unpublish intent
    // with the pre-retirement version. The already-achieved state absorbs it.
    expect(await executeCommandCore(
      db,
      landlord,
      envelope(
        'command_availability_unpublish',
        'listing.unpublish',
        'listing_available_1',
        1,
        {},
      ),
      now,
    )).toMatchObject({ status: 'applied', serverVersion: 2 });
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()?.activeListingCount).toBe(0);

    const manualOccupied = await executeCommandCore(
      db,
      landlord,
      envelope(
        'command_availability_2',
        'unit.update',
        'unit_available_1',
        2,
        { occupancyStatus: 'occupied' },
      ),
      now,
    );
    expect(manualOccupied).toMatchObject({
      status: 'rejected',
      error: { code: 'VALIDATION_FAILED', details: { reason: 'unitOccupancyLeaseManaged' } },
    });
  });

  it('retires a public listing when a tenancy occupies its unit', async () => {
    await seedLandlord();
    await db.doc(`landlordAccounts/${landlord.uid}`).update({ activeListingCount: 1 });
    await db.doc('units/unit_tenancy_1').set({
      id: 'unit_tenancy_1', landlordId: landlord.uid, propertyId: 'property_1234', label: 'T1',
      occupancyStatus: 'vacant', activeLeaseId: null, activePublicListingId: 'listing_tenancy_1',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('privateListings/listing_tenancy_1').set({
      id: 'listing_tenancy_1', landlordId: landlord.uid, unitId: 'unit_tenancy_1',
      publicationState: 'published', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('publicListings/listing_tenancy_1').set({
      id: 'listing_tenancy_1', status: 'published', version: 1,
      expiresAt: Timestamp.fromMillis(now.toMillis() + 7 * 24 * 60 * 60 * 1000),
      createdAt: now, updatedAt: now,
    });

    const result = await executeCommandCore(
      db,
      landlord,
      envelope(
        'command_tenancy_1',
        'tenancy.establish',
        'tenancy_123456',
        0,
        {
          unitId: 'unit_tenancy_1',
          displayName: 'Amina Tenant',
          email: 'amina@example.com',
          phone: '+256700000001',
          startDate: '2026-08-01T00:00:00.000Z',
          endDate: '2027-07-31T00:00:00.000Z',
          monthlyRentMinor: 100_000,
        },
      ),
      now,
    );

    expect(result).toMatchObject({ status: 'applied' });
    expect((await db.doc('units/unit_tenancy_1').get()).data()).toMatchObject({
      occupancyStatus: 'occupied',
      activeLeaseId: 'tenancy_123456',
      activePublicListingId: null,
    });
    expect((await db.doc('privateListings/listing_tenancy_1').get()).data()?.publicationState).toBe('unpublished');
    expect((await db.doc('publicListings/listing_tenancy_1').get()).data()?.status).toBe('unpublished');
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()?.activeListingCount).toBe(0);
  });

  it('retires a public listing when a draft lease is activated', async () => {
    await seedLandlord();
    await db.doc(`landlordAccounts/${landlord.uid}`).update({ activeListingCount: 1 });
    await db.doc('units/unit_lease_activate_1').set({
      id: 'unit_lease_activate_1', landlordId: landlord.uid, propertyId: 'property_1234',
      occupancyStatus: 'vacant', activeLeaseId: null, activePublicListingId: 'listing_lease_activate_1',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('leases/lease_activate_1').set({
      id: 'lease_activate_1', landlordId: landlord.uid, unitId: 'unit_lease_activate_1',
      tenantRecordId: 'tenant_record_1', tenantUserUid: null, status: 'draft',
      version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('privateListings/listing_lease_activate_1').set({
      id: 'listing_lease_activate_1', landlordId: landlord.uid, unitId: 'unit_lease_activate_1',
      publicationState: 'published', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    await db.doc('publicListings/listing_lease_activate_1').set({
      id: 'listing_lease_activate_1', status: 'published', version: 1,
      expiresAt: Timestamp.fromMillis(now.toMillis() + 7 * 24 * 60 * 60 * 1000),
      createdAt: now, updatedAt: now,
    });

    const result = await executeCommandCore(
      db,
      landlord,
      envelope('command_lease_activate_1', 'lease.activate', 'lease_activate_1', 1, {}),
      now,
    );

    expect(result).toMatchObject({ status: 'applied', serverVersion: 2 });
    expect((await db.doc('units/unit_lease_activate_1').get()).data()).toMatchObject({
      occupancyStatus: 'occupied',
      activeLeaseId: 'lease_activate_1',
      activePublicListingId: null,
    });
    expect((await db.doc('privateListings/listing_lease_activate_1').get()).data()?.publicationState).toBe('unpublished');
    expect((await db.doc('publicListings/listing_lease_activate_1').get()).data()?.status).toBe('unpublished');
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()?.activeListingCount).toBe(0);
    expect((await db.doc('backendJobs/command_lease_activate_1_cleanup').get()).data()).toMatchObject({
      type: 'cleanupListingMedia', payload: { listingId: 'listing_lease_activate_1' },
    });
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

  it('bootstraps a payment-gated landlord account on onboarding', async () => {
    await db.doc(`users/${landlord.uid}`).set({
      id: landlord.uid, displayName: 'Landlord', email: 'landlord@nyumba.test', role: 'client',
      status: 'active', version: 1, createdAt: now, updatedAt: now, isDeleted: false,
    });
    const result = await executeCommandCore(db, landlord, envelope('command_onboard', 'landlord.onboard', landlord.uid, 0, {
      businessName: 'Mugisha Rentals', phone: '+256772000100',
    }), now);
    expect(result.status).toBe('applied');
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()).toMatchObject({ approvalStatus: 'pending' });
    expect((await db.doc(`subscriptions/${landlord.uid}`).get()).data()).toMatchObject({ tier: 'starter', status: 'pending_payment' });
    expect((await db.doc(`users/${landlord.uid}`).get()).data()).toMatchObject({ role: 'landlord' });
  });

  it('lets a payment-pending landlord select a plan but never activate themselves', async () => {
    await seedLandlord({ subscription: 'pending_payment' });
    const select = await executeCommandCore(db, landlord, envelope('command_sub_01', 'subscription.selectPlan', landlord.uid, 1, { tier: 'pro' }), now);
    expect(select).toMatchObject({ status: 'applied' });
    expect((await db.doc(`subscriptions/${landlord.uid}`).get()).data()).toMatchObject({ tier: 'pro', status: 'pending_payment' });

    const unknownTier = await executeCommandCore(db, landlord, envelope('command_sub_02', 'subscription.selectPlan', landlord.uid, 2, { tier: 'Gold' }), now);
    expect(unknownTier).toMatchObject({ status: 'rejected', error: { code: 'ENTITLEMENT_MISSING' } });

    const selfConfirm = await executeCommandCore(db, landlord, envelope('command_sub_03', 'subscription.confirmPayment', landlord.uid, 2, { reference: 'MoMo TX 100' }), now);
    expect(selfConfirm).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });
    expect((await db.doc(`subscriptions/${landlord.uid}`).get()).data()).toMatchObject({ status: 'pending_payment' });
  });

  it('opens the workspace exactly when an admin confirms payment', async () => {
    await seedLandlord({ subscription: 'pending_payment' });
    const before = await executeCommandCore(db, landlord, envelope('command_sub_04', 'unit.create', 'unit_123456', 0, unitPayload()), now);
    expect(before).toMatchObject({ status: 'rejected', error: { code: 'SUBSCRIPTION_INACTIVE' } });

    // Activation must carry a payment reference; a blank one is rejected so the
    // audit trail always records what money justified opening the workspace.
    const noReference = await executeCommandCore(db, admin, envelope('command_sub_04b', 'subscription.confirmPayment', landlord.uid, 1, {}), now);
    expect(noReference).toMatchObject({ status: 'rejected', error: { code: 'VALIDATION_FAILED' } });

    const confirm = await executeCommandCore(db, admin, envelope('command_sub_05', 'subscription.confirmPayment', landlord.uid, 1, { reference: 'MoMo TX 998877' }), now);
    expect(confirm).toMatchObject({ status: 'applied' });
    expect((await db.doc(`subscriptions/${landlord.uid}`).get()).data()).toMatchObject({
      status: 'active', tier: 'starter', paymentReference: 'MoMo TX 998877',
    });

    const after = await executeCommandCore(db, landlord, envelope('command_sub_06', 'unit.create', 'unit_234567', 0, unitPayload('A2')), now);
    expect(after.status).toBe('applied');

    // Tier changes on a live subscription are billing events; self-service ends
    // at activation.
    const lateSwitch = await executeCommandCore(db, landlord, envelope('command_sub_07', 'subscription.selectPlan', landlord.uid, 2, { tier: 'pro' }), now);
    expect(lateSwitch).toMatchObject({ status: 'rejected', error: { code: 'VALIDATION_FAILED' } });
  });

  it('approves a pending landlord account in the same payment confirmation', async () => {
    await seedLandlord({ approval: 'pending', subscription: 'pending_payment' });
    const confirm = await executeCommandCore(db, admin, envelope('command_sub_08', 'subscription.confirmPayment', landlord.uid, 1, { reference: 'MoMo TX 445566' }), now);
    expect(confirm).toMatchObject({ status: 'applied' });
    expect((await db.doc(`subscriptions/${landlord.uid}`).get()).data()).toMatchObject({ status: 'active' });
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()).toMatchObject({
      approvalStatus: 'approved', approvalReasonCode: 'PAYMENT_CONFIRMED', version: 2,
    });

    // One confirmed payment fully opens the workspace — no separate approval step.
    const create = await executeCommandCore(db, landlord, envelope('command_sub_09', 'unit.create', 'unit_345678', 0, unitPayload()), now);
    expect(create.status).toBe('applied');
  });

  it('never lets a payment confirmation undo a suspension', async () => {
    await seedLandlord({ approval: 'suspended', subscription: 'pending_payment' });
    const confirm = await executeCommandCore(db, admin, envelope('command_sub_10', 'subscription.confirmPayment', landlord.uid, 1, { reference: 'MoMo TX 445567' }), now);
    expect(confirm).toMatchObject({ status: 'rejected', error: { code: 'VALIDATION_FAILED' } });
    expect((await db.doc(`subscriptions/${landlord.uid}`).get()).data()).toMatchObject({ status: 'pending_payment' });
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()).toMatchObject({ approvalStatus: 'suspended' });
  });

  it('rejects malformed landlord approval state before activating a subscription', async () => {
    await seedLandlord({ subscription: 'pending_payment' });
    const invalidStatuses: Array<[string, unknown]> = [
      ['missing', FieldValue.delete()],
      ['malformed', 42],
      ['unexpected', 'archived'],
    ];
    for (const [label, approvalStatus] of invalidStatuses) {
      await db.doc(`landlordAccounts/${landlord.uid}`).update({ approvalStatus });
      const confirm = await executeCommandCore(
        db,
        admin,
        envelope(
          `command_sub_invalid_${label}`,
          'subscription.confirmPayment',
          landlord.uid,
          1,
          { reference: `MoMo TX invalid ${label}` },
        ),
        now,
      );
      expect(confirm).toMatchObject({
        status: 'rejected',
        error: {
          code: 'VALIDATION_FAILED',
          details: { reason: 'accountApprovalStatusInvalid' },
        },
      });
      expect((await db.doc(`subscriptions/${landlord.uid}`).get()).data()).toMatchObject({
        status: 'pending_payment', version: 1,
      });
    }
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

describe('staff seats and roles', () => {
  const staff: Actor = { uid: 'staff_1234567', email: 'agent@nyumba.test', platformAdmin: false, superAdmin: false, emailVerified: true, signInProvider: 'password' };
  const membershipId = `${landlord.uid}__${staff.uid}`;
  const claim = { commandId: 'command_staff_claim_1', type: 'staff.claimInvite', schemaVersion: 1 as const, payload: {}, client: { installationId: 'install_1234', appVersion: '1.0.0', platform: 'web' as const } };

  async function invitePremiumAgent(): Promise<void> {
    await seedLandlord({ tier: 'premium' });
    const invite = await executeCommandCore(db, landlord, envelope('command_staff_invite_1', 'staff.invite', 'staffinv_1234', 0, {
      // Mixed-case email must normalize just like tenant invites.
      email: 'Agent@Nyumba.test', displayName: 'Agent', permissions: ['manageProperties', 'manageMaintenance'],
    }), now);
    expect(invite.status).toBe('applied');
  }

  it('honours a custom permission subset on Premium and links a deterministic membership', async () => {
    await invitePremiumAgent();
    expect((await db.doc('staffInvites/staffinv_1234').get()).data()).toMatchObject({
      email: 'agent@nyumba.test', inviteState: 'pending', permissions: ['manageProperties', 'manageMaintenance'],
    });
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()).toMatchObject({
      activeStaffSeatCount: 1,
    });

    const linked = await executeCommandCore(db, staff, claim, now);
    expect(linked.status).toBe('applied');
    expect(linked.result).toMatchObject({ linkedMemberships: 1 });
    expect((await db.doc(`staffMemberships/${membershipId}`).get()).data()).toMatchObject({
      landlordId: landlord.uid, memberUid: staff.uid, active: true, permissions: ['manageProperties', 'manageMaintenance'],
    });
    expect((await db.doc('staffInvites/staffinv_1234').get()).data()).toMatchObject({ inviteState: 'accepted', memberUid: staff.uid });
  });

  it('lets a staff member run granted commands against the owner workspace', async () => {
    await invitePremiumAgent();
    await executeCommandCore(db, staff, claim, now);

    // manageProperties is granted -> the property is created under the OWNER.
    const created = await executeCommandCore(db, staff, envelope('command_staff_prop_1', 'property.create', 'propstaff_1234', 0, {
      name: 'Block B', addressLine: '12 Kira Road', city: 'Kampala',
    }), now);
    expect(created.status).toBe('applied');
    expect((await db.doc('properties/propstaff_1234').get()).data()).toMatchObject({ landlordId: landlord.uid });
  });

  it('denies commands the staff member was not granted', async () => {
    await invitePremiumAgent();
    await executeCommandCore(db, staff, claim, now);

    // manageTenants was not granted.
    const denied = await executeCommandCore(db, staff, envelope('command_staff_tenant_1', 'tenant.invite', 'tenantrec_staff1', 0, {
      displayName: 'Someone', email: 'someone@example.com', phone: '+256772000111',
    }), now);
    expect(denied).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });
  });

  it('keeps owner-only commands out of staff reach', async () => {
    await invitePremiumAgent();
    await executeCommandCore(db, staff, claim, now);

    // subscription.* resolves the workspace from the actor uid, never staff.
    const upgrade = await executeCommandCore(db, staff, envelope('command_staff_upgrade_1', 'subscription.requestUpgrade', landlord.uid, 1, {
      tier: 'premium', billingChannel: 'mobile_money',
    }), now);
    expect(upgrade).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });
  });

  it('revokes a seat, cutting the membership and command access', async () => {
    await invitePremiumAgent();
    await executeCommandCore(db, staff, claim, now);

    // Claiming bumped the invite to version 2.
    const revoke = await executeCommandCore(db, landlord, envelope('command_staff_revoke_1', 'staff.revoke', 'staffinv_1234', 2, {}), now);
    expect(revoke.status).toBe('applied');
    expect((await db.doc(`staffMemberships/${membershipId}`).get()).exists).toBe(false);
    expect((await db.doc('staffInvites/staffinv_1234').get()).data()).toMatchObject({ inviteState: 'revoked', memberUid: null });
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()).toMatchObject({
      activeStaffSeatCount: 0,
    });

    const afterRevoke = await executeCommandCore(db, staff, envelope('command_staff_prop_2', 'property.create', 'propstaff_5678', 0, {
      name: 'Block C', addressLine: '9 Ntinda', city: 'Kampala',
    }), now);
    expect(afterRevoke).toMatchObject({ status: 'rejected', error: { code: 'PERMISSION_DENIED' } });
  });

  it('coerces a Pro invite to the standard preset', async () => {
    await seedLandlord({ tier: 'pro' });
    const invite = await executeCommandCore(db, landlord, envelope('command_staff_invite_pro', 'staff.invite', 'staffinv_pro1', 0, {
      email: 'pro.agent@nyumba.test', permissions: ['manageMaintenance'],
    }), now);
    expect(invite.status).toBe('applied');
    const stored = (await db.doc('staffInvites/staffinv_pro1').get()).data();
    expect([...(stored?.permissions as string[])].sort()).toEqual([...STAFF_PERMISSIONS].sort());
  });

  it('rejects invites past the plan seat limit', async () => {
    await seedLandlord({ tier: 'pro', staffSeatLimit: 1 });
    const first = await executeCommandCore(db, landlord, envelope('command_staff_seat_1', 'staff.invite', 'staffinv_seat1', 0, {
      email: 'one@nyumba.test', permissions: ['manageProperties'],
    }), now);
    expect(first.status).toBe('applied');
    const second = await executeCommandCore(db, landlord, envelope('command_staff_seat_2', 'staff.invite', 'staffinv_seat2', 0, {
      email: 'two@nyumba.test', permissions: ['manageProperties'],
    }), now);
    expect(second).toMatchObject({ status: 'rejected', error: { code: 'SEAT_LIMIT_REACHED' } });
  });

  it('backfills a legacy landlord seat counter from active invites', async () => {
    await seedLandlord({ tier: 'premium' });
    await db.doc(`landlordAccounts/${landlord.uid}`).update({
      activeStaffSeatCount: FieldValue.delete(),
    });

    const invited = await executeCommandCore(db, landlord, envelope(
      'command_staff_legacy_invite',
      'staff.invite',
      'staffinv_legacy1',
      0,
      { email: 'legacy.agent@nyumba.test', permissions: ['manageProperties'] },
    ), now);
    expect(invited.status).toBe('applied');
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()).toMatchObject({
      activeStaffSeatCount: 1,
    });

    // Simulate the same legacy shape with an existing seat. Revoke must count
    // the invite transactionally and repair the counter instead of stranding it.
    await db.doc(`landlordAccounts/${landlord.uid}`).update({
      activeStaffSeatCount: FieldValue.delete(),
    });
    const revoked = await executeCommandCore(db, landlord, envelope(
      'command_staff_legacy_revoke',
      'staff.revoke',
      'staffinv_legacy1',
      1,
      {},
    ), now);
    expect(revoked.status).toBe('applied');
    expect((await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()).toMatchObject({
      activeStaffSeatCount: 0,
    });
  });

  it('rejects a claim addressed to more than one landlord workspace', async () => {
    await invitePremiumAgent();
    const secondLandlord: Actor = {
      uid: 'landlord_second_1', email: 'second@nyumba.test', platformAdmin: false,
      superAdmin: false, emailVerified: true, signInProvider: 'password',
    };
    const firstAccount = (await db.doc(`landlordAccounts/${landlord.uid}`).get()).data()!;
    const firstSubscription = (await db.doc(`subscriptions/${landlord.uid}`).get()).data()!;
    await db.doc(`landlordAccounts/${secondLandlord.uid}`).set({
      ...firstAccount,
      id: secondLandlord.uid,
      ownerUid: secondLandlord.uid,
      activeStaffSeatCount: 0,
    });
    await db.doc(`subscriptions/${secondLandlord.uid}`).set({
      ...firstSubscription,
      id: secondLandlord.uid,
    });
    const invited = await executeCommandCore(db, secondLandlord, envelope(
      'command_staff_invite_2',
      'staff.invite',
      'staffinv_second',
      0,
      { email: staff.email, permissions: ['manageProperties'] },
    ), now);
    expect(invited.status).toBe('applied');

    const result = await executeCommandCore(db, staff, claim, now);
    expect(result).toMatchObject({
      status: 'rejected',
      error: { code: 'VALIDATION_FAILED', details: { reason: 'multipleWorkspaceInvites' } },
    });
    expect((await db.collection('staffMemberships').where('memberUid', '==', staff.uid).get()).empty).toBe(true);
  });

  it('requires the custom-role entitlement to change permissions', async () => {
    await seedLandlord({ tier: 'pro' });
    await executeCommandCore(db, landlord, envelope('command_staff_invite_upd', 'staff.invite', 'staffinv_upd1', 0, {
      email: 'upd.agent@nyumba.test', permissions: ['manageProperties'],
    }), now);
    const update = await executeCommandCore(db, landlord, envelope('command_staff_update_1', 'staff.updatePermissions', 'staffinv_upd1', 1, {
      permissions: ['manageBilling'],
    }), now);
    expect(update).toMatchObject({ status: 'rejected', error: { code: 'CUSTOM_ROLES_UNAVAILABLE' } });
  });
});
