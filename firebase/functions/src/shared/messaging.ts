import { randomUUID } from 'node:crypto';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { newAggregate } from './aggregates';
import { COLLECTIONS } from './collections';
import { APP_ORIGIN } from './config';
import {
  notificationTemplate,
  supportedLocale,
  type NotificationTemplateKey,
} from './localization';

/**
 * Device tokens live on the user document because they are read on almost every
 * notification and are worthless without the user. Each entry is keyed by token
 * so re-registering the same device is idempotent.
 */
export interface DeviceToken {
  token: string;
  platform: string;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface NotificationContent {
  title: string;
  body: string;
  /** Deep-link route and IDs. Values must be strings; FCM data is string-only. */
  data?: Record<string, string>;
}

export interface InboxNotificationContent
  extends Omit<NotificationContent, 'title' | 'body'> {
  /** Stable per business event, so a retried job cannot duplicate the inbox. */
  id: string;
  kind: 'application' | 'enquiry' | 'tenant_notice' | 'system';
  templateKey?: NotificationTemplateKey;
  /**
   * Author-written copy (platform broadcasts) delivered verbatim to every
   * recipient in place of a localized template. Exactly one of `templateKey`
   * or `custom` must be provided.
   */
  custom?: { title: string; body: string };
  relatedEntityId?: string;
}

export interface PushDeliveryResult {
  state:
    | 'sent'
    | 'partial'
    | 'failed_permanent'
    | 'skipped_preference'
    | 'skipped_no_devices'
    | 'skipped_no_user';
  sent: number;
  pruned: number;
}

/** Tokens FCM tells us are permanently invalid; anything else may be transient. */
const DEAD_TOKEN_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
  'messaging/invalid-argument',
]);

/**
 * Sends a push to every device a user has registered, honoring their stored
 * push preference, and prunes tokens FCM reports as permanently dead.
 *
 * Throws only when no delivery is known to have succeeded and the failure may
 * be transient, allowing the durable backend job to retry. Permanent failures,
 * preference skips, and partial delivery return a result because retrying those
 * would either be pointless or duplicate a successful device.
 */
export async function notifyUser(
  uid: string,
  content: NotificationContent,
): Promise<PushDeliveryResult> {
  const db = getFirestore();
  const userRef = db.collection(COLLECTIONS.users).doc(uid);
  const snapshot = await userRef.get();
  if (!snapshot.exists) return { state: 'skipped_no_user', sent: 0, pruned: 0 };
  const user = snapshot.data()!;

  // Absent preference means opted in: the profile command defaults push to true
  // and a user who never opened settings still expects to hear about their rent.
  const notifications = user.notifications as { push?: unknown } | undefined;
  if (notifications?.push === false) {
    return { state: 'skipped_preference', sent: 0, pruned: 0 };
  }

  const tokens = readTokens(user.deviceTokens);
  if (tokens.length === 0) {
    return { state: 'skipped_no_devices', sent: 0, pruned: 0 };
  }

  // Browser-displayed web notifications do nothing on click unless FCM is
  // given an explicit link; native platforms route through the app's own
  // message handlers instead. Web notifications use the same canonical public
  // origin as transactional email rather than fragmenting traffic
  // across Firebase's generated hosting hostname.
  const route = content.data?.route;
  const webpush = route
    ? { fcmOptions: { link: new URL(route, APP_ORIGIN).href } }
    : undefined;

  let response;
  try {
    response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title: content.title, body: content.body },
      data: content.data ?? {},
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
      ...(webpush ? { webpush } : {}),
    });
  } catch {
    // No token-level result exists, so no delivery is known to have happened.
    // Throwing lets the durable backend job retry with its existing backoff.
    throw new Error('FCM transport failure.');
  }

  const dead: string[] = [];
  let transientFailures = 0;
  response.responses.forEach((result, index) => {
    const code = result.error?.code;
    const token = tokens[index];
    if (token && code && DEAD_TOKEN_CODES.has(code)) dead.push(token);
    else if (code) transientFailures++;
  });
  if (dead.length > 0) {
    await userRef.update({
      deviceTokens: FieldValue.arrayRemove(
        ...readEntries(user.deviceTokens).filter((entry) => dead.includes(entry.token)),
      ),
    });
  }
  // Retrying after a partial success would duplicate the successful devices.
  // Retry only when the response proves that no device accepted the message
  // and at least one failure may be transient.
  if (response.successCount === 0 && transientFailures > 0) {
    throw new Error('FCM transient token delivery failure.');
  }
  return {
    state: response.successCount === tokens.length
      ? 'sent'
      : response.successCount > 0
        ? 'partial'
        : 'failed_permanent',
    sent: response.successCount,
    pruned: dead.length,
  };
}

/**
 * Creates the durable in-app inbox item, then sends the optional push nudge.
 *
 * The inbox is authoritative for the user experience. A stable document ID
 * makes creation idempotent. A transactional lease ensures only one worker
 * calls FCM at a time; an expired lease can be reclaimed after a crash. A
 * process crash after FCM accepted a message but before completion is written
 * can still duplicate the nudge because FCM provides no idempotency key.
 */
export async function deliverUserNotification(
  uid: string,
  content: InboxNotificationContent,
): Promise<PushDeliveryResult> {
  const db = getFirestore();
  const user = await db.collection(COLLECTIONS.users).doc(uid).get();
  if (!content.custom && !content.templateKey) {
    throw new Error('Inbox notification needs either a templateKey or custom content.');
  }
  const rendered = content.custom
    ?? notificationTemplate(
      content.templateKey!,
      supportedLocale(user.data()?.locale),
    );
  const localizedContent: NotificationContent = {
    ...rendered,
    ...(content.data ? { data: content.data } : {}),
  };
  const ref = db
    .collection(COLLECTIONS.notificationInboxes)
    .doc(uid)
    .collection('items')
    .doc(content.id);
  const now = Timestamp.now();
  const leaseOwner = randomUUID();
  const leaseUntil = Timestamp.fromMillis(now.toMillis() + 5 * 60 * 1_000);
  const claimed = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) {
      tx.create(ref, {
        ...newAggregate(content.id, now),
        recipientUid: uid,
        kind: content.kind,
        title: rendered.title,
        body: rendered.body,
        route: content.data?.route ?? '/',
        relatedEntityId: content.relatedEntityId ?? null,
        isRead: false,
        readAt: null,
        pushState: 'sending',
        pushCompletedAt: null,
        pushLeaseOwner: leaseOwner,
        pushLeaseUntil: leaseUntil,
      });
      return true;
    }
    const current = snapshot.data() ?? {};
    if (current.pushCompletedAt instanceof Timestamp) return false;
    if (current.pushLeaseUntil instanceof Timestamp &&
        current.pushLeaseUntil.toMillis() > now.toMillis()) {
      return false;
    }
    const currentVersion = Number.isInteger(current.version)
      ? Number(current.version)
      : 1;
    tx.update(ref, {
      pushState: 'sending',
      pushLeaseOwner: leaseOwner,
      pushLeaseUntil: leaseUntil,
      version: currentVersion + 1,
      updatedAt: now,
    });
    return true;
  });
  if (!claimed) {
    return { state: 'sent', sent: 0, pruned: 0 };
  }

  const result = await notifyUser(uid, localizedContent);
  const completedAt = Timestamp.now();
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const current = snapshot.data();
    // A worker that outlived its lease must not overwrite a later claimant.
    if (!snapshot.exists || current?.pushLeaseOwner !== leaseOwner) return;
    const currentVersion = Number.isInteger(current.version)
      ? Number(current.version)
      : 1;
    tx.update(ref, {
      pushState: result.state,
      pushSentCount: result.sent,
      pushPrunedCount: result.pruned,
      pushCompletedAt: completedAt,
      pushLeaseOwner: null,
      pushLeaseUntil: null,
      version: currentVersion + 1,
      updatedAt: completedAt,
    });
  });
  return result;
}

function readEntries(raw: unknown): { token: string; platform: string; updatedAt: unknown }[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (entry): entry is { token: string; platform: string; updatedAt: unknown } =>
      typeof entry === 'object'
      && entry !== null
      && typeof (entry as { token?: unknown }).token === 'string',
  );
}

function readTokens(raw: unknown): string[] {
  return [...new Set(readEntries(raw).map((entry) => entry.token))];
}
