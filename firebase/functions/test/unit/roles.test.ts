import { describe, expect, it } from 'vitest';
import { mergeRoles } from '../../src/shared/roles';

describe('mergeRoles', () => {
  it('seeds from the legacy scalar when no array exists yet', () => {
    expect(mergeRoles(undefined, 'tenant', 'landlord')).toEqual(['landlord', 'tenant']);
    expect(mergeRoles(undefined, 'landlord', 'tenant')).toEqual(['landlord', 'tenant']);
  });

  it('drops the client placeholder as soon as a real role exists', () => {
    expect(mergeRoles(undefined, 'client', 'tenant')).toEqual(['tenant']);
    expect(mergeRoles(['client'], 'client', 'landlord')).toEqual(['landlord']);
    expect(mergeRoles(undefined, undefined, 'tenant')).toEqual(['tenant']);
  });

  it('keeps client only when it is the whole story', () => {
    expect(mergeRoles(undefined, undefined, 'client')).toEqual(['client']);
    expect(mergeRoles(['client'], 'client', 'client')).toEqual(['client']);
  });

  it('prefers the array over the scalar when both exist', () => {
    // The scalar is the primary presentation role; the array is the record.
    // A landlord-who-was-a-tenant has scalar 'landlord' but both in the array.
    expect(mergeRoles(['landlord', 'tenant'], 'landlord', 'tenant')).toEqual([
      'landlord',
      'tenant',
    ]);
  });

  it('is idempotent and stable', () => {
    const once = mergeRoles(undefined, 'tenant', 'landlord');
    const twice = mergeRoles(once, 'landlord', 'landlord');
    expect(twice).toEqual(once);
  });

  it('discards unknown strings instead of trusting them', () => {
    expect(mergeRoles(['admin', 'x', 42], 'tenant', 'tenant')).toEqual(['tenant']);
    expect(mergeRoles('landlord', 'tenant', 'tenant')).toEqual(['tenant']);
  });
});
