import { bumpVersion, requireAggregate } from '../shared/aggregates';
import { COLLECTIONS } from '../shared/collections';
import { DomainError } from '../shared/errors';
import { strictPayload, type CommandHandler } from '../shared/handlers';

/** Marks one server-owned inbox item read for the authenticated recipient. */
export const notificationMarkRead: CommandHandler<Record<string, never>> = {
  payloadSchema: strictPayload({}),
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db
      .collection(COLLECTIONS.notificationInboxes)
      .doc(actor.uid)
      .collection('items')
      .doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const current = requireAggregate<{
      version: number;
      recipientUid: string;
      isRead: boolean;
    }>(snapshot, undefined);

    // The UID-scoped path is the authorization boundary, but retaining and
    // checking the denormalized recipient makes malformed server data fail
    // closed instead of becoming readable through a misplaced document.
    if (current.recipientUid !== actor.uid) {
      throw new DomainError('PERMISSION_DENIED');
    }
    if (current.isRead) {
      return {
        status: 'applied',
        aggregateId: cmd.aggregateId!,
        serverVersion: current.version,
        changedFields: [],
      };
    }
    // A second device that already marked the item read is absorbed above.
    // Unread edits still use ordinary optimistic concurrency.
    requireAggregate(snapshot, cmd.expectedVersion);

    tx.update(ref, {
      isRead: true,
      readAt: now,
      ...bumpVersion(current, now),
    });
    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: current.version + 1,
      changedFields: ['isRead', 'readAt'],
    };
  },
};
