#!/usr/bin/env node
/**
 * Read-only audit of the published plan catalogue.
 *
 * Two documents describe a plan and they are written by different paths:
 * `planCatalog/{tier}` is what clients render, and `backendConfig/entitlements`
 * is what commands enforce. `plan.update` writes both in one transaction, but
 * `scripts/seed-entitlements.mjs` and any hand edit can leave them disagreeing
 * — and a landlord then sees a capacity the server will not honour.
 *
 * This also reproduces the client's own parser
 * (`publicPlanCatalogProvider` in lib/features/subscriptions/application/
 * subscription_providers.dart), which silently drops any catalogue document
 * missing `displayName`, `unitLimit`, or `activeListingLimit` as the right
 * type. A dropped tier still renders as a card, but with a hardcoded fallback
 * name and no price or capacity at all.
 *
 * Writes nothing. Usage:
 *   node scripts/check-plan-catalog.mjs [--project <projectId>]
 *
 * Requires Application Default Credentials (`gcloud auth application-default
 * login`).
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { isEntitlementPlanObject } from './check-plan-catalog-helpers.mjs';

const args = process.argv.slice(2);
const projectFlag = args.indexOf('--project');
const projectId =
  projectFlag !== -1
    ? args[projectFlag + 1]
    : process.env.GOOGLE_CLOUD_PROJECT ?? 'nyumba-property-management';

if (projectFlag !== -1 && !args[projectFlag + 1]) {
  console.error('--project needs a project ID.');
  process.exit(1);
}

initializeApp({ projectId });
const db = getFirestore();

const ugx = (minor) =>
  typeof minor === 'number' ? `UGX ${(minor / 100).toLocaleString('en-UG')}` : '—';

/** The exact acceptance test the Flutter client applies. */
function clientWouldRender(data) {
  return (
    typeof data.displayName === 'string' &&
    data.displayName.length > 0 &&
    Number.isInteger(data.unitLimit) &&
    Number.isInteger(data.activeListingLimit)
  );
}

const [catalogSnap, entitlementsSnap] = await Promise.all([
  db.collection('planCatalog').get(),
  db.doc('backendConfig/entitlements').get(),
]);

console.log(`Project: ${projectId}\n`);

const problems = [];

if (catalogSnap.empty) {
  problems.push(
    'planCatalog is EMPTY — every plan card renders a hardcoded fallback name ' +
      'with no price and no capacity. Run scripts/seed-entitlements.mjs.',
  );
}

const entitlements = entitlementsSnap.exists
  ? (entitlementsSnap.data()?.plans ?? {})
  : null;
if (!entitlementsSnap.exists) {
  problems.push(
    'backendConfig/entitlements is MISSING — loadEntitlements fails closed, so ' +
      'every landlord command that checks capacity is rejected.',
  );
} else {
  console.log('backendConfig/entitlements');
  console.log('-'.repeat(78));
  for (const [tier, plan] of Object.entries(entitlements).sort()) {
    if (!isEntitlementPlanObject(plan)) {
      problems.push(
        `${tier}: backendConfig/entitlements plan is malformed ` +
          `(expected a non-null object).`,
      );
      continue;
    }
    console.log(
      `  ${tier.padEnd(12)} unitLimit=${plan.unitLimit}  ` +
        `activeListingLimit=${plan.activeListingLimit}  ` +
        `staffSeatLimit=${plan.staffSeatLimit}`,
    );
  }
  console.log();
}

console.log('planCatalog');
console.log('-'.repeat(78));
for (const doc of catalogSnap.docs.sort((a, b) => a.id.localeCompare(b.id))) {
  const data = doc.data();
  const renders = clientWouldRender(data);
  const isPublic = data.isPublic === true;

  console.log(`\n  ${doc.id}`);
  console.log(`    displayName        ${data.displayName ?? '(missing)'}`);
  console.log(`    isPublic           ${data.isPublic}`);
  console.log(`    monthlyPriceMinor  ${data.monthlyPriceMinor ?? '(missing)'}  ${ugx(data.monthlyPriceMinor)}`);
  console.log(`    yearlyPriceMinor   ${data.yearlyPriceMinor ?? '(missing)'}  ${ugx(data.yearlyPriceMinor)}`);
  console.log(`    unitLimit          ${data.unitLimit ?? '(missing)'}`);
  console.log(`    activeListingLimit ${data.activeListingLimit ?? '(missing)'}`);
  console.log(`    version            ${data.version ?? '(missing)'}`);

  if (!renders) {
    problems.push(
      `${doc.id}: the client DROPS this document (needs a non-empty displayName ` +
        `plus integer unitLimit and activeListingLimit). It renders as a bare ` +
        `fallback card with no price or capacity.`,
    );
  }
  if (!isPublic) {
    problems.push(`${doc.id}: isPublic is not true, so the public query never returns it.`);
  }
  if (typeof data.monthlyPriceMinor !== 'number') {
    problems.push(`${doc.id}: no monthlyPriceMinor, so the card shows no price.`);
  }

  // The divergence that makes an advertised capacity a lie.
  const enforced = entitlements?.[doc.id];
  if (entitlements && enforced === undefined) {
    problems.push(
      `${doc.id}: advertised in planCatalog but absent from backendConfig/entitlements — ` +
        `commands fail closed for anyone on this tier.`,
    );
  } else if (isEntitlementPlanObject(enforced)) {
    if (enforced.unitLimit !== data.unitLimit) {
      problems.push(
        `${doc.id}: unitLimit MISMATCH — catalogue advertises ${data.unitLimit}, ` +
          `entitlements enforce ${enforced.unitLimit}.`,
      );
    }
    if (enforced.activeListingLimit !== data.activeListingLimit) {
      problems.push(
        `${doc.id}: activeListingLimit MISMATCH — catalogue advertises ` +
          `${data.activeListingLimit}, entitlements enforce ${enforced.activeListingLimit}.`,
      );
    }
  }
}

if (entitlements) {
  const advertised = new Set(catalogSnap.docs.map((doc) => doc.id));
  for (const tier of Object.keys(entitlements)) {
    if (!advertised.has(tier)) {
      problems.push(`${tier}: in backendConfig/entitlements but has no planCatalog document.`);
    }
  }
}

console.log(`\n\n${'='.repeat(78)}`);
if (problems.length === 0) {
  console.log('No problems. The catalogue and the enforced entitlements agree,');
  console.log('and every document survives the client parser.');
} else {
  console.log(`${problems.length} problem(s) found:\n`);
  for (const problem of problems) console.log(`  - ${problem}`);
}
