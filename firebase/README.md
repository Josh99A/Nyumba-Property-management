# Firebase handoff

This directory is environment-neutral and contains no project IDs or secrets.

- `firestore.rules`: deny-by-default, read-scoped Firestore Rules; client canonical writes use callable commands.
- `storage.rules`: two-phase private upload staging and server-owned public/private paths.
- `firestore.indexes.json`: baseline indexes for sync and core screens. Add only query-backed indexes discovered in emulator tests.
- `functions/COMMANDS.md`: Cloud Functions module handoff and links to the command contract.
- `firebase.json`: rules/index configuration plus local emulator ports.

The production Hosting configuration at the repository root routes public
marketplace pages and `sitemap.xml` to the `publicSeo` HTTP Function. Deploy
Functions before Hosting whenever those rewrites change; the CI workflow
enforces that dependency. The renderer is a read-only consumer of the
server-owned `publicListings` whitelist and must never read private listing,
property, or unit collections.

From this directory, validate with the Firebase Emulator Suite after selecting a non-production demo project:

```sh
firebase emulators:start --config firebase.json --project <your-dev-project-id>
```

Before any deployment:

1. Select the project through CI/environment configuration; do not commit a production `.firebaserc` by accident. Use `<your-dev-project-id>` locally (Blaze, region `europe-west1`).
2. Add emulator tests for every permitted/denied actor and query shape.
3. Register and enforce App Check for each Flutter platform.
4. Upload limits are finalized: property photos 5 MB (jpeg/png/webp, max 5 per property), listing photos 5 MB (jpeg/png/webp, max 10 per listing), documents 10 MB (pdf/jpeg/png); staging paths enforce per-file limits in `storage.rules`, while finalizing Functions enforce counts and ordering.
5. Implement and test callable commands; these rules intentionally deny direct client writes.
6. Finalized: region `europe-west1`, listing expiry 30 days renewable, retention (financial 7 years, deleted media purged after 90 days, maintenance media 2 years). Still **TBD:** plan pricing/unit limits and the payment provider.

Administrator roles are separate custom claims. Grant an operational Admin
with `functions/scripts/grant-admin.mjs <email> --project <project-id>` and a
Super Admin only from a controlled operator environment by adding
`--super-admin`. Never grant either role from Flutter or a writable document.

Deployment should use an explicit `--project` value and reviewed CI environment. Never put provider keys, webhook secrets, service-account JSON, or Flutter Firebase option values in these rules/configuration files.
