import { describe, expect, it } from 'vitest';
import { propertyCreate, propertyUpdate } from '../../src/commands/portfolio';

const staged = (count: number) =>
  Array.from(
    { length: count },
    (_, index) => `uploads/landlord_1234/command_1234/photo-${index}.webp`,
  );

describe('property photo limits', () => {
  it('accepts two staged photos and rejects a third on create', () => {
    const validProperty = {
      name: 'Acacia Court',
      addressLine: '12 Acacia Avenue',
      city: 'Kampala',
    };

    expect(
      propertyCreate.payloadSchema.safeParse({
        ...validProperty,
        stagedImagePaths: staged(2),
      }).success,
    ).toBe(true);
    expect(
      propertyCreate.payloadSchema.safeParse({
        ...validProperty,
        stagedImagePaths: staged(3),
      }).success,
    ).toBe(false);
  });

  it('rejects a third staged photo on update', () => {
    expect(
      propertyUpdate.payloadSchema.safeParse({
        stagedImagePaths: staged(2),
      }).success,
    ).toBe(true);
    expect(
      propertyUpdate.payloadSchema.safeParse({
        stagedImagePaths: staged(3),
      }).success,
    ).toBe(false);
  });
});
