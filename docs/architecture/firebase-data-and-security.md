# Firebase data and security model

This is the target logical model, not a request to expose every collection directly to Flutter. Canonical writes go through authenticated Cloud Functions. Firestore Rules permit only scoped reads; the small public and tenant/client read models are server-owned projections.

## Trust boundaries

| Actor | May read | May mutate |
| --- | --- | --- |
| Anonymous browser | active `publicListings` and public listing media | nothing |
| Authenticated client/applicant | own profile and `clientPortals/{uid}`; public listings | contact/application commands, subject to App Check/rate limits |
| Tenant | own profile and `tenantPortals/{uid}` | tenant commands such as maintenance submission and payment initiation |
| Landlord | canonical documents whose `landlordId` equals their UID; own account/subscription | landlord commands if approval/subscription/feature policy permits |
| Platform admin | operational collections required by admin role | audited admin commands; billing still follows provider authority |
| Cloud Functions/service accounts | canonical and projection data required by the operation | validated transactions, projections, jobs, provider callbacks |

Firestore and Storage Rules are not applied to Admin SDK calls. Every function must therefore repeat authentication, authorization, validation, account-state, entitlement, and ownership checks. UI route guards are never a security boundary.

## Identity and roles

- Firebase Authentication UID is the actor identifier.
- `platformAdmin: true` is a server-issued custom claim and is required for platform-wide reads/commands. Never infer admin from an email domain or a writable document.
- `users/{uid}.role` drives UI routing but remains server-owned. Supported values are `client`, `tenant`, `landlord`, and `admin`; a user may gain tenant and landlord capabilities over time, so authorization should check actual relationships/claims as well as display role.
- The initial model assumes one owner per landlord account and uses `landlordId == owner UID`. **TBD:** if staff/collaborator accounts are required, add a server-owned membership collection and explicit permissions; do not overload role strings.
- `landlordAccounts/{uid}.approvalStatus` and `subscriptions/{uid}.status` are mutable server documents, not long-lived custom claims, so suspension or expiry takes effect without waiting for token refresh.

## Canonical private collections

All canonical records include `id`, integer `version`, `createdAt`, `updatedAt`, `isDeleted`, and optional `deletedAt` unless noted. Timestamps are server timestamps.

| Path | Selected fields | Read scope / authority |
| --- | --- | --- |
| `users/{uid}` | role, status, safe profile, locale, accessGeneration | self/admin; server writes except command-based profile updates |
| `landlordAccounts/{landlordId}` | ownerUid, approvalStatus, approvalReasonCode, approvedAt, suspendedAt, activeUnitCount | owner/admin; approval and count are server-only |
| `subscriptions/{landlordId}` | tier, status, provider refs, period dates, entitlementsVersion | owner/admin; billing webhook/server-only |
| `planCatalog/{tier}` | display name, public price projection, `isPublic` | published plans may be public; server-only writes |
| `properties/{propertyId}` | landlordId, name, private address, property type, internal notes | owning landlord/admin |
| `units/{unitId}` | landlordId, propertyId, label, type, rentMinor, currency, occupancyStatus | owning landlord/admin |
| `tenantRecords/{tenantRecordId}` | landlordId, userUid?, contact details, emergency/contact metadata | owning landlord/admin |
| `leases/{leaseId}` | landlordId, unitId, tenantRecordId, tenantUserUid?, terms, dates, status | owning landlord/admin; tenant gets projection |
| `invoices/{invoiceId}` | landlordId, leaseId, tenantUserUid?, line items, totals, balance, due date, status | owning landlord/admin; tenant gets projection |
| `payments/{paymentId}` | landlordId, invoice allocations, amountMinor, currency, method, provider refs, status, paidAt | owning landlord/admin; provider/server controls confirmation |
| `receipts/{receiptId}` | landlordId, paymentId, receipt number, amount, issuedAt, documentId | owning landlord/admin; tenant gets projection |
| `maintenanceRequests/{requestId}` | landlordId, leaseId/unitId, tenantUserUid, category, priority, description, status | owning landlord/admin; tenant gets projection |
| `notices/{noticeId}` | landlordId, audience selector, subject/body, publish state | owning landlord/admin; recipients get projections |
| `documents/{documentId}` | landlordId, storage path, checksum, content type, byte size, owning aggregate | owning landlord/admin; recipients get projections |
| `privateListings/{listingId}` | landlordId, unitId, draft content, moderation, publication state | owning landlord/admin |
| `applications/{applicationId}` | landlordId, listingId, applicantUid, answers, status, landlord notes | owning landlord/admin; applicant gets projection without notes |
| `contactRequests/{requestId}` | landlordId, listingId, requesterUid, message, delivery state | owning landlord/admin; requester gets safe projection |
| `reportSnapshots/{reportId}` | ownerType/ownerId, parameters, derived totals, generated document | owning landlord or admin according to owner fields |
| `commandReceipts/{commandId}` | actorUid, command type, aggregate, status, safe result/error, timestamps | originating actor/admin; server-only writes |
| `auditLogs/{eventId}` | actor, action, target, before/after hashes or redacted diff, source, timestamp | admin-only; append-only server writes |
| `backendJobs/{jobId}` / `providerEvents/{eventId}` | processing state, retry metadata, provider event hash | server-only; no client reads |

Landlord reads must query using `where('landlordId', isEqualTo: currentUid)`; rules do not filter an unscoped query after the fact. Private documents may contain exact addresses, unit labels, contact details, internal notes, provider references, and reconciliation data, so they are never reused as public results.

## Tenant and client projections

Tenant access is represented under the tenant's UID, not inferred in a client query across private collections:

```text
tenantPortals/{tenantUid}
  leases/{leaseId}
  invoices/{invoiceId}
  payments/{paymentId}
  receipts/{receiptId}
  maintenance/{requestId}
  notices/{noticeId}
  documents/{documentId}

clientPortals/{clientUid}
  applications/{applicationId}
  contactRequests/{requestId}
```

Projection documents include the canonical ID/version and only fields needed by that actor. They are written idempotently by the same transaction as the canonical mutation when practical, or by an idempotent projector with measurable lag. Removing lease/application access increments the portal root's `accessGeneration` and removes or tombstones affected projections.

Projection rules are UID-path based and all projection writes are denied to clients. A landlord cannot read a tenant portal merely because one of their leases appears in it; the landlord reads the canonical collection instead.

## Public listing projection

`publicListings/{listingId}` is a deliberate, denormalized whitelist. It may contain:

- listing ID and opaque landlord/public contact token;
- title, description, property/unit type, amenities, bedroom/bathroom counts;
- county/city/neighborhood and an intentionally approximate map location;
- monthly rent in integer minor units and currency;
- server-approved public image paths;
- `status`, `publishedAt`, `expiresAt`, and projection version.

It must not contain the exact address, private unit label, landlord email/phone unless product policy explicitly opts in, tenant/occupancy identity, internal notes, provider IDs, document paths, or private property/unit snapshots. Contact flows reference the listing ID and let the server route the message without revealing private contact data.

Public reads require `status == 'published'` and `expiresAt > request.time`. Browse queries must include those constraints and a page limit of at most 50; the composite index is provided in `firebase/firestore.indexes.json`. Publication images live under a separate public Storage prefix and are server-copied only after validation.

## Server-authoritative invariants

### Landlord approval and suspension

Only an admin command may approve or suspend. It writes the account state and audit event in a transaction. Every landlord mutation reloads the account; a suspended account cannot mutate portfolio, publish, or contact applicants. Read/export access remains available by default. **TBD:** legal/product policy for read access and active tenant operations during suspension. Tenant maintenance and access to their own records should remain available unless a safety/legal policy says otherwise.

### Subscription and unit limits

The payment/billing provider webhook controls subscription status. The client can request checkout but cannot activate a tier. `createUnit` transactionally reads the account, subscription, plan entitlement, and current counter; it creates the unit and increments the counter only if below the limit. Archive/restore adjusts counters idempotently. A periodic reconciliation compares counters with canonical active units.

**TBD:** exact Starter/Pro/Premium/Enterprise prices, billing periods, unit limits, grace periods, and features. They belong in versioned backend configuration, not Flutter or rules. Until configured, unknown/missing entitlements fail closed. Advertising requires approval plus an active/trialing subscription and an explicit advertising entitlement.

### Payments, invoices, and receipts

The server calculates invoice totals from validated line items. Electronic payments begin as `pending`; only a verified, deduplicated provider webhook may set `confirmed`/`failed`. The callback transaction records the provider event ID, payment, allocations, invoice balances, receipt, tenant projections, and an audit event. Manual payments require an authorized landlord command, evidence/reference policy, and audit trail. Never trust client amount, paid time, provider status, or receipt number. **TBD:** payment provider and final reconciliation/refund/chargeback policy.

### Listing publication

`listing.publish` transactionally checks ownership, landlord approval, active entitlement, unit existence, unit availability, content validation, media validation, moderation policy, and absence of a conflicting active listing. It then updates the private state and writes the public whitelist projection. Suspension, subscription loss, unit occupancy, explicit unpublish, or expiry removes public readability and schedules public-media cleanup. **TBD:** listing lifetime and moderation policy; the secure default is to stop or unpublish advertising when entitlement is inactive.

## Security controls outside rules

- Enforce App Check for Firestore, Storage, and callable Functions; use rate limits and abuse detection for contact/application endpoints.
- Verify provider webhook signatures against secrets held only in Secret Manager. Never ship secrets in Flutter, this repository, or Firebase config files.
- Validate all payloads with allowlisted fields, lengths, enum values, normalized phone/email formats, integer money bounds, and ownership derived from server reads.
- Use random opaque IDs; existence of an ID never grants access.
- Redact PII and payment details from logs, analytics, crash reports, notifications, and audit diffs.
- FCM payloads contain IDs and generic text, not balances, addresses, lease details, or maintenance descriptions; the app fetches authorized data.
- Apply retention/TTL jobs to staging uploads, command receipts, provider payloads, contact requests, and tombstones only after product/legal policies are approved.
- Test rules against cross-landlord queries, forged IDs/roles, expired listings, suspended accounts, tenant-to-tenant access, admin-claim absence, and emulator/Admin SDK differences.

## Deployment placeholders

No project ID or secret is committed. Create environment-specific aliases only after the Firebase projects exist:

```text
dev     -> TBD_NYUMBA_FIREBASE_DEV_PROJECT_ID
staging -> TBD_NYUMBA_FIREBASE_STAGING_PROJECT_ID
prod    -> TBD_NYUMBA_FIREBASE_PROD_PROJECT_ID
```

The checked-in `firebase/firebase.json` references rules and indexes only. Real project selection belongs in local/CI environment configuration, and production deployment should require review and emulator tests.
