# Nyumba architecture

Status: implementation baseline. Decisions marked **TBD** must be resolved before a production release.

## Goals

Nyumba is a multi-tenant, offline-first Flutter application for web, Android, and iOS. The same codebase serves five authenticated experiences: super administrator, platform administrator, landlord, tenant, and prospective client. Anonymous visitors may browse the public marketplace. The architecture prioritizes:

- a useful read and write experience during intermittent connectivity;
- strict separation between landlord-private, tenant-private, administrative, and public listing data;
- server authority for money, subscriptions, approvals, entitlement limits, and publication;
- idempotent synchronization that tolerates retries and duplicate delivery;
- feature-level isolation so the property, tenancy, billing, maintenance, and listing domains can evolve independently.

Nyumba's four-language contract (English, Luganda, Kiswahili, and Arabic),
locale persistence, RTL rules, notification localization, and PDF behavior are
defined in [`localization.md`](localization.md).

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

- **Super admin:** identified by a server-issued `superAdmin` custom claim. This role manages privileged accounts and platform-wide configuration through audited operations.
- **Platform admin:** identified by a separate server-issued `platformAdmin` custom claim. It has broad operational access but cannot manage Admin or Super Admin accounts.
- **Landlord:** normally owns the account whose ID equals their Firebase UID. Approval and subscription records are server-owned and checked at mutation time.
- **Tenant:** reads a UID-scoped tenant portal. The server creates or removes projections as lease access changes.
- **Client:** may browse public listings anonymously. Contact and application submission require Firebase Authentication (anonymous authentication is acceptable), App Check, rate limiting, and server validation.

Do not trust a `uid`, `landlordId`, role, amount, status, unit count, or timestamp supplied in a client payload. Derive identity from the verified token and derive sensitive values from server documents/provider events.

The complete CRUD matrix and privileged-role constraints are normative in
[role-permissions.md](role-permissions.md).

## Canonical value conventions

- IDs are client-generated UUIDv7/ULID-style identifiers where offline creation is needed. A retry must reuse the same ID.
- Money is `{amountMinor: integer, currency: ISO-4217}`; never store floating-point currency values.
- Firestore timestamps are UTC server timestamps. `Africa/Kampala` is a presentation/reporting timezone, not a storage format.
- Mutable aggregates carry a monotonically increasing `version`, `createdAt`, `updatedAt`, and optional `deletedAt`.
- Deletion is a server-written tombstone (`isDeleted: true`, `deletedAt`) until every supported sync horizon has elapsed. Hard deletion is a retention job.
- Sensitive fields are omitted from projections rather than hidden only in the UI.

## Operational baseline

- Separate Firebase projects for development, staging, and production. The connected development project is `nyumba-property-management` (Blaze plan); staging and production project IDs are **TBD**.
- Regional deployment is finalized as **`europe-west1`** for Firestore, Cloud Functions, and Storage (full product availability with reliable latency to East Africa).
- Enforce App Check for callable Functions, Firestore, and Storage after each platform is registered.
- Use the Firebase Emulator Suite for rules and command integration tests.
- Export audit logs and monitor rejected rules, command failures, duplicate provider callbacks, projection lag, outbox age, and notification failures.
- Back up Firestore and define retention/deletion policies before collecting production data.
- Clear user-scoped local data and Firebase persistence on sign-out/account switch. Mobile local storage containing private data should be encrypted with a key protected by the OS keystore; web storage should minimize retained PII.

## Finalized product configuration

Decided on 2026-07-14 (client mirror in `lib/core/config/market_config.dart`; the backend remains authoritative and must validate independently):

- **Market:** Uganda only at launch. Currency is UGX (amounts stored in integer minor units), phone numbers are E.164 `+256` followed by nine digits, reporting timezone is `Africa/Kampala`. Payment rails are MTN Mobile Money, Airtel Money, bank transfer, and landlord-recorded cash. Uganda VAT (standard 18%) applies to platform subscription fees and is computed server-side only.
- **Region:** `europe-west1` for Firestore, Cloud Functions, and Storage.
- **Web origin:** `https://nyumba.online` is the planned canonical production
  origin. It currently serves the `nyumba-property-management` development
  Firebase project and must be treated as a development deployment until a
  separate production project is provisioned and the domain is mapped to it.
  Generated Firebase Hosting hostnames are deployment endpoints, not canonical
  public URLs.
- **Public listings:** a published listing expires 30 days after (re)publication; landlords can renew. Expiry is enforced by a backend projection job, never by the client.
- **Upload limits:** property photos max 5 per property and listing photos max 10 per listing, 5 MB each (`image/jpeg`, `image/png`, `image/webp`); documents max 10 MB (`application/pdf`, `image/jpeg`, `image/png`). Enforced in `firebase/storage.rules` and the finalizing command handler. Property media order is significant: the first accepted image is the primary image.
- **Retention:** financial records (invoices, payments, receipts) 7 years; deleted listings and their media purged 90 days after deletion; maintenance media 2 years.

## Unresolved product configuration

The following values must not be hard-coded in Flutter or security rules:

- **TBD:** staging/production Firebase project IDs and application IDs,
  environment sender IDs, and the staging hosting domain. The planned
  production hosting origin is finalized as `https://nyumba.online`, but its
  current Firebase project mapping is development-only;
- Tier structure, capability matrix, suggested limits, free tenant/prospect access, non-paywall rules, and downgrade policy are defined in [subscription-tiers.md](subscription-tiers.md). **TBD:** monetary prices, billing intervals, trials, and exact grace-period lengths;
- Money routing is **decided**: Nyumba's own merchant account collects
  subscription payments only. Rent is the landlord's money and must settle to
  the landlord, never through a Nyumba-held balance — so a rent adapter has to
  collect into a landlord-owned destination (provider subaccount or equivalent),
  and any integration that pools rent into Nyumba's account is wrong regardless
  of how it settles afterwards. **TBD:** aggregator choice, how landlords are
  onboarded to their collection destination, fees, reconciliation policy, and
  the webhook contract;
- **TBD:** listing moderation policy, application retention, and contact-channel policy;
- **TBD:** local offline retention horizon on device.

Until finalized, backend configuration should fail closed: an unknown plan grants no publishing or unit-creation entitlement, and a missing payment configuration cannot mark a payment successful.

## Enabling App Check and push (operator steps)

Status (2026-07-16): the development project's web reCAPTCHA v3 site key and web
push VAPID key are registered and wired into the deploy workflow
(`.github/workflows/ci-cd.yml`). Both values are public by design (they ship in
the web bundle) but environment-specific — a staging/production workflow must
register and carry its own. `ENFORCE_APP_CHECK` remains **off**; see the
enforcement sequence below.

**App Check (web).** Register the web app in Firebase Console → App Check,
choosing reCAPTCHA v3. Pass the issued site key at build time:

```sh
flutter build web --release --dart-define=NYUMBA_RECAPTCHA_V3_SITE_KEY=<site-key>
```

An empty define skips activation entirely, so a local `flutter run` without it
still works — requests are simply unattested.

**App Check (Android).** Registered (Play Integrity, 2026-07-16); no build
input is needed. However, Play Integrity only returns valid verdicts for builds
installed **from Google Play** (any track, including internal testing). APKs
sideloaded from GitHub Releases never attest — additionally, CI builds fall
back to the runner's throwaway debug keystore (`android/key.properties` is
absent in CI), whose signature is not registered, so Google sign-in also fails
on those artifacts. Local builds signed with the registered debug keys are
unaffected. **App Check (iOS).** App Attest requires a paid Apple Developer
team; deferred until one exists — which costs nothing today, because iOS cannot
be distributed at all without one.

**Enforcement sequence.** Do not flip `ENFORCE_APP_CHECK`
(`firebase/functions/src/shared/config.ts`) or console enforcement immediately:

1. Deploy with the site key active and Android registered.
2. Publish the Android app to a Play track (internal testing is enough) with a
   real upload keystore whose SHA-256 is registered in Firebase — sideloaded
   APKs can never attest, so enforcing while Android users sideload locks all
   of them out while web keeps working.
3. Watch App Check request metrics in the console until verified traffic
   dominates (a day or two of real usage).
4. Register a **debug token** for local development (console → App Check →
   Apps → manage debug tokens) — after enforcement, un-attested local runs are
   rejected.
5. Flip `ENFORCE_APP_CHECK`, deploy functions, then enable console enforcement
   for Firestore and Storage.

iOS absence is irrelevant while no iOS build can ship.

**Push (web).** Firebase Console → Project settings → Cloud Messaging → Web
Push certificates → generate a key pair. Pass the public key at build time:

```sh
flutter build web --release --dart-define=NYUMBA_VAPID_PUBLIC_KEY=<public-key>
```

Without it, `registerForPush` returns `unavailable` and web push is simply off.
`web/firebase-messaging-sw.js` reads its Firebase config from the registration
URL. The Flutter registration code supplies that environment's `FirebaseOptions`
as an encoded query parameter, so the worker needs no editing per environment.

Push is a courtesy channel over the durable in-app inbox. Application,
enquiry, and tenant-notice workers first create an idempotent
`notificationInboxes/{uid}/items/{notificationId}` document, then attempt FCM.
Foreground messages render an in-app banner; notification taps accept only a
small allowlist of application routes. Signing out revokes and deletes the
device token before the Firebase Auth session closes.

**Push (iOS).** Requires the same paid Apple Developer account: an APNs auth
key (`.p8`) uploaded under Cloud Messaging → Apple app configuration, plus Push
Notifications and Background Modes → Remote notifications in Xcode. Android
needs nothing beyond `google-services.json`.

**Application email.** Not configured. Firebase Auth may still send its own
verification and password-reset templates, but Nyumba has no transactional
mail provider, SMTP extension, mail job adapter, sender-domain verification, or
bounce/complaint processing. Enabling application email requires a selected
provider, SPF/DKIM/DMARC for the sending domain, provider credentials in Secret
Manager, durable idempotent mail jobs/templates, preference enforcement, and
delivery/bounce observability. Firebase Hosting custom-domain approval is
separate from email-domain verification.
