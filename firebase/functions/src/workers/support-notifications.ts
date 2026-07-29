import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import type { DocumentSnapshot } from 'firebase-admin/firestore';
import { COLLECTIONS } from '../shared/collections';
import { SUPPORT_EMAIL } from '../shared/config';
import { APP_ORIGIN, buildEmailHtml, sendEmail } from '../shared/email';
import { deliverUserNotification } from '../shared/messaging';

/**
 * Support desk delivery.
 *
 * Administrator rights are Firebase Auth custom claims, which cannot be queried,
 * so `scripts/grant-admin.mjs` mirrors them into `platformStaff` purely so this
 * file has an audience to resolve. Both directions therefore use the same
 * inbox + push + courtesy email path the rest of the app uses.
 *
 * The mailbox send is kept regardless, and deliberately: the roster can be empty
 * on a project where the script has not been re-run, and an alert that reaches
 * nobody is indistinguishable from no tickets. Belt and braces is the right
 * trade for the one channel that carries "a paying customer is stuck".
 */

interface LoadedTicket {
  id: string;
  data: FirebaseFirestore.DocumentData;
}

/** Reads the canonical ticket, or null when there is nothing to announce. */
async function loadTicket(ticketId: string): Promise<LoadedTicket | null> {
  const db = getFirestore();
  const snapshot: DocumentSnapshot = await db
    .collection(COLLECTIONS.supportTickets)
    .doc(ticketId)
    .get();
  const data = snapshot.data();
  if (!snapshot.exists || !data || data.isDeleted === true) return null;
  return { id: snapshot.id, data };
}

function messageBody(data: FirebaseFirestore.DocumentData, messageId: string): string | null {
  const messages = Array.isArray(data.messages) ? data.messages : [];
  const match = messages.find(
    (entry): entry is { id: string; body: unknown } =>
      typeof entry === 'object' && entry !== null && (entry as { id?: unknown }).id === messageId,
  );
  return typeof match?.body === 'string' && match.body ? match.body : null;
}

function text(value: unknown, fallback = '—'): string {
  return typeof value === 'string' && value ? value : fallback;
}

/**
 * Everyone currently holding an administrator claim, per `platformStaff`.
 *
 * Empty is a legitimate answer, not an error: a project whose ops script has
 * not been re-run since the mirror was introduced has no rows yet. The caller
 * emails the mailbox either way, so an empty roster degrades to the Phase 1
 * behaviour rather than to silence.
 */
async function adminRecipients(): Promise<string[]> {
  const snapshot = await getFirestore().collection(COLLECTIONS.platformStaff).get();
  return snapshot.docs
    .map((doc) => doc.id)
    .filter((uid) => uid.length > 0);
}

/**
 * Announces a new ticket or a landlord's reply to the Nyumba team.
 *
 * Two channels on purpose. The in-app inbox reaches each administrator where
 * they already work and carries a push nudge; the mailbox email is kept
 * unconditionally because the roster can be empty and an alert that reaches
 * nobody is indistinguishable from no tickets at all. Duplication is the right
 * trade for the one channel that carries "a paying customer is stuck".
 *
 * The email includes the whole message: an alert that only says "someone wrote
 * to you" costs the reader a round trip into the console before they can even
 * tell whether it is urgent, and the mailbox is internal, so there is no
 * disclosure concern in doing so.
 */
export async function notifySupportTeam(payload: Record<string, unknown>): Promise<void> {
  const ticketId = String(payload.ticketId);
  const messageId = String(payload.messageId);
  const ticket = await loadTicket(ticketId);
  if (!ticket) return;
  const body = messageBody(ticket.data, messageId);
  // A message that is no longer on the ticket was superseded or never landed;
  // either way there is nothing to announce and retrying will not change it.
  if (!body) return;

  const subject = text(ticket.data.subject, 'Support request');
  const isFirstMessage = messageId.endsWith('_initial');

  // Bounded concurrency, like the broadcast fanout: a burst of tickets must not
  // serialize one FCM round trip per administrator, nor fire without limit.
  const recipients = await adminRecipients();
  for (let start = 0; start < recipients.length; start += 10) {
    await Promise.all(
      recipients.slice(start, start + 10).map((uid) =>
        deliverUserNotification(uid, {
          // Keyed by message so a second question on the same thread is a
          // second thing to hear about, while a retried job is not.
          id: `support_team_${messageId}`,
          kind: 'system',
          templateKey: 'support_new_ticket',
          relatedEntityId: ticketId,
          data: { route: `/admin/support/${ticketId}`, ticketId },
        }),
      ),
    );
  }

  await sendEmail({
    to: SUPPORT_EMAIL,
    subject: `[${text(ticket.data.priority, 'normal')}] ${
      isFirstMessage ? 'New support ticket' : 'Landlord replied'
    }: ${subject}`,
    idempotencyKey: `support_team_${ticketId}_${messageId}`,
    html: buildEmailHtml({
      heading: subject,
      paragraphs: body.split(/\n+/).map((line) => line.trim()).filter(Boolean),
      rows: [
        { label: 'From', value: text(ticket.data.landlordName) },
        { label: 'Email', value: text(ticket.data.landlordEmail) },
        { label: 'Category', value: text(ticket.data.category) },
        { label: 'Plan', value: text(ticket.data.planTier, 'none') },
        { label: 'Subscription', value: text(ticket.data.subscriptionStatus) },
        { label: 'Account', value: text(ticket.data.approvalStatus) },
        {
          label: 'Client',
          value: `${text(ticket.data.platform)} ${text(ticket.data.appVersion)}`,
        },
      ],
      cta: {
        label: 'Open in Nyumba admin',
        url: new URL(`/admin/support/${ticketId}`, APP_ORIGIN).href,
      },
    }),
  });
}

/** Tells the landlord an agent answered: inbox item, push nudge, courtesy email. */
export async function notifyLandlordSupportReply(
  payload: Record<string, unknown>,
): Promise<void> {
  const ticketId = String(payload.ticketId);
  const messageId = String(payload.messageId);
  const ticket = await loadTicket(ticketId);
  if (!ticket) return;
  const landlordId = typeof ticket.data.landlordId === 'string' ? ticket.data.landlordId : null;
  if (!landlordId) return;
  const body = messageBody(ticket.data, messageId);
  if (!body) return;

  const subject = text(ticket.data.subject, 'your support request');
  const route = `/support/${ticketId}`;
  await deliverUserNotification(landlordId, {
    // Keyed by message, not by ticket: a second reply on the same thread is a
    // second thing to hear about, unlike a retried job on the same message.
    id: `support_reply_${messageId}`,
    kind: 'system',
    templateKey: 'support_reply',
    relatedEntityId: ticketId,
    data: { route, ticketId },
  });

  const email = typeof ticket.data.landlordEmail === 'string' ? ticket.data.landlordEmail : null;
  if (!email) return;
  await sendEmail({
    to: email,
    subject: `Re: ${subject}`,
    idempotencyKey: `support_reply_${ticketId}_${messageId}`,
    html: buildEmailHtml({
      recipientName: typeof ticket.data.landlordName === 'string' ? ticket.data.landlordName : null,
      heading: 'Nyumba support replied',
      paragraphs: [
        ...body.split(/\n+/).map((line) => line.trim()).filter(Boolean),
        'Reply in the app and we will pick it up on the same conversation.',
      ],
      cta: { label: 'Open the conversation', url: new URL(route, APP_ORIGIN).href },
    }),
  });
}

/**
 * Tells the landlord their request was resolved without a reply attached.
 *
 * `support.updateStatus` only enqueues this when the resolution is itself the
 * news — an agent who answered and then resolved has already been announced by
 * that answer.
 */
export async function notifyLandlordSupportStatus(
  payload: Record<string, unknown>,
): Promise<void> {
  const ticketId = String(payload.ticketId);
  const ticket = await loadTicket(ticketId);
  if (!ticket) return;
  // Re-read rather than trust the payload: a ticket reopened between the command
  // and this job must not be announced as resolved.
  if (ticket.data.status !== 'resolved') return;
  const landlordId = typeof ticket.data.landlordId === 'string' ? ticket.data.landlordId : null;
  if (!landlordId) return;

  const resolvedAt = ticket.data.resolvedAt;
  const stamp = resolvedAt instanceof Timestamp ? resolvedAt.toMillis() : 0;
  await deliverUserNotification(landlordId, {
    id: `support_resolved_${ticketId}_${stamp}`,
    kind: 'system',
    templateKey: 'support_resolved',
    relatedEntityId: ticketId,
    data: { route: `/support/${ticketId}`, ticketId },
  });
}
