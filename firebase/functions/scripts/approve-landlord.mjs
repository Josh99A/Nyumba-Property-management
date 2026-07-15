#!/usr/bin/env node
/**
 * Approves (or suspends/reinstates) a landlord account through the same
 * audited command path the future admin UI will use — receipts and audit
 * events are written exactly as for an in-app admin.
 *
 * Usage:
 *   node scripts/approve-landlord.mjs <email> [--action approve|suspend|reinstate] [--project <projectId>]
 *
 * Run `npm run build` first (imports the compiled router from lib/).
 */
import { randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { executeCommandCore } from '../lib/shared/router.js';

const args = process.argv.slice(2);
const email = args.find((arg) => !arg.startsWith('--'));
const actionFlag = args.indexOf('--action');
const action = actionFlag !== -1 ? args[actionFlag + 1] : 'approve';
const projectFlag = args.indexOf('--project');
const projectId =
  projectFlag !== -1 ? args[projectFlag + 1] : process.env.GOOGLE_CLOUD_PROJECT ?? 'nyumba-property-management';

const commandTypes = {
  approve: { type: 'landlord.approve', reasonCode: 'IDENTITY_VERIFIED' },
  suspend: { type: 'landlord.suspend', reasonCode: 'POLICY_VIOLATION' },
  reinstate: { type: 'landlord.reinstate', reasonCode: 'APPEAL_APPROVED' },
};

if (!email || !commandTypes[action]) {
  console.error('Usage: node scripts/approve-landlord.mjs <email> [--action approve|suspend|reinstate]');
  process.exit(1);
}

initializeApp({ projectId });
const db = getFirestore();
const user = await getAuth().getUserByEmail(email);
const account = await db.collection('landlordAccounts').doc(user.uid).get();
if (!account.exists) {
  console.error(`${email} (uid ${user.uid}) has no landlord account. They must complete onboarding first.`);
  process.exit(2);
}

const operator = { uid: 'ops_script_admin', email: null, platformAdmin: true, superAdmin: false, emailVerified: true, signInProvider: null };
const response = await executeCommandCore(db, operator, {
  commandId: `opscmd_${randomUUID().replaceAll('-', '')}`,
  type: commandTypes[action].type,
  schemaVersion: 1,
  aggregateId: user.uid,
  expectedVersion: account.data().version,
  payload: { reasonCode: commandTypes[action].reasonCode },
  client: { installationId: 'ops_script_00000000', appVersion: '0.0.0', platform: 'web' },
});

if (response.status === 'rejected') {
  console.error(`Rejected: ${response.error?.code}`, response.error?.details ?? '');
  process.exit(3);
}
console.log(`${action} applied for ${email} (uid ${user.uid}); approvalStatus now recorded with audit trail.`);
