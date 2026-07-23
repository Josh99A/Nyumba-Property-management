# Cloud Functions implementation handoff

The authoritative command contract and pseudocode are in [`docs/architecture/backend-command-contracts.md`](../../docs/architecture/backend-command-contracts.md). Implement Functions in TypeScript with strict runtime schemas, Admin SDK transactions, Emulator Suite integration tests, App Check enforcement, Secret Manager, and structured redacted logs.

Suggested modules:

```text
src/
  callable/execute-command.ts
  commands/{identity,admin,portfolio,tenancy,billing,maintenance,listings}.ts
  http/{billing-webhook}.ts
  workers/{provider-jobs,projections,notifications,retention,reconciliation}.ts
  shared/{auth,envelope,errors,idempotency,money,audit}.ts
  schemas/v1/*.ts
```

Deployment configuration:

- Region is finalized as `europe-west1`.
- `TBD_NYUMBA_*_PROJECT_ID` for dev/staging/prod
- `TBD_PAYMENT_PROVIDER` and Secret Manager secret names
- Plan prices and unit limits are seeded by `scripts/seed-entitlements.mjs` and edited at runtime by administrators via `plan.update` (docs/architecture/subscription-tiers.md records the launch prices); trials and grace periods remain TBD
- The `superAdmin` claim gates exactly the irreversible commands — `user.delete`, `property.delete`, `unit.delete`, `listing.delete`, `document.purge` (see `src/commands/purge.ts`). Everything else an administrator does is reversible and needs only `platformAdmin`
- Listing lifetime and upload limits are finalized in `docs/architecture/README.md`; retry and operational retention policies remain deployment-reviewed.

Do not replace a placeholder with a guessed production value. Unknown plan/payment/publication configuration must fail closed.
