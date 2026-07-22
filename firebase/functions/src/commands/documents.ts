import { Timestamp } from 'firebase-admin/firestore';
import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import { requireOwnedByLandlord, requireWorkspace } from '../shared/accounts';
import { COLLECTIONS } from '../shared/collections';
import { MAX_DOCUMENT_BYTES, MAX_IMAGE_BYTES } from '../shared/config';
import { DomainError } from '../shared/errors';
import { createJob, idSchema, shortText, strictPayload, type CommandHandler } from '../shared/handlers';

const contentTypes = ['application/pdf', 'image/jpeg', 'image/png'] as const;
const uploadSchema = strictPayload({
  ownerType: z.enum(['property', 'unit', 'lease', 'maintenance']),
  ownerId: idSchema,
  storagePath: z.string().min(1).max(1_024),
  fileName: shortText,
  contentType: z.enum(contentTypes),
  byteSize: z.number().int().positive(),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
});

const ownerCollections: Record<z.infer<typeof uploadSchema>['ownerType'], string> = {
  property: COLLECTIONS.properties,
  unit: COLLECTIONS.units,
  lease: COLLECTIONS.leases,
  maintenance: COLLECTIONS.maintenanceRequests,
};

export const documentFinalizeUpload: CommandHandler<z.infer<typeof uploadSchema>> = {
  payloadSchema: uploadSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const expectedPrefix = `uploads/${actor.uid}/${cmd.commandId}/`;
    if (!cmd.payload.storagePath.startsWith(expectedPrefix)) {
      throw new DomainError('VALIDATION_FAILED', { fields: ['storagePath'] });
    }
    const limit = cmd.payload.contentType === 'application/pdf' ? MAX_DOCUMENT_BYTES : MAX_IMAGE_BYTES;
    if (cmd.payload.byteSize > limit) throw new DomainError('VALIDATION_FAILED', { fields: ['byteSize'] });
    const documentRef = db.collection(COLLECTIONS.documents).doc(cmd.aggregateId!);
    const ownerRef = db.collection(ownerCollections[cmd.payload.ownerType]).doc(cmd.payload.ownerId);
    const [documentSnap, ownerSnap] = await Promise.all([tx.get(documentRef), tx.get(ownerRef)]);
    requireAbsent(documentSnap);
    const owner = requireAggregate<Record<string, unknown> & { version: number; landlordId?: string; tenantUserUid?: string | null }>(ownerSnap, undefined);
    let landlordId: string;
    if (owner.tenantUserUid === actor.uid) {
      landlordId = owner.landlordId as string;
    } else {
      const landlord = await requireWorkspace(tx, db, actor, 'manageDocuments');
      requireOwnedByLandlord(owner, landlord.landlordId);
      landlordId = landlord.landlordId;
    }
    const document = {
      ...newAggregate(cmd.aggregateId!, now), landlordId, uploadedByUid: actor.uid,
      ownerType: cmd.payload.ownerType, ownerId: cmd.payload.ownerId, storagePath: cmd.payload.storagePath,
      fileName: cmd.payload.fileName, contentType: cmd.payload.contentType, byteSize: cmd.payload.byteSize,
      sha256: cmd.payload.sha256, state: 'pending', privatePath: null,
    };
    tx.create(documentRef, document);
    createJob(tx, db, `${cmd.commandId}_move`, 'movePrivateDocument', { documentId: cmd.aggregateId!, landlordId, sourcePath: cmd.payload.storagePath }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: ['state', 'storagePath'] };
  },
};

export const documentDelete: CommandHandler<Record<string, never>> = {
  payloadSchema: strictPayload({}),
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.documents).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const document = requireAggregate<{ version: number; landlordId: string; uploadedByUid: string }>(snapshot, cmd.expectedVersion);
    if (document.uploadedByUid !== actor.uid) {
      const landlord = await requireWorkspace(tx, db, actor, 'manageDocuments');
      requireOwnedByLandlord(document, landlord.landlordId);
    }
    const purgeAt = Timestamp.fromMillis(now.toMillis() + 90 * 24 * 60 * 60 * 1000);
    tx.update(ref, { isDeleted: true, deletedAt: now, purgeAt, state: 'deleted', ...bumpVersion(document, now) });
    createJob(tx, db, `${cmd.commandId}_purge`, 'purgeDocument', { documentId: cmd.aggregateId!, purgeAt: purgeAt.toDate().toISOString() }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: document.version + 1, changedFields: ['isDeleted', 'deletedAt', 'purgeAt', 'state'] };
  },
};
