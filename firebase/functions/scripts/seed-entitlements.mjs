#!/usr/bin/env node
/**
 * Seeds the server-owned `backendConfig/entitlements` document.
 *
 * Every landlord command fails closed with ENTITLEMENT_MISSING until this
 * exists. Values follow the suggested limits in
 * docs/architecture/subscription-tiers.md; monetary prices remain TBD and are
 * deliberately absent. Safe to re-run — bumps the version and overwrites.
 *
 * Usage: node scripts/seed-entitlements.mjs [--project <projectId>]
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const projectFlag = args.indexOf('--project');
const projectId =
  projectFlag !== -1 ? args[projectFlag + 1] : process.env.GOOGLE_CLOUD_PROJECT ?? 'nyumba-property-management';

initializeApp({ projectId });
const db = getFirestore();

const plans = {
  starter: { unitLimit: 10, activeListingLimit: 3, advertising: true },
  pro: { unitLimit: 50, activeListingLimit: 25, advertising: true },
  premium: { unitLimit: 200, activeListingLimit: 200, advertising: true },
  enterprise: { unitLimit: 1000, activeListingLimit: 1000, advertising: true },
};

const ref = db.collection('backendConfig').doc('entitlements');
await db.runTransaction(async (tx) => {
  const existing = await tx.get(ref);
  const version = (existing.data()?.version ?? 0) + 1;
  tx.set(ref, { version, plans, updatedAt: FieldValue.serverTimestamp() });
});
console.log(`Seeded backendConfig/entitlements on ${projectId}:`);
console.table(plans);
