import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { COLLECTIONS } from '../shared/collections';
import { LISTING_LIFETIME_DAYS } from '../shared/config';
import {
  APP_ORIGIN,
  buildEmailHtml,
  formatEmailMoney,
  sendEmail,
} from '../shared/email';

/**
 * Email delivery workers. Every email is a courtesy copy of state the app
 * already shows — the canonical record is Firestore, so a missing address or
 * a stale aggregate skips quietly instead of failing the job. Each send uses
 * a business-stable idempotency key, so a retried job cannot double-send
 * within Resend's dedupe window.
 */

const METHOD_LABELS: Record<string, string> = {
  cash: 'Cash',
  bank_transfer: 'Bank transfer',
  mtn_momo: 'MTN Mobile Money',
  airtel_money: 'Airtel Money',
};

async function userEmail(
  db: Firestore,
  uid: string | null | undefined,
): Promise<{ email: string; name: string | null } | null> {
  if (!uid) return null;
  const snapshot = await db.collection(COLLECTIONS.users).doc(uid).get();
  const user = snapshot.data();
  if (!user || user.isDeleted === true || typeof user.email !== 'string' || !user.email) {
    return null;
  }
  return { email: user.email, name: typeof user.displayName === 'string' ? user.displayName : null };
}

/**
 * A tenant's address: their account profile once the invite is claimed,
 * otherwise the email the landlord entered on the tenant record.
 */
async function tenantEmailForLease(
  db: Firestore,
  lease: { tenantUserUid?: unknown; tenantRecordId?: unknown },
): Promise<{ email: string; name: string | null } | null> {
  const fromUser = await userEmail(
    db,
    typeof lease.tenantUserUid === 'string' ? lease.tenantUserUid : null,
  );
  if (fromUser) return fromUser;
  if (typeof lease.tenantRecordId !== 'string') return null;
  const snapshot = await db.collection(COLLECTIONS.tenantRecords).doc(lease.tenantRecordId).get();
  const record = snapshot.data();
  if (!record || record.isDeleted === true || typeof record.email !== 'string' || !record.email) {
    return null;
  }
  return {
    email: record.email,
    name: typeof record.displayName === 'string' ? record.displayName : null,
  };
}

/** The landlord's public-facing name: business name, else profile name. */
async function landlordDisplayName(db: Firestore, landlordId: string): Promise<string> {
  const [accountSnap, owner] = await Promise.all([
    db.collection(COLLECTIONS.landlordAccounts).doc(landlordId).get(),
    userEmail(db, landlordId),
  ]);
  const businessName = accountSnap.data()?.businessName;
  if (typeof businessName === 'string' && businessName) return businessName;
  return owner?.name ?? 'your landlord';
}

/**
 * Invites the person a landlord just registered as a tenant. Signing in with
 * this exact address is what links the tenancy (tenant.claimInvite), so the
 * email spells that out rather than carrying any secret.
 */
export async function sendTenantInviteEmail(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const tenantRecordId = String(payload.tenantRecordId);
  const snapshot = await db.collection(COLLECTIONS.tenantRecords).doc(tenantRecordId).get();
  const record = snapshot.data();
  if (!record || record.isDeleted === true) return;
  // An already-claimed invite means the person is in the app; greeting them
  // with "you've been invited" after the fact would only confuse.
  if (record.inviteState !== 'pending') return;
  if (typeof record.email !== 'string' || !record.email) return;
  const landlordName = await landlordDisplayName(db, String(record.landlordId ?? ''));

  await sendEmail({
    to: record.email,
    subject: 'You have been invited to Nyumba',
    idempotencyKey: `tenant_invite_${tenantRecordId}`,
    html: buildEmailHtml({
      recipientName: typeof record.displayName === 'string' ? record.displayName : null,
      heading: 'Your tenancy is ready on Nyumba',
      paragraphs: [
        `${landlordName} manages your tenancy with Nyumba and has invited you to the tenant portal.`,
        'There you can see your lease, rent balance, receipts, and report maintenance issues.',
        `To join, open Nyumba and sign in with this email address (${record.email}) — `
        + 'use Google sign-in or create a password. Your tenancy links automatically once your email is verified.',
      ],
      cta: { label: 'Open Nyumba', url: APP_ORIGIN },
    }),
  });
}

/**
 * Emails the tenant their rent receipt after the server confirmed a payment.
 * The receipt facts come from the canonical receipt/payment records — the
 * same server-owned values the PDF is rendered from.
 */
export async function sendPaymentReceiptEmail(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const receiptId = String(payload.receiptId);
  const receiptSnap = await db.collection(COLLECTIONS.receipts).doc(receiptId).get();
  const receipt = receiptSnap.data();
  if (!receipt || receipt.isDeleted === true) return;
  const paymentSnap = await db
    .collection(COLLECTIONS.payments)
    .doc(String(receipt.paymentId))
    .get();
  const payment = paymentSnap.data() ?? {};

  const leaseId = typeof payment.leaseId === 'string' ? payment.leaseId : null;
  const leaseSnap = leaseId
    ? await db.collection(COLLECTIONS.leases).doc(leaseId).get()
    : null;
  const recipient = await tenantEmailForLease(db, {
    tenantUserUid: receipt.tenantUserUid,
    tenantRecordId: leaseSnap?.data()?.tenantRecordId,
  });
  if (!recipient) return;

  const rows = [
    { label: 'Receipt', value: String(receipt.receiptNumber ?? receiptId) },
    { label: 'Amount', value: formatEmailMoney(Number(receipt.amountMinor ?? 0)) },
    { label: 'Method', value: METHOD_LABELS[String(payment.method)] ?? String(payment.method ?? 'unknown') },
  ];
  if (typeof payment.period === 'string' && payment.period) {
    rows.push({ label: 'Period', value: payment.period });
  }
  if (typeof payment.reference === 'string' && payment.reference) {
    rows.push({ label: 'Reference', value: payment.reference });
  }

  await sendEmail({
    to: recipient.email,
    subject: `Rent receipt ${String(receipt.receiptNumber ?? '')}`.trim(),
    idempotencyKey: `receipt_${receiptId}`,
    html: buildEmailHtml({
      recipientName: recipient.name,
      heading: 'Payment received — thank you',
      paragraphs: [
        'Your rent payment has been recorded and confirmed. Here are the details for your records.',
        'The full receipt is available in your Nyumba tenant portal.',
      ],
      rows,
      cta: { label: 'View in Nyumba', url: APP_ORIGIN },
    }),
  });
}

/** Tells a landlord their account was approved and the workspace is live. */
export async function sendLandlordApprovedEmail(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const landlordId = String(payload.landlordId);
  // Approval can be reversed; only an account still approved gets the email.
  const accountSnap = await db.collection(COLLECTIONS.landlordAccounts).doc(landlordId).get();
  if (accountSnap.data()?.approvalStatus !== 'approved') return;
  const recipient = await userEmail(db, landlordId);
  if (!recipient) return;

  await sendEmail({
    to: recipient.email,
    subject: 'Your Nyumba landlord account is approved',
    idempotencyKey: `landlord_approved_${landlordId}`,
    html: buildEmailHtml({
      recipientName: recipient.name,
      heading: 'Welcome aboard — you are approved',
      paragraphs: [
        'Your landlord account has been reviewed and approved.',
        'You can now add properties and units, invite tenants, record rent payments, and publish listings.',
      ],
      cta: { label: 'Open your workspace', url: APP_ORIGIN },
    }),
  });
}

const REMINDER_KINDS = new Set(['upcoming', 'overdue']);

/**
 * Rent reminder for one invoice, enqueued by the daily scheduler. The invoice
 * is re-read at send time: one settled between enqueue and send skips.
 */
export async function sendRentReminderEmail(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const invoiceId = String(payload.invoiceId);
  const kind = String(payload.kind);
  if (!REMINDER_KINDS.has(kind)) return;
  const invoiceSnap = await db.collection(COLLECTIONS.invoices).doc(invoiceId).get();
  const invoice = invoiceSnap.data();
  if (!invoice || invoice.isDeleted === true) return;
  const balanceMinor = Number(invoice.balanceMinor ?? 0);
  if (balanceMinor <= 0 || (invoice.status !== 'due' && invoice.status !== 'part_paid')) return;

  const leaseSnap = typeof invoice.leaseId === 'string'
    ? await db.collection(COLLECTIONS.leases).doc(invoice.leaseId).get()
    : null;
  const recipient = await tenantEmailForLease(db, {
    tenantUserUid: invoice.tenantUserUid,
    tenantRecordId: leaseSnap?.data()?.tenantRecordId,
  });
  if (!recipient) return;

  const dueDate = typeof invoice.dueDate === 'string' ? invoice.dueDate.slice(0, 10) : '';
  const upcoming = kind === 'upcoming';
  await sendEmail({
    to: recipient.email,
    subject: upcoming ? 'Rent due soon — Nyumba reminder' : 'Rent overdue — Nyumba reminder',
    idempotencyKey: `rent_${kind}_${invoiceId}`,
    html: buildEmailHtml({
      recipientName: recipient.name,
      heading: upcoming ? 'Your rent is due soon' : 'Your rent is overdue',
      paragraphs: [
        upcoming
          ? 'A friendly reminder that a rent payment is coming due on your tenancy.'
          : 'Our records show a rent balance on your tenancy that is now past its due date.',
        'If you have already paid, you can ignore this message — payments recorded by your landlord can take a moment to reflect.',
      ],
      rows: [
        { label: 'Outstanding', value: formatEmailMoney(balanceMinor) },
        ...(dueDate ? [{ label: 'Due date', value: dueDate }] : []),
      ],
      cta: { label: 'View your balance', url: APP_ORIGIN },
    }),
  });
}

const MAINTENANCE_STATUS_LINES: Record<string, string> = {
  acknowledged: 'Your landlord has seen your maintenance request and acknowledged it.',
  scheduled: 'Your landlord has scheduled work for your maintenance request.',
  in_progress: 'Work on your maintenance request is now in progress.',
  resolved: 'Your maintenance request has been marked as resolved.',
  closed: 'Your maintenance request has been closed.',
};

/** Tells the tenant their maintenance request moved to a new status. */
export async function sendMaintenanceStatusEmail(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const requestId = String(payload.requestId);
  const snapshot = await db.collection(COLLECTIONS.maintenanceRequests).doc(requestId).get();
  const request = snapshot.data();
  if (!request || request.isDeleted === true) return;
  // The canonical record, not the job payload, says what the status is now; a
  // request that moved again before this ran reports its latest state once.
  const line = MAINTENANCE_STATUS_LINES[String(request.status)];
  if (!line) return;
  const recipient = await userEmail(
    db,
    typeof request.tenantUserUid === 'string' ? request.tenantUserUid : null,
  );
  if (!recipient) return;

  const note = typeof request.statusNote === 'string' && request.statusNote ? request.statusNote : null;
  await sendEmail({
    to: recipient.email,
    subject: 'Update on your maintenance request',
    idempotencyKey: `maintenance_${requestId}_${String(request.status)}`,
    html: buildEmailHtml({
      recipientName: recipient.name,
      heading: 'Maintenance request update',
      paragraphs: [
        line,
        ...(note ? [`Note from your landlord: ${note}`] : []),
        'You can follow progress and add comments in your Nyumba tenant portal.',
      ],
      rows: [
        ...(typeof request.title === 'string' && request.title
          ? [{ label: 'Request', value: request.title }]
          : []),
        { label: 'Status', value: String(request.status).replace('_', ' ') },
      ],
      cta: { label: 'View request', url: APP_ORIGIN },
    }),
  });
}

/**
 * Warns both sides of a tenancy that the lease term ends soon, enqueued by
 * the daily scheduler once per lease end date.
 */
export async function sendLeaseExpiryEmail(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const leaseId = String(payload.leaseId);
  const snapshot = await db.collection(COLLECTIONS.leases).doc(leaseId).get();
  const lease = snapshot.data();
  if (!lease || lease.isDeleted === true || lease.status !== 'active') return;
  const endDate = typeof lease.endDate === 'string' ? lease.endDate.slice(0, 10) : '';
  if (!endDate) return;

  const [tenant, landlord] = await Promise.all([
    tenantEmailForLease(db, lease),
    userEmail(db, typeof lease.landlordId === 'string' ? lease.landlordId : null),
  ]);
  const rows = [{ label: 'Lease ends', value: endDate }];
  if (tenant) {
    await sendEmail({
      to: tenant.email,
      subject: 'Your lease ends soon — Nyumba',
      idempotencyKey: `lease_expiry_tenant_${leaseId}_${endDate}`,
      html: buildEmailHtml({
        recipientName: tenant.name,
        heading: 'Your lease term is ending soon',
        paragraphs: [
          'The lease on your tenancy reaches its end date soon.',
          'If you plan to renew or move out, this is a good time to talk to your landlord.',
        ],
        rows,
        cta: { label: 'View your lease', url: APP_ORIGIN },
      }),
    });
  }
  if (landlord) {
    await sendEmail({
      to: landlord.email,
      subject: 'A lease ends soon — Nyumba',
      idempotencyKey: `lease_expiry_landlord_${leaseId}_${endDate}`,
      html: buildEmailHtml({
        recipientName: landlord.name,
        heading: 'One of your leases is ending soon',
        paragraphs: [
          'A lease in your portfolio reaches its end date soon.',
          'Renew it or end the tenancy in Nyumba so your occupancy and listings stay accurate.',
        ],
        rows,
        cta: { label: 'Open your workspace', url: APP_ORIGIN },
      }),
    });
  }
}

/**
 * Warns a landlord their public listing expires soon (listings live
 * LISTING_LIFETIME_DAYS, then the hourly worker unpublishes them).
 */
export async function sendListingExpiryWarningEmail(
  payload: Record<string, unknown>,
): Promise<void> {
  const db = getFirestore();
  const listingId = String(payload.listingId);
  const snapshot = await db.collection(COLLECTIONS.publicListings).doc(listingId).get();
  const listing = snapshot.data();
  if (!listing || listing.status !== 'published') return;
  const recipient = await userEmail(
    db,
    typeof listing.landlordId === 'string' ? listing.landlordId : null,
  );
  if (!recipient) return;

  const title = typeof listing.title === 'string' && listing.title ? listing.title : 'Your listing';
  await sendEmail({
    to: recipient.email,
    subject: 'Your listing expires soon — Nyumba',
    idempotencyKey: `listing_expiry_${listingId}_${String(payload.expiresAtMillis ?? '')}`,
    html: buildEmailHtml({
      recipientName: recipient.name,
      heading: 'A listing is about to expire',
      paragraphs: [
        `“${title}” reaches the end of its ${LISTING_LIFETIME_DAYS}-day publication window soon and will be taken off the public site automatically.`,
        'If the unit is still available, republish it from your workspace to keep it visible.',
      ],
      cta: { label: 'Manage listings', url: APP_ORIGIN },
    }),
  });
}
