import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { requireOwnedByLandlord, requireWorkspace } from '../shared/accounts';
import { COLLECTIONS, LANDLORD_PORTAL_SECTIONS, TENANT_PORTAL_SECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import { createJob, idSchema, nonNegativeMoney, optionalShortText, shortText, strictPayload, type CommandHandler } from '../shared/handlers';
import {
  applyActiveListingRetirement,
  loadActiveListingRetirement,
} from '../shared/listing-retirement';
import { landlordTenancyProjection, tenantLeaseProjection } from '../shared/projections';

// Invite emails are stored lowercased so tenant.claimInvite can match the
// verified token email with an exact Firestore equality query.
const inviteEmail = z.string().email().max(320).transform((value) => value.toLowerCase());

const tenantCreateSchema = strictPayload({
  displayName: shortText,
  email: inviteEmail,
  phone: z.string().trim().min(7).max(32),
  tenantUserUid: idSchema.optional(),
  notes: z.string().trim().max(2_000).optional(),
});

export const tenantInvite: CommandHandler<z.infer<typeof tenantCreateSchema>> = {
  payloadSchema: tenantCreateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireWorkspace(tx, db, actor, 'manageTenants');
    const ref = db.collection(COLLECTIONS.tenantRecords).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    requireAbsent(snapshot);
    tx.create(ref, { ...newAggregate(cmd.aggregateId!, now), landlordId: landlord.landlordId, inviteState: 'pending', ...cmd.payload });
    // The invite email is how the person learns the tenancy exists; the
    // record above is canonical, so the email job may retry independently.
    createJob(tx, db, `${cmd.commandId}_invite_email`, 'sendTenantInviteEmail', { tenantRecordId: cmd.aggregateId! }, now);
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: Object.keys(cmd.payload) };
  },
};

const tenantUpdateSchema = strictPayload({
  displayName: shortText.optional(),
  email: inviteEmail.optional(),
  phone: z.string().trim().min(7).max(32).optional(),
  tenantUserUid: idSchema.optional(),
  notes: z.string().trim().max(2_000).optional(),
}).refine((value) => Object.values(value).some((field) => field !== undefined));

export const tenantUpdate: CommandHandler<z.infer<typeof tenantUpdateSchema>> = {
  payloadSchema: tenantUpdateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireWorkspace(tx, db, actor, 'manageTenants');
    const ref = db.collection(COLLECTIONS.tenantRecords).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<Record<string, unknown> & { version: number }>(snapshot, cmd.expectedVersion);
    requireOwnedByLandlord(current, landlord.landlordId);
    const changes = Object.fromEntries(Object.entries(cmd.payload).filter(([, value]) => value !== undefined));
    tx.update(ref, { ...changes, ...bumpVersion(current, now) });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: current.version + 1, changedFields: Object.keys(changes) };
  },
};

const claimInviteSchema = strictPayload({});

/**
 * Executed by a signed-in user to claim tenant invitations addressed to their
 * verified email. Tenants never self-register: a landlord creates the tenant
 * record first (tenant.invite), and this command only links an auth account
 * whose token email matches. It is idempotent — zero matches is a success.
 */
export const tenantClaimInvite: CommandHandler<Record<string, never>> = {
  payloadSchema: claimInviteSchema,
  aggregateIdMode: 'forbidden',
  expectedVersionMode: 'none',
  async apply({ tx, db, actor, cmd, now }) {
    void cmd;
    if (!actor.emailVerified || !actor.email) {
      throw new DomainError('PERMISSION_DENIED', { reason: 'verifiedEmailRequired' });
    }
    const email = actor.email.toLowerCase();

    // All reads must complete before the first buffered write.
    const inviteSnap = await tx.get(
      db
        .collection(COLLECTIONS.tenantRecords)
        .where('email', '==', email)
        .where('inviteState', '==', 'pending')
        .limit(20),
    );
    const claimable = inviteSnap.docs.filter((doc) => {
      const record = doc.data() as { tenantUserUid?: string | null; isDeleted?: boolean };
      const linkedElsewhere =
        typeof record.tenantUserUid === 'string' && record.tenantUserUid !== actor.uid;
      return record.isDeleted !== true && !linkedElsewhere;
    });

    const leaseSnaps = await Promise.all(
      claimable.map((doc) =>
        tx.get(
          db
            .collection(COLLECTIONS.leases)
            .where('tenantRecordId', '==', doc.id)
            .limit(10),
        ),
      ),
    );
    const userRef = db.collection(COLLECTIONS.users).doc(actor.uid);
    const userSnap = await tx.get(userRef);
    const user = requireAggregate<{ version: number; role?: string }>(userSnap, undefined);

    let linkedLeases = 0;
    for (const doc of claimable) {
      const record = doc.data() as Record<string, unknown> & { version: number };
      tx.update(doc.ref, {
        tenantUserUid: actor.uid,
        inviteState: 'accepted',
        ...bumpVersion(record, now),
      });
    }
    for (const leaseSnap of leaseSnaps) {
      for (const leaseDoc of leaseSnap.docs) {
        const lease = leaseDoc.data() as Record<string, unknown> & {
          version: number;
          status: string;
          tenantUserUid?: string | null;
        };
        if (typeof lease.tenantUserUid === 'string' && lease.tenantUserUid !== actor.uid) continue;
        const nextLease = { ...lease, tenantUserUid: actor.uid, ...bumpVersion(lease, now) };
        tx.update(leaseDoc.ref, {
          tenantUserUid: actor.uid,
          ...bumpVersion(lease, now),
        });
        if (lease.status === 'active') {
          tx.set(
            db
              .collection(COLLECTIONS.tenantPortals)
              .doc(actor.uid)
              .collection(TENANT_PORTAL_SECTIONS.leases)
              .doc(leaseDoc.id),
            tenantLeaseProjection(nextLease),
          );
        }
        linkedLeases += 1;
      }
    }
    // Admins and landlords keep their primary role; the portal projection is
    // keyed by uid, so access still works for them.
    if (claimable.length > 0 && (user.role === 'client' || user.role === undefined)) {
      tx.update(userRef, { role: 'tenant', ...bumpVersion(user, now) });
    }
    return {
      status: 'applied',
      aggregateId: actor.uid,
      safeResult: { linkedRecords: claimable.length, linkedLeases },
      changedFields: claimable.length > 0 ? ['tenantUserUid', 'inviteState'] : [],
    };
  },
};

const tenancyEstablishSchema = strictPayload({
  unitId: idSchema,
  displayName: shortText,
  email: inviteEmail,
  phone: z.string().trim().min(7).max(32),
  startDate: z.string().datetime(),
  endDate: z.string().datetime(),
  monthlyRentMinor: nonNegativeMoney,
  depositMinor: nonNegativeMoney.optional(),
  openingBalanceMinor: nonNegativeMoney.optional(),
});

/** Derives the tenant record ID owned by a tenancy, so a retry rebuilds it. */
export function tenantRecordIdFor(tenancyId: string): string {
  return `${tenancyId}_tenant`;
}

/**
 * Establishes a whole tenancy in one transaction: the tenant record, an active
 * lease, the unit's occupancy flip, and an opening-balance invoice when the
 * landlord carried a debt forward.
 *
 * The Flutter client models a tenancy as a single aggregate (tenant identity +
 * lease + balance), so it can only produce one outbox entry and one idempotency
 * key for the whole act. Splitting that into tenant.invite -> lease.create ->
 * lease.activate on the client would mean three commands per entry, which the
 * at-least-once outbox contract cannot express safely. This composite keeps one
 * entry mapped to one command while the server still owns occupancy invariants.
 *
 * The lease ID is the client's tenancy ID; the tenant record hangs off it by a
 * derived ID so a replay after a lost response rebuilds the same two documents.
 */
export const tenancyEstablish: CommandHandler<z.infer<typeof tenancyEstablishSchema>> = {
  payloadSchema: tenancyEstablishSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireWorkspace(tx, db, actor, 'manageTenants');
    if (Date.parse(cmd.payload.startDate) >= Date.parse(cmd.payload.endDate)) {
      throw new DomainError('VALIDATION_FAILED', { fields: ['startDate', 'endDate'] });
    }
    const tenancyId = cmd.aggregateId!;
    const tenantRecordId = tenantRecordIdFor(tenancyId);
    const leaseRef = db.collection(COLLECTIONS.leases).doc(tenancyId);
    const tenantRef = db.collection(COLLECTIONS.tenantRecords).doc(tenantRecordId);
    const unitRef = db.collection(COLLECTIONS.units).doc(cmd.payload.unitId);
    const [leaseSnap, tenantSnap, unitSnap] = await Promise.all([
      tx.get(leaseRef),
      tx.get(tenantRef),
      tx.get(unitRef),
    ]);
    requireAbsent(leaseSnap);
    requireAbsent(tenantSnap);
    const unit = requireAggregate<{
      version: number;
      landlordId: string;
      occupancyStatus: string;
      propertyId: string;
      label?: string;
      activePublicListingId?: string | null;
    }>(unitSnap, undefined);
    requireOwnedByLandlord(unit, landlord.landlordId);
    if (unit.occupancyStatus !== 'vacant') {
      throw new DomainError('ALREADY_EXISTS', { reason: 'unitOccupied' });
    }
    // Read for the landlord projection's denormalized labels. Must happen
    // before the first write below: a transaction cannot read after it writes.
    const propertySnap = await tx.get(db.collection(COLLECTIONS.properties).doc(unit.propertyId));
    const property = requireAggregate<{ version: number; landlordId: string; name?: string }>(propertySnap, undefined);
    requireOwnedByLandlord(property, landlord.landlordId);
    const listingRetirement = await loadActiveListingRetirement(tx, db, unit);

    tx.create(tenantRef, {
      ...newAggregate(tenantRecordId, now),
      landlordId: landlord.landlordId,
      inviteState: 'pending',
      tenantUserUid: null,
      displayName: cmd.payload.displayName,
      email: cmd.payload.email,
      phone: cmd.payload.phone,
    });
    tx.create(leaseRef, {
      ...newAggregate(tenancyId, now),
      landlordId: landlord.landlordId,
      tenantRecordId,
      tenantUserUid: null,
      unitId: cmd.payload.unitId,
      startDate: cmd.payload.startDate,
      endDate: cmd.payload.endDate,
      monthlyRentMinor: cmd.payload.monthlyRentMinor,
      depositMinor: cmd.payload.depositMinor ?? 0,
      currency: 'UGX',
      status: 'active',
      activatedAt: now,
    });
    tx.update(unitRef, {
      occupancyStatus: 'occupied',
      activeLeaseId: tenancyId,
      ...(unit.activePublicListingId ? { activePublicListingId: null } : {}),
      ...bumpVersion(unit, now),
    });
    applyActiveListingRetirement(
      tx,
      db,
      landlord,
      listingRetirement,
      cmd.commandId,
      now,
    );
    createJob(tx, db, `${cmd.commandId}_invite_email`, 'sendTenantInviteEmail', { tenantRecordId }, now);

    // An opening balance is a real debt, so it becomes a real invoice rather
    // than a client-authored number. Everything downstream derives the
    // tenancy balance from open invoices, so this is what makes it settleable.
    const openingBalanceMinor = cmd.payload.openingBalanceMinor ?? 0;
    if (openingBalanceMinor > 0) {
      const invoiceId = openingInvoiceIdFor(tenancyId);
      const invoice = {
        ...newAggregate(invoiceId, now),
        landlordId: landlord.landlordId,
        leaseId: tenancyId,
        tenantUserUid: null,
        dueDate: cmd.payload.startDate,
        period: 'Opening balance',
        lineItems: [{ description: 'Balance carried forward', amountMinor: openingBalanceMinor }],
        memo: null,
        totalMinor: openingBalanceMinor,
        balanceMinor: openingBalanceMinor,
        currency: 'UGX',
        status: 'due',
      };
      tx.create(db.collection(COLLECTIONS.invoices).doc(invoiceId), invoice);
    }

    // The landlord read model. Without it, a landlord signing in on a second
    // device has no collection it can reconstruct a Tenancy from: the identity
    // lives on tenantRecords, the term on leases, and the labels on unit and
    // property.
    tx.set(
      db.collection(COLLECTIONS.landlordPortals).doc(landlord.landlordId)
        .collection(LANDLORD_PORTAL_SECTIONS.tenancies).doc(tenancyId),
      landlordTenancyProjection({
        leaseId: tenancyId,
        version: 1,
        landlordId: landlord.landlordId,
        tenantUserUid: null,
        propertyId: unit.propertyId,
        unitId: cmd.payload.unitId,
        tenantName: cmd.payload.displayName,
        email: cmd.payload.email,
        phone: cmd.payload.phone,
        unitLabel: unit.label ?? 'Unit',
        propertyName: property.name ?? 'Property',
        monthlyRentMinor: cmd.payload.monthlyRentMinor,
        balanceMinor: openingBalanceMinor,
        leaseStart: cmd.payload.startDate,
        leaseEnd: cmd.payload.endDate,
        status: 'active',
        createdAt: now,
        updatedAt: now,
      }),
    );

    return {
      status: 'applied',
      aggregateId: tenancyId,
      serverVersion: 1,
      safeResult: { tenantRecordId },
      changedFields: ['status', 'activatedAt', 'occupancyStatus'],
    };
  },
};

/** Opening-balance invoices use a derived ID so a replay cannot double-bill. */
export function openingInvoiceIdFor(tenancyId: string): string {
  return `${tenancyId}_opening`;
}

const leaseCreateSchema = strictPayload({
  unitId: idSchema,
  tenantRecordId: idSchema,
  startDate: z.string().datetime(),
  endDate: z.string().datetime(),
  monthlyRentMinor: nonNegativeMoney,
  depositMinor: nonNegativeMoney,
});

export const leaseCreate: CommandHandler<z.infer<typeof leaseCreateSchema>> = {
  payloadSchema: leaseCreateSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireWorkspace(tx, db, actor, 'manageTenants');
    if (Date.parse(cmd.payload.startDate) >= Date.parse(cmd.payload.endDate)) {
      throw new DomainError('VALIDATION_FAILED', { fields: ['startDate', 'endDate'] });
    }
    const leaseRef = db.collection(COLLECTIONS.leases).doc(cmd.aggregateId!);
    const unitRef = db.collection(COLLECTIONS.units).doc(cmd.payload.unitId);
    const tenantRef = db.collection(COLLECTIONS.tenantRecords).doc(cmd.payload.tenantRecordId);
    const [leaseSnap, unitSnap, tenantSnap] = await Promise.all([tx.get(leaseRef), tx.get(unitRef), tx.get(tenantRef)]);
    requireAbsent(leaseSnap);
    const unit = requireAggregate<Record<string, unknown> & { version: number }>(unitSnap, undefined);
    const tenant = requireAggregate<Record<string, unknown> & { version: number; tenantUserUid?: string }>(tenantSnap, undefined);
    requireOwnedByLandlord(unit, landlord.landlordId);
    requireOwnedByLandlord(tenant, landlord.landlordId);
    tx.create(leaseRef, {
      ...newAggregate(cmd.aggregateId!, now), landlordId: landlord.landlordId, status: 'draft', currency: 'UGX',
      tenantUserUid: tenant.tenantUserUid ?? null, ...cmd.payload,
    });
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: [...Object.keys(cmd.payload), 'status', 'currency'] };
  },
};

const empty = strictPayload({});

export const leaseActivate: CommandHandler<Record<string, never>> = {
  payloadSchema: empty,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireWorkspace(tx, db, actor, 'manageTenants');
    const leaseRef = db.collection(COLLECTIONS.leases).doc(cmd.aggregateId!);
    const leaseSnap = await tx.get(leaseRef);
    const lease = requireAggregate<Record<string, unknown> & { version: number; landlordId: string; unitId: string; status: string; tenantUserUid?: string | null }>(leaseSnap, cmd.expectedVersion);
    requireOwnedByLandlord(lease, landlord.landlordId);
    if (lease.status !== 'draft') throw new DomainError('VALIDATION_FAILED', { reason: 'leaseNotDraft' });
    const unitRef = db.collection(COLLECTIONS.units).doc(lease.unitId);
    const unitSnap = await tx.get(unitRef);
    const unit = requireAggregate<{
      version: number;
      landlordId: string;
      occupancyStatus: string;
      activePublicListingId?: string | null;
    }>(unitSnap, undefined);
    requireOwnedByLandlord(unit, landlord.landlordId);
    if (unit.occupancyStatus !== 'vacant') throw new DomainError('ALREADY_EXISTS', { reason: 'unitOccupied' });
    const listingRetirement = await loadActiveListingRetirement(tx, db, unit);
    const nextLease = { ...lease, status: 'active', activatedAt: now, ...bumpVersion(lease, now) };
    tx.update(leaseRef, { status: 'active', activatedAt: now, ...bumpVersion(lease, now) });
    tx.update(unitRef, {
      occupancyStatus: 'occupied',
      activeLeaseId: cmd.aggregateId!,
      ...(unit.activePublicListingId ? { activePublicListingId: null } : {}),
      ...bumpVersion(unit, now),
    });
    applyActiveListingRetirement(
      tx,
      db,
      landlord,
      listingRetirement,
      cmd.commandId,
      now,
    );
    if (lease.tenantUserUid) {
      tx.set(db.collection(COLLECTIONS.tenantPortals).doc(lease.tenantUserUid).collection(TENANT_PORTAL_SECTIONS.leases).doc(cmd.aggregateId!), tenantLeaseProjection(nextLease));
    }
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: lease.version + 1, changedFields: ['status', 'activatedAt'] };
  },
};

const leaseEndSchema = strictPayload({ reason: optionalShortText });

export const leaseEnd: CommandHandler<z.infer<typeof leaseEndSchema>> = {
  payloadSchema: leaseEndSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireWorkspace(tx, db, actor, 'manageTenants');
    const leaseRef = db.collection(COLLECTIONS.leases).doc(cmd.aggregateId!);
    const leaseSnap = await tx.get(leaseRef);
    const lease = requireAggregate<Record<string, unknown> & { version: number; landlordId: string; unitId: string; status: string; tenantUserUid?: string | null }>(leaseSnap, cmd.expectedVersion);
    requireOwnedByLandlord(lease, landlord.landlordId);
    if (lease.status !== 'active') throw new DomainError('VALIDATION_FAILED', { reason: 'leaseNotActive' });
    const unitRef = db.collection(COLLECTIONS.units).doc(lease.unitId);
    const unitSnap = await tx.get(unitRef);
    const unit = requireAggregate<{ version: number; landlordId: string }>(unitSnap, undefined);
    const nextLease = { ...lease, status: 'ended', endedAt: now, endReason: cmd.payload.reason ?? null, ...bumpVersion(lease, now) };
    tx.update(leaseRef, { status: 'ended', endedAt: now, endReason: cmd.payload.reason ?? null, ...bumpVersion(lease, now) });
    tx.update(unitRef, { occupancyStatus: 'vacant', activeLeaseId: null, ...bumpVersion(unit, now) });
    if (lease.tenantUserUid) {
      tx.set(db.collection(COLLECTIONS.tenantPortals).doc(lease.tenantUserUid).collection(TENANT_PORTAL_SECTIONS.leases).doc(cmd.aggregateId!), tenantLeaseProjection(nextLease));
    }
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: lease.version + 1, changedFields: ['status', 'endedAt', 'endReason'] };
  },
};
