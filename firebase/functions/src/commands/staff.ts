import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import {
  requireActiveLandlord,
  requireOwnedByLandlord,
  sanitizeStaffPermissions,
  STAFF_PERMISSIONS,
  STANDARD_STAFF_PERMISSIONS,
  staffMembershipId,
  type StaffPermission,
} from '../shared/accounts';
import { COLLECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import {
  createJob,
  optionalShortText,
  strictPayload,
  type CommandHandler,
} from '../shared/handlers';

// Invite emails are stored lowercased so staff.claimInvite can match the
// verified token email with an exact Firestore equality query.
const inviteEmail = z.string().email().max(320).transform((value) => value.toLowerCase());

const permissionSchema = z.enum(STAFF_PERMISSIONS);
const permissionsSchema = z.array(permissionSchema).min(1).max(STAFF_PERMISSIONS.length);

/**
 * Resolves the permission set to persist. Tiers without the custom-role
 * entitlement (Starter/Pro) are locked to the fixed standard preset regardless
 * of the requested subset; only Premium+ honour a bespoke selection.
 */
function resolvePermissions(
  requested: StaffPermission[],
  customStaffRoles: boolean,
): StaffPermission[] {
  const sanitized = sanitizeStaffPermissions(requested);
  if (sanitized.length === 0) throw new DomainError('VALIDATION_FAILED', { fields: ['permissions'] });
  return customStaffRoles ? sanitized : [...STANDARD_STAFF_PERMISSIONS];
}

const staffInviteSchema = strictPayload({
  email: inviteEmail,
  displayName: optionalShortText,
  permissions: permissionsSchema,
});

/**
 * A landlord adds a staff member by email. The invite occupies a seat as soon
 * as it is created (pending) — capacity is the owner plan's staffSeatLimit, and
 * revoked invites free their seat. The person joins by signing in with this
 * exact address (staff.claimInvite); the invite carries no secret.
 */
export const staffInvite: CommandHandler<z.infer<typeof staffInviteSchema>> = {
  payloadSchema: staffInviteSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const ref = db.collection(COLLECTIONS.staffInvites).doc(cmd.aggregateId!);

    // All reads before the first buffered write. A single-equality query keeps
    // this index-free; revoked invites are filtered out in memory.
    const [snapshot, existingInvites] = await Promise.all([
      tx.get(ref),
      tx.get(
        db
          .collection(COLLECTIONS.staffInvites)
          .where('landlordId', '==', landlord.landlordId)
          .limit(500),
      ),
    ]);
    requireAbsent(snapshot);

    const active = existingInvites.docs.filter((doc) => {
      const invite = doc.data() as { inviteState?: string; isDeleted?: boolean };
      return invite.isDeleted !== true && invite.inviteState !== 'revoked';
    });
    if (active.length >= landlord.entitlements.staffSeatLimit) {
      throw new DomainError('SEAT_LIMIT_REACHED', {
        staffSeatLimit: landlord.entitlements.staffSeatLimit,
      });
    }
    // One seat per person: a still-open invite to the same address is a reuse,
    // not a second seat.
    if (active.some((doc) => (doc.data() as { email?: string }).email === cmd.payload.email)) {
      throw new DomainError('ALREADY_EXISTS', { field: 'email' });
    }

    const permissions = resolvePermissions(
      cmd.payload.permissions,
      landlord.entitlements.customStaffRoles,
    );
    tx.create(ref, {
      ...newAggregate(cmd.aggregateId!, now),
      landlordId: landlord.landlordId,
      email: cmd.payload.email,
      displayName: cmd.payload.displayName ?? null,
      permissions,
      inviteState: 'pending',
      memberUid: null,
    });
    createJob(tx, db, `${cmd.commandId}_staff_invite_email`, 'sendStaffInviteEmail', { inviteId: cmd.aggregateId! }, now);
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: 1,
      changedFields: ['email', 'permissions', 'inviteState'],
    };
  },
};

const claimInviteSchema = strictPayload({});

/**
 * Executed by a signed-in user to claim staff invitations addressed to their
 * verified email. Linking creates a deterministic `staffMemberships` doc so
 * Firestore Rules can authorize the person's workspace reads with an O(1)
 * `exists()`. Idempotent — zero matches is a success.
 */
export const staffClaimInvite: CommandHandler<Record<string, never>> = {
  payloadSchema: claimInviteSchema,
  aggregateIdMode: 'forbidden',
  expectedVersionMode: 'none',
  async apply({ tx, db, actor, cmd, now }) {
    void cmd;
    if (!actor.emailVerified || !actor.email) {
      throw new DomainError('PERMISSION_DENIED', { reason: 'verifiedEmailRequired' });
    }
    const email = actor.email.toLowerCase();

    const inviteSnap = await tx.get(
      db
        .collection(COLLECTIONS.staffInvites)
        .where('email', '==', email)
        .where('inviteState', '==', 'pending')
        .limit(20),
    );
    const claimable = inviteSnap.docs.filter((doc) => {
      const invite = doc.data() as { memberUid?: string | null; isDeleted?: boolean; landlordId?: unknown };
      const linkedElsewhere = typeof invite.memberUid === 'string' && invite.memberUid !== actor.uid;
      return invite.isDeleted !== true && !linkedElsewhere && typeof invite.landlordId === 'string';
    });

    for (const doc of claimable) {
      const invite = doc.data() as Record<string, unknown> & { version: number; landlordId: string };
      const permissions = sanitizeStaffPermissions(invite.permissions);
      tx.update(doc.ref, {
        memberUid: actor.uid,
        inviteState: 'accepted',
        ...bumpVersion(invite, now),
      });
      tx.set(
        db.collection(COLLECTIONS.staffMemberships).doc(staffMembershipId(invite.landlordId, actor.uid)),
        {
          ...newAggregate(staffMembershipId(invite.landlordId, actor.uid), now),
          landlordId: invite.landlordId,
          memberUid: actor.uid,
          email,
          permissions,
          active: true,
        },
      );
    }
    return {
      status: 'applied',
      aggregateId: actor.uid,
      safeResult: { linkedMemberships: claimable.length },
      changedFields: claimable.length > 0 ? ['memberUid', 'inviteState'] : [],
    };
  },
};

/**
 * Revokes a staff invite/membership. The invite's seat is freed and the
 * deterministic membership doc is deleted, which immediately cuts the person's
 * workspace reads (Firestore Rules) and command access (requireWorkspace).
 */
export const staffRevoke: CommandHandler<Record<string, never>> = {
  payloadSchema: strictPayload({}),
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const ref = db.collection(COLLECTIONS.staffInvites).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const invite = requireAggregate<Record<string, unknown> & { version: number; memberUid?: string | null }>(
      snapshot,
      cmd.expectedVersion,
    );
    requireOwnedByLandlord(invite, landlord.landlordId);

    tx.update(ref, { inviteState: 'revoked', memberUid: null, ...bumpVersion(invite, now) });
    if (typeof invite.memberUid === 'string') {
      tx.delete(
        db.collection(COLLECTIONS.staffMemberships).doc(staffMembershipId(landlord.landlordId, invite.memberUid)),
      );
    }
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: invite.version + 1,
      changedFields: ['inviteState', 'memberUid'],
    };
  },
};

const updatePermissionsSchema = strictPayload({ permissions: permissionsSchema });

/**
 * Changes a staff member's granted permissions. Custom subsets require the
 * owner plan's custom-role entitlement (Premium+); the membership doc is
 * updated in the same transaction so command enforcement never runs on stale
 * permissions.
 */
export const staffUpdatePermissions: CommandHandler<z.infer<typeof updatePermissionsSchema>> = {
  payloadSchema: updatePermissionsSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    if (!landlord.entitlements.customStaffRoles) {
      throw new DomainError('CUSTOM_ROLES_UNAVAILABLE');
    }
    const ref = db.collection(COLLECTIONS.staffInvites).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const invite = requireAggregate<Record<string, unknown> & { version: number; memberUid?: string | null }>(
      snapshot,
      cmd.expectedVersion,
    );
    requireOwnedByLandlord(invite, landlord.landlordId);

    const membershipRef = typeof invite.memberUid === 'string'
      ? db.collection(COLLECTIONS.staffMemberships).doc(staffMembershipId(landlord.landlordId, invite.memberUid))
      : null;
    const membershipSnap = membershipRef ? await tx.get(membershipRef) : null;

    const permissions = resolvePermissions(cmd.payload.permissions, true);
    tx.update(ref, { permissions, ...bumpVersion(invite, now) });
    if (membershipRef && membershipSnap?.exists) {
      const membership = membershipSnap.data() as { version: number };
      tx.update(membershipRef, { permissions, ...bumpVersion(membership, now) });
    }
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: invite.version + 1,
      changedFields: ['permissions'],
    };
  },
};
