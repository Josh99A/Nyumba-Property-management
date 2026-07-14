import { describe, expect, it } from 'vitest';
import { parseEnvelope } from '../../src/shared/envelope';
import { DomainError } from '../../src/shared/errors';

function validEnvelope(): Record<string, unknown> {
  return {
    commandId: 'command_1234',
    type: 'unit.create',
    schemaVersion: 1,
    aggregateId: 'unit_123456',
    expectedVersion: 0,
    payload: {},
    client: { installationId: 'install_1234', appVersion: '1.0.0', platform: 'web' },
  };
}

describe('strict command envelope', () => {
  it('accepts version one', () => {
    expect(parseEnvelope(validEnvelope()).schemaVersion).toBe(1);
  });

  it.each([
    { extra: true },
    { schemaVersion: 2 },
    { commandId: 'short' },
    { client: { installationId: 'install_1234', appVersion: '1', platform: 'web', extra: true } },
  ])('rejects malformed or unknown fields: %j', (patch) => {
    expect(() => parseEnvelope({ ...validEnvelope(), ...patch })).toThrow(DomainError);
  });

  it('rejects envelopes over 64 KiB', () => {
    expect(() => parseEnvelope({ ...validEnvelope(), payload: { value: 'x'.repeat(70_000) } })).toThrow(DomainError);
  });
});
