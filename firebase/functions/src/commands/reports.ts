import { z } from 'zod';
import { newAggregate, requireAbsent } from '../shared/aggregates';
import { requireActiveLandlord } from '../shared/accounts';
import { COLLECTIONS } from '../shared/collections';
import { createJob, strictPayload, type CommandHandler } from '../shared/handlers';

const reportSchema = strictPayload({
  reportType: z.enum(['rent_roll', 'arrears', 'occupancy', 'payments', 'maintenance']),
  from: z.string().datetime(),
  to: z.string().datetime(),
  format: z.enum(['pdf', 'csv']),
});

export const reportRequest: CommandHandler<z.infer<typeof reportSchema>> = {
  payloadSchema: reportSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const ref = db.collection(COLLECTIONS.reportSnapshots).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    requireAbsent(snapshot);
    const report = {
      ...newAggregate(cmd.aggregateId!, now), landlordId: landlord.landlordId,
      // firestore.rules ownsReport() authorizes reads on ownerType/ownerId.
      ownerType: 'landlord', ownerId: landlord.landlordId,
      requestedByUid: actor.uid, ...cmd.payload, state: 'queued', downloadPath: null,
    };
    tx.create(ref, report);
    createJob(tx, db, `${cmd.commandId}_report`, 'generateReport', { reportId: cmd.aggregateId!, landlordId: landlord.landlordId }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: ['state'] };
  },
};
