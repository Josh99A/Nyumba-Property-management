import type { Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import type { Actor } from './actor';
import { COLLECTIONS } from './collections';

export interface AuditEventInput {
  actor: Actor;
  commandId: string;
  commandType: string;
  aggregateId: string | null;
  outcome: 'applied' | 'accepted' | 'rejected';
  errorCode?: string;
  reasonCode?: string;
  /** Names of fields that changed — never their values. */
  changedFields?: string[];
}

/**
 * Append-only, redacted audit trail. Payload bodies, PII, and money amounts
 * are intentionally absent; investigations join on aggregate IDs instead.
 */
export function writeAudit(
  tx: Transaction,
  db: Firestore,
  now: Timestamp,
  event: AuditEventInput,
): void {
  const ref = db.collection(COLLECTIONS.auditLogs).doc();
  tx.create(ref, {
    id: ref.id,
    actorUid: event.actor.uid,
    actorIsAdmin: event.actor.platformAdmin,
    commandId: event.commandId,
    action: event.commandType,
    aggregateId: event.aggregateId,
    outcome: event.outcome,
    errorCode: event.errorCode ?? null,
    reasonCode: event.reasonCode ?? null,
    changedFields: event.changedFields ?? [],
    at: now,
  });
}
