import { describe, expect, it } from 'vitest';
import { isEntitlementPlanObject } from '../../scripts/check-plan-catalog-helpers.mjs';

describe('plan catalog audit', () => {
  it.each([null, undefined, false, 0, 'starter', []])(
    'rejects malformed entitlement plan value %j',
    (value) => {
      expect(isEntitlementPlanObject(value)).toBe(false);
    },
  );

  it('accepts a non-null plan object', () => {
    expect(
      isEntitlementPlanObject({
        unitLimit: 10,
        activeListingLimit: 3,
        staffSeatLimit: 0,
      }),
    ).toBe(true);
  });
});
