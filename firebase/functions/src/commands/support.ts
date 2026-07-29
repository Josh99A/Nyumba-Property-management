import { Timestamp } from 'firebase-admin/firestore';
import { z } from 'zod';
import { bumpVersion, newAggregate, requireAbsent, requireAggregate } from '../shared/aggregates';
import type { LandlordAccount, Subscription } from '../shared/accounts';
import { requirePlatformAdmin } from '../shared/actor';
import { COLLECTIONS } from '../shared/collections';
import {
  SUPPORT_MAX_ATTACHMENTS,
  SUPPORT_MAX_MESSAGES,
  SUPPORT_MAX_OPEN_TICKETS,
  SUPPORT_OPEN_COOLDOWN_SECONDS,
  SUPPORT_REOPEN_WINDOW_DAYS,
  SUPPORT_REPLY_COOLDOWN_SECONDS,
} from '../shared/config';
import { DomainError } from '../shared/errors';
import {
  createJob,
  longText,
  rejectIfWithin,
  shortText,
  strictPayload,
  type CommandHandler,
} from '../shared/handlers';

/**
 * Landlord ↔ Nyumba support conversations.
 *
 * Deliberately separate from `feedback.ts`. Feedback is one-way telemetry the
 * author never reads back; a support ticket is a conversation the landlord is
 * waiting on an answer to, so it carries a status, a reply path, and an
 * ordering that says who is holding the ball. Sharing an aggregate between the
 * two would have given feedback a lifecycle it does not have and support a
 * silence it cannot afford.
 *
 * Also separate from `communication.ts`: notices and broadcasts are one-way
 * announcements with a fanout, not a thread with two authors.
 */

export type SupportStatus =
  | 'open'
  | 'in_progress'
  | 'awaiting_landlord'
  | 'resolved'
  | 'closed';

type SupportAuthorRole = 'landlord' | 'support';

interface SupportMessage {
  id: string;
  authorUid: string;
  authorRole: SupportAuthorRole;
  body: string;
  attachmentPaths: string[];
  createdAt: Timestamp;
}

interface SupportTicket {
  version: number;
  landlordId: string;
  status: SupportStatus;
  messages?: SupportMessage[];
  lastMessageAuthorRole?: SupportAuthorRole;
  firstResponseAt?: Timestamp | null;
  resolvedAt?: Timestamp | null;
}

/**
 * The support cadence timestamps live on `landlordAccounts` for the same reason
 * the feedback ones do — a cooldown tracked on the device resets on reinstall —
 * but neither is part of that document's modelled shape. A local extension keeps
 * the scoping visible instead of widening `LandlordAccount` for a concern only
 * this file reads and writes.
 */
interface SupportCadence {
  lastSupportOpenedAt?: Timestamp;
  lastSupportRepliedAt?: Timestamp;
}

/**
 * A ticket is terminal once it needs nothing further from either side. Stored
 * rather than derived because the open-ticket cap below is a Firestore query,
 * and a single equality filter beats an `in` over the non-terminal statuses.
 */
function isTerminalStatus(status: SupportStatus): boolean {
  return status === 'resolved' || status === 'closed';
}

const TRANSITIONS: Record<SupportStatus, ReadonlySet<SupportStatus>> = {
  open: new Set<SupportStatus>(['in_progress', 'awaiting_landlord', 'closed']),
  in_progress: new Set<SupportStatus>(['awaiting_landlord', 'resolved', 'closed']),
  awaiting_landlord: new Set<SupportStatus>(['in_progress', 'resolved', 'closed']),
  // Reopening is a real transition, not a new ticket: the history is the point.
  resolved: new Set<SupportStatus>(['in_progress', 'closed']),
  closed: new Set<SupportStatus>(),
};

const CATEGORIES = [
  'billing',
  'payments',
  'tenants',
  'listings',
  'account',
  'other',
] as const;

const attachmentPaths = z
  .array(z.string().max(1_024))
  .max(SUPPORT_MAX_ATTACHMENTS)
  .default([]);

/** Staged uploads must live under the actor's own prefix, as in `maintenance.ts`. */
function requireOwnedUploads(paths: string[], uid: string): void {
  if (paths.some((path) => !path.startsWith(`uploads/${uid}/`))) {
    throw new DomainError('VALIDATION_FAILED', { fields: ['stagedAttachmentPaths'] });
  }
}

const openSchema = strictPayload({
  subject: shortText,
  category: z.enum(CATEGORIES),
  body: longText,
  stagedAttachmentPaths: attachmentPaths,
  appVersion: shortText,
  platform: z.enum(['android', 'ios', 'web']),
});

/**
 * Opens a conversation with the Nyumba team.
 *
 * Note what this does NOT require: an approved account or an active
 * subscription. `requireActiveLandlord` would have been the obvious gate and is
 * exactly wrong here — it rejects `past_due`, `pending_payment` and suspended
 * accounts, which is the precise set of landlords who most need to reach a
 * human. A support channel that closes when billing breaks is a support channel
 * that is shut on the day it matters. The gate is therefore: a live user account
 * and a landlord account that exists. Approval and subscription state are
 * recorded on the ticket instead, where they are context for whoever answers.
 */
export const supportOpen: CommandHandler<z.infer<typeof openSchema>> = {
  payloadSchema: openSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'create',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.supportTickets).doc(cmd.aggregateId!);
    const accountRef = db.collection(COLLECTIONS.landlordAccounts).doc(actor.uid);
    // Every read first, as every handler in this directory does.
    const [snapshot, userSnap, accountSnap, subscriptionSnap, openTickets] = await Promise.all([
      tx.get(ref),
      tx.get(db.collection(COLLECTIONS.users).doc(actor.uid)),
      tx.get(accountRef),
      tx.get(db.collection(COLLECTIONS.subscriptions).doc(actor.uid)),
      tx.get(
        db
          .collection(COLLECTIONS.supportTickets)
          .where('landlordId', '==', actor.uid)
          .where('isTerminal', '==', false)
          .limit(SUPPORT_MAX_OPEN_TICKETS),
      ),
    ]);
    requireAbsent(snapshot);

    // The user document is read here rather than through `requireActiveAccount`
    // because the denormalized fields below need it anyway; a second helper call
    // would read the same document twice for the same answer.
    const user = userSnap.data();
    if (!userSnap.exists || !user || user.status !== 'active' || user.isDeleted === true) {
      throw new DomainError('PERMISSION_DENIED');
    }
    const account = accountSnap.data() as (LandlordAccount & SupportCadence) | undefined;
    if (!accountSnap.exists || !account) throw new DomainError('PERMISSION_DENIED');

    rejectIfWithin(account.lastSupportOpenedAt, SUPPORT_OPEN_COOLDOWN_SECONDS * 1_000, now);
    if (openTickets.size >= SUPPORT_MAX_OPEN_TICKETS) {
      throw new DomainError('VALIDATION_FAILED', {
        reason: 'tooManyOpenTickets',
        limit: SUPPORT_MAX_OPEN_TICKETS,
      });
    }
    requireOwnedUploads(cmd.payload.stagedAttachmentPaths, actor.uid);

    const subscription = subscriptionSnap.data() as Subscription | undefined;
    const subscriptionStatus = subscription?.status ?? 'none';
    const approvalStatus = account.approvalStatus ?? 'pending';

    // Priority is derived, never sent. A client-chosen priority is a field where
    // everyone picks urgent; the two things that genuinely cannot wait are money
    // and being locked out, and the server can see both without being told.
    const blocked = approvalStatus !== 'approved' || subscriptionStatus !== 'active';
    const priority =
      blocked || cmd.payload.category === 'billing' || cmd.payload.category === 'account'
        ? 'high'
        : 'normal';

    const message: SupportMessage = {
      id: `${cmd.commandId}_initial`,
      authorUid: actor.uid,
      authorRole: 'landlord',
      body: cmd.payload.body,
      attachmentPaths: cmd.payload.stagedAttachmentPaths,
      createdAt: now,
    };
    tx.create(ref, {
      ...newAggregate(cmd.aggregateId!, now),
      landlordId: actor.uid,
      // Distinct from `landlordId` so opening on someone else's behalf (a staff
      // seat, an admin filing on a phone call) needs no schema change later.
      openedByUid: actor.uid,
      subject: cmd.payload.subject,
      category: cmd.payload.category,
      status: 'open' satisfies SupportStatus,
      isTerminal: false,
      priority,
      messages: [message],
      lastMessageAt: now,
      // Whoever is holding the ball, denormalized so both queues can be built
      // without reading every thread's message array.
      lastMessageAuthorRole: 'landlord' satisfies SupportAuthorRole,
      firstResponseAt: null,
      resolvedAt: null,
      closedAt: null,
      // Denormalized at open time, for the same reason platformFeedback carries
      // the tier: joining `subscriptions` a week later reads whatever they moved
      // *to*, which is precisely the value that would mislead whoever answers.
      landlordName: typeof user.displayName === 'string' ? user.displayName : null,
      landlordEmail: typeof user.email === 'string' ? user.email : null,
      planTier: subscription?.tier ?? null,
      subscriptionStatus,
      approvalStatus,
      appVersion: cmd.payload.appVersion,
      platform: cmd.payload.platform,
      locale: typeof user.locale === 'string' ? user.locale : null,
    });
    tx.update(accountRef, { lastSupportOpenedAt: now });
    createJob(
      tx,
      db,
      `${cmd.commandId}_support_alert`,
      'notifySupportTeam',
      { ticketId: cmd.aggregateId!, messageId: message.id },
      now,
    );

    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: 1,
      changedFields: ['status', 'messages'],
    };
  },
};

const replySchema = strictPayload({
  body: z.string().trim().min(1).max(2_000),
  stagedAttachmentPaths: attachmentPaths,
});

/**
 * Appends a message from either side.
 *
 * Replying also moves the status, so an agent who only ever types still leaves a
 * correct queue behind them and a landlord never has to set a state to have a
 * conversation. A landlord replying to a `resolved` ticket reopens it: the
 * honest reading of someone answering a resolution is that it was not resolved.
 */
export const supportReply: CommandHandler<z.infer<typeof replySchema>> = {
  payloadSchema: replySchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.supportTickets).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const ticket = requireAggregate<SupportTicket>(snapshot, cmd.expectedVersion);

    // Which document to read next depends on who this is, so this read cannot
    // join the batch above. Still a read, and still before every write.
    const isLandlord = ticket.landlordId === actor.uid;
    const accountRef = db.collection(COLLECTIONS.landlordAccounts).doc(actor.uid);
    if (isLandlord) {
      const accountSnap = await tx.get(accountRef);
      const account = accountSnap.data() as (LandlordAccount & SupportCadence) | undefined;
      if (!accountSnap.exists || !account) throw new DomainError('PERMISSION_DENIED');
      rejectIfWithin(account.lastSupportRepliedAt, SUPPORT_REPLY_COOLDOWN_SECONDS * 1_000, now);
    } else {
      requirePlatformAdmin(actor);
    }

    if (ticket.status === 'closed') {
      throw new DomainError('VALIDATION_FAILED', { reason: 'supportTicketClosed' });
    }
    const messages = ticket.messages ?? [];
    if (messages.length >= SUPPORT_MAX_MESSAGES) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'supportMessageLimitReached' });
    }
    requireOwnedUploads(cmd.payload.stagedAttachmentPaths, actor.uid);

    const authorRole: SupportAuthorRole = isLandlord ? 'landlord' : 'support';
    const status: SupportStatus = isLandlord
      ? ticket.status === 'open'
        ? 'open'
        : 'in_progress'
      : 'awaiting_landlord';
    const message: SupportMessage = {
      id: cmd.commandId,
      authorUid: actor.uid,
      authorRole,
      body: cmd.payload.body,
      attachmentPaths: cmd.payload.stagedAttachmentPaths,
      createdAt: now,
    };
    const changes = {
      messages: [...messages, message],
      status,
      isTerminal: isTerminalStatus(status),
      lastMessageAt: now,
      lastMessageAuthorRole: authorRole,
      // The one number worth measuring this desk by, and it can only be set
      // once — a later reply must not overwrite how long the first one took.
      ...(authorRole === 'support' && !ticket.firstResponseAt
        ? { firstResponseAt: now }
        : {}),
      ...bumpVersion(ticket, now),
    };
    tx.update(ref, changes);
    if (isLandlord) tx.update(accountRef, { lastSupportRepliedAt: now });

    // Exactly one direction per reply: nobody is notified about their own
    // message, and the two job types never both fire. Written as two calls with
    // literal type names rather than one call with a conditional, because
    // job-registry.test.ts reads the type out of the source — a computed type is
    // invisible to it and would reach production unregistered.
    const notifyId = `${cmd.commandId}_support_notify`;
    const notifyPayload = { ticketId: cmd.aggregateId!, messageId: message.id };
    if (isLandlord) {
      createJob(tx, db, notifyId, 'notifySupportTeam', notifyPayload, now);
    } else {
      createJob(tx, db, notifyId, 'notifyLandlordSupportReply', notifyPayload, now);
    }

    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: ticket.version + 1,
      changedFields: ['messages', 'status'],
    };
  },
};

const statusSchema = strictPayload({
  // `open` is absent on purpose: nothing transitions back to it. A reopened
  // ticket goes to `in_progress`, which is what is actually true of it.
  status: z.enum(['in_progress', 'awaiting_landlord', 'resolved', 'closed']),
  note: z.string().trim().max(1_000).optional(),
});

/**
 * Moves a ticket through its lifecycle. Administrators drive this; a landlord
 * gets exactly two of the transitions, and both are ones they are entitled to
 * make about their own request — closing it because it sorted itself out, and
 * reopening a resolution that did not hold.
 */
export const supportUpdateStatus: CommandHandler<z.infer<typeof statusSchema>> = {
  payloadSchema: statusSchema,
  aggregateIdMode: 'required',
  expectedVersionMode: 'edit',
  async apply({ tx, db, actor, cmd, now }) {
    const ref = db.collection(COLLECTIONS.supportTickets).doc(cmd.aggregateId!);
    const snapshot = await tx.get(ref);
    const ticket = requireAggregate<SupportTicket>(snapshot, cmd.expectedVersion);
    const next = cmd.payload.status;

    const isLandlord = ticket.landlordId === actor.uid;
    if (isLandlord) {
      const reopenDeadline =
        ticket.resolvedAt instanceof Timestamp
          ? ticket.resolvedAt.toMillis() + SUPPORT_REOPEN_WINDOW_DAYS * 24 * 60 * 60 * 1_000
          : 0;
      const mayReopen =
        next === 'in_progress'
        && ticket.status === 'resolved'
        && now.toMillis() <= reopenDeadline;
      if (next !== 'closed' && !mayReopen) throw new DomainError('PERMISSION_DENIED');
    } else {
      requirePlatformAdmin(actor);
    }

    if (!TRANSITIONS[ticket.status]?.has(next)) {
      throw new DomainError('VALIDATION_FAILED', { reason: 'invalidSupportTransition' });
    }

    const changes = {
      status: next,
      isTerminal: isTerminalStatus(next),
      statusNote: cmd.payload.note ?? null,
      ...(next === 'resolved' ? { resolvedAt: now } : {}),
      ...(next === 'closed' ? { closedAt: now } : {}),
      ...bumpVersion(ticket, now),
    };
    tx.update(ref, changes);

    // Only when the resolution is itself the news. An agent who replies and then
    // marks it resolved has already been announced by that reply; a second push
    // moments later is noise, and noise is how people mute the channel that
    // carries their rent reminders.
    if (!isLandlord && next === 'resolved' && ticket.lastMessageAuthorRole !== 'support') {
      createJob(
        tx,
        db,
        `${cmd.commandId}_support_status`,
        'notifyLandlordSupportStatus',
        { ticketId: cmd.aggregateId! },
        now,
      );
    }

    return {
      status: 'applied',
      aggregateId: cmd.aggregateId!,
      serverVersion: ticket.version + 1,
      changedFields: ['status', 'statusNote'],
    };
  },
};
