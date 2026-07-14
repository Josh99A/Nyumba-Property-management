import { z } from 'zod';
import { DomainError } from './errors';

/** Client-generated IDs (ULID/UUID-style). Existence of an ID never grants access. */
export const ID_PATTERN = /^[A-Za-z0-9_-]{8,128}$/;

const MAX_ENVELOPE_BYTES = 64 * 1024;
const MAX_AGGREGATE_VERSION = 1_000_000_000;

const clientInfoSchema = z
  .object({
    installationId: z.string().min(1).max(128),
    appVersion: z.string().min(1).max(32),
    platform: z.enum(['android', 'ios', 'web']),
  })
  .strict();

const envelopeSchema = z
  .object({
    commandId: z.string().regex(ID_PATTERN),
    type: z
      .string()
      .min(3)
      .max(64)
      .regex(/^[a-z][a-zA-Z]*\.[a-z][a-zA-Z]*$/),
    schemaVersion: z.literal(1),
    aggregateId: z.string().regex(ID_PATTERN).optional(),
    expectedVersion: z.number().int().min(0).max(MAX_AGGREGATE_VERSION).optional(),
    payload: z.record(z.unknown()),
    client: clientInfoSchema,
  })
  .strict();

export type CommandEnvelope = z.infer<typeof envelopeSchema>;

export function zodIssuesToDetails(error: z.ZodError): { fields: string[] } {
  const fields = [...new Set(error.issues.map((issue) => issue.path.join('.') || '(root)'))];
  return { fields: fields.slice(0, 20) };
}

/**
 * Strict envelope parsing. Unknown fields, command types, or schema versions
 * are rejected; a malformed envelope has no trustworthy commandId, so this
 * failure is thrown (never persisted as a receipt).
 */
export function parseEnvelope(raw: unknown): CommandEnvelope {
  if (typeof raw !== 'object' || raw === null) {
    throw new DomainError('VALIDATION_FAILED', { reason: 'envelopeNotAnObject' });
  }
  let encodedLength: number;
  try {
    encodedLength = Buffer.byteLength(JSON.stringify(raw), 'utf8');
  } catch {
    throw new DomainError('VALIDATION_FAILED', { reason: 'envelopeNotSerializable' });
  }
  if (encodedLength > MAX_ENVELOPE_BYTES) {
    throw new DomainError('VALIDATION_FAILED', {
      reason: 'envelopeTooLarge',
      maxBytes: MAX_ENVELOPE_BYTES,
    });
  }
  const parsed = envelopeSchema.safeParse(raw);
  if (!parsed.success) {
    throw new DomainError('VALIDATION_FAILED', {
      reason: 'envelopeInvalid',
      ...zodIssuesToDetails(parsed.error),
    });
  }
  return parsed.data;
}
