import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import PDFDocument from 'pdfkit';
import { COLLECTIONS } from '../shared/collections';

/** Rows are built as plain strings so CSV and PDF render from one source. */
interface ReportTable {
  title: string;
  headers: string[];
  rows: string[][];
}

/**
 * Builds a landlord report snapshot from canonical records and stores it under
 * the landlord's private prefix.
 *
 * Every figure is derived here from canonical documents rather than accepted
 * from a client total, which is the whole reason reports are a server job.
 */
export async function generateReport(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const reportId = String(payload.reportId);
  const ref = db.collection(COLLECTIONS.reportSnapshots).doc(reportId);
  const snapshot = await ref.get();
  if (!snapshot.exists) return;
  const report = snapshot.data()!;
  if (report.state === 'ready') return;
  const landlordId = String(report.landlordId);

  const from = String(report.from);
  const to = String(report.to);
  const format = String(report.format) === 'pdf' ? 'pdf' : 'csv';

  let table: ReportTable;
  try {
    table = await build(String(report.reportType), landlordId, from, to);
  } catch (error) {
    await ref.update({
      state: 'failed',
      failureReason: error instanceof Error ? error.message.slice(0, 300) : 'Report build failed.',
      version: Number(report.version ?? 1) + 1,
      updatedAt: Timestamp.now(),
    });
    return;
  }

  const body = format === 'pdf' ? renderPdf(table, from, to) : Buffer.from(renderCsv(table), 'utf8');
  const downloadPath = `private/landlords/${landlordId}/reports/${reportId}.${format}`;
  await getStorage().bucket().file(downloadPath).save(await body, {
    contentType: format === 'pdf' ? 'application/pdf' : 'text/csv; charset=utf-8',
    resumable: false,
    metadata: { cacheControl: 'private, max-age=0, no-transform' },
  });

  await ref.update({
    state: 'ready',
    downloadPath,
    rowCount: table.rows.length,
    generatedAt: Timestamp.now(),
    version: Number(report.version ?? 1) + 1,
    updatedAt: Timestamp.now(),
  });
}

async function build(
  reportType: string,
  landlordId: string,
  from: string,
  to: string,
): Promise<ReportTable> {
  const db = getFirestore();
  const QUERY_LIMIT = 5_000;
  const owned = async (collection: string): Promise<FirebaseFirestore.DocumentData[]> => {
    const allDocs: FirebaseFirestore.DocumentData[] = [];
    let query = db.collection(collection).where('landlordId', '==', landlordId).limit(QUERY_LIMIT);
    let snapshot = await query.get();
    while (!snapshot.empty) {
      allDocs.push(...snapshot.docs.map((doc) => doc.data()));
      if (snapshot.size < QUERY_LIMIT) break;
      if (snapshot.size >= QUERY_LIMIT) {
        throw new Error(`Report query limit exceeded: more than ${QUERY_LIMIT} records in ${collection}.`);
      }
      const lastDoc = snapshot.docs[snapshot.docs.length - 1];
      query = query.startAfter(lastDoc);
      snapshot = await query.get();
    }
    return allDocs;
  };
  const live = (docs: FirebaseFirestore.DocumentData[]) =>
    docs.filter((row) => row.isDeleted !== true);

  switch (reportType) {
    case 'rent_roll': {
      const leases = live(await owned(COLLECTIONS.leases))
        .filter((lease) => lease.status === 'active');
      return {
        title: 'Rent roll',
        headers: ['Lease', 'Unit', 'Start', 'End', 'Monthly rent (minor)'],
        rows: leases.map((lease) => [
          String(lease.id), String(lease.unitId), String(lease.startDate),
          String(lease.endDate), String(lease.monthlyRentMinor ?? 0),
        ]),
      };
    }
    case 'arrears': {
      const invoices = live(await owned(COLLECTIONS.invoices))
        .filter((invoice) => Number(invoice.balanceMinor ?? 0) > 0);
      return {
        title: 'Arrears',
        headers: ['Invoice', 'Lease', 'Due', 'Total (minor)', 'Outstanding (minor)'],
        rows: invoices.map((invoice) => [
          String(invoice.id), String(invoice.leaseId), String(invoice.dueDate),
          String(invoice.totalMinor ?? 0), String(invoice.balanceMinor ?? 0),
        ]),
      };
    }
    case 'occupancy': {
      const units = live(await owned(COLLECTIONS.units));
      return {
        title: 'Occupancy',
        headers: ['Unit', 'Property', 'Label', 'Status', 'Active lease'],
        rows: units.map((unit) => [
          String(unit.id), String(unit.propertyId), String(unit.label ?? ''),
          String(unit.occupancyStatus ?? 'unknown'), String(unit.activeLeaseId ?? ''),
        ]),
      };
    }
    case 'payments': {
      const payments = live(await owned(COLLECTIONS.payments))
        .filter((payment) => withinRange(payment.confirmedAt, from, to));
      return {
        title: 'Payments',
        headers: ['Payment', 'Lease', 'Confirmed', 'Method', 'Amount (minor)'],
        rows: payments.map((payment) => [
          String(payment.id), String(payment.leaseId ?? ''), isoOf(payment.confirmedAt),
          String(payment.method ?? payment.rail ?? ''), String(payment.amountMinor ?? 0),
        ]),
      };
    }
    case 'maintenance': {
      const requests = live(await owned(COLLECTIONS.maintenanceRequests))
        .filter((request) => withinRange(request.createdAt, from, to));
      return {
        title: 'Maintenance',
        headers: ['Request', 'Unit', 'Raised', 'Priority', 'Status'],
        rows: requests.map((request) => [
          String(request.id), String(request.unitId ?? ''), isoOf(request.createdAt),
          String(request.priority ?? ''), String(request.status ?? ''),
        ]),
      };
    }
    default:
      throw new Error(`Unsupported report type "${reportType}".`);
  }
}

function isoOf(value: unknown): string {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  return typeof value === 'string' ? value : '';
}

function withinRange(value: unknown, from: string, to: string): boolean {
  const iso = isoOf(value);
  return iso !== '' && iso >= from && iso <= to;
}

/** RFC 4180 quoting: a field containing a quote, comma, or newline is quoted. */
function csvField(value: string): string {
  return /[",\r\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
}

function renderCsv(table: ReportTable): string {
  return [table.headers, ...table.rows]
    .map((row) => row.map(csvField).join(','))
    .join('\r\n');
}

function renderPdf(table: ReportTable, from: string, to: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 40, layout: 'landscape' });
    const chunks: Buffer[] = [];
    doc.on('data', (chunk: Buffer) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    doc.fillColor('#123A6F').fontSize(20).text(`Nyumba — ${table.title}`);
    doc.fillColor('#5F6B7A').fontSize(9)
      .text(`${from.slice(0, 10)} to ${to.slice(0, 10)} · ${table.rows.length} row(s)`);
    doc.moveDown(1);

    const width = (doc.page.width - 80) / table.headers.length;
    doc.fontSize(9).fillColor('#123A6F');
    table.headers.forEach((header, index) => {
      doc.text(header, 40 + index * width, doc.y, { width, continued: index < table.headers.length - 1 });
    });
    doc.moveDown(0.5);
    doc.fillColor('#000000');
    for (const row of table.rows) {
      if (doc.y > doc.page.height - 60) doc.addPage();
      const top = doc.y;
      row.forEach((cell, index) => {
        doc.text(cell, 40 + index * width, top, { width, height: 12, ellipsis: true, lineBreak: false });
      });
      doc.moveDown(0.6);
    }
    if (table.rows.length === 0) {
      doc.fillColor('#5F6B7A').text('No records matched this range.');
    }
    doc.end();
  });
}
