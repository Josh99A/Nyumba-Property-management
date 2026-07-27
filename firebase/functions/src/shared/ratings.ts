import type { Timestamp } from 'firebase-admin/firestore';
import {
  REVIEW_PRIOR_MEAN,
  REVIEW_PRIOR_WEIGHT,
  REVIEW_PUBLIC_DISPLAY_MIN_COUNT,
} from './config';

/**
 * Running rating totals for one landlord.
 *
 * Totals rather than a stored average: a review can be edited, withdrawn, or
 * hidden by a moderator, and every one of those has to *remove* its old
 * contribution exactly. Keeping `sum`, `count`, and the per-star distribution
 * makes each of those an arithmetic inverse instead of a recount over every
 * review the landlord has ever received.
 *
 * These are recomputed inside the same transaction as the review itself, so
 * FieldValue.increment is neither needed nor wanted — the handler already holds
 * the prior document and can subtract from it precisely.
 */
export const REVIEW_DIMENSIONS = [
  'responsiveness',
  'maintenance',
  'listingAccuracy',
  'depositFairness',
] as const;

export type ReviewDimension = typeof REVIEW_DIMENSIONS[number];

export type DimensionScores = Record<ReviewDimension, number | null>;

export interface RatingTotals {
  count: number;
  sum: number;
  /** Index 0 holds one-star reviews through index 4 holding five-star. */
  distribution: number[];
  dimensionSums: Record<ReviewDimension, number>;
  dimensionCounts: Record<ReviewDimension, number>;
}

export function emptyDimensionScores(): DimensionScores {
  return {
    responsiveness: null,
    maintenance: null,
    listingAccuracy: null,
    depositFairness: null,
  };
}

export function emptyTotals(): RatingTotals {
  return {
    count: 0,
    sum: 0,
    distribution: [0, 0, 0, 0, 0],
    dimensionSums: { responsiveness: 0, maintenance: 0, listingAccuracy: 0, depositFairness: 0 },
    dimensionCounts: { responsiveness: 0, maintenance: 0, listingAccuracy: 0, depositFairness: 0 },
  };
}

function asCount(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}

/**
 * Reads totals from a stored rating document.
 *
 * Deliberately tolerant: a missing document is a landlord with no reviews yet,
 * not an error, and this runs on the first review anyone ever leaves them.
 */
export function readTotals(data: Record<string, unknown> | undefined): RatingTotals {
  const totals = emptyTotals();
  if (!data) return totals;
  totals.count = asCount(data.count);
  totals.sum = asCount(data.sum);
  const distribution = data.distribution;
  if (Array.isArray(distribution)) {
    for (let index = 0; index < 5; index += 1) {
      totals.distribution[index] = asCount(distribution[index]);
    }
  }
  const sums = (data.dimensionSums ?? {}) as Record<string, unknown>;
  const counts = (data.dimensionCounts ?? {}) as Record<string, unknown>;
  for (const dimension of REVIEW_DIMENSIONS) {
    totals.dimensionSums[dimension] = asCount(sums[dimension]);
    totals.dimensionCounts[dimension] = asCount(counts[dimension]);
  }
  return totals;
}

/**
 * Adds (`sign: 1`) or removes (`sign: -1`) one review's contribution.
 *
 * Clamped at zero throughout. Totals surviving a partial historical write, or a
 * review whose scores were reshaped by a later schema change, must not be able
 * to drive a count negative and render "-1 reviews" on a public page.
 */
export function applyReview(
  totals: RatingTotals,
  overall: number,
  dimensions: DimensionScores,
  sign: 1 | -1,
): RatingTotals {
  const next: RatingTotals = {
    count: Math.max(0, totals.count + sign),
    sum: Math.max(0, totals.sum + sign * overall),
    distribution: [...totals.distribution],
    dimensionSums: { ...totals.dimensionSums },
    dimensionCounts: { ...totals.dimensionCounts },
  };
  const bucket = Math.min(5, Math.max(1, Math.round(overall))) - 1;
  next.distribution[bucket] = Math.max(0, (next.distribution[bucket] ?? 0) + sign);
  for (const dimension of REVIEW_DIMENSIONS) {
    const score = dimensions[dimension];
    if (typeof score !== 'number') continue;
    next.dimensionSums[dimension] = Math.max(0, next.dimensionSums[dimension] + sign * score);
    next.dimensionCounts[dimension] = Math.max(0, next.dimensionCounts[dimension] + sign);
  }
  return next;
}

/** Plain mean, or null when there is nothing to average. */
export function averageOf(totals: RatingTotals): number | null {
  return totals.count === 0 ? null : totals.sum / totals.count;
}

/**
 * Shrunk mean used for ordering.
 *
 * `(C·m + sum) / (C + count)` pulls a thin sample toward the platform prior, so
 * a single five-star review lands near the prior rather than at the top of the
 * marketplace, and a landlord with real volume converges on their true mean.
 * See REVIEW_PRIOR_* in config.ts for why the prior is a fixed constant.
 */
export function rankScoreOf(totals: RatingTotals): number {
  return (
    (REVIEW_PRIOR_WEIGHT * REVIEW_PRIOR_MEAN + totals.sum)
    / (REVIEW_PRIOR_WEIGHT + totals.count)
  );
}

export function dimensionAveragesOf(totals: RatingTotals): Record<ReviewDimension, number | null> {
  const averages = {} as Record<ReviewDimension, number | null>;
  for (const dimension of REVIEW_DIMENSIONS) {
    const count = totals.dimensionCounts[dimension];
    averages[dimension] = count === 0 ? null : totals.dimensionSums[dimension] / count;
  }
  return averages;
}

/**
 * Whether a star average may be shown publicly at all.
 *
 * Below the threshold the marketplace shows a "new to Nyumba" state. The
 * totals still accumulate — this gates *display*, not collection, so a landlord
 * crossing the threshold does not start from zero.
 */
export function isDisplayable(totals: RatingTotals): boolean {
  return totals.count >= REVIEW_PUBLIC_DISPLAY_MIN_COUNT;
}

/**
 * The stored rating document.
 *
 * Averages and `rankScore` are derived, yet stored: Firestore cannot compute
 * them at query or render time, and every reader — marketplace card, profile
 * page, landlord dashboard — needs them without a second round trip. The raw
 * totals stay alongside so the next edit can still invert exactly.
 */
export function ratingDocument(
  id: string,
  totals: RatingTotals,
  now: Timestamp,
  createdAt: unknown,
): Record<string, unknown> {
  return {
    id,
    count: totals.count,
    sum: totals.sum,
    distribution: totals.distribution,
    dimensionSums: totals.dimensionSums,
    dimensionCounts: totals.dimensionCounts,
    average: averageOf(totals),
    rankScore: rankScoreOf(totals),
    dimensionAverages: dimensionAveragesOf(totals),
    isDisplayable: isDisplayable(totals),
    createdAt: createdAt ?? now,
    updatedAt: now,
    isDeleted: false,
  };
}

/**
 * The badge stamped onto each of a landlord's published listings.
 *
 * Kept to three fields on purpose: this is denormalized across every listing a
 * landlord has live, so each added field multiplies by the fan-out and by every
 * marketplace card a browser downloads.
 */
export function ratingBadge(totals: RatingTotals): Record<string, unknown> {
  const displayable = isDisplayable(totals);
  return {
    ratingAverage: displayable ? averageOf(totals) : null,
    ratingCount: totals.count,
    ratingRankScore: rankScoreOf(totals),
  };
}
