import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { COLLECTIONS } from '../shared/collections';
import { SUBSCRIPTION_GRACE_DAYS } from '../shared/config';
import { APP_ORIGIN, buildEmailHtml, sendEmail } from '../shared/email';
import { deliverUserNotification } from '../shared/messaging';

/**
 * Every subscription-lifecycle message a landlord can receive.
 *
 * One worker rather than one per message: they share a recipient, a layout,
 * and the same re-read-at-send-time rule, and a single job type keeps the
 * command handlers and the renewal sweep from each growing their own.
 */
export type SubscriptionNoticeKind =
  | 'activated'
  | 'renewal_due'
  | 'grace_started'
  | 'grace_ending'
  | 'expired'
  | 'payment_rejected'
  | 'downgraded'
  | 'deactivated';

const REJECTION_REASONS: Record<string, string> = {
  PAYMENT_NOT_RECEIVED: 'we could not find the payment',
  AMOUNT_INCORRECT: 'the amount did not match the plan price',
  REFERENCE_INVALID: 'the payment reference could not be matched',
  DUPLICATE_REQUEST: 'this request duplicated another one',
  ADMIN_CORRECTION: 'of an account correction',
};

function dayLabel(value: unknown): string | null {
  if (!(value instanceof Timestamp)) return null;
  return value.toDate().toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'Africa/Kampala',
  });
}

/**
 * Sends one subscription notice by email and to the in-app inbox.
 *
 * The subscription is re-read here rather than trusted from the payload, so a
 * landlord who paid between the sweep and the send is not warned about a
 * deadline that no longer exists. Each kind states what changed, what it means
 * for their tenants, and what to do next.
 */
export async function sendSubscriptionNoticeEmail(
  payload: Record<string, unknown>,
): Promise<void> {
  const db = getFirestore();
  const landlordId = String(payload.landlordId);
  const kind = String(payload.kind) as SubscriptionNoticeKind;
  const [subscriptionSnap, recipient] = await Promise.all([
    db.collection(COLLECTIONS.subscriptions).doc(landlordId).get(),
    landlordContact(db, landlordId),
  ]);
  const subscription = subscriptionSnap.data();
  if (!subscription) return;

  // Deadline warnings are only true while the subscription is still active and
  // still overdue; a settled account must never receive them.
  const stillDue = subscription.status === 'active';
  if ((kind === 'renewal_due' || kind === 'grace_started' || kind === 'grace_ending') && !stillDue) {
    return;
  }
  if (kind === 'expired' && subscription.status !== 'expired') return;

  const renewalDue = dayLabel(subscription.renewalDueAt);
  const graceEnds = dayLabel(subscription.graceEndsAt);
  const tier = String(subscription.tier ?? 'your plan');
  const content = noticeContent(kind, {
    tier,
    renewalDue,
    graceEnds,
    reasonCode: typeof payload.reasonCode === 'string' ? payload.reasonCode : null,
    note: typeof payload.note === 'string' ? payload.note : null,
  });
  if (!content) return;

  if (recipient?.email) {
    await sendEmail({
      to: recipient.email,
      subject: content.subject,
      // Keyed by the milestone, not the job, so a retry cannot double-send but
      // a genuinely new milestone still goes out.
      idempotencyKey: `subscription_${kind}_${landlordId}_${content.milestone}`,
      html: buildEmailHtml({
        recipientName: recipient.name,
        heading: content.heading,
        paragraphs: content.paragraphs,
        cta: { label: 'Open your subscription', url: `${APP_ORIGIN}/subscription` },
      }),
    });
  }
  await deliverUserNotification(landlordId, {
    id: `subscription_${kind}_${landlordId}_${content.milestone}`,
    kind: 'system',
    custom: { title: content.heading, body: content.paragraphs[0] ?? content.subject },
    relatedEntityId: landlordId,
    data: { route: '/subscription' },
  });
}

interface NoticeFacts {
  tier: string;
  renewalDue: string | null;
  graceEnds: string | null;
  reasonCode: string | null;
  note: string | null;
}

interface RenderedNotice {
  subject: string;
  heading: string;
  paragraphs: string[];
  /** Distinguishes one deadline from the next in the idempotency key. */
  milestone: string;
}

function noticeContent(
  kind: SubscriptionNoticeKind,
  facts: NoticeFacts,
): RenderedNotice | null {
  const tenantsSafe =
    'Your tenants are not affected — they keep their portal, balances, '
    + 'receipts and documents throughout.';
  switch (kind) {
    case 'activated':
      return {
        subject: 'Your Nyumba subscription is confirmed',
        heading: 'Your payment is confirmed — your workspace is open',
        paragraphs: [
          `We have confirmed payment for your ${facts.tier} plan.`,
          'You can sign back in now and enter your workspace — no further action is needed.',
        ],
        milestone: facts.tier,
      };
    case 'renewal_due':
      return {
        subject: 'Your Nyumba subscription renews soon',
        heading: 'Your subscription payment is due soon',
        paragraphs: [
          `Your ${facts.tier} plan is due for renewal on ${facts.renewalDue ?? 'the coming days'}.`,
          `If it is not paid by then, your workspace stays open for a further `
          + `${SUBSCRIPTION_GRACE_DAYS} days before it locks, so there is time to sort it out.`,
          tenantsSafe,
        ],
        milestone: facts.renewalDue ?? 'due',
      };
    case 'grace_started':
      return {
        subject: 'Your Nyumba subscription payment is overdue',
        heading: 'Your subscription payment is overdue',
        paragraphs: [
          `Payment for your ${facts.tier} plan was due on ${facts.renewalDue ?? 'a recent date'} `
          + 'and has not been confirmed yet.',
          `Your workspace is still open. It will lock on ${facts.graceEnds ?? 'the end of the grace period'} `
          + 'unless the payment is confirmed before then.',
          'Nothing is deleted when it locks — your properties, tenants and records are all kept, and '
          + 'paying reopens the workspace immediately.',
          tenantsSafe,
        ],
        milestone: facts.graceEnds ?? 'grace',
      };
    case 'grace_ending':
      return {
        subject: 'Your Nyumba workspace locks in a few days',
        heading: 'Your workspace locks soon',
        paragraphs: [
          `Your ${facts.tier} plan payment is still outstanding, and your workspace locks on `
          + `${facts.graceEnds ?? 'the end of the grace period'}.`,
          'Pay now to keep working without interruption. Nothing is deleted if it does lock, and '
          + 'paying reopens it immediately.',
          tenantsSafe,
        ],
        milestone: `${facts.graceEnds ?? 'grace'}_ending`,
      };
    case 'expired':
      return {
        subject: 'Your Nyumba workspace is locked',
        heading: 'Your workspace is locked',
        paragraphs: [
          `The grace period for your ${facts.tier} plan has ended, so your workspace is now locked.`,
          'Everything is preserved — your properties, rental spaces, tenants, payments and documents '
          + 'are all still here. Paying your subscription reopens the workspace with all of it intact.',
          tenantsSafe,
        ],
        milestone: facts.graceEnds ?? 'expired',
      };
    case 'payment_rejected': {
      const why = facts.reasonCode ? REJECTION_REASONS[facts.reasonCode] : null;
      return {
        subject: 'Your Nyumba payment could not be confirmed',
        heading: 'We could not confirm that payment',
        paragraphs: [
          `Nyumba reviewed the payment you reported and could not confirm it because `
          + `${why ?? 'it could not be verified'}.`,
          ...(facts.note ? [facts.note] : []),
          'Your plan has not changed. You can submit the payment again from your subscription '
          + 'page, or contact Nyumba support if you believe this is a mistake.',
        ],
        milestone: `${facts.reasonCode ?? 'rejected'}`,
      };
    }
    case 'downgraded':
      return {
        subject: 'Your Nyumba plan has changed',
        heading: `Your plan is now ${facts.tier}`,
        paragraphs: [
          `Your subscription has been moved to the ${facts.tier} plan.`,
          'Nothing has been deleted. If you are currently above what this plan allows, everything '
          + 'stays visible and editable — you simply cannot add new rental spaces or publish new '
          + 'listings until you are back within the plan limits.',
          tenantsSafe,
        ],
        milestone: facts.tier,
      };
    case 'deactivated':
      return {
        subject: 'Your Nyumba subscription has ended',
        heading: 'Your subscription has ended',
        paragraphs: [
          'Your Nyumba subscription has been ended, so your workspace is locked.',
          'Everything is preserved — your properties, rental spaces, tenants, payments and documents '
          + 'are all still here, and paying reopens the workspace with all of it intact.',
          tenantsSafe,
        ],
        milestone: facts.reasonCode ?? 'deactivated',
      };
    default:
      return null;
  }
}

async function landlordContact(
  db: Firestore,
  landlordId: string,
): Promise<{ email: string; name: string | null } | null> {
  const snapshot = await db.collection(COLLECTIONS.users).doc(landlordId).get();
  const user = snapshot.data();
  if (!user || user.isDeleted === true) return null;
  if (typeof user.email !== 'string' || !user.email) return null;
  return {
    email: user.email,
    name: typeof user.displayName === 'string' ? user.displayName : null,
  };
}
