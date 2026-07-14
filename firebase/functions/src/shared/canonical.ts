import { createHash } from 'node:crypto';

/**
 * Deterministic JSON canonicalization: object keys sorted recursively,
 * arrays kept in order, `undefined` object members omitted. Non-finite
 * numbers are rejected because they cannot round-trip through JSON.
 */
export function canonicalJson(value: unknown): string {
  if (value === null) return 'null';
  switch (typeof value) {
    case 'string':
      return JSON.stringify(value);
    case 'boolean':
      return value ? 'true' : 'false';
    case 'number':
      if (!Number.isFinite(value)) {
        throw new TypeError('Non-finite numbers are not canonicalizable.');
      }
      return JSON.stringify(value);
    case 'object':
      break;
    default:
      throw new TypeError(`Cannot canonicalize a ${typeof value}.`);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item === undefined ? null : item)).join(',')}]`;
  }
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, member]) => member !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([key, member]) => `${JSON.stringify(key)}:${canonicalJson(member)}`);
  return `{${entries.join(',')}}`;
}

/**
 * Stable hash of the command body stored with its receipt. The `client`
 * metadata block is deliberately excluded: an app update between retries
 * changes `appVersion` without changing the command's meaning, and must not
 * surface as IDEMPOTENCY_KEY_REUSED.
 */
export function hashCanonicalCommand(command: {
  commandId: string;
  type: string;
  schemaVersion: number;
  aggregateId?: string | undefined;
  expectedVersion?: number | undefined;
  payload: Record<string, unknown>;
}): string {
  const body = {
    commandId: command.commandId,
    type: command.type,
    schemaVersion: command.schemaVersion,
    aggregateId: command.aggregateId ?? null,
    expectedVersion: command.expectedVersion ?? null,
    payload: command.payload,
  };
  return createHash('sha256').update(canonicalJson(body), 'utf8').digest('hex');
}
