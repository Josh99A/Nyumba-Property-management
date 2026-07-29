import { Timestamp as TimestampClass } from 'firebase-admin/firestore';
import type { Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { z } from 'zod';
import type { Actor } from './actor';
import type { CommandEnvelope } from './envelope';
import { DomainError } from './errors';

export type AggregateIdMode = 'required' | 'forbidden';
export type ExpectedVersionMode = 'create' | 'edit' | 'none' | 'createOrEdit';

export interface CommandOutcome {
  status: 'applied' | 'accepted';
  aggregateId: string;
  serverVersion?: number;
  safeResult?: Record<string, unknown>;
  changedFields?: string[];
  reasonCode?: string;
}

export interface CommandContext<P> {
  tx: Transaction;
  db: Firestore;
  actor: Actor;
  cmd: Omit<CommandEnvelope, 'payload'> & { payload: P };
  now: Timestamp;
}

export interface CommandHandler<P = unknown> {
  payloadSchema: z.ZodType<P, z.ZodTypeDef, unknown>;
  aggregateIdMode: AggregateIdMode;
  expectedVersionMode: ExpectedVersionMode;
  apply(context: CommandContext<P>): Promise<CommandOutcome>;
}

export const idSchema = z.string().regex(/^[A-Za-z0-9_-]{8,128}$/);
export const shortText = z.string().trim().min(1).max(200);
export const longText = z.string().trim().min(1).max(5_000);
export const optionalShortText = z.string().trim().max(200).optional();
export const nonNegativeMoney = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);

/**
 * A map pin, at the precision the client captured it.
 *
 * Shared so `property` and `listing` cannot drift into two spellings of the
 * same idea. This is the *private* precision: coarsening for public exposure
 * happens at publication (see `listingPublish`), never here, because the
 * landlord's own screens legitimately need the exact point they placed.
 */
export const coordinateSchema = z
  .object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) })
  .strict();

export function strictPayload<T extends z.ZodRawShape>(shape: T): z.ZodObject<T, 'strict'> {
  return z.object(shape).strict();
}

/**
 * Enqueues a background job atomically with the command that produced it.
 *
 * `runAt` defers the first attempt: `claimJob` refuses a pending job until
 * `nextAttemptAt` has passed and `sweepBackendJobs` polls for the ones that
 * have. Omit it for work that should run as soon as the write lands.
 */
export function createJob(
  tx: Transaction,
  db: Firestore,
  id: string,
  type: string,
  payload: Record<string, unknown>,
  now: Timestamp,
  runAt?: Timestamp,
): void {
  tx.create(db.collection('backendJobs').doc(id), {
    id,
    type,
    payload,
    state: 'pending',
    attemptCount: 0,
    nextAttemptAt: runAt ?? now,
    leaseUntil: null,
    createdAt: now,
    updatedAt: now,
  });
}

/**
 * Rejects a write that arrived inside a per-actor cooldown.
 *
 * The last-write timestamp lives on whatever document already tracks that
 * actor's cadence (`landlordAccounts` for feedback and support), so callers
 * pass the value they read rather than a path this helper would have to know.
 * A missing or malformed timestamp is treated as "no cooldown in effect":
 * failing open here only ever costs one extra write, while failing closed
 * would lock out an account whose first cadence field has never been set.
 */
export function rejectIfWithin(
  last: unknown,
  cooldownMs: number,
  now: Timestamp,
): void {
  if (!(last instanceof TimestampClass)) return;
  const elapsed = now.toMillis() - last.toMillis();
  if (elapsed < cooldownMs) {
    throw new DomainError('RATE_LIMITED', {
      retryAfterSeconds: Math.ceil((cooldownMs - elapsed) / 1000),
    });
  }
}

export function requireInteger(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw new TypeError(`${field} must be an integer.`);
  }
  return value;
}
