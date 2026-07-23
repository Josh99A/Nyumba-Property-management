import type { Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { z } from 'zod';
import type { Actor } from './actor';
import type { CommandEnvelope } from './envelope';

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

export function requireInteger(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw new TypeError(`${field} must be an integer.`);
  }
  return value;
}
