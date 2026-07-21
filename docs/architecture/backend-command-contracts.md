# Backend command contracts

All client mutations use one versioned callable command boundary (or thin per-domain callables implementing the same envelope). This keeps offline retries, authorization, validation, audit, and error handling consistent. Reads still use Firestore under Rules.

## Request envelope

```json
{
  "commandId": "01J... stable ID reused on retry",
  "type": "unit.create",
  "schemaVersion": 1,
  "aggregateId": "01J...",
  "expectedVersion": 0,
  "payload": {},
  "client": {
    "installationId": "non-advertising installation ID",
    "appVersion": "1.0.0",
    "platform": "android|ios|web"
  }
}
```

Requirements:

- Firebase Authentication and enforced App Check are required. Public browsers may use anonymous Firebase Auth before contact/application submission.
- `commandId` and new aggregate IDs are generated once on-device and survive process death/retry.
- Maximum envelope and per-field lengths are enforced server-side. Unknown fields, command types, or schema versions are rejected.
- `expectedVersion` is mandatory for edits and `0` for creates. Commands that do not edit an aggregate may omit it only when their schema says so.
- `profile.update` is the explicit low-risk last-write-wins exception: it omits `expectedVersion` so a new device can save personal display/notification preferences before it has mirrored a user-document revision.
- Actor UID, role, landlord ownership, prices, amounts, statuses, timestamps, and entitlements are not accepted as authority from `payload`.
- A deterministic hash of the canonicalized command body is stored with the receipt. Reusing a command ID with different content returns `IDEMPOTENCY_KEY_REUSED`.

## Response envelope

```json
{
  "commandId": "01J...",
  "status": "applied|accepted|rejected",
  "aggregateId": "01J...",
  "serverVersion": 4,
  "serverUpdatedAt": "Firestore timestamp or encoded UTC instant",
  "result": {},
  "error": {
    "code": "VERSION_CONFLICT",
    "messageKey": "sync.versionConflict",
    "details": {}
  }
}
```

`accepted` means durable asynchronous work exists; it never means payment confirmed, listing published, notification delivered, or subscription activated. The client observes `commandReceipts/{commandId}` and canonical/projection changes until a terminal result. Error `details` contain only safe remediation data, never another user's record or secrets.

Stable domain error codes include:

```text
UNAUTHENTICATED, APP_CHECK_REQUIRED, PERMISSION_DENIED,
ACCOUNT_NOT_APPROVED, ACCOUNT_SUSPENDED, SUBSCRIPTION_INACTIVE,
ENTITLEMENT_MISSING, UNIT_LIMIT_REACHED, VALIDATION_FAILED,
NOT_FOUND, ALREADY_EXISTS, VERSION_CONFLICT,
IDEMPOTENCY_KEY_REUSED, RATE_LIMITED, REQUIRES_ONLINE,
PAYMENT_PROVIDER_UNAVAILABLE, PAYMENT_PENDING, INTERNAL_RETRYABLE
```

Map these to callable HTTPS status codes, but branch client behavior on the stable domain code.

## Command catalog

Names are versioned contracts. Payload schemas should live beside Functions and have unit tests.

| Domain | Commands | Authority notes |
| --- | --- | --- |
| Identity | `profile.update`, `profile.registerDevice`, `profile.unregisterDevice`, `landlord.onboard` | `profile.update` accepts validated display/contact, the `en`, `lg`, `sw`, or `ar` locale, and personal notification preferences only; device commands bind or revoke the current FCM token; server controls identity, role, and status fields |
| Admin | `landlord.approve`, `landlord.suspend`, `landlord.reinstate` | platform-admin or super-admin claim; mandatory reason and audit; privileged-account management is super-admin-only |
| Admin | `user.archive`, `user.restore`, `user.delete` | super-admin claim only, never self; mandatory reason and audit; versioned against `users/{uid}`. Archive marks the profile `archived`, disables the Auth account (background job), and unpublishes any landlord listings; restore reverses it. Delete is legal only from `archived`: it tombstones the profile (`isDeleted`, hidden from the directory) and deletes the Auth account via a background job |
| Admin | `user.changeRole` | super-admin claim only, never self, never on an archived account; ordinary roles (`client`, `tenant`, or `landlord`) only — administrator privileges are Auth custom claims granted exclusively by the ops script. Promotion to landlord provisions the missing landlord aggregates fail-closed (`pending` approval, `pending_payment` subscription); demotion leaves them in place as the audited record |
| Portfolio | `property.create/update/archive`, `unit.create/update/archive/restore` | owning landlord or audited Admin/Super Admin acting for a canonical target landlord; account/entitlement checks; property create/update accepts at most five validated staged image paths in display order (first is primary); unit counter transaction. Landlords may set vacant/reserved/maintenance/inactive availability when no lease is active; `occupied` is tenancy-managed |
| Tenancy | `tenant.invite/update`, `lease.create/activate/end` | owning landlord; activation checks unit occupancy; tenant acceptance policy **TBD** |
| Billing | `invoice.generate`, `payment.initiate`, `payment.recordManual`, `receipt.regenerate` | server computes money; provider/server confirms payment |
| Maintenance | `maintenance.create`, `maintenance.updateStatus`, `maintenance.addComment` | tenant lease scope or owning landlord; transition matrix enforced |
| Communication | `notice.publish`, `notification.markRead` | server resolves notice audiences and queues notification jobs; inbox content/recipient are server-owned and the client may only mark its own item read |
| Listing | `listing.saveDraft/publish/unpublish` | owner or audited Admin/Super Admin acting for the canonical landlord; approval, availability, advertising entitlement, moderation |
| Application | `application.submit/withdraw`, `contact.submit` | applicant identity from auth; active listing, App Check, throttling |
| Reporting | `report.request` | scoped parameters; asynchronous server-derived document |
| Documents | `document.finalizeUpload/delete` | staging object ownership, checksum/type/size, owning aggregate access |
| Subscription | `subscription.selectPlan` | owner only; tier validated against server entitlement config; rejected once `active` — can never change status |
| Subscription | `subscription.requestUpgrade` | owner only, `active` subscriptions only; records `requestedTier` (validated against entitlement config, must differ from the current tier), the chosen `billingChannel` (`mobile_money`/`card`/`cash`), and an `upgradeState` — never entitlements. `cash` parks the request as `awaiting_admin` for manual confirmation. `mobile_money`/`card` are the electronic path (`awaiting_payment`, auto-confirmed by the aggregator webhook) and **fail closed with `PAYMENT_PROVIDER_UNAVAILABLE`** until `backendConfig/subscriptionBilling.enabled` is true, so a plan is never upgraded against money that never moved. Re-requesting overwrites the previous request |
| Subscription | `subscription.confirmPayment` | Admin/Super Admin only, never self; the audited transition to `active`. It is both the manual (cash) confirmation and the exact transition the electronic aggregator's signed webhook will call to auto-activate a `mobile_money`/`card` upgrade with no admin. Also approves a still-`pending` landlord account (`approvalReasonCode: PAYMENT_CONFIRMED`) in the same transaction; rejects over a `suspended` account so payment never undoes a suspension. On an already-`active` subscription it applies a paid plan change instead (explicit `tier` or the landlord's `requestedTier`, clearing the request and its billing channel, recording `planChangedAt`); an active subscription with no tier change still rejects |
| Subscription | `plan.update` | super-admin claim only; edits one existing `planCatalog/{tier}` (prices, presentation, feature `implemented` flags, visibility) and mirrors changed limits into `backendConfig/entitlements` in the same transaction so display and enforcement cannot drift. Tier travels in the payload (`expectedCatalogVersion` is the concurrency token) because tier IDs are shorter than the envelope aggregateId pattern. Rejects a yearly price above twelve monthly payments |
| Communication | `platform.broadcast` | super-admin claim only; records a `platformBroadcasts/{id}` announcement targeted at `all_users`, a role group (`landlords`/`tenants`/`clients`), one subscription `tier`, or one `user`, then hands delivery (notification inbox + push + email copy) to the durable `broadcastFanout` job. Scoped audiences are validated up front — unknown tiers fail closed, missing/deleted users reject with NOT_FOUND |

New landlord subscriptions start as `pending_payment`, and landlord workspace
access requires `active`. A landlord may change the tier they intend to pay for
with `subscription.selectPlan` while unpaid, but activation happens only
through `subscription.confirmPayment` — platform staff today (see
`scripts/confirm-subscription.mjs`), a signed billing webhook once provider
integration exists. There is no self-service confirmation. Plan prices and
limits live in the server-owned catalog (seeded by
`scripts/seed-entitlements.mjs`, edited by super admins via `plan.update` —
see docs/architecture/subscription-tiers.md for the launch prices). Payment
provider schemas remain **TBD**, so in-app checkout remains unavailable and
fails closed.

Confirming payment is also the account activation: if the landlord account is
still `pending` approval, the same transaction approves it, so a confirmed
payment fully opens the workspace without a separate `landlord.approve` step.
`landlord.approve` remains available for approving an account ahead of payment.
A `suspended` account is never reopened by payment — the command rejects, and
`landlord.reinstate` stays the only path back from suspension.

## Idempotent execution

For Firestore-only commands, one transaction:

1. Reads `commandReceipts/{commandId}`.
2. If it exists, checks actor UID and request hash, then returns the prior result.
3. Loads current actor/account/subscription/aggregate records.
4. Authorizes the action and checks `expectedVersion`.
5. Calculates server-owned fields and writes canonical record, relevant projections, counters, audit event, and terminal receipt.
6. Uses server timestamps and increments aggregate version exactly once.

Do not call payment, email, FCM, or other remote providers inside a Firestore transaction; transactions can retry. Instead, the transaction writes a durable `backendJobs` record and an `accepted` receipt. A worker claims the job with a lease, calls the provider using the command ID as its provider idempotency key where supported, then commits the result. At-least-once delivery is assumed everywhere.

### Callable pseudocode

```ts
executeCommand = onCall({ enforceAppCheck: true, region: REGION }, async request => {
  requireAuthenticated(request.auth);
  const cmd = parseStrictEnvelope(request.data);
  const actor = actorFromVerifiedToken(request.auth); // never payload.uid
  const requestHash = hashCanonicalCommand(cmd);
  const receiptRef = db.doc(`commandReceipts/${cmd.commandId}`);

  return db.runTransaction(async tx => {
    const prior = await tx.get(receiptRef);
    if (prior.exists) {
      requireSameActorAndHash(prior.data(), actor.uid, requestHash);
      return safeResponse(prior.data());
    }

    // handler reads all required documents via tx, validates role/ownership,
    // current approval + subscription, payload schema, and expectedVersion.
    const outcome = await handlers[cmd.type].apply({ tx, actor, cmd });

    tx.create(receiptRef, {
      actorUid: actor.uid,
      requestHash,
      type: cmd.type,
      aggregateId: cmd.aggregateId,
      status: outcome.isAsync ? 'accepted' : 'applied',
      safeResult: outcome.safeResult,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      expiresAt: receiptRetentionDeadline()
    });
    tx.create(db.collection('auditLogs').doc(), redactedAudit(actor, cmd, outcome));
    return outcome.response;
  });
});
```

Validation/authorization failures can either be returned without persistence or stored as a `rejected` receipt in a short transaction. Persisting deterministic rejections is preferred so offline retries get a stable answer. Rate-limit checks occur before expensive reads; security-relevant rejection logging is redacted.

## Required transactional handlers

### Unit creation

```text
read landlord account + subscription + versioned plan configuration
require owner, approved, not suspended, active paid subscription, unit-management entitlement
read property and require same landlord
read/check unit ID does not exist
require activeUnitCount < configured unitLimit (unknown limit => deny)
create unit(version=1, occupancyStatus=vacant)
increment activeUnitCount
write audit + command receipt
```

Archive/restore use aggregate state and command ID to ensure the counter changes once. A scheduled reconciler alerts on drift rather than silently rewriting without an audit record.

### Listing publication

```text
read private listing, unit, property, landlord account, subscription, entitlement config
require owner, approved, active paid subscription, advertising entitlement
require unit is vacant/available and no other active public listing for the unit
validate public text/media and moderation policy
validate structured public location (never exact address), unit facts,
amenities/accessibility, availability, disclosed charges/lease terms, and policies
construct a new public document from an explicit field allowlist
update private publication state + write public projection atomically
schedule expiry and public-media projection jobs
```

The client never supplies the public projection as a document. Unpublish/occupancy/suspension/subscription workers set private state and remove public readability idempotently.
Any transition away from `vacant` retires the active public listing in the same
transaction. This includes a direct landlord availability change,
`tenancy.establish`, and `lease.activate`: the private listing becomes
`unpublished`, the public document stops matching the public query, the unit's
active-listing pointer is cleared, and public-media cleanup is queued. A client
cannot set `occupied` through `unit.create` or `unit.update`; an active tenancy
is the authority for that state.

### Invoice and payment

```text
invoice.generate: load lease + server rent/fee configuration; calculate integer totals;
                  create invoice and tenant projection transactionally
payment.initiate: load invoice balance and provider config; create pending payment + provider job
provider callback: verify signature before trusting event; claim provider event ID once;
                   update payment/allocations/invoice balance; issue receipt only when confirmed;
                   update tenant projections + audit in one transaction
```

Refunds, reversals, chargebacks, overpayments, partial allocations, and manual-payment evidence require explicit states and tests before production. **TBD:** provider and final accounting policy.

## Projection and notification workers

- Projectors are idempotent on `(canonicalId, canonicalVersion)` and never apply an older version over a newer projection.
- Every authenticated actor has one server-owned `notificationInboxes/{uid}/items/{notificationId}` read model. Business-event IDs produce deterministic notification IDs, so job replay cannot duplicate inbox rows. Widgets read the Sembast mirror; they never query this collection directly.
- Notification jobs store audience IDs and template/data IDs, not sensitive rendered bodies. Delivery resolves the recipient's validated locale, falls back to English, and writes the same localized copy to the durable inbox and push payload. Each delivery has a deduplication key.
- Scheduled invoice, listing-expiry, retention, and reconciliation jobs use a deterministic period/job ID so reruns do not duplicate records.
- Workers lease jobs transactionally, record attempt count/next attempt, and dead-letter after a configured threshold. **TBD:** retry/retention values and deployment region.
- Operational dashboards alert on job age, projection lag, dead letters, provider callback verification failures, unit-counter drift, and audit-write failures.

## Admin and provider boundaries

Admin commands require either the `platformAdmin` or `superAdmin` custom claim plus recent authentication for destructive/high-impact actions. Only a Super Admin may manage privileged accounts; self-promotion, self-suspension, and client-granted claims are forbidden. Approval/suspension reasons are enumerated, and every action records actor, target, source IP metadata where legally appropriate, and a redacted diff. The detailed matrix is in [role-permissions.md](role-permissions.md).

Billing/provider webhooks use dedicated HTTP endpoints, raw-body signature verification, Secret Manager credentials, provider event-ID deduplication, and replay-window checks. They do not trust a Firebase client token as proof of payment. Provider secrets and actual Firebase project IDs are intentionally absent from this repository.
