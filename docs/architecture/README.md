# Nyumba architecture

Status: implementation baseline. Decisions marked **TBD** must be resolved before a production release.

## Goals

Nyumba is a multi-tenant, offline-first Flutter application for web, Android, and iOS. The same codebase serves four experiences: platform administrator, landlord, tenant, and prospective client. The architecture prioritizes:

- a useful read and write experience during intermittent connectivity;
- strict separation between landlord-private, tenant-private, administrative, and public listing data;
- server authority for money, subscriptions, approvals, entitlement limits, and publication;
- idempotent synchronization that tolerates retries and duplicate delivery;
- feature-level isolation so the property, tenancy, billing, maintenance, and listing domains can evolve independently.

## Dependency rule

Each feature is split into four conceptual layers. Dependencies point inward only.

```text
presentation (Flutter + Riverpod + routing)
              |
application (use cases, policies, orchestration)
              |
domain (entities, value objects, repository contracts)
              ^
data (Sembast stores, Firebase adapters, DTOs, sync engine)
```

- **Domain** is pure Dart. It does not import Flutter, Firebase, Sembast, JSON DTOs, or UI state.
- **Application** coordinates repository contracts and expresses use-case results. It owns decisions such as whether a mutation may be optimistic.
- **Data** maps between domain models, local records, Firestore documents, Storage objects, and callable command envelopes.
- **Presentation** renders repository streams and invokes use cases. Widgets do not query Firestore or open Sembast directly.

Cross-cutting code belongs in a small core area: identifiers, clocks, money, failures, authentication session, connectivity hints, and synchronization primitives. Avoid a generic `utils` layer and avoid importing one feature's data implementation from another feature.

## Feature boundaries

| Feature | Primary aggregates | Important invariants |
| --- | --- | --- |
| Identity | user, actor session | role and account status are not client-authoritative |
| Subscriptions | plan, entitlement, subscription | provider/webhook controls status; unit limits are transactional |
| Portfolio | property, unit | a unit belongs to one property and landlord; archived units are retained |
| Tenancy | tenant, lease | one active occupancy per unit; lease lifecycle is server-controlled |
| Billing | invoice, payment, receipt | amounts use integer minor units; confirmed provider events settle invoices |
| Maintenance | request, update, attachment | tenant can submit for an accessible tenancy; status transitions are authorized |
| Communications | notice, delivery | audience is derived server-side; delivery is asynchronous |
| Listings | private listing, public projection | only approved and entitled landlords can publish available units |
| Applications | application, contact request | applicant identity and listing state are validated server-side |
| Reporting | report projection | aggregates are derived from canonical records, never client totals |
| Documents | document metadata, stored object | access follows the owning lease/property and is rechecked on download |

Aggregates reference each other by stable IDs, not embedded mutable objects. Read models may intentionally duplicate display fields; canonical writes remain in the owning aggregate.

## Local and remote responsibilities

Sembast is the application's local source of truth on every platform. Repository reads emit local records immediately. Firestore listeners and cursor-based pulls update those records; they do not feed widgets directly. Firestore's built-in persistence may remain enabled as a transport optimization, but it is not a second application cache.

Local writes and an outbox entry are committed in one Sembast transaction. The sync runner later sends the outbox command to a callable Cloud Function. For low-risk edits, the local record can be shown optimistically. Financial state, approval, subscription state, lease activation, and publication never appear as confirmed before a server response or pull. Detailed semantics are in [offline-sync.md](offline-sync.md).

The remote model uses canonical private collections plus purpose-built projections:

- landlord/admin queries read canonical documents filtered by `landlordId`;
- tenants read a server-owned `tenantPortals/{uid}/...` projection containing only their permitted fields;
- unauthenticated browsing reads `publicListings`, never private properties or units;
- reports and audit events are server-derived.

The collection and security contract is in [firebase-data-and-security.md](firebase-data-and-security.md). Mutating operations and idempotency are in [backend-command-contracts.md](backend-command-contracts.md).

## Actor and authorization model

Route guards and role-specific navigation improve user experience but are not authorization controls. Every remote operation is checked again by Firestore/Storage Rules or a Cloud Function.

- **Platform admin:** identified by a server-issued `platformAdmin` custom claim. Administrative mutations go through audited functions.
- **Landlord:** normally owns the account whose ID equals their Firebase UID. Approval and subscription records are server-owned and checked at mutation time.
- **Tenant:** reads a UID-scoped tenant portal. The server creates or removes projections as lease access changes.
- **Client:** may browse public listings anonymously. Contact and application submission require Firebase Authentication (anonymous authentication is acceptable), App Check, rate limiting, and server validation.

Do not trust a `uid`, `landlordId`, role, amount, status, unit count, or timestamp supplied in a client payload. Derive identity from the verified token and derive sensitive values from server documents/provider events.

## Canonical value conventions

- IDs are client-generated UUIDv7/ULID-style identifiers where offline creation is needed. A retry must reuse the same ID.
- Money is `{amountMinor: integer, currency: ISO-4217}`; never store floating-point currency values.
- Firestore timestamps are UTC server timestamps. `Africa/Nairobi` is a presentation/reporting timezone, not a storage format.
- Mutable aggregates carry a monotonically increasing `version`, `createdAt`, `updatedAt`, and optional `deletedAt`.
- Deletion is a server-written tombstone (`isDeleted: true`, `deletedAt`) until every supported sync horizon has elapsed. Hard deletion is a retention job.
- Sensitive fields are omitted from projections rather than hidden only in the UI.

## Operational baseline

- Separate Firebase projects for development, staging, and production. **TBD:** actual Firebase project IDs.
- Enforce App Check for callable Functions, Firestore, and Storage after each platform is registered.
- Use the Firebase Emulator Suite for rules and command integration tests.
- Export audit logs and monitor rejected rules, command failures, duplicate provider callbacks, projection lag, outbox age, and notification failures.
- Back up Firestore and define retention/deletion policies before collecting production data.
- Clear user-scoped local data and Firebase persistence on sign-out/account switch. Mobile local storage containing private data should be encrypted with a key protected by the OS keystore; web storage should minimize retained PII.

## Unresolved product configuration

The following values must not be hard-coded in Flutter or security rules:

- **TBD:** Firebase project IDs, application IDs, hosting domains, sender IDs, and regional deployment choice;
- **TBD:** Starter, Pro, Premium, and Enterprise prices, billing intervals, unit limits, trials, grace periods, and feature entitlements;
- **TBD:** payment provider, supported currencies, fees, reconciliation policy, and webhook contract;
- **TBD:** public-listing lifetime, moderation policy, application retention, and contact-channel policy;
- **TBD:** document retention, maximum upload sizes by document type, and local offline retention horizon.

Until finalized, backend configuration should fail closed: an unknown plan grants no publishing or unit-creation entitlement, and a missing payment configuration cannot mark a payment successful.
