import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import type { Actor } from './actor';
import { writeAudit } from './audit';
import { hashCanonicalCommand } from './canonical';
import { COLLECTIONS } from './collections';
import { RECEIPT_RETENTION_DAYS } from './config';
import { parseEnvelope, zodIssuesToDetails } from './envelope';
import { DomainError } from './errors';
import type { CommandHandler, CommandOutcome } from './handlers';
import { commandHandlers } from '../commands';

export interface CommandResponse {
  commandId: string;
  status: 'applied' | 'accepted' | 'rejected';
  aggregateId: string | null;
  serverVersion?: number;
  serverUpdatedAt: string;
  result: Record<string, unknown>;
  error: ReturnType<DomainError['toSafeError']> | null;
}

function validateModes(handler: CommandHandler, cmd: ReturnType<typeof parseEnvelope>): void {
  if (handler.aggregateIdMode === 'required' && !cmd.aggregateId) {
    throw new DomainError('VALIDATION_FAILED', { fields: ['aggregateId'] });
  }
  if (handler.aggregateIdMode === 'forbidden' && cmd.aggregateId !== undefined) {
    throw new DomainError('VALIDATION_FAILED', { fields: ['aggregateId'] });
  }
  switch (handler.expectedVersionMode) {
    case 'create':
      if (cmd.expectedVersion !== 0) {
        throw new DomainError('VALIDATION_FAILED', { fields: ['expectedVersion'] });
      }
      break;
    case 'edit':
      if (cmd.expectedVersion === undefined || cmd.expectedVersion < 1) {
        throw new DomainError('VALIDATION_FAILED', { fields: ['expectedVersion'] });
      }
      break;
    case 'createOrEdit':
      if (cmd.expectedVersion === undefined) {
        throw new DomainError('VALIDATION_FAILED', { fields: ['expectedVersion'] });
      }
      break;
    case 'none':
      if (cmd.expectedVersion !== undefined) {
        throw new DomainError('VALIDATION_FAILED', { fields: ['expectedVersion'] });
      }
      break;
  }
}

function responseForSuccess(
  commandId: string,
  outcome: CommandOutcome,
  now: Timestamp,
): CommandResponse {
  return {
    commandId,
    status: outcome.status,
    aggregateId: outcome.aggregateId,
    ...(outcome.serverVersion === undefined ? {} : { serverVersion: outcome.serverVersion }),
    serverUpdatedAt: now.toDate().toISOString(),
    result: outcome.safeResult ?? {},
    error: null,
  };
}

/**
 * Transport-independent command executor.
 *
 * Firestore transactions buffer writes. Every handler must therefore finish
 * all reads and validation before its first write. This guarantees that a
 * deterministic rejection cannot accidentally commit partial aggregate work
 * beside its rejected receipt.
 */
export async function executeCommandCore(
  db: Firestore,
  actor: Actor,
  rawData: unknown,
  now: Timestamp = Timestamp.now(),
): Promise<CommandResponse> {
  const cmd = parseEnvelope(rawData);
  const handler = commandHandlers.get(cmd.type);
  if (!handler) {
    // A newer client may know a command this deployment does not. Do not pin
    // that mismatch into a deterministic receipt.
    throw new DomainError('VALIDATION_FAILED', { reason: 'unknownCommandType' });
  }
  const requestHash = hashCanonicalCommand(cmd);

  let heldValidationError: DomainError | null = null;
  let payload: unknown = cmd.payload;
  try {
    validateModes(handler, cmd);
    const parsed = handler.payloadSchema.safeParse(cmd.payload);
    if (!parsed.success) {
      throw new DomainError('VALIDATION_FAILED', zodIssuesToDetails(parsed.error));
    }
    payload = parsed.data;
  } catch (error) {
    if (error instanceof DomainError && error.deterministic) heldValidationError = error;
    else throw error;
  }

  return db.runTransaction(async (tx) => {
    const receiptRef = db.collection(COLLECTIONS.commandReceipts).doc(cmd.commandId);
    const prior = await tx.get(receiptRef);
    if (prior.exists) {
      const data = prior.data();
      if (data?.actorUid !== actor.uid || data.requestHash !== requestHash) {
        throw new DomainError('IDEMPOTENCY_KEY_REUSED');
      }
      return data.response as CommandResponse;
    }

    let outcome: CommandOutcome;
    try {
      if (heldValidationError) throw heldValidationError;
      outcome = await handler.apply({
        tx,
        db,
        actor,
        cmd: { ...cmd, payload },
        now,
      });
    } catch (error) {
      if (!(error instanceof DomainError) || !error.deterministic) throw error;
      const response: CommandResponse = {
        commandId: cmd.commandId,
        status: 'rejected',
        aggregateId: cmd.aggregateId ?? null,
        serverUpdatedAt: now.toDate().toISOString(),
        result: {},
        error: error.toSafeError(),
      };
      const expiresAt = Timestamp.fromMillis(
        now.toMillis() + RECEIPT_RETENTION_DAYS * 24 * 60 * 60 * 1000,
      );
      tx.create(receiptRef, {
        actorUid: actor.uid,
        requestHash,
        type: cmd.type,
        aggregateId: cmd.aggregateId ?? null,
        status: 'rejected',
        safeResult: {},
        error: error.toSafeError(),
        response,
        createdAt: now,
        updatedAt: now,
        expiresAt,
      });
      writeAudit(tx, db, now, {
        actor,
        commandId: cmd.commandId,
        commandType: cmd.type,
        aggregateId: cmd.aggregateId ?? null,
        outcome: 'rejected',
        errorCode: error.code,
      });
      return response;
    }

    const response = responseForSuccess(cmd.commandId, outcome, now);
    const expiresAt = Timestamp.fromMillis(
      now.toMillis() + RECEIPT_RETENTION_DAYS * 24 * 60 * 60 * 1000,
    );
    tx.create(receiptRef, {
      actorUid: actor.uid,
      requestHash,
      type: cmd.type,
      aggregateId: outcome.aggregateId,
      status: outcome.status,
      safeResult: outcome.safeResult ?? {},
      error: null,
      response,
      createdAt: now,
      updatedAt: now,
      expiresAt,
    });
    writeAudit(tx, db, now, {
      actor,
      commandId: cmd.commandId,
      commandType: cmd.type,
      aggregateId: outcome.aggregateId,
      outcome: outcome.status,
      ...(outcome.changedFields ? { changedFields: outcome.changedFields } : {}),
      ...(outcome.reasonCode ? { reasonCode: outcome.reasonCode } : {}),
    });
    return response;
  });
}
