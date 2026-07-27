import { describe, expect, it } from 'vitest';
import {
  REVIEW_PRIOR_MEAN,
  REVIEW_PRIOR_WEIGHT,
  REVIEW_PUBLIC_DISPLAY_MIN_COUNT,
} from '../../src/shared/config';
import {
  applyReview,
  averageOf,
  emptyDimensionScores,
  emptyTotals,
  isDisplayable,
  rankScoreOf,
  ratingBadge,
  readTotals,
  type DimensionScores,
} from '../../src/shared/ratings';

function scores(overrides: Partial<DimensionScores> = {}): DimensionScores {
  return { ...emptyDimensionScores(), ...overrides };
}

describe('rating totals', () => {
  it('treats a missing document as a landlord with no reviews', () => {
    const totals = readTotals(undefined);
    expect(totals.count).toBe(0);
    expect(averageOf(totals)).toBeNull();
  });

  it('accumulates overall scores into the star distribution', () => {
    let totals = emptyTotals();
    totals = applyReview(totals, 5, scores(), 1);
    totals = applyReview(totals, 3, scores(), 1);
    expect(totals.count).toBe(2);
    expect(totals.sum).toBe(8);
    expect(totals.distribution).toEqual([0, 0, 1, 0, 1]);
    expect(averageOf(totals)).toBe(4);
  });

  it('inverts a contribution exactly, which is what makes an edit safe', () => {
    let totals = emptyTotals();
    totals = applyReview(totals, 2, scores({ responsiveness: 1 }), 1);
    totals = applyReview(totals, 5, scores({ maintenance: 4 }), 1);
    // An edit removes the old scores and adds the new ones; the result must
    // equal a corpus that only ever contained the new value.
    totals = applyReview(totals, 2, scores({ responsiveness: 1 }), -1);
    totals = applyReview(totals, 4, scores({ responsiveness: 3 }), 1);

    expect(totals.count).toBe(2);
    expect(totals.sum).toBe(9);
    expect(totals.distribution).toEqual([0, 0, 0, 1, 1]);
    expect(totals.dimensionSums.responsiveness).toBe(3);
    expect(totals.dimensionCounts.responsiveness).toBe(1);
    expect(totals.dimensionSums.maintenance).toBe(4);
  });

  it('never lets totals go negative', () => {
    // A partial historical write, or a review whose scores were reshaped by a
    // later migration, must not be able to render "-1 reviews" publicly.
    const totals = applyReview(emptyTotals(), 4, scores(), -1);
    expect(totals.count).toBe(0);
    expect(totals.sum).toBe(0);
    expect(totals.distribution.every((bucket) => bucket >= 0)).toBe(true);
  });

  it('only counts dimensions the reviewer actually scored', () => {
    let totals = applyReview(emptyTotals(), 4, scores({ responsiveness: 5 }), 1);
    totals = applyReview(totals, 4, scores(), 1);
    // Two reviews, one responsiveness score: the dimension average must be 5,
    // not 2.5. Averaging over reviewers who skipped the question would punish
    // a landlord for the optional fields being optional.
    expect(totals.dimensionCounts.responsiveness).toBe(1);
    expect(totals.dimensionSums.responsiveness).toBe(5);
  });
});

describe('ranking score', () => {
  it('pulls a single review toward the prior instead of to the top', () => {
    const one = applyReview(emptyTotals(), 5, scores(), 1);
    expect(averageOf(one)).toBe(5);
    // The whole point of shrinkage: a lone five-star review must not outrank a
    // landlord with real volume.
    expect(rankScoreOf(one)).toBeLessThan(5);
    expect(rankScoreOf(one)).toBe(
      (REVIEW_PRIOR_WEIGHT * REVIEW_PRIOR_MEAN + 5) / (REVIEW_PRIOR_WEIGHT + 1),
    );

    let many = emptyTotals();
    for (let index = 0; index < 50; index += 1) many = applyReview(many, 5, scores(), 1);
    expect(rankScoreOf(many)).toBeGreaterThan(rankScoreOf(one));
  });

  it('converges on the true mean as volume grows', () => {
    let totals = emptyTotals();
    for (let index = 0; index < 200; index += 1) totals = applyReview(totals, 4, scores(), 1);
    expect(rankScoreOf(totals)).toBeCloseTo(4, 2);
  });

  it('scores an empty corpus at the prior', () => {
    expect(rankScoreOf(emptyTotals())).toBe(REVIEW_PRIOR_MEAN);
  });
});

describe('public display threshold', () => {
  it('withholds an average until enough reviews exist', () => {
    let totals = emptyTotals();
    for (let index = 1; index < REVIEW_PUBLIC_DISPLAY_MIN_COUNT; index += 1) {
      totals = applyReview(totals, 1, scores(), 1);
      expect(isDisplayable(totals)).toBe(false);
      // Collection continues below the threshold; only display is gated.
      expect(totals.count).toBe(index);
      expect(ratingBadge(totals).ratingAverage).toBeNull();
    }
    totals = applyReview(totals, 1, scores(), 1);
    expect(isDisplayable(totals)).toBe(true);
    expect(ratingBadge(totals).ratingAverage).toBe(1);
  });

  it('keeps the count on the badge even while the average is withheld', () => {
    // The marketplace needs to distinguish "no reviews" from "too few to show".
    const badge = ratingBadge(applyReview(emptyTotals(), 5, scores(), 1));
    expect(badge.ratingCount).toBe(1);
    expect(badge.ratingAverage).toBeNull();
  });
});

describe('reading stored totals', () => {
  it('round-trips its own output', () => {
    let totals = applyReview(emptyTotals(), 5, scores({ maintenance: 4 }), 1);
    totals = applyReview(totals, 2, scores({ depositFairness: 1 }), 1);
    expect(readTotals({ ...totals })).toEqual(totals);
  });

  it('ignores malformed stored fields rather than throwing', () => {
    const totals = readTotals({
      count: 'three',
      sum: null,
      distribution: 'nope',
      dimensionSums: 7,
    } as unknown as Record<string, unknown>);
    expect(totals).toEqual(emptyTotals());
  });
});
