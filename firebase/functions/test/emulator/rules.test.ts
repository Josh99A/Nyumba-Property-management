import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, limit, query, setDoc, Timestamp, where } from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-nyumba-rules',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
    storage: { rules: readFileSync('../storage.rules', 'utf8') },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const future = Timestamp.fromDate(new Date('2100-01-01T00:00:00Z'));
    const past = Timestamp.fromDate(new Date('2020-01-01T00:00:00Z'));
    await Promise.all([
      setDoc(doc(db, 'publicListings/published_1'), { status: 'published', expiresAt: future }),
      setDoc(doc(db, 'publicListings/expired_123'), { status: 'published', expiresAt: past }),
      setDoc(doc(db, 'publicListings/malformed_1'), { status: 'published', expiresAt: '2100-01-01' }),
      setDoc(doc(db, 'properties/landlord_one'), { landlordId: 'landlord_1' }),
      setDoc(doc(db, 'properties/landlord_two'), { landlordId: 'landlord_2' }),
      setDoc(doc(db, 'tenantPortals/tenant_1/leases/lease_123'), { id: 'lease_123' }),
      setDoc(doc(db, 'commandReceipts/command_1'), { actorUid: 'tenant_1' }),
      setDoc(doc(db, 'reportSnapshots/report_1'), { ownerType: 'landlord', ownerId: 'landlord_1' }),
      setDoc(doc(db, 'backendJobs/job_123456'), { state: 'pending' }),
      setDoc(doc(db, 'auditLogs/audit_123'), { action: 'test' }),
    ]);
  });
  await env.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(
      ref(context.storage(), 'private/landlords/landlord_1/document.pdf'),
      new Uint8Array([1, 2, 3]),
      { contentType: 'application/pdf' },
    );
  });
});

afterAll(async () => env.cleanup());

describe('Firestore rules matrix', () => {
  it('allows anonymous reads of only published, unexpired public listings', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, 'publicListings/published_1')));
    await assertFails(getDoc(doc(db, 'publicListings/expired_123')));
    await assertFails(getDoc(doc(db, 'publicListings/malformed_1')));
    await assertSucceeds(getDocs(query(
      collection(db, 'publicListings'),
      where('status', '==', 'published'),
      where('expiresAt', '>', Timestamp.fromDate(new Date('2099-01-01T00:00:00Z'))),
      limit(50),
    )));
    await assertFails(getDocs(query(collection(db, 'publicListings'), limit(51))));
  });

  it('isolates landlord and tenant reads', async () => {
    const landlordDb = env.authenticatedContext('landlord_1').firestore();
    await assertSucceeds(getDoc(doc(landlordDb, 'properties/landlord_one')));
    await assertFails(getDoc(doc(landlordDb, 'properties/landlord_two')));
    const tenantDb = env.authenticatedContext('tenant_1').firestore();
    await assertSucceeds(getDoc(doc(tenantDb, 'tenantPortals/tenant_1/leases/lease_123')));
    await assertFails(getDoc(doc(tenantDb, 'tenantPortals/tenant_2/leases/lease_123')));
    await assertSucceeds(getDoc(doc(landlordDb, 'reportSnapshots/report_1')));
    await assertFails(getDoc(doc(env.authenticatedContext('landlord_2').firestore(), 'reportSnapshots/report_1')));
  });

  it('denies canonical client writes and protects receipts/jobs/audits', async () => {
    const tenantDb = env.authenticatedContext('tenant_1').firestore();
    for (const path of [
      'users/user_1234', 'properties/property_1', 'units/unit_123456', 'leases/lease_1234',
      'invoices/invoice_1', 'payments/payment_1', 'privateListings/listing_1',
      'applications/app_1234', 'documents/document_1',
    ]) {
      await assertFails(setDoc(doc(tenantDb, path), { landlordId: 'tenant_1' }));
    }
    await assertSucceeds(getDoc(doc(tenantDb, 'commandReceipts/command_1')));
    await assertFails(getDoc(doc(env.authenticatedContext('tenant_2').firestore(), 'commandReceipts/command_1')));
    await assertFails(getDoc(doc(tenantDb, 'backendJobs/job_123456')));
    await assertFails(getDoc(doc(tenantDb, 'auditLogs/audit_123')));

    const adminDb = env.authenticatedContext('admin_123', { platformAdmin: true }).firestore();
    await assertFails(getDoc(doc(adminDb, 'backendJobs/job_123456')));
    await assertSucceeds(getDoc(doc(adminDb, 'auditLogs/audit_123')));

    const superAdminDb = env.authenticatedContext('super_admin_123', { superAdmin: true }).firestore();
    await assertSucceeds(getDoc(doc(superAdminDb, 'properties/landlord_two')));
    await assertSucceeds(getDoc(doc(superAdminDb, 'auditLogs/audit_123')));
    await assertFails(getDoc(doc(superAdminDb, 'backendJobs/job_123456')));
  });

  it('allows both administrator claims to read canonical private media', async () => {
    const path = 'private/landlords/landlord_1/document.pdf';
    const adminStorage = env.authenticatedContext('admin_123', { platformAdmin: true }).storage();
    const superAdminStorage = env.authenticatedContext('super_admin_123', { superAdmin: true }).storage();
    const tenantStorage = env.authenticatedContext('tenant_123').storage();

    await assertSucceeds(getBytes(ref(adminStorage, path)));
    await assertSucceeds(getBytes(ref(superAdminStorage, path)));
    await assertFails(getBytes(ref(tenantStorage, path)));
  });
});
