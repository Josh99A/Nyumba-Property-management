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

Deployment placeholders:

- `TBD_FIREBASE_REGION`
- `TBD_NYUMBA_*_PROJECT_ID` for dev/staging/prod
- `TBD_PAYMENT_PROVIDER` and Secret Manager secret names
- `TBD_PLAN_PRICES`, `TBD_PLAN_UNIT_LIMITS`, trials, grace periods, and entitlements
- `TBD_LISTING_LIFETIME`, upload limits, retry limits, and retention durations

Do not replace a placeholder with a guessed production value. Unknown plan/payment/publication configuration must fail closed.
