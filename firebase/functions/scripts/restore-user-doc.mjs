#!/usr/bin/env node
/**
 * Recreates missing `users/{uid}` profile documents from Firebase Auth.
 *
 * The app cannot resolve a session without `users/{uid}` (the session
 * controller waits for it and then fails with "Your account is still being
 * set up"), and the document is only ever created by the `onUserCreated`
 * Auth trigger — deleting the collection therefore locks every existing
 * account out, including administrators. This script backfills the same
 * shape the trigger writes.
 *
 * Usage:
 *   node scripts/restore-user-doc.mjs <email> [--role client|tenant|landlord] [--project <projectId>]
 *   node scripts/restore-user-doc.mjs --all [--project <projectId>]
 *
 * `--all` walks every Firebase Auth user and restores any missing profile
 * document (role defaults to `client`; landlords whose `landlordAccounts`
 * document survived are restored as `landlord`).
 *
 * Requires Application Default Credentials with permission on the target
 * project (e.g. `gcloud auth application-default login`). Existing documents
 * are never overwritten.
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const email = args.find((arg) => !arg.startsWith('--'));
const all = args.includes('--all');
const roleFlag = args.indexOf('--role');
const role = roleFlag !== -1 ? args[roleFlag + 1] : null;
const projectFlag = args.indexOf('--project');
const projectId =
  projectFlag !== -1 ? args[projectFlag + 1] : process.env.GOOGLE_CLOUD_PROJECT ?? 'nyumba-property-management';

const VALID_ROLES = new Set(['client', 'tenant', 'landlord']);
if ((!all && (!email || !email.includes('@'))) || (role !== null && !VALID_ROLES.has(role))) {
  console.error('Usage: node scripts/restore-user-doc.mjs <email> [--role client|tenant|landlord] [--project <projectId>]');
  console.error('       node scripts/restore-user-doc.mjs --all [--project <projectId>]');
  process.exit(1);
}

initializeApp({ projectId });
const auth = getAuth();
const db = getFirestore();

async function restoreProfile(user, explicitRole) {
  const ref = db.collection('users').doc(user.uid);
  const existing = await ref.get();
  if (existing.exists) {
    console.log(`users/${user.uid} already exists for ${user.email ?? user.uid}; left untouched.`);
    return false;
  }
  let restoredRole = explicitRole;
  if (!restoredRole) {
    const landlordAccount = await db.collection('landlordAccounts').doc(user.uid).get();
    restoredRole = landlordAccount.exists ? 'landlord' : 'client';
  }
  const createdAt = user.metadata.creationTime
    ? Timestamp.fromDate(new Date(user.metadata.creationTime))
    : Timestamp.now();
  await ref.create({
    id: user.uid,
    displayName: user.displayName || null,
    email: user.email ?? null,
    role: restoredRole,
    status: 'active',
    version: 1,
    createdAt,
    updatedAt: Timestamp.now(),
    isDeleted: false,
  });
  console.log(`Restored users/${user.uid} for ${user.email ?? user.uid} as ${restoredRole}.`);
  return true;
}

if (all) {
  let restored = 0;
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      if (await restoreProfile(user, null)) restored += 1;
    }
    pageToken = page.pageToken;
  } while (pageToken);
  console.log(`Done: restored ${restored} profile document(s) on ${projectId}.`);
} else {
  try {
    const user = await auth.getUserByEmail(email);
    await restoreProfile(user, role);
    const claims = user.customClaims ?? {};
    if (claims.superAdmin === true || claims.platformAdmin === true) {
      console.log('This account holds an administrator claim; it survives in Firebase Auth and needs no re-grant.');
    }
    console.log('Sign out and back in on the device for the session to resolve.');
  } catch (error) {
    if (error?.code === 'auth/user-not-found') {
      console.error(`No Firebase Auth user exists for ${email} on ${projectId}.`);
      process.exit(2);
    }
    throw error;
  }
}
