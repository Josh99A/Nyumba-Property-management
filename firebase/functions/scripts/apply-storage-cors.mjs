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
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const VALUE_FLAGS = new Set(['bucket', 'origins']);
const BOOLEAN_FLAGS = new Set(['dry-run']);

/**
 * Parses argv strictly.
 *
 * This script updates a bucket in a real project, so an argument it does not
 * understand is a stop condition rather than something to skip: with
 * STORAGE_BUCKET exported, a typo like `--buket staging` would otherwise be
 * ignored and the environment's bucket updated instead — the wrong bucket,
 * silently, with a plausible-looking success message.
 */
function parseArguments(argv) {
  const values = new Map();
  const errors = [];

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      errors.push(`unexpected argument: ${token}`);
      continue;
    }
    const name = token.slice(2);
    if (values.has(name)) {
      errors.push(`repeated flag: --${name}`);
      continue;
    }
    if (BOOLEAN_FLAGS.has(name)) {
      values.set(name, true);
      continue;
    }
    if (!VALUE_FLAGS.has(name)) {
      errors.push(`unknown flag: --${name}`);
      continue;
    }
    const value = argv[index + 1];
    if (value === undefined || value.startsWith('--')) {
      errors.push(`--${name} needs a value`);
      continue;
    }
    values.set(name, value);
    index += 1;
  }

  return { values, errors };
}

/**
 * Whether [candidate] is not something Cloud Storage can match.
 *
 * Compared byte for byte against the browser's `Origin` header, which is
 * always exactly scheme://host[:port] — no credentials, no path, no query. A
 * near-miss here is accepted by the bucket and then never matches anything,
 * which on the client is indistinguishable from CORS never having been
 * configured at all.
 */
function isInvalidOrigin(candidate) {
  let url;
  try {
    url = new URL(candidate);
  } catch {
    return true;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return true;
  if (url.username !== '' || url.password !== '') return true;
  if (url.pathname !== '/' || url.search !== '' || url.hash !== '') return true;
  // Round-trip check: rejects a trailing slash, a default port written out,
  // and any other spelling the browser would not send.
  return url.origin !== candidate;
}

const { values, errors } = parseArguments(process.argv.slice(2));
if (errors.length > 0) {
  console.error(`${errors.join('\n')}\n`);
  console.error(
    'Usage: node scripts/apply-storage-cors.mjs '
      + '[--bucket <bucket>] [--origins a,b] [--dry-run]',
  );
  process.exit(1);
}

const dryRun = values.get('dry-run') === true;
const bucket = values.get('bucket') ?? process.env.STORAGE_BUCKET;
const origins = (values.get('origins') ?? process.env.WEB_ORIGINS ?? '')
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

const malformed = origins.filter(isInvalidOrigin);
if (malformed.length > 0) {
  console.error(
    `Not scheme://host origins: ${malformed.join(', ')}\n`
      + 'Drop any trailing slash, path, query, or credentials.',
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

// gcloud reads the policy from a file, so one has to exist for the length of
// the call and no longer — including when the call throws.
const directory = mkdtempSync(join(tmpdir(), 'nyumba-cors-'));
try {
  const file = join(directory, 'cors.json');
  writeFileSync(file, rendered, 'utf8');
  execFileSync(
    process.platform === 'win32' ? 'gcloud.cmd' : 'gcloud',
    ['storage', 'buckets', 'update', `gs://${bucket}`, `--cors-file=${file}`],
    { stdio: 'inherit' },
  );
} finally {
  rmSync(directory, { recursive: true, force: true });
}

console.log(
  '\nApplied. Verify with a GET carrying an allowed Origin — the response\n'
    + 'must echo Access-Control-Allow-Origin:\n'
    + `  curl -sS -D - -o /dev/null -H "Origin: ${origins[0]}" "<download-url>"`,
);
