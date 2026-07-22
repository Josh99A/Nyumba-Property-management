#!/usr/bin/env node
/**
 * Seeds the server-owned `backendConfig/entitlements` document and the public
 * `planCatalog/{tier}` documents the client renders.
 *
 * Every landlord command fails closed with ENTITLEMENT_MISSING until the
 * entitlements config exists, and the subscription screen shows no plan
 * limits until the catalog exists — limits and prices are never hard-coded in
 * Flutter. Structure follows docs/architecture/subscription-tiers.md.
 *
 * Prices are UGX in minor units (x100), decided 2026-07-20: Starter 50,000,
 * Pro 100,000, Premium 200,000, Enterprise 300,000 per month. Yearly billing
 * is ten months' worth (two months free, ~17% off). Super admins can change
 * any of these later through the audited `plan.update` command; this script
 * only establishes the baseline and is safe to re-run — it bumps versions and
 * overwrites, so run it BEFORE granting plan editing to admins or their edits
 * will be clobbered.
 *
 * Each catalog entry carries a `features` list with an `implemented` flag the
 * client uses to grey out benefits that are sold on the roadmap but not yet
 * shipped. Flip a feature to implemented via `plan.update` when it ships.
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

// staffSeatLimit counts seats beyond the owner (owner is always seat zero), so
// it is the marketing "accounts" number minus one: 1/3/10/custom accounts ->
// 0/2/9/199 staff. customStaffRoles unlocks per-permission roles (Premium+);
// Pro is coerced to the fixed standard preset.
const plans = {
  starter: { unitLimit: 10, activeListingLimit: 3, advertising: true, staffSeatLimit: 0, customStaffRoles: false },
  pro: { unitLimit: 50, activeListingLimit: 25, advertising: true, staffSeatLimit: 2, customStaffRoles: false },
  premium: { unitLimit: 200, activeListingLimit: 200, advertising: true, staffSeatLimit: 9, customStaffRoles: true },
  enterprise: { unitLimit: 1000, activeListingLimit: 1000, advertising: true, staffSeatLimit: 199, customStaffRoles: true },
};

/** UGX minor units (x100). */
const MONTH = { starter: 5_000_000, pro: 10_000_000, premium: 20_000_000, enterprise: 30_000_000 };
/** Yearly = 10 x monthly: two months free (~17% off), shown as a saving in the UI. */
const YEAR = Object.fromEntries(Object.entries(MONTH).map(([tier, m]) => [tier, m * 10]));

const feature = (id, label, implemented) => ({ id, label, implemented });

/**
 * Per-tier benefits, incremental over `includesTier`. `implemented: false`
 * marks roadmap benefits the client greys out ("coming soon"); operational
 * promises (support, onboarding, SLA) count as implemented because they are
 * delivered by people, not code.
 */
const features = {
  starter: [
    feature('property-unit-management', 'Property and rental space management', true),
    feature('tenant-lease-records', 'Tenant profiles and lease records', true),
    feature('rent-tracking', 'Rent balances and payment recording', true),
    feature('invoices-receipts', 'Invoices and printable receipts', true),
    feature('maintenance-requests', 'Maintenance request tracking', true),
    feature('tenant-notices', 'Tenant notices and documents', true),
    feature('dashboard-reports', 'Dashboard and basic reports', true),
    feature('offline-sync', 'Offline access and synchronization', true),
    feature('data-export', 'Data export', true),
  ],
  pro: [
    feature('payment-reminders', 'Payment and overdue rent reminders', true),
    feature('lease-expiry-reminders', 'Lease expiry and renewal reminders', true),
    feature('bulk-notices', 'Bulk notices to all tenants', true),
    feature('applications', 'Application and prospect management', true),
    feature('recurring-invoices', 'Automatic recurring rent invoices', false),
    feature('late-fees', 'Configurable late-fee policies', false),
    feature('document-templates', 'Document templates', false),
    feature('staff-accounts', 'Staff accounts with standard roles', true),
    feature('priority-support', 'Priority support', true),
  ],
  premium: [
    feature('all-vacant-advertising', 'Advertise every vacant rental space', true),
    feature('workflow-automation', 'Workflow automation', false),
    feature('advanced-reports', 'Advanced dashboards and custom reports', false),
    feature('portfolio-groups', 'Multiple portfolios and property groups', false),
    feature('vendor-work-orders', 'Vendor and work-order management', false),
    feature('inspections', 'Inspection records', false),
    feature('bulk-operations', 'Bulk space, tenant, and payment operations', false),
    feature('api-webhooks', 'API and webhook access', false),
    feature('custom-roles', 'Custom staff roles and permissions', true),
    feature('priority-onboarding', 'Priority onboarding and support', true),
  ],
  enterprise: [
    feature('custom-limits', 'Custom rental space and user limits', true),
    feature('multi-branch', 'Multiple branches or organizations', false),
    feature('sso', 'Enterprise single sign-on', false),
    feature('dedicated-onboarding', 'Dedicated onboarding and data migration', true),
    feature('scheduled-exports', 'Scheduled report and data exports', false),
    feature('custom-integrations', 'Custom integrations', false),
    feature('account-manager', 'Dedicated account manager', true),
    feature('sla', 'Guaranteed response times (SLA)', true),
    feature('branded-portals', 'Branded portals and custom domain', false),
  ],
};

/** Public presentation facts the subscription and admin screens render. */
const catalog = {
  starter: { displayName: 'Starter', tagline: 'Individual landlords and small portfolios', sortOrder: 1 },
  pro: { displayName: 'Pro', tagline: 'Growing landlords and small teams', sortOrder: 2, includesTier: 'starter' },
  premium: { displayName: 'Premium', tagline: 'Professional property managers', sortOrder: 3, includesTier: 'pro' },
  enterprise: {
    displayName: 'Enterprise',
    tagline: 'Agencies, institutions, and large companies',
    sortOrder: 4,
    capacityLabel: 'Custom capacity and controls',
    includesTier: 'premium',
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
      staffSeatLimit: plans[tier].staffSeatLimit,
      customStaffRoles: plans[tier].customStaffRoles,
      currency: 'UGX',
      monthlyPriceMinor: MONTH[tier],
      yearlyPriceMinor: YEAR[tier],
      features: features[tier],
      isPublic: true,
      version: (existingCatalog[index].data()?.version ?? 0) + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
});
console.log(`Seeded backendConfig/entitlements and planCatalog on ${projectId}:`);
console.table(
  Object.fromEntries(
    Object.entries(plans).map(([tier, plan]) => [
      tier,
      {
        ...plan,
        monthlyUgx: MONTH[tier] / 100,
        yearlyUgx: YEAR[tier] / 100,
        features: features[tier].length,
      },
    ]),
  ),
);
