# Firebase handoff

This directory is environment-neutral and contains no project IDs or secrets.

- `firestore.rules`: deny-by-default, read-scoped Firestore Rules; client canonical writes use callable commands.
- `storage.rules`: two-phase private upload staging and server-owned public/private paths.
- `functions/scripts/apply-storage-cors.mjs`: applies the bucket CORS policy the web build needs — see below.
- `firestore.indexes.json`: baseline indexes for sync and core screens. Add only query-backed indexes discovered in emulator tests.
- `functions/COMMANDS.md`: Cloud Functions module handoff and links to the command contract.
- `firebase.json`: rules/index configuration plus local emulator ports.

The development Hosting configuration at the repository root routes public
marketplace pages and `sitemap.xml` to the `publicSeo` HTTP Function. Deploy
Functions before Hosting whenever those rewrites change; the CI workflow
enforces that dependency. The renderer is a read-only consumer of the
server-owned `publicListings` whitelist and must never read private listing,
property, or unit collections.

## Storage CORS (required for the web build)

`firebase deploy --only storage` deploys Storage *Rules*. It does not touch the
bucket's CORS policy, which is a Cloud Storage setting and is unset by default.
Rules and CORS answer different questions — rules decide whether a caller may
read an object, CORS decides whether a *browser* will hand the bytes to page
JavaScript once it has them.

The web client downloads photo bytes over `fetch`/XHR, so without this policy
every image fails with `No 'Access-Control-Allow-Origin' header is present`
even though the download URL is valid and the rules allow the read. Android and
iOS never see this: CORS is a browser mechanism, so those builds render the same
URLs fine, which is why the symptom looks platform-specific.

Apply it once per bucket, and again whenever an origin is added. Bucket and
origins come from the environment, so no deployment identifier is committed
here; `--dry-run` prints the policy without touching the bucket:

```bash
cd firebase/functions
STORAGE_BUCKET="<projectId>.firebasestorage.app" \
WEB_ORIGINS="https://<app-origin>,https://<projectId>.web.app,http://localhost:8087" \
  node scripts/apply-storage-cors.mjs
```

Verify with a GET carrying an allowed `Origin`, which is the request the
browser actually makes. `curl -I` would send `HEAD` and prove less than it
looks like it does. A configured bucket echoes the origin back:

```bash
curl -sS -D - -o /dev/null -H "Origin: https://<app-origin>" "<download-url>"
```

```
HTTP/1.1 200 OK
Access-Control-Allow-Origin: https://<app-origin>
```

## Verification and deployment limitations

- Local verification on 2026-07-25 uses
  `cd firebase/functions && npm run typecheck && npm test && npm run test:emulator`.
  All three passed: TypeScript reported no errors, all 47 unit tests passed, and
  the rules/command emulator suite completed successfully against
  `demo-nyumba`. The most recent local raw-response smoke check (2026-07-24)
  also passed for the Function's
  `308` root redirect, HTML explore/listing responses, XML sitemap, missing
  listing `404`/`noindex`, and short-lived cache headers.
- A Hosting smoke check with
  `curl -sS -D - -o /dev/null https://nyumba.online/<path>` currently shows
  that the checked-in rewrites have not reached the development live channel:
  `/` returns `200` instead of the Function's `308`, while `/sitemap.xml` and a
  missing `/listing/not-a-valid-id` path return the static Flutter HTML with
  `200` instead of XML and `404`. Deploy Functions first and then Hosting
  before treating public SEO as remotely verified.
- The deployment service account needs Firebase Admin, Cloud Functions Admin,
  and Service Account User for the backend deployment; Firebase Hosting Admin
  for Hosting; and Secret Manager Viewer on each Function-bound secret. The
  Functions runtime service account separately needs Secret Manager Secret
  Accessor.
- CI and the custom domain currently target the configured development
  project. Staging and production Firebase project IDs, application IDs,
  credentials, and deployment workflows remain unresolved; no production
  deployment is configured or verified.

From this directory, validate with the Firebase Emulator Suite after selecting a non-production demo project:

```sh
firebase emulators:start --config firebase.json --project <your-dev-project-id>
```

Before any deployment:

1. Select the project through CI/environment configuration; do not commit a production `.firebaserc` by accident. Use `<your-dev-project-id>` locally (Blaze, region `europe-west1`).
2. Add emulator tests for every permitted/denied actor and query shape.
3. Register and enforce App Check for each Flutter platform.
4. Upload limits are finalized: property photos are 5 MB each (jpeg/png/webp, max 2 per aggregate), listing photos are 5 MB each (jpeg/png/webp, max 5 per aggregate), and documents are 10 MB (pdf/jpeg/png); staging paths enforce per-file limits in `storage.rules`, while finalizing Functions enforce counts and ordering. New client selections are auto-oriented, stripped, bounded to 1920×1440, and recompressed as quality-82 JPEG before staging. Public listing delivery copies are independently stripped, bounded to 1920×1440, and encoded as WebP.
5. Implement and test callable commands; these rules intentionally deny direct client writes.
6. Finalized: region `europe-west1`, listing expiry 30 days renewable, retention (financial 7 years, deleted media purged after 90 days, maintenance media 2 years). Still **TBD:** plan pricing/unit limits and the payment provider.

Administrator roles are separate custom claims. Grant an operational Admin
with `functions/scripts/grant-admin.mjs <email> --project <project-id>` and a
Super Admin only from a controlled operator environment by adding
`--super-admin`. Never grant either role from Flutter or a writable document.

Deployment should use an explicit `--project` value and reviewed CI environment. Never put provider keys, webhook secrets, service-account JSON, or Flutter Firebase option values in these rules/configuration files.
