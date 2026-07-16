import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { COLLECTIONS } from './collections';

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
 * Never throws on delivery failure: a notification is a courtesy channel, and a
 * failed push must not fail (or endlessly retry) the job that produced the
 * underlying state change. The state change is already durable in Firestore and
 * the portal projection, which is what the user actually reads.
 */
export async function notifyUser(
  uid: string,
  content: NotificationContent,
): Promise<{ sent: number; pruned: number }> {
  const db = getFirestore();
  const userRef = db.collection(COLLECTIONS.users).doc(uid);
  const snapshot = await userRef.get();
  if (!snapshot.exists) return { sent: 0, pruned: 0 };
  const user = snapshot.data()!;

  // Absent preference means opted in: the profile command defaults push to true
  // and a user who never opened settings still expects to hear about their rent.
  const notifications = user.notifications as { push?: unknown } | undefined;
  if (notifications?.push === false) return { sent: 0, pruned: 0 };

  const tokens = readTokens(user.deviceTokens);
  if (tokens.length === 0) return { sent: 0, pruned: 0 };

  let response;
  try {
    response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title: content.title, body: content.body },
      data: content.data ?? {},
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  } catch {
    // A transport-level failure tells us nothing about individual tokens.
    return { sent: 0, pruned: 0 };
  }

  const dead: string[] = [];
  response.responses.forEach((result, index) => {
    const code = result.error?.code;
    const token = tokens[index];
    if (token && code && DEAD_TOKEN_CODES.has(code)) dead.push(token);
  });
  if (dead.length > 0) {
    await userRef.update({
      deviceTokens: FieldValue.arrayRemove(
        ...readEntries(user.deviceTokens).filter((entry) => dead.includes(entry.token)),
      ),
    });
  }
  return { sent: response.successCount, pruned: dead.length };
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
