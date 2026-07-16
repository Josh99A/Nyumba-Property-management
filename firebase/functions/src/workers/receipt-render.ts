import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import PDFDocument from 'pdfkit';
import { COLLECTIONS, TENANT_PORTAL_SECTIONS } from '../shared/collections';
import { CURRENCY } from '../shared/config';
import { tenantReceiptProjection } from '../shared/projections';

/**
 * Renders a payment receipt to PDF and stores it under the owning landlord's
 * private prefix, plus the tenant's when the lease is claimed.
 *
 * The client can already draw a receipt locally, but a locally drawn receipt is
 * only evidence that the device believes it was paid. This artifact is written
 * after the server confirmed the payment, from server-owned values (the receipt
 * number comes from the landlord's counter), which is what makes it a record
 * rather than a rendering.
 *
 * Idempotent: rendering the same receipt twice overwrites the same object.
 */
export async function renderReceipt(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const receiptId = String(payload.receiptId);
  const receiptRef = db.collection(COLLECTIONS.receipts).doc(receiptId);
  const receiptSnap = await receiptRef.get();
  if (!receiptSnap.exists) return;
  const receipt = receiptSnap.data()!;
  if (receipt.renderState === 'rendered') return;

  const landlordId = String(receipt.landlordId);
  const paymentSnap = await db.collection(COLLECTIONS.payments).doc(String(receipt.paymentId)).get();
  const payment = paymentSnap.data() ?? {};

  const pdf = await draw({
    receiptNumber: String(receipt.receiptNumber ?? receiptId),
    amountMinor: Number(receipt.amountMinor ?? 0),
    currency: String(receipt.currency ?? CURRENCY),
    issuedAt: toDate(receipt.issuedAt),
    method: String(payment.method ?? 'unknown'),
    period: String(payment.period ?? ''),
    reference: typeof payment.reference === 'string' ? payment.reference : null,
  });

  const bucket = getStorage().bucket();
  const storagePath = `private/landlords/${landlordId}/receipts/${receiptId}.pdf`;
  await bucket.file(storagePath).save(pdf, {
    contentType: 'application/pdf',
    resumable: false,
    metadata: { cacheControl: 'private, max-age=0, no-transform' },
  });

  let tenantStoragePath: string | null = null;
  if (typeof receipt.tenantUserUid === 'string') {
    tenantStoragePath = `private/tenants/${receipt.tenantUserUid}/receipts/${receiptId}.pdf`;
    await bucket.file(tenantStoragePath).save(pdf, {
      contentType: 'application/pdf',
      resumable: false,
      metadata: { cacheControl: 'private, max-age=0, no-transform' },
    });
  }

  const now = Timestamp.now();
  const next = {
    ...receipt,
    renderState: 'rendered',
    storagePath,
    tenantStoragePath,
    renderedAt: now,
    version: Number(receipt.version ?? 1) + 1,
    updatedAt: now,
  };
  await receiptRef.update({
    renderState: 'rendered',
    storagePath,
    tenantStoragePath,
    renderedAt: now,
    version: next.version,
    updatedAt: now,
  });
  if (typeof receipt.tenantUserUid === 'string') {
    await db
      .collection(COLLECTIONS.tenantPortals)
      .doc(receipt.tenantUserUid)
      .collection(TENANT_PORTAL_SECTIONS.receipts)
      .doc(receiptId)
      .set(tenantReceiptProjection(next));
  }
}

interface ReceiptView {
  receiptNumber: string;
  amountMinor: number;
  currency: string;
  issuedAt: Date;
  method: string;
  period: string;
  reference: string | null;
}

const METHOD_LABELS: Record<string, string> = {
  cash: 'Cash',
  bank_transfer: 'Bank transfer',
  mtn_momo: 'MTN Mobile Money',
  airtel_money: 'Airtel Money',
};

function draw(view: ReceiptView): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 56 });
    const chunks: Buffer[] = [];
    doc.on('data', (chunk: Buffer) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    // Midnight Navy / Terracotta Gold, per the brand palette in AGENTS.md.
    doc.fillColor('#123A6F').fontSize(24).text('Nyumba', { continued: false });
    doc.fillColor('#C98B2E').fontSize(12).text('Rent receipt');
    doc.moveDown(1.5);

    doc.fillColor('#123A6F').fontSize(18).text(view.receiptNumber);
    doc.moveDown(1);

    doc.fillColor('#000000').fontSize(11);
    row(doc, 'Amount', formatMoney(view.amountMinor, view.currency));
    row(doc, 'Method', METHOD_LABELS[view.method] ?? view.method);
    if (view.period) row(doc, 'Period', view.period);
    row(doc, 'Issued', view.issuedAt.toISOString().slice(0, 10));
    if (view.reference) row(doc, 'Reference', view.reference);

    doc.moveDown(2);
    doc
      .fillColor('#5F6B7A')
      .fontSize(9)
      .text(
        'Issued by Nyumba on behalf of the landlord after the payment was confirmed. '
        + 'Amounts are shown in Ugandan Shillings.',
        { width: 400 },
      );
    doc.end();
  });
}

function row(doc: PDFKit.PDFDocument, label: string, value: string): void {
  doc.fillColor('#5F6B7A').text(label, { continued: true, width: 160 });
  doc.fillColor('#000000').text(`   ${value}`);
  doc.moveDown(0.4);
}

/** UGX has no minor unit in practice, but amounts are stored in minor units. */
function formatMoney(amountMinor: number, currency: string): string {
  const major = amountMinor / 100;
  return `${currency} ${major.toLocaleString('en-UG', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

function toDate(value: unknown): Date {
  if (value instanceof Timestamp) return value.toDate();
  return new Date();
}
