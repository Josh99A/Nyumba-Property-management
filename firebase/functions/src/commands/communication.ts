import { z } from 'zod';
import { newAggregate, requireAbsent } from '../shared/aggregates';
import { requireActiveLandlord } from '../shared/accounts';
import { COLLECTIONS } from '../shared/collections';
import { createJob, longText, shortText, strictPayload, type CommandHandler } from '../shared/handlers';

const noticeSchema = strictPayload({
  title: shortText,
  body: longText,
  audience: z.enum(['all_active_tenants', 'property', 'lease']),
  audienceId: z.string().regex(/^[A-Za-z0-9_-]{8,128}$/).optional(),
}).superRefine((value, context) => {
  if (value.audience !== 'all_active_tenants' && !value.audienceId) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['audienceId'], message: 'audienceId is required.' });
  }
});

export const noticePublish: CommandHandler<z.infer<typeof noticeSchema>> = {
  payloadSchema: noticeSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const landlord = await requireActiveLandlord(tx, db, actor);
    const ref = db.collection(COLLECTIONS.notices).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    requireAbsent(snapshot);
    tx.create(ref, {
      ...newAggregate(cmd.aggregateId!, now), landlordId: landlord.landlordId,
      ...cmd.payload, audienceId: cmd.payload.audienceId ?? null, publishState: 'pending', publishedAt: null,
    });
    createJob(tx, db, `${cmd.commandId}_fanout`, 'noticeFanout', { noticeId: cmd.aggregateId!, landlordId: landlord.landlordId }, now);
    return { status: 'accepted', aggregateId: cmd.aggregateId!, serverVersion: 1, changedFields: ['publishState'] };
  },
};
