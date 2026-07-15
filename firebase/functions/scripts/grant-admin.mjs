#!/usr/bin/env node
/**
 * Grants (or revokes) an administrator custom claim.
 *
 * Usage:
 *   node scripts/grant-admin.mjs <email> [--super-admin] [--project <projectId>] [--revoke]
 *
 * Requires Application Default Credentials with permission on the target
 * project (e.g. `gcloud auth application-default login`). The target user must
 * already exist in Firebase Auth — sign in to the app once first. The claim
 * takes effect on the user's next token refresh (sign out/in forces it).
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const args = process.argv.slice(2);
const email = args.find((arg) => !arg.startsWith('--'));
const revoke = args.includes('--revoke');
const superAdmin = args.includes('--super-admin');
const projectFlag = args.indexOf('--project');
const projectId =
  projectFlag !== -1 ? args[projectFlag + 1] : process.env.GOOGLE_CLOUD_PROJECT ?? 'nyumba-property-management';

if (!email || !email.includes('@')) {
  console.error('Usage: node scripts/grant-admin.mjs <email> [--super-admin] [--project <projectId>] [--revoke]');
  process.exit(1);
}

initializeApp({ projectId });
const auth = getAuth();

try {
  const user = await auth.getUserByEmail(email);
  const claims = { ...(user.customClaims ?? {}) };
  const claim = superAdmin ? 'superAdmin' : 'platformAdmin';
  if (revoke) {
    delete claims[claim];
  } else {
    claims[claim] = true;
    delete claims[superAdmin ? 'platformAdmin' : 'superAdmin'];
  }
  await auth.setCustomUserClaims(user.uid, claims);
  await auth.revokeRefreshTokens(user.uid);
  console.log(
    `${revoke ? 'Revoked' : 'Granted'} ${claim} for ${email} (uid ${user.uid}) on ${projectId}.`,
  );
  console.log('The user must sign out and back in (or refresh their token) for the change to apply.');
} catch (error) {
  if (error?.code === 'auth/user-not-found') {
    console.error(`No Firebase Auth user exists for ${email} on ${projectId}.`);
    console.error('Ask them to sign in to the app once (Google or email/password), then re-run this script.');
    process.exit(2);
  }
  throw error;
}
