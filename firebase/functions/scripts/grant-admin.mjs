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
 *
 * Also maintains `platformStaff/{uid}`, a queryable mirror of who holds a
 * claim. The claim remains the only thing that authorizes anything; the mirror
 * exists because custom claims cannot be queried, so without it a job that
 * needs to notify "every administrator" has no audience to resolve and would
 * have to page the entire Auth directory. Anyone granted a claim before this
 * script wrote the mirror is invisible to those notifications until it is
 * re-run for them — see `--backfill`.
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const email = args.find((arg) => !arg.startsWith('--'));
const revoke = args.includes('--revoke');
const superAdmin = args.includes('--super-admin');
const backfill = args.includes('--backfill');
const projectFlag = args.indexOf('--project');
const projectId =
  projectFlag !== -1 ? args[projectFlag + 1] : process.env.GOOGLE_CLOUD_PROJECT ?? 'nyumba-property-management';

if (!backfill && (!email || !email.includes('@'))) {
  console.error('Usage: node scripts/grant-admin.mjs <email> [--super-admin] [--project <projectId>] [--revoke]');
  console.error('       node scripts/grant-admin.mjs --backfill [--project <projectId>]');
  process.exit(1);
}

initializeApp({ projectId });
const auth = getAuth();
const db = getFirestore();

/** The claim level this user holds, or null when they hold neither. */
function levelOf(claims) {
  if (claims?.superAdmin === true) return 'superAdmin';
  if (claims?.platformAdmin === true) return 'platformAdmin';
  return null;
}

/**
 * Points the mirror at whatever the claims now say.
 *
 * Derived from the claims rather than from the flags this script was called
 * with, so the mirror cannot drift from the thing it mirrors — including on a
 * backfill, where no flags were passed at all.
 */
async function syncMirror(user) {
  const ref = db.collection('platformStaff').doc(user.uid);
  const level = levelOf(user.customClaims);
  if (!level) {
    await ref.delete();
    return null;
  }
  await ref.set(
    {
      uid: user.uid,
      email: user.email ?? null,
      displayName: user.displayName ?? null,
      level,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return level;
}

/**
 * Rebuilds the mirror from the Auth directory.
 *
 * The one-off for administrators granted before the mirror existed, and the
 * repair for a mirror that fell out of step. Pages the whole directory, which
 * is exactly what the mirror exists to avoid doing on every notification —
 * acceptable once, by hand.
 */
async function runBackfill() {
  let pageToken;
  let found = 0;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      if (!levelOf(user.customClaims)) continue;
      const level = await syncMirror(user);
      found += 1;
      console.log(`  ${user.email ?? user.uid} → ${level}`);
    }
    pageToken = page.pageToken;
  } while (pageToken);
  console.log(`Mirrored ${found} administrator${found === 1 ? '' : 's'} on ${projectId}.`);
}

if (backfill) {
  await runBackfill();
  process.exit(0);
}

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
  // Re-read so the mirror reflects what Auth actually stored, not what was
  // sent. A write that partially applied must not leave a mirror claiming
  // access the token does not carry.
  await syncMirror(await auth.getUser(user.uid));
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
