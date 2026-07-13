# Firebase handoff

This directory is environment-neutral and contains no project IDs or secrets.

- `firestore.rules`: deny-by-default, read-scoped Firestore Rules; client canonical writes use callable commands.
- `storage.rules`: two-phase private upload staging and server-owned public/private paths.
- `firestore.indexes.json`: baseline indexes for sync and core screens. Add only query-backed indexes discovered in emulator tests.
- `functions/COMMANDS.md`: Cloud Functions module handoff and links to the command contract.
- `firebase.json`: rules/index configuration plus local emulator ports.

From this directory, validate with the Firebase Emulator Suite after selecting a non-production demo project:

```sh
firebase emulators:start --config firebase.json --project TBD_NYUMBA_FIREBASE_DEV_PROJECT_ID
```

Before any deployment:

1. Replace the local command's project placeholder through CI/environment configuration; do not commit a production `.firebaserc` by accident.
2. Add emulator tests for every permitted/denied actor and query shape.
3. Register and enforce App Check for each Flutter platform.
4. Review the provisional 10 MiB staging-upload ceiling. **TBD:** final per-document limits and retention.
5. Implement and test callable commands; these rules intentionally deny direct client writes.
6. Confirm **TBD** region, plan pricing/unit limits, payment provider, listing expiry, and retention policies.

Deployment should use an explicit `--project` value and reviewed CI environment. Never put provider keys, webhook secrets, service-account JSON, or Flutter Firebase option values in these rules/configuration files.
