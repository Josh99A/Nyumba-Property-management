import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { COLLECTIONS } from './collections';
import { DomainError } from './errors';

/** Finalized deployment region (docs/architecture/README.md). */
export const REGION = 'europe-west1';

/** Planned canonical public origin (docs/architecture/README.md). */
export const APP_ORIGIN = 'https://nyumba.online';

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
export const MAX_PROPERTY_PHOTOS = 2;
export const MAX_LISTING_PHOTOS = 5;
/**
 * A public advert with no photo is indistinguishable from a broken one: the
 * card renders an empty grey tile and renters skip it. Enforced at the publish
 * transition rather than on the stored record, so adverts published before this
 * rule keep working until their landlord next edits them.
 */
export const MIN_LISTING_PHOTOS = 1;
/**
 * Radius of the privacy circle drawn on a public listing map, in metres.
 *
 * Mirrored in lib/core/config/maps_config.dart — keep in sync. Deliberately
 * wider than the ~110 m the published coordinate is coarsened to: the
 * coarsening alone is not anonymity, and in a sparse area a tight circle can
 * still identify a single compound.
 */
export const MAPS_PUBLIC_PRIVACY_RADIUS_METRES = 250;

export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
export const MAX_DOCUMENT_BYTES = 10 * 1024 * 1024;
export const MAX_PUBLIC_LISTING_IMAGE_WIDTH = 1_920;
export const MAX_PUBLIC_LISTING_IMAGE_HEIGHT = 1_440;

/**
 * Grid tiles are at most ~420 logical pixels wide on the widest marketplace
 * layout and full-bleed on a phone. Serving them the 1920px detail copy meant a
 * card downloaded and decoded roughly nine times the pixels it could display —
 * the single largest cost in a fifty-card grid. This variant covers those tiles
 * at better than 1.5x device pixel ratio.
 */
export const MEDIA_THUMB_IMAGE_WIDTH = 640;
export const MEDIA_THUMB_IMAGE_HEIGHT = 480;

/** Suffixes distinguishing the two delivery copies of one source photo. */
export const MEDIA_THUMB_SUFFIX = 'thumb';
export const MEDIA_FULL_SUFFIX = 'full';

/**
 * Delivery objects are content-addressed: the source photo's digest is part of
 * the file name, so a republished photo is written to a *different* path rather
 * than overwriting one a cache may still be serving. That is what makes a
 * one-year immutable lifetime safe — previously these objects carried a
 * 60-second lifetime purely because the path was reused, which meant repeat
 * visitors re-downloaded every photo on essentially every page view.
 */
export const MEDIA_IMMUTABLE_CACHE_CONTROL =
  'public, max-age=31536000, immutable';

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

/**
 * Reputation policy (docs/architecture/reviews-and-feedback-plan.md).
 *
 * A review is keyed by the lease it describes, so eligibility is a question
 * about that lease rather than about the tenant. The two windows below are what
 * keep the corpus honest at both ends: a tenant cannot review in week one, when
 * nothing has been experienced and a dispute is still hot, and cannot review a
 * tenancy that ended long enough ago that the landlord has no chance to answer.
 */
export const REVIEW_MIN_TENANCY_DAYS = 30;
export const REVIEW_POST_TENANCY_WINDOW_DAYS = 90;
/** How long the author may still edit or withdraw their own review. */
export const REVIEW_EDIT_WINDOW_DAYS = 14;

/**
 * Bayesian shrinkage for the public ranking score.
 *
 * A raw mean lets one five-star review outrank a landlord holding 4.7 across
 * fifty, which is exactly the outcome that makes a rating system worthless. The
 * shrunk score pulls small samples toward the platform mean and lets real
 * volume earn its way out. Firestore cannot compute this at query time, so
 * `rankScore` is stored on the rating document and recomputed on every write.
 *
 * REVIEW_PRIOR_MEAN is a seeded assumption until there is enough data to
 * measure it; revisit manually rather than computing it live, so ranking never
 * shifts underneath users because of one bad week.
 */
export const REVIEW_PRIOR_MEAN = 4;
export const REVIEW_PRIOR_WEIGHT = 5;

/**
 * Reviews needed before a star average is shown at all.
 *
 * Below this the marketplace shows a "new to Nyumba" state instead. One review
 * is noise, and one *bad* review is a weapon; neither should read as a verdict.
 */
export const REVIEW_PUBLIC_DISPLAY_MIN_COUNT = 3;

/** Landlord-facing NPS may be asked at most this often, per landlord. */
export const FEEDBACK_NPS_COOLDOWN_DAYS = 90;

/**
 * Floor between any two feedback submissions from the same landlord,
 * regardless of kind. Shorter than the NPS-specific cooldown above on
 * purpose: this exists to stop double-submits and scripted abuse, not to
 * ration how often a paying customer may tell the team something is broken.
 */
export const FEEDBACK_SUBMIT_COOLDOWN_SECONDS = 30;

/**
 * Support desk (docs/architecture/support-desk-plan.md).
 *
 * The mailbox every new ticket and landlord reply is announced to. Administrator
 * rights are Auth custom claims granted by `scripts/grant-admin.mjs` and are not
 * mirrored anywhere in Firestore, so there is no queryable roster to fan a
 * notification out to — one email to a monitored address is the alert channel
 * until `platformStaff` exists.
 */
export const SUPPORT_EMAIL = 'support@nyumba.online';

/** Floor between two ticket opens, and between two replies, per landlord. */
export const SUPPORT_OPEN_COOLDOWN_SECONDS = 60;
export const SUPPORT_REPLY_COOLDOWN_SECONDS = 10;

/**
 * Conversations a landlord may have running at once. Not an anti-abuse number
 * so much as an anti-fragmentation one: four parallel threads about the same
 * problem get four partial answers. The rejection tells the client to reply on
 * an existing thread instead.
 */
export const SUPPORT_MAX_OPEN_TICKETS = 3;

/** Messages one thread may hold, matching the maintenance comment ceiling. */
export const SUPPORT_MAX_MESSAGES = 100;
export const SUPPORT_MAX_ATTACHMENTS = 5;

/** How long a landlord may reopen a resolved ticket rather than start again. */
export const SUPPORT_REOPEN_WINDOW_DAYS = 14;

/** Background job retry policy. Product-final values are TBD; fail toward dead-letter. */
export const JOB_MAX_ATTEMPTS = 8;
export const JOB_BASE_BACKOFF_SECONDS = 30;
export const JOB_LEASE_SECONDS = 120;

export interface PlanEntitlements {
  unitLimit: number;
  activeListingLimit: number;
  advertising: boolean;
  /** Staff seats available beyond the owner (owner is always seat zero). */
  staffSeatLimit: number;
  /** Whether the owner may grant custom per-permission staff roles. */
  customStaffRoles: boolean;
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
    const staffSeatLimit = asPositiveInt(plan.staffSeatLimit);
    if (
      unitLimit === null
      || activeListingLimit === null
      || staffSeatLimit === null
      || typeof plan.advertising !== 'boolean'
      || typeof plan.customStaffRoles !== 'boolean'
    ) {
      continue;
    }
    plans[tier] = {
      unitLimit,
      activeListingLimit,
      advertising: plan.advertising,
      staffSeatLimit,
      customStaffRoles: plan.customStaffRoles,
    };
  }
  return { version, plans };
}

export function planForTier(config: EntitlementsConfig, tier: string): PlanEntitlements {
  const plan = config.plans[tier];
  // Unknown tiers fail closed rather than inheriting a guessed default.
  if (!plan) throw new DomainError('ENTITLEMENT_MISSING', { tier });
  return plan;
}
