import { z } from 'zod';
import { bumpVersion, newAggregate, requireAggregate } from '../shared/aggregates';
import { requirePlatformAdmin, requireSuperAdmin } from '../shared/actor';
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
      // First approval only: reinstatement returns an account it already
      // welcomed, and suspension is deliberately silent in email.
      if (from === 'pending' && to === 'approved') {
        createJob(tx, db, `${cmd.commandId}_approved_email`, 'sendLandlordApprovedEmail', { landlordId }, now);
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

const userLifecycleReasonSchema = strictPayload({
  reasonCode: z.enum([
    'POLICY_VIOLATION',
    'FRAUD_RISK',
    'USER_REQUESTED',
    'APPEAL_APPROVED',
    'ADMIN_CORRECTION',
  ]),
});

interface UserProfileAggregate {
  version: number;
  status?: string;
  role?: string;
}

/**
 * Archives any user account: the profile is marked `archived` and a background
 * job disables the Firebase Auth account so the person can no longer sign in.
 * Super-admin only — this acts across every role, unlike the landlord
 * approval transitions above. Records are retained; `user.delete` is the only
 * path out of the archive besides `user.restore`.
 */
export const userArchive: CommandHandler<z.infer<typeof userLifecycleReasonSchema>> = {
  payloadSchema: userLifecycleReasonSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requireSuperAdmin(actor);
    const targetUid = cmd.aggregateId!;
    if (targetUid === actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.users).doc(targetUid);
    const accountRef = db.collection(COLLECTIONS.landlordAccounts).doc(targetUid);
    const [snapshot, landlordAccount] = await Promise.all([tx.get(ref), tx.get(accountRef)]);
    const current = requireAggregate<UserProfileAggregate>(snapshot, cmd.expectedVersion);
    if (current.status === 'archived') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'alreadyArchived' });
    }
    tx.update(ref, {
      status: 'archived',
      archivedAt: now,
      archiveReasonCode: cmd.payload.reasonCode,
      ...bumpVersion(current, now),
    });
    createJob(tx, db, `${cmd.commandId}_disable`, 'setAuthUserDisabled', {
      uid: targetUid,
      disabled: true,
      expectedUserVersion: current.version + 1,
      expectedUserStatus: 'archived',
    }, now);
    // An archived landlord must not keep advertising: take their public
    // listings down through the same worker suspension uses.
    if (landlordAccount.exists) {
      createJob(tx, db, `${cmd.commandId}_unpublish`, 'unpublishLandlordListings', { landlordId: targetUid }, now);
    }
    return {
      status: 'accepted',
      aggregateId: targetUid,
      serverVersion: current.version + 1,
      changedFields: ['status', 'archivedAt', 'archiveReasonCode'],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

/** Returns an archived account to active and re-enables sign-in. */
export const userRestore: CommandHandler<z.infer<typeof userLifecycleReasonSchema>> = {
  payloadSchema: userLifecycleReasonSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requireSuperAdmin(actor);
    const targetUid = cmd.aggregateId!;
    if (targetUid === actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.users).doc(targetUid);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<UserProfileAggregate>(snapshot, cmd.expectedVersion);
    if (current.status !== 'archived') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'notArchived' });
    }
    tx.update(ref, {
      status: 'active',
      archivedAt: null,
      archiveReasonCode: null,
      ...bumpVersion(current, now),
    });
    createJob(tx, db, `${cmd.commandId}_enable`, 'setAuthUserDisabled', {
      uid: targetUid,
      disabled: false,
      expectedUserVersion: current.version + 1,
      expectedUserStatus: 'active',
    }, now);
    return {
      status: 'accepted',
      aggregateId: targetUid,
      serverVersion: current.version + 1,
      changedFields: ['status', 'archivedAt', 'archiveReasonCode'],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

/**
 * Permanently deletes an account out of the archive: the profile is
 * tombstoned (`isDeleted`, which every directory read filters out) and a
 * background job deletes the Firebase Auth account. Only an already-archived
 * account can be deleted, so removal is always a deliberate two-step act.
 */
export const userDelete: CommandHandler<z.infer<typeof userLifecycleReasonSchema>> = {
  payloadSchema: userLifecycleReasonSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requireSuperAdmin(actor);
    const targetUid = cmd.aggregateId!;
    if (targetUid === actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.users).doc(targetUid);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<UserProfileAggregate>(snapshot, cmd.expectedVersion);
    if (current.status !== 'archived') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'notArchived' });
    }
    tx.update(ref, {
      isDeleted: true,
      deletedAt: now,
      deleteReasonCode: cmd.payload.reasonCode,
      ...bumpVersion(current, now),
    });
    createJob(tx, db, `${cmd.commandId}_delete`, 'deleteAuthUser', { uid: targetUid }, now);
    return {
      status: 'accepted',
      aggregateId: targetUid,
      serverVersion: current.version + 1,
      changedFields: ['isDeleted', 'deletedAt', 'deleteReasonCode'],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};

const changeRoleSchema = strictPayload({
  // Only the server-owned ordinary roles. Administrator privileges are Auth
  // custom claims granted exclusively by the audited ops script; a command
  // that could mint an admin would hand that power to any stolen admin
  // session.
  role: z.enum(['client', 'tenant', 'landlord']),
  reasonCode: z.enum([
    'IDENTITY_VERIFIED',
    'COMPLIANCE_APPROVED',
    'USER_REQUESTED',
    'ADMIN_CORRECTION',
  ]),
});

/**
 * Changes any account's ordinary role. Super-admin only, never self, and
 * never on an archived account (restore it first so the archive stays an
 * inert state). Promoting to landlord provisions the landlord aggregates the
 * rest of the backend requires — approval starts `pending` and the
 * subscription `pending_payment`, so the workspace still fails closed until
 * the normal approval and payment paths run.
 */
export const userChangeRole: CommandHandler<z.infer<typeof changeRoleSchema>> = {
  payloadSchema: changeRoleSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    requireSuperAdmin(actor);
    const targetUid = cmd.aggregateId!;
    if (targetUid === actor.uid) throw new DomainError('PERMISSION_DENIED');
    const ref = db.collection(COLLECTIONS.users).doc(targetUid);
    const accountRef = db.collection(COLLECTIONS.landlordAccounts).doc(targetUid);
    const subscriptionRef = db.collection(COLLECTIONS.subscriptions).doc(targetUid);
    const [snapshot, landlordAccount, subscription] = await Promise.all([
      tx.get(ref),
      tx.get(accountRef),
      tx.get(subscriptionRef),
    ]);
    const current = requireAggregate<UserProfileAggregate>(snapshot, cmd.expectedVersion);
    if (current.status === 'archived') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'accountArchived' });
    }
    if (current.role === cmd.payload.role) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'roleUnchanged' });
    }
    if (cmd.payload.role === 'landlord') {
      if (!landlordAccount.exists) {
        tx.create(accountRef, {
          ...newAggregate(targetUid, now),
          ownerUid: targetUid,
          approvalStatus: 'pending',
          activeUnitCount: 0,
          activeListingCount: 0,
          activeStaffSeatCount: 0,
          receiptCounter: 0,
          businessName: null,
          phone: null,
        });
      }
      if (!subscription.exists) {
        tx.create(subscriptionRef, {
          ...newAggregate(targetUid, now),
          tier: 'starter',
          status: 'pending_payment',
          requestedAt: now,
        });
      }
    }
    // Demotion leaves the landlord aggregates in place: they are the audited
    // record of past standing, and restoring the role finds them again.
    tx.update(ref, {
      role: cmd.payload.role,
      roleChangedAt: now,
      roleChangeReasonCode: cmd.payload.reasonCode,
      ...bumpVersion(current, now),
    });
    return {
      status: 'applied',
      aggregateId: targetUid,
      serverVersion: current.version + 1,
      changedFields: ['role', 'roleChangedAt', 'roleChangeReasonCode'],
      reasonCode: cmd.payload.reasonCode,
    };
  },
};
