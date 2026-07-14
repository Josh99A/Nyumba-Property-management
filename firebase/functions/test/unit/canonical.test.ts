import { describe, expect, it } from 'vitest';
import { canonicalJson, hashCanonicalCommand } from '../../src/shared/canonical';

describe('canonical command hashing', () => {
  it('sorts nested object keys and drops undefined object members', () => {
    expect(canonicalJson({ z: 2, a: { d: undefined, c: 1 } })).toBe('{"a":{"c":1},"z":2}');
  });

  it('rejects non-finite numbers', () => {
    expect(() => canonicalJson({ value: Number.NaN })).toThrow(/Non-finite/);
  });

  it('excludes client metadata from the idempotency hash', () => {
    const body = {
      commandId: 'command_1234', type: 'unit.create', schemaVersion: 1,
      aggregateId: 'unit_123456', expectedVersion: 0,
      payload: { label: 'A1' },
    };
    const first = hashCanonicalCommand({ ...body, client: { appVersion: '1' } } as typeof body);
    const second = hashCanonicalCommand({ ...body, client: { appVersion: '2' } } as typeof body);
    expect(first).toBe(second);
  });
});
