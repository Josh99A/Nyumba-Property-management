#!/usr/bin/env node
/**
 * Applies the Cloud Storage CORS policy the web build depends on.
 *
 * `firebase deploy --only storage` deploys Storage *Rules*, not CORS. They
 * answer different questions: rules decide whether a caller may read an
 * object, CORS decides whether a browser will hand the bytes to page
 * JavaScript once it already has them. A bucket with correct rules and no CORS
 * policy serves every photo with a valid download URL that the browser then
 * discards, which is exactly what happened here — a blank grid on web while
 * Android and iOS rendered the same URLs fine, because CORS is a browser
 * mechanism and native HTTP clients never consult it.
 *
 * Nothing in the deploy pipeline sets this, so it is a deliberate, occasional
 * operator action: run it once per bucket, and again whenever an origin is
 * added or removed.
 *
 * The policy shape lives here rather than in a checked-in JSON file so this
 * directory keeps its environment-neutral contract: bucket and origins come
 * from the environment, matching how the other scripts here resolve
 * `GOOGLE_CLOUD_PROJECT`.
 *
 * Usage:
 *   node scripts/apply-storage-cors.mjs \
 *     --bucket <bucket> \
 *     --origins https://app.example,https://app.web.app,http://localhost:8087
 *
 * Falls back to STORAGE_BUCKET and WEB_ORIGINS. Pass --dry-run to print the
 * policy without touching the bucket. Requires the gcloud CLI, authenticated
 * with permission to update the bucket.
 */
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const args = process.argv.slice(2);

function flag(name) {
  const index = args.indexOf(`--${name}`);
  if (index === -1) return undefined;
  const value = args[index + 1];
  if (!value || value.startsWith('--')) {
    console.error(`--${name} needs a value.`);
    process.exit(1);
  }
  return value;
}

const dryRun = args.includes('--dry-run');
const bucket = flag('bucket') ?? process.env.STORAGE_BUCKET;
const origins = (flag('origins') ?? process.env.WEB_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter((origin) => origin.length > 0);

if (!bucket) {
  console.error(
    'No bucket. Pass --bucket <bucket> or set STORAGE_BUCKET.\n'
      + 'The Firebase default is usually <projectId>.firebasestorage.app.',
  );
  process.exit(1);
}
if (origins.length === 0) {
  console.error(
    'No origins. Pass --origins a,b or set WEB_ORIGINS (comma separated).\n'
      + 'Include every origin the web app is served from, plus any local\n'
      + 'development ports — an origin absent here cannot load a single photo.',
  );
  process.exit(1);
}

const malformed = origins.filter((origin) => !/^https?:\/\/[^/]+$/.test(origin));
if (malformed.length > 0) {
  // A trailing slash or a path silently never matches, which reads on the
  // client as "CORS is still broken" long after this script reported success.
  console.error(
    `Not scheme://host origins: ${malformed.join(', ')}\n`
      + 'Drop any trailing slash or path.',
  );
  process.exit(1);
}

const policy = [
  {
    origin: origins,
    // Reads only. The client uploads through the Firebase SDK, which does not
    // depend on this policy, so granting write methods here would widen the
    // bucket for nothing.
    method: ['GET', 'HEAD'],
    responseHeader: [
      'Content-Type',
      'Content-Length',
      'Content-Range',
      'Accept-Ranges',
      'Cache-Control',
    ],
    maxAgeSeconds: 3600,
  },
];

const rendered = `${JSON.stringify(policy, null, 2)}\n`;
console.log(`Bucket: gs://${bucket}`);
console.log(rendered);

if (dryRun) {
  console.log('--dry-run: bucket not modified.');
  process.exit(0);
}

const file = join(mkdtempSync(join(tmpdir(), 'nyumba-cors-')), 'cors.json');
writeFileSync(file, rendered, 'utf8');

execFileSync(
  process.platform === 'win32' ? 'gcloud.cmd' : 'gcloud',
  ['storage', 'buckets', 'update', `gs://${bucket}`, `--cors-file=${file}`],
  { stdio: 'inherit' },
);

console.log(
  '\nApplied. Verify with a GET carrying an allowed Origin — the response\n'
    + 'must echo Access-Control-Allow-Origin:\n'
    + `  curl -sS -D - -o /dev/null -H "Origin: ${origins[0]}" "<download-url>"`,
);
