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
| Identity | `profile.update`, `landlord.onboard` | `profile.update` accepts validated display/contact and personal notification preferences only; server controls identity, role, and status fields |
| Admin | `landlord.approve`, `landlord.suspend`, `landlord.reinstate` | platform-admin or super-admin claim; mandatory reason and audit; privileged-account management is super-admin-only |
| Portfolio | `property.create/update/archive`, `unit.create/update/archive/restore` | owning landlord or audited Admin/Super Admin acting for a canonical target landlord; account/entitlement checks; property create/update accepts at most five validated staged image paths in display order (first is primary); unit counter transaction |
| Tenancy | `tenant.invite/update`, `lease.create/activate/end` | owning landlord; activation checks unit occupancy; tenant acceptance policy **TBD** |
| Billing | `invoice.generate`, `payment.initiate`, `payment.recordManual`, `receipt.regenerate` | server computes money; provider/server confirms payment |
| Maintenance | `maintenance.create`, `maintenance.updateStatus`, `maintenance.addComment` | tenant lease scope or owning landlord; transition matrix enforced |
| Communication | `notice.publish` | server resolves audience and queues notification job |
| Listing | `listing.saveDraft/publish/unpublish` | owner or audited Admin/Super Admin acting for the canonical landlord; approval, availability, advertising entitlement, moderation |
| Application | `application.submit/withdraw`, `contact.submit` | applicant identity from auth; active listing, App Check, throttling |
| Reporting | `report.request` | scoped parameters; asynchronous server-derived document |
| Documents | `document.finalizeUpload/delete` | staging object ownership, checksum/type/size, owning aggregate access |

Subscription activation/change is initiated by a checkout command but finalized only by a signed billing webhook. Exact plan pricing/limits and payment provider schemas are **TBD**.

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
require owner, approved, not suspended, active/trialing, unit-management entitlement
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
require owner, approved, active/trialing, advertising entitlement
require unit is vacant/available and no other active public listing for the unit
validate public text/media and moderation policy
validate structured public location (never exact address), unit facts,
amenities/accessibility, availability, disclosed charges/lease terms, and policies
construct a new public document from an explicit field allowlist
update private publication state + write public projection atomically
schedule expiry and public-media projection jobs
```

The client never supplies the public projection as a document. Unpublish/occupancy/suspension/subscription workers set private state and remove public readability idempotently.

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
- Notification jobs store audience IDs and template/data IDs, not sensitive rendered bodies. Each delivery has a deduplication key.
- Scheduled invoice, listing-expiry, retention, and reconciliation jobs use a deterministic period/job ID so reruns do not duplicate records.
- Workers lease jobs transactionally, record attempt count/next attempt, and dead-letter after a configured threshold. **TBD:** retry/retention values and deployment region.
- Operational dashboards alert on job age, projection lag, dead letters, provider callback verification failures, unit-counter drift, and audit-write failures.

## Admin and provider boundaries

Admin commands require either the `platformAdmin` or `superAdmin` custom claim plus recent authentication for destructive/high-impact actions. Only a Super Admin may manage privileged accounts; self-promotion, self-suspension, and client-granted claims are forbidden. Approval/suspension reasons are enumerated, and every action records actor, target, source IP metadata where legally appropriate, and a redacted diff. The detailed matrix is in [role-permissions.md](role-permissions.md).

Billing/provider webhooks use dedicated HTTP endpoints, raw-body signature verification, Secret Manager credentials, provider event-ID deduplication, and replay-window checks. They do not trust a Firebase client token as proof of payment. Provider secrets and actual Firebase project IDs are intentionally absent from this repository.
