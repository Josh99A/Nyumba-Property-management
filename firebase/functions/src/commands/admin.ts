import { z } from 'zod';
import { bumpVersion, requireAggregate } from '../shared/aggregates';
import { requirePlatformAdmin } from '../shared/actor';
import { COLLECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import { createJob, strictPayload, type CommandHandler } from '../shared/handlers';

const reasonSchema = strictPayload({
  reasonCode: z.enum([
    'IDENTITY_VERIFIED',
    'COMPLIANCE_APPROVED',
    'POLICY_VIOLATION',
    'FRAUD_RISK',
    'APPEAL_APPROVED',
    'ADMIN_CORRECTION',
  ]),
});

function adminTransition(from: string, to: string, enqueueUnpublish = false): CommandHandler<z.infer<typeof reasonSchema>> {
  return {
    payloadSchema: reasonSchema,
    aggregateIdMode: 'required',
    expectedVersionMode: 'edit',
    async apply({ tx, db, actor, cmd, now }) {
      requirePlatformAdmin(actor);
      const landlordId = cmd.aggregateId!;
      if (landlordId === actor.uid) throw new DomainError('PERMISSION_DENIED');
      const ref = db.collection(COLLECTIONS.landlordAccounts).doc(landlordId);
      const snapshot = await tx.get(ref);
      const current = requireAggregate<{ version: number; approvalStatus: string }>(
        snapshot,
        cmd.expectedVersion,
      );
      if (current.approvalStatus !== from) {
        throw new DomainError('VALIDATION_FAILED', { reason: 'invalidApprovalTransition' });
      }
      tx.update(ref, {
        approvalStatus: to,
        approvalReasonCode: cmd.payload.reasonCode,
        ...bumpVersion(current, now),
      });
      if (enqueueUnpublish) {
        createJob(
          tx,
          db,
          `${cmd.commandId}_unpublish`,
          'unpublishLandlordListings',
          { landlordId },
          now,
        );
      }
      return {
        status: enqueueUnpublish ? 'accepted' : 'applied',
        aggregateId: landlordId,
        serverVersion: current.version + 1,
        changedFields: ['approvalStatus', 'approvalReasonCode'],
        reasonCode: cmd.payload.reasonCode,
      };
    },
  };
}

export const landlordApprove = adminTransition('pending', 'approved');
export const landlordSuspend = adminTransition('approved', 'suspended', true);
export const landlordReinstate = adminTransition('suspended', 'approved');
