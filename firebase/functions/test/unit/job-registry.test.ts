import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { registeredJobTypes } from '../../src/workers/jobs';

const COMMANDS_DIR = join(__dirname, '../../src/commands');

/**
 * Scrapes every `createJob(..., 'type', ...)` literal out of the command
 * handlers. Importing the handlers to observe their enqueues would need a live
 * Firestore transaction per command; the type is always a literal at the call
 * site, so reading it from source is both sufficient and cheap.
 */
function commandEnqueuedJobTypes(): Map<string, string> {
  const found = new Map<string, string>();
  for (const file of readdirSync(COMMANDS_DIR).filter((name) => name.endsWith('.ts'))) {
    const source = readFileSync(join(COMMANDS_DIR, file), 'utf8');
    // createJob(tx, db, <id expr>, '<type>', ...) — the 4th argument.
    const pattern = /createJob\(\s*tx\s*,\s*db\s*,\s*[^,]+,\s*'([^']+)'/g;
    for (const match of source.matchAll(pattern)) {
      found.set(match[1]!, file);
    }
  }
  return found;
}

describe('background job registry', () => {
  it('registers a processor for every job type a command can enqueue', () => {
    const enqueued = commandEnqueuedJobTypes();
    expect(enqueued.size).toBeGreaterThan(0);

    const unregistered = [...enqueued.entries()]
      .filter(([type]) => !registeredJobTypes.has(type))
      .map(([type, file]) => `${type} (enqueued by commands/${file})`);

    // An unregistered type is invisible in production: the job retries to
    // dead_letter and the user's payment/notification/report never happens.
    expect(unregistered).toEqual([]);
  });

  it('finds the job types that are known to be enqueued', () => {
    // Guards the scraper itself: a regex that silently matches nothing would
    // make the assertion above vacuously pass.
    const enqueued = commandEnqueuedJobTypes();
    expect([...enqueued.keys()].sort()).toEqual([
      'broadcastFanout',
      'cleanupListingMedia',
      'deleteAuthUser',
      'deliverContactRequest',
      'generateReport',
      'initiatePayment',
      'movePrivateDocument',
      'noticeFanout',
      'notifyLandlordApplication',
      'notifyLandlordPaymentDeclared',
      'notifyTenantPaymentRejected',
      'publishListingMedia',
      'purgeDocument',
      'renderReceipt',
      'sendLandlordApprovedEmail',
      'sendMaintenanceStatusEmail',
      'sendPaymentReceiptEmail',
      'sendStaffInviteEmail',
      'sendSubscriptionNoticeEmail',
      'sendTenantInviteEmail',
      'setAuthUserDisabled',
      'unpublishLandlordListings',
    ]);
  });
});
