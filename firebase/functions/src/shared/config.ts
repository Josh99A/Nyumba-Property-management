import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { COLLECTIONS } from './collections';
import { DomainError } from './errors';

/** Finalized deployment region (docs/architecture/README.md). */
export const REGION = 'europe-west1';

/**
 * TODO(release): flip to true once every Flutter platform is registered with
 * App Check (web reCAPTCHA v3, Android Play Integrity, iOS App Attest) and the
 * client ships real provider keys. Enforcing before registration would reject
 * every callable command; Firestore/Storage enforcement is likewise enabled in
 * the console only after registration (docs/architecture/README.md).
 */
export const ENFORCE_APP_CHECK = false;

/** Finalized market configuration mirrored from lib/core/config/market_config.dart. */
export const CURRENCY = 'UGX';
export const COUNTRY = 'Uganda';
export const LISTING_LIFETIME_DAYS = 30;
export const MAX_LISTING_PHOTOS = 10;
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
export const MAX_DOCUMENT_BYTES = 10 * 1024 * 1024;

/**
 * Receipts must outlive the longest plausible offline retry window. Product
 * retention policy is still TBD, so nothing deletes them yet; the field only
 * marks eligibility for a future TTL job.
 */
export const RECEIPT_RETENTION_DAYS = 90;

/**
 * Subscription billing lifecycle (docs/architecture/subscription-tiers.md).
 *
 * A paid period runs for one interval from confirmation. When it lapses the
 * subscription deliberately stays `active` for GRACE_DAYS so the landlord —
 * and every tenant depending on their workspace — keeps working while the
 * renewal is settled; only then does it expire and lock the workspace.
 * Warnings go out RENEWAL_WARNING_DAYS before the deadline and again inside
 * the grace period, so nobody is locked out unannounced.
 */
export const SUBSCRIPTION_GRACE_DAYS = 7;
export const SUBSCRIPTION_RENEWAL_WARNING_DAYS = 7;
/** Days of grace remaining when the second warning goes out. */
export const SUBSCRIPTION_GRACE_WARNING_DAYS_LEFT = 3;

/** Background job retry policy. Product-final values are TBD; fail toward dead-letter. */
export const JOB_MAX_ATTEMPTS = 8;
export const JOB_BASE_BACKOFF_SECONDS = 30;
export const JOB_LEASE_SECONDS = 120;

export interface PlanEntitlements {
  unitLimit: number;
  activeListingLimit: number;
  advertising: boolean;
}

export interface EntitlementsConfig {
  version: number;
  plans: Record<string, PlanEntitlements>;
}

function asPositiveInt(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : null;
}

/**
 * Versioned server-owned entitlement configuration. Plan prices and limits
 * are TBD product decisions, so they live in `backendConfig/entitlements`
 * (deployed operationally, never committed). A missing or malformed document
 * fails closed with ENTITLEMENT_MISSING.
 */
export async function loadEntitlements(
  tx: Transaction,
  db: Firestore,
): Promise<EntitlementsConfig> {
  const snapshot = await tx.get(db.collection(COLLECTIONS.backendConfig).doc('entitlements'));
  const data = snapshot.data();
  if (!snapshot.exists || !data) throw new DomainError('ENTITLEMENT_MISSING');
  const version = asPositiveInt(data.version);
  const rawPlans = data.plans;
  if (version === null || typeof rawPlans !== 'object' || rawPlans === null) {
    throw new DomainError('ENTITLEMENT_MISSING');
  }
  const plans: Record<string, PlanEntitlements> = {};
  for (const [tier, raw] of Object.entries(rawPlans as Record<string, unknown>)) {
    if (typeof raw !== 'object' || raw === null) continue;
    const plan = raw as Record<string, unknown>;
    const unitLimit = asPositiveInt(plan.unitLimit);
    const activeListingLimit = asPositiveInt(plan.activeListingLimit);
    if (unitLimit === null || activeListingLimit === null || typeof plan.advertising !== 'boolean') {
      continue;
    }
    plans[tier] = { unitLimit, activeListingLimit, advertising: plan.advertising };
  }
  return { version, plans };
}

export function planForTier(config: EntitlementsConfig, tier: string): PlanEntitlements {
  const plan = config.plans[tier];
  // Unknown tiers fail closed rather than inheriting a guessed default.
  if (!plan) throw new DomainError('ENTITLEMENT_MISSING', { tier });
  return plan;
}
