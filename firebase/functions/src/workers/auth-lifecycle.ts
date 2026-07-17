import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { COLLECTIONS } from '../shared/collections';

function isUserNotFound(error: unknown): boolean {
  return (error as { code?: string } | null)?.code === 'auth/user-not-found';
}

/**
 * Enables or disables sign-in for a Firebase Auth account, enqueued by
 * `user.archive` / `user.restore`. Disabling also revokes refresh tokens so an
 * open session dies at its next token refresh instead of living out the hour.
 * A missing Auth account is success, not failure: the profile can outlive the
 * account (see `onUserDeleted`), and retrying to dead_letter helps no one.
 */
export async function setAuthUserDisabled(payload: Record<string, unknown>): Promise<void> {
  const uid = String(payload.uid);
  const disabled = payload.disabled === true;
  const expectedUserVersion = Number(payload.expectedUserVersion);
  const expectedUserStatus = String(payload.expectedUserStatus);
  const profile = await getFirestore().collection(COLLECTIONS.users).doc(uid).get();
  const current = profile.data();
  // Archive and restore jobs may be delayed independently. Never let an old
  // disable retry undo a newer restore (or an old enable undo a re-archive).
  if (!profile.exists ||
      current?.version !== expectedUserVersion ||
      current?.status !== expectedUserStatus) {
    return;
  }
  try {
    const auth = getAuth();
    const user = await auth.getUser(uid);
    if (user.disabled !== disabled) await auth.updateUser(uid, { disabled });
    if (disabled) await getAuth().revokeRefreshTokens(uid);
  } catch (error) {
    if (!isUserNotFound(error)) throw error;
  }
}

/**
 * Deletes the Firebase Auth account behind a `user.delete` command. The
 * profile document was already tombstoned in the command's transaction; the
 * `onUserDeleted` trigger re-marking it is a harmless idempotent overlap.
 */
export async function deleteAuthUser(payload: Record<string, unknown>): Promise<void> {
  const uid = String(payload.uid);
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    if (!isUserNotFound(error)) throw error;
  }
}
