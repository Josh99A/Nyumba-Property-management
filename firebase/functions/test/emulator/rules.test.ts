import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, limit, query, setDoc, Timestamp, where } from 'firebase/firestore';
import { getBytes, listAll, ref, uploadBytes } from 'firebase/storage';
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
      // Reputation. The canonical review names its author, the two public
      // mirrors name nobody, and the whole point of the split is that only the
      // mirrors are reachable without a UID.
      setDoc(doc(db, 'landlordReviews/lease_1'), {
        landlordId: 'landlord_1', reviewerUid: 'tenant_1', overall: 4, status: 'published',
      }),
      setDoc(doc(db, 'landlordRatings/landlord_1'), { count: 4, average: 4.25 }),
      setDoc(doc(db, 'publicReviews/lease_1'), {
        landlordToken: 'token_abc', overall: 4, status: 'published',
      }),
      setDoc(doc(db, 'publicLandlordRatings/token_abc'), { count: 4, average: 4.25 }),
      setDoc(doc(db, 'platformFeedback/feedback_1'), {
        actorUid: 'landlord_1', kind: 'nps', score: 3,
      }),
      setDoc(doc(db, 'supportTickets/ticket_1'), {
        landlordId: 'landlord_1', status: 'open', isTerminal: false, subject: 'Billing',
      }),
      // The queryable mirror of who holds an admin claim. `landlord_1` is listed
      // deliberately: the tests below prove a row here grants them nothing.
      setDoc(doc(db, 'platformStaff/admin_123'), {
        uid: 'admin_123', email: 'ops@nyumba.test', level: 'platformAdmin',
      }),
      setDoc(doc(db, 'platformStaff/landlord_1'), {
        uid: 'landlord_1', email: 'impostor@nyumba.test', level: 'superAdmin',
      }),
      setDoc(doc(db, 'properties/landlord_two'), { landlordId: 'landlord_2' }),
      setDoc(doc(db, 'payments/payment_one'), { landlordId: 'landlord_1' }),
      setDoc(doc(db, 'staffInvites/invite_1'), {
        landlordId: 'landlord_1', email: 'agent@nyumba.test', inviteState: 'pending',
      }),
      setDoc(doc(db, 'staffMemberships/landlord_1__staff_1'), {
        landlordId: 'landlord_1', memberUid: 'staff_1', active: true, permissions: ['manageProperties'],
      }),
      setDoc(doc(db, 'staffMemberships/landlord_1__staff_2'), {
        landlordId: 'landlord_1', memberUid: 'staff_2', active: false, permissions: [],
      }),
      setDoc(doc(db, 'staffMemberships/landlord_1__staff_billing'), {
        landlordId: 'landlord_1', memberUid: 'staff_billing', active: true,
        permissions: ['manageBilling', 'viewReports'],
      }),
      // The portal projections are gated on the owner's account/subscription
      // being live, so both must exist for those reads to be reachable at all.
      setDoc(doc(db, 'landlordAccounts/landlord_1'), { approvalStatus: 'approved' }),
      setDoc(doc(db, 'subscriptions/landlord_1'), { status: 'active' }),
      setDoc(doc(db, 'landlordPortals/landlord_1/tenancies/tenancy_1'), { id: 'tenancy_1' }),
      setDoc(doc(db, 'landlordPortals/landlord_1/payments/portal_payment_1'), { id: 'portal_payment_1' }),
      setDoc(doc(db, 'tenantPortals/tenant_1/leases/lease_123'), { id: 'lease_123' }),
      setDoc(doc(db, 'notificationInboxes/tenant_1/items/notice_123'), {
        id: 'notice_123', recipientUid: 'tenant_1', isRead: false,
      }),
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
    await assertSucceeds(getDoc(doc(tenantDb, 'notificationInboxes/tenant_1/items/notice_123')));
    await assertFails(getDoc(doc(
      env.authenticatedContext('tenant_2').firestore(),
      'notificationInboxes/tenant_1/items/notice_123',
    )));
    await assertSucceeds(getDoc(doc(landlordDb, 'reportSnapshots/report_1')));
    await assertFails(getDoc(doc(env.authenticatedContext('landlord_2').firestore(), 'reportSnapshots/report_1')));
  });

  it('scopes staff reads to the capabilities they were granted', async () => {
    const portfolioStaff = env.authenticatedContext('staff_1').firestore();
    // manageProperties opens the portfolio, including a list query scoped to
    // the owner and authorized per document...
    await assertSucceeds(getDoc(doc(portfolioStaff, 'properties/landlord_one')));
    await assertSucceeds(getDocs(query(
      collection(portfolioStaff, 'properties'),
      where('landlordId', '==', 'landlord_1'),
      limit(20),
    )));
    // ...but never the financial ledger.
    await assertFails(getDoc(doc(portfolioStaff, 'payments/payment_one')));

    // manageBilling is the mirror image.
    const billingStaff = env.authenticatedContext('staff_billing').firestore();
    await assertSucceeds(getDoc(doc(billingStaff, 'payments/payment_one')));
    await assertFails(getDoc(doc(billingStaff, 'properties/landlord_one')));

    // viewReports opens the owner's report snapshots; without it they stay shut.
    await assertSucceeds(getDoc(doc(billingStaff, 'reportSnapshots/report_1')));
    await assertFails(getDoc(doc(portfolioStaff, 'reportSnapshots/report_1')));

    // Another landlord's workspace stays closed either way.
    await assertFails(getDoc(doc(portfolioStaff, 'properties/landlord_two')));

    // An inactive membership grants nothing, and neither does a non-member.
    await assertFails(getDoc(doc(
      env.authenticatedContext('staff_2').firestore(), 'properties/landlord_one',
    )));
    await assertFails(getDoc(doc(
      env.authenticatedContext('staff_3').firestore(), 'properties/landlord_one',
    )));
    // A member still cannot forge writes to canonical documents.
    await assertFails(setDoc(doc(portfolioStaff, 'properties/landlord_one'), { landlordId: 'landlord_1' }));

    // The owner keeps unrestricted access to their own workspace.
    const ownerDb = env.authenticatedContext('landlord_1').firestore();
    await assertSucceeds(getDoc(doc(ownerDb, 'properties/landlord_one')));
    await assertSucceeds(getDoc(doc(ownerDb, 'payments/payment_one')));
    await assertSucceeds(getDoc(doc(ownerDb, 'staffMemberships/landlord_1__staff_1')));
    await assertSucceeds(getDocs(query(
      collection(ownerDb, 'staffInvites'),
      where('landlordId', '==', 'landlord_1'),
      limit(20),
    )));
    // A member reads their own membership to discover the workspace.
    await assertSucceeds(getDoc(doc(portfolioStaff, 'staffMemberships/landlord_1__staff_1')));
  });

  it('redacts the portal projections by capability too', async () => {
    const ownerDb = env.authenticatedContext('landlord_1').firestore();
    await assertSucceeds(getDoc(doc(ownerDb, 'landlordPortals/landlord_1/tenancies/tenancy_1')));
    await assertSucceeds(getDoc(doc(ownerDb, 'landlordPortals/landlord_1/payments/portal_payment_1')));

    // Billing sees the payment projection and nothing else.
    const billingStaff = env.authenticatedContext('staff_billing').firestore();
    await assertSucceeds(getDoc(doc(billingStaff, 'landlordPortals/landlord_1/payments/portal_payment_1')));
    await assertFails(getDoc(doc(billingStaff, 'landlordPortals/landlord_1/tenancies/tenancy_1')));

    // A portfolio-only member holds neither capability.
    const portfolioStaff = env.authenticatedContext('staff_1').firestore();
    await assertFails(getDoc(doc(portfolioStaff, 'landlordPortals/landlord_1/payments/portal_payment_1')));
    await assertFails(getDoc(doc(portfolioStaff, 'landlordPortals/landlord_1/tenancies/tenancy_1')));
  });

  it('denies canonical client writes and protects receipts/jobs/audits', async () => {
    const tenantDb = env.authenticatedContext('tenant_1').firestore();
    for (const path of [
      'users/user_1234', 'properties/property_1', 'units/unit_123456', 'leases/lease_1234',
      'invoices/invoice_1', 'payments/payment_1', 'privateListings/listing_1',
      'applications/app_1234', 'documents/document_1',
      'notificationInboxes/tenant_1/items/notice_123',
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

  it('exposes reputation only through the anonymous mirrors', async () => {
    const anonymous = env.unauthenticatedContext().firestore();
    // A browser must be able to read a published review and a landlord's
    // aggregate without signing in — anonymous browsing is a supported mode.
    await assertSucceeds(getDoc(doc(anonymous, 'publicReviews/lease_1')));
    await assertSucceeds(getDoc(doc(anonymous, 'publicLandlordRatings/token_abc')));
    // ...but never the canonical review, which names the tenant who wrote it.
    await assertFails(getDoc(doc(anonymous, 'landlordReviews/lease_1')));
    // Enumerating every landlord's rating would let anyone build a leaderboard
    // of the platform's worst-rated landlords keyed by an opaque token they
    // could then match back to listings.
    await assertFails(getDocs(query(collection(anonymous, 'publicLandlordRatings'), limit(10))));
    // The list rule reads `resource.data.status`, which Firestore can only
    // satisfy when the query itself constrains it — an unconstrained list is
    // denied outright rather than filtered. This is the same query
    // `fetchPublicReviews` issues, so the two cannot drift.
    const publishedFor = (token: string, rows: number) => query(
      collection(anonymous, 'publicReviews'),
      where('status', '==', 'published'),
      where('landlordToken', '==', token),
      limit(rows),
    );
    await assertSucceeds(getDocs(publishedFor('token_abc', 50)));
    // Rules cap the page at 50 so no single read can drain the corpus.
    await assertFails(getDocs(publishedFor('token_abc', 51)));
    await assertFails(getDocs(query(collection(anonymous, 'publicReviews'), limit(10))));

    // A landlord sees their own totals — including below the public display
    // threshold, so a rating never appears on their listings unannounced.
    const landlordDb = env.authenticatedContext('landlord_1').firestore();
    await assertSucceeds(getDoc(doc(landlordDb, 'landlordRatings/landlord_1')));
    // The canonical review stays closed even to its subject: they read their
    // copy from landlordPortals, which withholds the reviewer's UID.
    await assertFails(getDoc(doc(landlordDb, 'landlordReviews/lease_1')));
    await assertFails(getDoc(doc(env.authenticatedContext('landlord_2').firestore(), 'landlordRatings/landlord_1')));

    // No client may write any of it, including the review's own author.
    const tenantDb = env.authenticatedContext('tenant_1').firestore();
    for (const path of [
      'landlordReviews/lease_1',
      'landlordRatings/landlord_1',
      'publicReviews/lease_1',
      'publicLandlordRatings/token_abc',
    ]) {
      await assertFails(setDoc(doc(tenantDb, path), { overall: 5 }));
    }

    const adminDb = env.authenticatedContext('admin_123', { platformAdmin: true }).firestore();
    await assertSucceeds(getDoc(doc(adminDb, 'landlordReviews/lease_1')));
  });

  it('keeps landlord feedback private to the platform team', async () => {
    // Not even the author reads it back: nothing in the app renders it, and a
    // readable path would make one landlord's complaints enumerable by another.
    await assertFails(getDoc(doc(env.authenticatedContext('landlord_1').firestore(), 'platformFeedback/feedback_1')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'platformFeedback/feedback_1')));
    await assertSucceeds(getDoc(doc(env.authenticatedContext('admin_123', { platformAdmin: true }).firestore(), 'platformFeedback/feedback_1')));
  });

  it('opens a support ticket to its landlord and the platform team, and nobody else', async () => {
    const path = 'supportTickets/ticket_1';
    // The inverse of platformFeedback above, and the distinction the whole
    // feature rests on: a conversation the author cannot read is not a
    // conversation.
    await assertSucceeds(getDoc(doc(env.authenticatedContext('landlord_1').firestore(), path)));
    await assertSucceeds(
      getDoc(doc(env.authenticatedContext('admin_123', { platformAdmin: true }).firestore(), path)),
    );
    await assertFails(getDoc(doc(env.authenticatedContext('landlord_2').firestore(), path)));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), path)));
    // Staff of this very workspace are excluded on purpose: `staff_1` reads the
    // owner's properties through their capability, and still cannot read the
    // owner's correspondence with us.
    await assertFails(getDoc(doc(env.authenticatedContext('staff_1').firestore(), path)));
    await assertFails(
      getDocs(query(
        collection(env.authenticatedContext('landlord_2').firestore(), 'supportTickets'),
        where('landlordId', '==', 'landlord_1'),
        limit(20),
      )),
    );
  });

  it('treats the platformStaff mirror as a directory, never as authority', async () => {
    const impostor = env.authenticatedContext('landlord_1').firestore();
    const admin = env
      .authenticatedContext('admin_123', { platformAdmin: true })
      .firestore();

    // `landlord_1` has a platformStaff row claiming superAdmin and holds no
    // claim. If any rule ever consulted this collection instead of the token,
    // these would start passing — which is the whole failure this pins.
    await assertFails(getDoc(doc(impostor, 'platformFeedback/feedback_1')));
    await assertFails(getDoc(doc(impostor, 'landlordReviews/lease_1')));
    await assertFails(getDoc(doc(impostor, 'auditLogs/audit_123')));
    await assertFails(getDoc(doc(impostor, 'properties/landlord_two')));
    // Not even the directory itself.
    await assertFails(getDoc(doc(impostor, 'platformStaff/admin_123')));
    await assertFails(
      getDocs(query(collection(impostor, 'platformStaff'), limit(10))),
    );

    // A real claim reads it, because the fanout worker needs an audience and
    // the admin console will eventually want to show who is on call.
    await assertSucceeds(getDoc(doc(admin, 'platformStaff/admin_123')));
    await assertSucceeds(
      getDocs(query(collection(admin, 'platformStaff'), limit(10))),
    );
    // Nobody writes it from a client; the ops script uses the Admin SDK.
    await assertFails(
      setDoc(doc(admin, 'platformStaff/self_promoted'), { level: 'superAdmin' }),
    );
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'platformStaff/admin_123')));
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

  it('allows anonymous get on public listing media, published or stale, but denies anonymous list', async () => {
    await env.withSecurityRulesDisabled(async (context) => {
      await Promise.all([
        uploadBytes(
          ref(context.storage(), 'public/listings/published_1/photo.jpg'),
          new Uint8Array([1, 2, 3]),
          { contentType: 'image/jpeg' },
        ),
        // `expired_123` matches the seeded Firestore doc whose expiresAt is in
        // the past: the rule does not check Firestore at all, so a stale
        // object is gettable until the cleanup sweep deletes it — that is the
        // documented, intentional gap. What must not be true is that it can
        // also be enumerated.
        uploadBytes(
          ref(context.storage(), 'public/listings/expired_123/photo.jpg'),
          new Uint8Array([1, 2, 3]),
          { contentType: 'image/jpeg' },
        ),
      ]);
    });

    const anonymousStorage = env.unauthenticatedContext().storage();
    await assertSucceeds(getBytes(ref(anonymousStorage, 'public/listings/published_1/photo.jpg')));
    await assertSucceeds(getBytes(ref(anonymousStorage, 'public/listings/expired_123/photo.jpg')));
    await assertFails(listAll(ref(anonymousStorage, 'public/listings/published_1')));
  });
});
