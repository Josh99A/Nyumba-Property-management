import type { DocumentSnapshot, Timestamp } from 'firebase-admin/firestore';
import { DomainError } from './errors';

/** Fields shared by every canonical record. */
export interface AggregateBase {
  id: string;
  version: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  isDeleted: boolean;
}

export function newAggregate(id: string, now: Timestamp): AggregateBase {
  return { id, version: 1, createdAt: now, updatedAt: now, isDeleted: false };
}

export function bumpVersion(current: { version: number }, now: Timestamp): {
  version: number;
  updatedAt: Timestamp;
} {
  return { version: current.version + 1, updatedAt: now };
}

/**
 * Loads an existing aggregate and enforces the optimistic-concurrency check.
 * A missing document is NOT_FOUND; a stale expectedVersion is VERSION_CONFLICT
 * with the current version as safe remediation data.
 */
export function requireAggregate<T extends { version: number; isDeleted?: boolean }>(
  snapshot: DocumentSnapshot,
  expectedVersion: number | undefined,
  options: { allowDeleted?: boolean } = {},
): T {
  const data = snapshot.data() as T | undefined;
  if (!snapshot.exists || !data) throw new DomainError('NOT_FOUND');
  if (data.isDeleted === true && !options.allowDeleted) throw new DomainError('NOT_FOUND');
  if (expectedVersion !== undefined && data.version !== expectedVersion) {
    throw new DomainError('VERSION_CONFLICT', {
      currentVersion: data.version,
      expectedVersion,
    });
  }
  return data;
}

/** Creates must target a fresh aggregate ID; replays are absorbed by receipts. */
export function requireAbsent(snapshot: DocumentSnapshot): void {
  if (snapshot.exists) throw new DomainError('ALREADY_EXISTS');
}
