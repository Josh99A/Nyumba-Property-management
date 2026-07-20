import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import type { DocumentSnapshot, Firestore } from 'firebase-admin/firestore';
import { COLLECTIONS } from '../shared/collections';
import { APP_ORIGIN, buildEmailHtml, sendEmail } from '../shared/email';
import { deliverUserNotification } from '../shared/messaging';

interface BroadcastRecipient {
  uid: string;
  email: string | null;
  name: string | null;
}

/**
 * Delivers a platform broadcast to its resolved audience: a durable in-app
 * inbox item (with push nudge) for every recipient, plus a courtesy email
 * where an address exists. Idempotent per recipient — the inbox write is
 * keyed by broadcast ID and the email is guarded by a dedupe document plus
 * Resend's idempotency key — so a retried job cannot double-deliver.
 */
export async function fanoutBroadcast(payload: Record<string, unknown>): Promise<void> {
  const db = getFirestore();
  const broadcastId = String(payload.broadcastId);
  const ref = db.collection(COLLECTIONS.platformBroadcasts).doc(broadcastId);
  const snapshot = await ref.get();
  if (!snapshot.exists) return;
  const broadcast = snapshot.data()!;
  if (broadcast.deliveryState === 'sent') return;
  const title = String(broadcast.title ?? '');
  const body = String(broadcast.body ?? '');
  if (!title || !body) return;

  const recipients = await resolveAudience(
    db,
    String(broadcast.audience ?? ''),
    typeof broadcast.audienceId === 'string' ? broadcast.audienceId : null,
  );

  // Bounded concurrency, like notice fanout: a platform-wide announcement
  // must not serialize one FCM round trip per user or burst without limit.
  for (let start = 0; start < recipients.length; start += 10) {
    await Promise.all(
      recipients.slice(start, start + 10).map(async (recipient) => {
        await deliverUserNotification(recipient.uid, {
          id: `broadcast_${broadcastId}`,
          kind: 'system',
          custom: { title, body },
          relatedEntityId: broadcastId,
          data: { route: '/', broadcastId },
        });
        await emailRecipient(db, broadcastId, recipient, title, body);
      }),
    );
  }

  await ref.update({
    deliveryState: 'sent',
    recipientCount: recipients.length,
    completedAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  });
}

/**
 * Resolves the audience to live accounts. Deleted and archived users are
 * excluded from every audience, including an individual target: a suspended
 * person must not keep receiving platform mail through a stale broadcast.
 */
async function resolveAudience(
  db: Firestore,
  audience: string,
  audienceId: string | null,
): Promise<BroadcastRecipient[]> {
  const users = db.collection(COLLECTIONS.users);
  let snapshots: DocumentSnapshot[];
  switch (audience) {
    case 'user': {
      if (!audienceId) return [];
      snapshots = [await users.doc(audienceId).get()];
      break;
    }
    case 'landlords':
    case 'tenants':
    case 'clients': {
      const role = audience.slice(0, -1);
      snapshots = (await users.where('role', '==', role).get()).docs;
      break;
    }
    case 'tier': {
      if (!audienceId) return [];
      const subscriptions = await db
        .collection(COLLECTIONS.subscriptions)
        .where('tier', '==', audienceId)
        .get();
      const refs = subscriptions.docs.map((doc) => users.doc(doc.id));
      snapshots = refs.length === 0 ? [] : await db.getAll(...refs);
      break;
    }
    case 'all_users': {
      snapshots = (await users.get()).docs;
      break;
    }
    default:
      return [];
  }
  const recipients: BroadcastRecipient[] = [];
  for (const doc of snapshots) {
    const user = doc.data();
    if (!doc.exists || !user) continue;
    if (user.isDeleted === true || user.status === 'archived') continue;
    recipients.push({
      uid: doc.id,
      email: typeof user.email === 'string' && user.email ? user.email : null,
      name: typeof user.displayName === 'string' && user.displayName ? user.displayName : null,
    });
  }
  return recipients;
}

/**
 * Courtesy email copy of the broadcast. The dedupe document is written after
 * a successful send, so a crash between send and mark can retry into Resend's
 * idempotency window rather than silently dropping the recipient.
 */
async function emailRecipient(
  db: Firestore,
  broadcastId: string,
  recipient: BroadcastRecipient,
  title: string,
  body: string,
): Promise<void> {
  if (!recipient.email) return;
  const dedupeRef = db
    .collection(COLLECTIONS.backendJobDedupe)
    .doc(`${broadcastId}_${recipient.uid}_email`);
  if ((await dedupeRef.get()).exists) return;
  await sendEmail({
    to: recipient.email,
    subject: title,
    idempotencyKey: `broadcast_${broadcastId}_${recipient.uid}`,
    html: buildEmailHtml({
      recipientName: recipient.name,
      heading: title,
      paragraphs: body
        .split(/\n+/)
        .map((paragraph) => paragraph.trim())
        .filter((paragraph) => paragraph.length > 0),
      cta: { label: 'Open Nyumba', url: APP_ORIGIN },
    }),
  });
  await dedupeRef.create({
    key: `${broadcastId}:${recipient.uid}:email`,
    createdAt: Timestamp.now(),
  });
}
