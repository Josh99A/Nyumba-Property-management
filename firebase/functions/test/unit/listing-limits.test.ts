import { describe, expect, it } from 'vitest';
import { listingSaveDraft } from '../../src/commands/listings';

const validDraft = {
  unitId: 'unit_123456',
  title: 'Bright apartment',
  description: 'A bright apartment near local amenities.',
  monthlyRentMinor: 150_000_000,
  unitType: 'apartment',
  city: 'Kampala',
  neighborhood: 'Ntinda',
  bedrooms: 2,
  bathrooms: 1,
  amenities: ['Parking'],
};

describe('listing photo limits', () => {
  it('accepts five staged photos and rejects a sixth', () => {
    const staged = (count: number) =>
      Array.from(
        { length: count },
        (_, index) => `uploads/landlord_1234/command_1234/photo-${index}.webp`,
      );

    expect(
      listingSaveDraft.payloadSchema.safeParse({
        ...validDraft,
        stagedImagePaths: staged(5),
      }).success,
    ).toBe(true);
    expect(
      listingSaveDraft.payloadSchema.safeParse({
        ...validDraft,
        stagedImagePaths: staged(6),
      }).success,
    ).toBe(false);
  });
});
