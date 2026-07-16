#!/usr/bin/env node
/**
 * Seeds the server-owned `backendConfig/entitlements` document and the public
 * `planCatalog/{tier}` documents the client renders.
 *
 * Every landlord command fails closed with ENTITLEMENT_MISSING until the
 * entitlements config exists, and the subscription screen shows no plan
 * limits until the catalog exists — limits are never hard-coded in Flutter.
 * Values follow the suggested limits in
 * docs/architecture/subscription-tiers.md; monetary prices remain TBD and are
 * deliberately absent. Safe to re-run — bumps versions and overwrites.
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

/** Public presentation facts; prices stay absent until the product decides them. */
const catalog = {
  starter: { displayName: 'Starter', tagline: 'Individual landlords and small portfolios', sortOrder: 1 },
  pro: { displayName: 'Pro', tagline: 'Growing landlords and small teams', sortOrder: 2 },
  premium: { displayName: 'Premium', tagline: 'Professional property managers', sortOrder: 3 },
  enterprise: {
    displayName: 'Enterprise',
    tagline: 'Agencies, institutions, and large companies',
    sortOrder: 4,
    capacityLabel: 'Custom capacity and controls',
  },
};

const ref = db.collection('backendConfig').doc('entitlements');
await db.runTransaction(async (tx) => {
  const catalogRefs = Object.keys(catalog).map((tier) => db.collection('planCatalog').doc(tier));
  const [existing, ...existingCatalog] = await Promise.all([
    tx.get(ref),
    ...catalogRefs.map((catalogRef) => tx.get(catalogRef)),
  ]);
  const version = (existing.data()?.version ?? 0) + 1;
  tx.set(ref, { version, plans, updatedAt: FieldValue.serverTimestamp() });
  catalogRefs.forEach((catalogRef, index) => {
    const tier = catalogRef.id;
    tx.set(catalogRef, {
      ...catalog[tier],
      unitLimit: plans[tier].unitLimit,
      activeListingLimit: plans[tier].activeListingLimit,
      isPublic: true,
      version: (existingCatalog[index].data()?.version ?? 0) + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
});
console.log(`Seeded backendConfig/entitlements and planCatalog on ${projectId}:`);
console.table(plans);
