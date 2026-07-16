#!/usr/bin/env node
/**
 * Confirms a landlord's subscription payment through the same audited command
 * path a future billing webhook will use — the subscription flips to `active`
 * with a receipt and audit event, exactly as for an in-app platform admin.
 *
 * Usage:
 *   node scripts/confirm-subscription.mjs <email> --reference <text> [--tier <tier>] [--project <projectId>]
 *
 * `--reference` is required and records the payment that justifies activation
 * (e.g. a mobile-money transaction ID); the command rejects a blank one so
 * every activation is auditable. `--tier` overrides the tier the landlord
 * selected (validated against backendConfig/entitlements).
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
const flag = (name) => {
  const index = args.indexOf(`--${name}`);
  return index !== -1 ? args[index + 1] : undefined;
};
const projectId = flag('project') ?? process.env.GOOGLE_CLOUD_PROJECT ?? 'nyumba-property-management';

const reference = flag('reference');
if (!email || !reference || !reference.trim()) {
  console.error('Usage: node scripts/confirm-subscription.mjs <email> --reference <text> [--tier <tier>]');
  console.error('--reference is required: record the payment (e.g. a mobile-money transaction ID) that justifies activation.');
  process.exit(1);
}

initializeApp({ projectId });
const db = getFirestore();
const user = await getAuth().getUserByEmail(email);
const subscription = await db.collection('subscriptions').doc(user.uid).get();
if (!subscription.exists) {
  console.error(`${email} (uid ${user.uid}) has no subscription. They must complete landlord onboarding first.`);
  process.exit(2);
}

const tier = flag('tier');
const operator = { uid: 'ops_script_admin', email: null, platformAdmin: true, superAdmin: false, emailVerified: true, signInProvider: null };
const response = await executeCommandCore(db, operator, {
  commandId: `opscmd_${randomUUID().replaceAll('-', '')}`,
  type: 'subscription.confirmPayment',
  schemaVersion: 1,
  aggregateId: user.uid,
  expectedVersion: subscription.data().version,
  payload: {
    reference: reference.trim(),
    ...(tier ? { tier } : {}),
  },
  client: { installationId: 'ops_script_00000000', appVersion: '0.0.0', platform: 'web' },
});

if (response.status === 'rejected') {
  console.error(`Rejected: ${response.error?.code}`, response.error?.details ?? '');
  process.exit(3);
}
const updated = (await subscription.ref.get()).data();
console.log(`Payment confirmed for ${email} (uid ${user.uid}): tier ${updated.tier}, status ${updated.status}; audit trail written.`);
