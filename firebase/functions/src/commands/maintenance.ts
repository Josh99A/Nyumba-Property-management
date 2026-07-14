import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { requireActiveLandlord, requireOwnedByLandlord } from '../shared/accounts';
import { COLLECTIONS, TENANT_PORTAL_SECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import { idSchema, longText, shortText, strictPayload, type CommandHandler } from '../shared/handlers';

const createSchema = strictPayload({
  leaseId: idSchema.optional(),
  unitId: idSchema.optional(),
  title: shortText,
  description: longText,
  category: z.enum(['plumbing', 'electrical', 'structural', 'appliance', 'security', 'other']),
  priority: z.enum(['low', 'normal', 'high', 'urgent']),
  stagedAttachmentPaths: z.array(z.string().max(1_024)).max(10).default([]),
}).refine((value) => (value.leaseId === undefined) !== (value.unitId === undefined), {
  message: 'Exactly one of leaseId or unitId is required.',
});

export const maintenanceCreate: CommandHandler<z.infer<typeof createSchema>> = {
  payloadSchema: createSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const requestRef = db.collection(COLLECTIONS.maintenanceRequests).doc(cmd.aggregateId!);
    const requestSnap = await tx.get(requestRef);
    requireAbsent(requestSnap);

    let landlordId: string;
    let unitId: string;
    let tenantUserUid: string | null = null;
    let authorRole: 'tenant' | 'landlord';
    if (cmd.payload.leaseId) {
      const leaseSnap = await tx.get(db.collection(COLLECTIONS.leases).doc(cmd.payload.leaseId));
      const lease = requireAggregate<{ version: number; landlordId: string; unitId: string; tenantUserUid?: string | null; status: string }>(leaseSnap, undefined);
      if (lease.tenantUserUid !== actor.uid || lease.status !== 'active') throw new DomainError('PERMISSION_DENIED');
      landlordId = lease.landlordId;
      unitId = lease.unitId;
      tenantUserUid = actor.uid;
      authorRole = 'tenant';
    } else {
      const landlord = await requireActiveLandlord(tx, db, actor);
      const unitSnap = await tx.get(db.collection(COLLECTIONS.units).doc(cmd.payload.unitId!));
      const unit = requireAggregate<Record<string, unknown> & { version: number }>(unitSnap, undefined);
      requireOwnedByLandlord(unit, landlord.landlordId);
      landlordId = landlord.landlordId;
      unitId = cmd.payload.unitId!;
      authorRole = 'landlord';
    }
    if (cmd.payload.stagedAttachmentPaths.some((path) => !path.startsWith(`uploads/${actor.uid}/`))) {
      throw new DomainError('VALIDATION_FAILED', { fields: ['stagedAttachmentPaths'] });
    }
    const request = {
      ...newAggregate(cmd.aggregateId!, now), landlordId, unitId, leaseId: cmd.payload.leaseId ?? null,
      tenantUserUid, title: cmd.payload.title, description: cmd.payload.description,
      category: cmd.payload.category, priority: cmd.payload.priority, status: 'submitted',
      stagedAttachmentPaths: cmd.payload.stagedAttachmentPaths,
      comments: [{ id: `${cmd.commandId}_initial`, authorUid: actor.uid, authorRole, body: cmd.payload.description, createdAt: now }],
    };
    tx.create(requestRef, request);
    if (tenantUserUid) {
      tx.set(db.collection(COLLECTIONS.tenantPortals).doc(tenantUserUid).collection(TENANT_PORTAL_SECTIONS.maintenance).doc(cmd.aggregateId!), request);
    }
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: ['status', 'comments'] };
  },
};

const statusSchema = strictPayload({
  status: z.enum(['acknowledged', 'scheduled', 'in_progress', 'resolved', 'closed', 'canceled']),
  note: z.string().trim().max(1_000).optional(),
});

const transitions: Record<string, ReadonlySet<string>> = {
  submitted: new Set(['acknowledged', 'scheduled', 'canceled']),
  acknowledged: new Set(['scheduled', 'in_progress', 'resolved']),
  scheduled: new Set(['in_progress', 'resolved']),
  in_progress: new Set(['resolved']),
  resolved: new Set(['closed', 'in_progress']),
  closed: new Set(),
  canceled: new Set(),
};

export const maintenanceUpdateStatus: CommandHandler<z.infer<typeof statusSchema>> = {
  payloadSchema: statusSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.maintenanceRequests).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const request = requireAggregate<Record<string, unknown> & { version: number; landlordId: string; tenantUserUid?: string | null; status: string }>(snapshot, cmd.expectedVersion);
    const isTenant = request.tenantUserUid === actor.uid;
    if (isTenant) {
      if (request.status !== 'submitted' || cmd.payload.status !== 'canceled') throw new DomainError('PERMISSION_DENIED');
    } else {
      const landlord = await requireActiveLandlord(tx, db, actor);
      requireOwnedByLandlord(request, landlord.landlordId);
    }
    if (!transitions[request.status]?.has(cmd.payload.status)) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'invalidMaintenanceTransition' });
    }
    const changes = { status: cmd.payload.status, statusNote: cmd.payload.note ?? null, ...bumpVersion(request, now) };
    tx.update(ref, changes);
    if (request.tenantUserUid) {
      tx.set(db.collection(COLLECTIONS.tenantPortals).doc(request.tenantUserUid).collection(TENANT_PORTAL_SECTIONS.maintenance).doc(cmd.aggregateId!), { ...request, ...changes });
    }
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: request.version + 1, changedFields: ['status', 'statusNote'] };
  },
};

const commentSchema = strictPayload({ body: z.string().trim().min(1).max(2_000) });

export const maintenanceAddComment: CommandHandler<z.infer<typeof commentSchema>> = {
  payloadSchema: commentSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.maintenanceRequests).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const request = requireAggregate<Record<string, unknown> & { version: number; landlordId: string; tenantUserUid?: string | null; comments?: unknown[] }>(snapshot, cmd.expectedVersion);
    let authorRole: 'tenant' | 'landlord';
    if (request.tenantUserUid === actor.uid) authorRole = 'tenant';
    else {
      const landlord = await requireActiveLandlord(tx, db, actor);
      requireOwnedByLandlord(request, landlord.landlordId);
      authorRole = 'landlord';
    }
    const comments = request.comments ?? [];
    if (comments.length >= 100) throw new DomainError('VALIDATION_FAILED', { reason: 'commentLimitReached' });
    const nextComments = [...comments, { id: cmd.commandId, authorUid: actor.uid, authorRole, body: cmd.payload.body, createdAt: now }];
    const changes = { comments: nextComments, ...bumpVersion(request, now) };
    tx.update(ref, changes);
    if (request.tenantUserUid) {
      tx.set(db.collection(COLLECTIONS.tenantPortals).doc(request.tenantUserUid).collection(TENANT_PORTAL_SECTIONS.maintenance).doc(cmd.aggregateId!), { ...request, ...changes });
    }
    return { status: 'applied', aggregateId: cmd.aggregateId!, serverVersion: request.version + 1, changedFields: ['comments'] };
  },
};
