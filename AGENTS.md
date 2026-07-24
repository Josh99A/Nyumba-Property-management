# Nyumba coding-agent guide

This file applies to the whole repository. Read the more detailed contracts in
`docs/architecture/` and `firebase/README.md` before changing persistence,
synchronization, authorization, billing, subscriptions, or public listings.

## Product and current state

Nyumba is a multi-tenant, offline-first property-management app built with
Flutter for web, Android, and iOS. It serves four actor experiences:

- admins operate the platform, users, landlord approval, subscriptions, and reports;
- landlords manage properties, rentable units, tenants, leases, rent, maintenance,
  notices, documents, and advertisements;
- tenants view balances and documents, pay rent, and submit maintenance requests;
- prospective clients browse public listings, contact landlords, and apply for units.

The checked-in app runs against a real development Firebase project
(`nyumba-property-management`). Cloud Functions, rules, indexes, and the callable
command router are implemented and deployed by CI from `main`. Per-environment
Firebase config (`firebase_options.dart`, `google-services.json`, `.firebaserc`)
is generated locally and git-ignored; regenerate with FlutterFire rather than
inventing values.

Not yet real, and not to be presented as real:

- **Payments.** No mobile-money provider is integrated. `payment.initiate`
  enqueues a job whose adapter registry is empty, so initiation fails closed
  with `providerNotConfigured`, and electronic subscription upgrades fail
  closed with `PAYMENT_PROVIDER_UNAVAILABLE`. Both surface a plain message and
  point at the manual path; do not simulate a successful collection to make a
  flow demoable. Rent therefore moves outside the app and someone reports it:
  a landlord recording money they hold settles immediately
  (`payment.recordAgainstTenancy`), while a tenant's report
  (`payment.declare`, proof reference mandatory) is only a claim — it
  allocates nothing and moves no balance until the landlord confirms it, or
  a tenant could clear their own arrears by asserting them away. Provider choice, fees, reconciliation, and the webhook
  contract are TBD. Settlement is **not** TBD: Nyumba collects subscriptions
  only, and rent must settle to the landlord (see
  `docs/architecture/README.md`).
- **App Check.** Attestation is active on web (the dev project's reCAPTCHA v3
  site key is wired into the deploy workflow) but **enforcement is off** —
  follow the sequence in `docs/architecture/README.md` before flipping
  `ENFORCE_APP_CHECK`. iOS App Attest is deferred: it needs a paid Apple
  Developer team, without which no iOS build can ship anyway.
- **Tenant and prospect aggregate pulls.** Landlords pull `property`, `unit`,
  `listing` (canonical) plus `tenancy` and `payment` (via `landlordPortals`
  read models). Every authenticated actor pulls the common UID-scoped
  `notificationInboxes` read model. Tenant and prospect domain-aggregate
  scopes still pull nothing — see "Known model divergence" below.
- **Admin plan drafts.** Local-only working state. The admin *account
  directory* is real: live admin sessions stream `users`/`landlordAccounts`/
  `subscriptions`/`auditLogs` directly (admin-read-only by rule, no local
  mirror — see `FirestoreAdminDirectory`), and act through the audited
  `landlord.approve|suspend|reinstate`, `subscription.confirmPayment`, and
  super-admin-only `user.archive|restore|delete|changeRole` commands
  (ordinary roles only — admin privileges stay claim-based and
  script-granted). There is still no command that creates a user or
  plain-suspends a non-landlord account, and the app does not pretend
  otherwise.

Anonymous/unauthenticated workspaces use an in-memory fallback gateway that
never reaches a server. Never present an unsynced local write as
server-confirmed.

## Known model divergence

The Flutter aggregates and the Firestore collections were designed separately
and do not correspond one-to-one. This is the single largest source of latent
bugs in the repository; read this before touching sync.

Only `property`, `unit`, and `listing` ever had a canonical server shape the
client's mappers accept. Every other pull wrote raw server JSON into a local
store whose mapper then threw a `FormatException` on the next read — so tenant,
prospect, and admin sync never worked; it only looked like it did.

- Client `Tenancy` is one aggregate (tenant + lease + balance). The server has
  `tenantRecords` and `leases`. Writes are reconciled by the composite
  `tenancy.establish` command; reads by the `landlordPortals` projection.
- Client `RentPayment` carries denormalized `tenantName`/`unitLabel`/
  `propertyName`; server `payments` carry none of them. Same resolution.
- Client `LeaseDocument` is a locally rendered index; server `documents` are
  uploaded files with a storage path and checksum. Unrelated things, similar
  names — now separate stores.
- `ApplicationMapper` wants `applicantName`/`unitId`/`propertyId`; server
  `applications` store `displayName` and no unit or property. **Unresolved.**
- `MaintenanceRequestMapper` wants `reference`/`landlordId`/`location`/
  `reporterName`; `NoticeMapper` wants `reference`/`audience`/`status` against a
  projection carrying `publishState`. **Unresolved.**

`RemotePullGateway._toLocalShape` translates only `unit` and `listing`. Do not
register a pull for a type until it has a shape the client's mapper accepts;
`FirestoreRemotePullGateway.landlordReadSource` throws for anything unclassified
rather than defaulting to the canonical collection.

The intended fix for the unresolved rows is a server-owned read model, as with
`landlordPortals/{uid}/tenancies|payments`. **It is not a mechanical reshape of
the tenant/client projections:** those are security whitelists that deliberately
withhold `landlordId` and unit/property IDs from tenants and prospects, and the
client's models currently require exactly those fields. Reconciling that is a
product and security decision.

`landlordPortals` projections are shaped in the *client's* field names, and
nothing type-checks across the two languages. `test/core/landlord_projection_shape_test.dart`
is what holds that contract — update it with any projection change.

Two known limits of these projections, both from denormalizing:

- **They go stale on edits elsewhere.** `landlordTenancyProjection` copies
  `unitLabel` and `propertyName`, but `unit.update` and `property.update` do not
  rewrite the tenancy rows that embedded them, so a renamed property shows its
  old name on another device until the tenancy is touched. `lease.end` and
  `tenant.claimInvite` likewise do not refresh `status`/`tenantUserId`. A
  fan-out job keyed on the owning aggregate is the fix.
- **They only exist going forward.** Tenancies created before the projections
  shipped have no `landlordPortals` document, and `payment.recordAgainstTenancy`
  skips the projection write when the tenancy view is absent. Existing data needs
  a backfill before a landlord sees it on a second device.

An aggregate with no command that can accept it must be written with
`OfflineDatabase.putLocalEntity` and carry `SyncMetadata.local()`. Never enqueue
an outbox entry no handler can satisfy: it fails permanently and silently, and
the UI goes on showing "pending" forever.

## Repository ownership map

- `lib/app/`: dependency bootstrap, route guards, navigation shell, and theming.
- `lib/core/domain/`: shared pure-Dart domain primitives, clocks, IDs, validation,
  failures, and sync metadata.
- `lib/core/offline/`: Sembast source of truth, durable outbox, sync engine, network
  hints, and remote gateway abstractions.
- `lib/core/presentation/`: reusable Nyumba UI primitives only; business behavior
  belongs in a feature.
- `lib/features/<feature>/domain/`: entities, value objects, validation, and
  repository contracts.
- `lib/features/<feature>/application/`: use cases, policies, orchestration, and
  presentation-ready state that is independent of widgets.
- `lib/features/<feature>/data/`: Sembast repositories, mappers, DTOs, and future
  Firebase/gateway adapters.
- `lib/features/<feature>/presentation/`: responsive widgets and Riverpod/GoRouter
  integration.
- `test/`: mirrors the production concern being tested; keep domain and sync tests
  fast and deterministic.
- `docs/architecture/`: normative architecture, offline, security, and backend
  command documentation.
- `firebase/`: environment-neutral rules, indexes, emulator config, and backend
  handoff. It must remain free of project IDs and secrets.
- `assets/branding/` and `assets/listings/`: app-shipped assets. `docs/design/`
  contains visual references rather than runtime assets.

## Clean architecture dependency rules

Dependencies point inward:

```text
presentation -> application -> domain <- data
```

- Domain code is pure Dart. It must not import Flutter, Riverpod, Firebase,
  Sembast, JSON/persistence DTOs, or presentation state.
- Application code depends on domain contracts, not concrete repositories.
- Data code implements domain contracts and owns all serialization/mapping.
- Presentation invokes use cases/repositories through providers and renders local
  streams. Widgets must not open Sembast or query Firestore directly.
- Inject clocks, ID generators, gateways, and repositories where behavior must be
  deterministic or replaceable.
- Do not import one feature's concrete data implementation from another feature.
  Share a small domain primitive or coordinate through application-layer contracts.
- Avoid a generic `utils` dumping ground and avoid mutable domain objects embedded
  across aggregates. Reference related aggregates by stable IDs.

When adding a feature, prefer a vertical slice with its domain contract, local data
implementation, application orchestration, presentation, and tests instead of
placing all logic in a screen.

## Offline-first invariants

Treat these as correctness requirements, not implementation suggestions:

1. Sembast is the application source of truth on every platform (IndexedDB on web,
   a local database file on mobile). Repository reads and widget streams come from
   local records, including immediately after launch or while offline.
2. Every offline-capable mutation writes the entity and its outbox command in the
   same Sembast transaction. Never leave an optimistic record without a durable
   sync intent, or enqueue a command without its corresponding local state.
3. Generate aggregate and command IDs once on the client and reuse command IDs for
   every retry. Remote delivery is at least once and must remain idempotent.
4. Preserve aggregate and cross-aggregate dependency order (for example property
   -> unit -> listing -> application). A permanent parent failure blocks dependents
   until an explicit recovery path resolves it.
5. Remote pulls may update local records only when they cannot overwrite an
   unsynced local edit. Keep version/conflict behavior explicit.
6. Expose pending, syncing, synced, conflicted/rejected, blocked, and last-synced
   states honestly. Connectivity is only a hint; a local write is not proof of
   server acceptance.
7. Keep timestamps UTC and deterministic in tests. Use integer minor units for
   money; never floating-point currency amounts.
8. A public listing is readable only after server publication acknowledgement and
   a synced published state. An uploaded image or local draft is never public by
   itself.

Any change to outbox schema, ordering, retry policy, conflict behavior, account
switching, or attachment handling must update the relevant architecture document
and add regression tests for process death, duplicate delivery, or lost responses
as applicable.

## Firebase and server-authoritative boundaries

Route guards and role-specific UI are user-experience controls, not authorization.
Firestore/Storage Rules or callable Cloud Functions must re-check identity,
ownership, role, account state, subscription/entitlement, and payload validation.

Canonical remote writes cross the versioned command envelope documented in
`docs/architecture/backend-command-contracts.md`. Never let client payloads be the
authority for actor IDs, roles, ownership, prices, totals, statuses, timestamps,
entitlements, or public projections.

The server remains authoritative for:

- landlord approval, suspension, and audited admin actions;
- subscription status, plan entitlements, and unit-limit enforcement;
- lease activation and occupancy invariants;
- invoice totals, payment confirmation/allocation, and receipt issuance;
- listing validation, moderation, publication, expiry, and public media;
- tenant/client projections, reports, notifications, and audit logs.

Use private canonical collections plus server-owned tenant/client/public projections.
Anonymous clients read only `publicListings`; they never read private properties or
units. Direct client writes to canonical Firestore documents remain denied. Do not
commit API keys, service-account files, provider secrets, `.firebaserc` production
aliases, real project IDs, tokens, PII, or payment details. Use an explicit
non-production `--project` when running Firebase commands.

The subscription tier structure (Starter/Pro/Premium/Enterprise, landlord- and
property-manager-only, free tenant and prospect access, non-paywall rules, and
downgrade safety) is normative in `docs/architecture/subscription-tiers.md`.
Finalized product configuration (market Uganda/UGX, region `europe-west1`,
30-day renewable listing lifetime, upload limits, retention) lives in
`docs/architecture/README.md` and `lib/core/config/market_config.dart`.
Monetary prices, billing intervals, provider choice, and staging/production
Firebase environment IDs are still TBD. Keep all entitlement
values in versioned server-owned configuration and fail closed when required
configuration is missing; do not hard-code guesses in Flutter or security rules.

## Public web SEO invariants

The production origin is `https://nyumba.online`. Search-visible marketplace
routes are server rendered by the `publicSeo` HTTP Function before Flutter starts:
`/explore`, `/listing/{listingId}`, and `/sitemap.xml`, with `/` redirecting to
`/explore`. The Hosting rewrites in `firebase.json`, renderer and handler in
`firebase/functions/src/http/public-seo*.ts`, `web/robots.txt`, and the
`noindex` fallback in `web/index.html` form one contract. Change and deploy them
together; deploy the Function before a Hosting rewrite that depends on it.

Treat these as correctness and privacy requirements:

1. A public route must return meaningful HTML without executing JavaScript.
   Render a unique, accurate title and description, one absolute canonical URL,
   Open Graph and Twitter metadata, valid JSON-LD, and ordinary crawlable
   `<a href>` links. Flutter may take over after the first frame, but it is not
   the crawler fallback.
2. Build SEO output only from an explicit allowlist mapped from the server-owned
   `publicListings` projection. Never read or serialize canonical properties,
   units, landlord records, contact details, storage paths, moderation notes, or
   arbitrary extra projection fields into public HTML, metadata, or structured
   data. Escape user-authored values in HTML and serialize JSON-LD safely.
3. Recheck the public invariant at request time: `status == published`,
   `isDeleted != true`, and `expiresAt` is in the future. Missing or malformed
   listing IDs return `404`; unpublished, deleted, or expired listings return
   `410` where distinguishable. Every unavailable/error/private response must
   carry both a `noindex, nofollow` meta directive when HTML is returned and an
   `X-Robots-Tag: noindex, nofollow` header.
4. The generic authenticated Flutter shell remains `noindex, nofollow`.
   `robots.txt` is crawl guidance, not authorization, and must not be used to
   hide private routes. Preview, emulator, and staging deployments must not
   advertise production canonicals as if their content were the production page.
5. Canonicals, social URLs, structured-data URLs, redirects, and sitemap entries
   use `https://nyumba.online` and clean stable paths. Do not create indexed
   duplicates from query parameters, fragments, alternate slashes, or obsolete
   routes; redirect or canonicalize them deliberately.
6. The sitemap contains active canonical public URLs only and must remain complete
   as listing volume grows. Update its query, pagination/limits, and tests together.
   Removed listings must leave the sitemap promptly. Public responses must not be
   cached in a way that keeps an unpublished or expired listing discoverable.
7. Structured data must describe what the visible page actually contains. Use
   supported Schema.org types and integer-minor-unit money converted consistently
   for display. Include listing media only when it has an approved, stable,
   publicly crawlable URL; never expose a private Storage path or mint crawler
   access by accident.
8. When adding, renaming, or removing a public route or public projection field,
   update the renderer, Hosting rewrites, canonical/internal links, sitemap,
   robots behavior, architecture documentation, and regression tests in the same
   change. User-authored names and descriptions remain untranslated; any future
   locale-specific public URLs also require self-canonical and reciprocal
   `hreflang` handling.

For SEO-affecting changes, inspect the raw HTTP response rather than only the
hydrated Flutter DOM. Test status codes, headers, canonical/meta tags, JSON-LD
parsing, HTML escaping and private-field non-disclosure, crawlable links,
unavailable listing behavior, and sitemap membership. Then verify at least one
explore page and one listing page at desktop and mobile widths with no console
errors, plus a JavaScript-disabled or source-response check. A successful Flutter
build alone is not SEO verification.

## Flutter and UI conventions

- Target the SDK constraints in `pubspec.yaml` and keep code compatible with web,
  Android, and iOS. Do not add a platform-specific dependency without guarded
  implementations or a documented platform limitation.
- Follow `flutter_lints`, format touched Dart files with `dart format`, prefer
  immutable values and `const` constructors, and keep async lifecycle handling safe.
- Use Riverpod for dependency/state wiring and GoRouter for navigation. Keep
  authorization checks at the remote boundary even when a route is guarded.
- Reuse the theme and shared presentation components. Brand colors are Midnight
  Navy `#123A6F`, Sage Green `#5F8F6B`, Terracotta Gold `#C98B2E`, and Soft Ivory
  `#F7F4ED`.
- Design and test responsive layouts for narrow mobile and wide web widths. Avoid
  fixed dimensions that overflow, and preserve keyboard navigation, semantic
  labels, readable contrast, loading/empty/error states, and visible sync status.
- Keep user-facing copy precise: use `pending` or `awaiting confirmation` for
  unacknowledged operations, never `paid`, `published`, or `approved`.

## Localization and language invariants

Nyumba ships in English (`en`), Luganda (`lg`), Kiswahili (`sw`), and Arabic
(`ar`). Localization is part of every feature's definition of done, not a
follow-up polish task.

- Add or change user-facing copy in all four `assets/l10n/app_*.arb` catalogs in
  the same change. Do not introduce a Flutter string literal that is visible,
  announced by accessibility services, used as a form label/error, or shown in
  a tooltip without a localization entry.
- Prefer generated `AppLocalizations` getters for new copy, especially messages
  with placeholders, plurals, or select forms. The localized `Text` bridge
  exists to cover legacy source strings while they are migrated; it is not a
  reason to skip ARB entries.
- Preserve placeholders as data. Translate the surrounding sentence, never a
  person's name, property/unit name, user-authored description, notice body, or
  message unless the product explicitly adds an opt-in content-translation
  workflow.
- Use locale-aware `intl` date, number, and currency formatting. Money remains
  integer minor units and the configured market currency remains UGX; changing
  language does not change financial authority or currency.
- Arabic must work right-to-left. Use `AlignmentDirectional`,
  `EdgeInsetsDirectional`, `BorderDirectional`, `PositionedDirectional`, and
  start/end-aware icons or ordering for semantic layout. Recheck compact mobile
  and wide web widths for translated text expansion and RTL navigation.
- Localize server-rendered notification templates and generated document/PDF
  labels using the recipient or active user's validated locale. Store only one
  of `en|lg|sw|ar`; fall back to English for absent/invalid legacy data.
- Add tests that keep locale catalogs in key parity, verify fallback and
  persistence/account switching, and render at least one narrow and one wide
  critical screen in Arabic RTL whenever shared navigation/layout changes.
- Machine-generated translations are drafts. Changes to legal, financial,
  tenancy, safety, or billing wording require review by a fluent speaker before
  production release.

## Tests and verification

Add tests at the lowest useful layer:

- domain tests for validation and invariants;
- repository/database tests for atomic entity-plus-outbox writes and local streams;
- sync tests for ordering, idempotency, retry/backoff, rejection, and blocking;
- widget/router tests for roles, responsive states, and critical interactions;
- Firebase Emulator tests for every allowed and denied actor/query before changing
  rules or implementing remote adapters;
- public SEO renderer/handler tests for every change to public routes, listing
  projection fields, Hosting rewrites, metadata, structured data, or sitemap
  behavior.

Run from the repository root:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
```

And from `firebase/functions/` for any backend change:

```sh
npm run typecheck
npm test            # unit tests, including the job-registry coverage check
npm run test:emulator   # rules + command integration against the emulator
```

On macOS with Xcode configured, also run:

```sh
flutter build ios --no-codesign
```

For documentation-only edits, inspect links and diffs; full Flutter builds are not
required. For narrow code changes, run the relevant test first, then `flutter
analyze` and the platform builds proportional to risk. Rules changes require
Firebase Emulator validation from `firebase/` with an explicit development project.

## Safe editing and generated files

- Preserve unrelated user changes in a dirty worktree. Inspect `git status` and the
  surrounding code before editing; never reset or overwrite unrelated work.
- Keep changes scoped. Update docs/tests with any contract or behavior change, and
  avoid broad mechanical rewrites unless the task requires them.
- Use `flutter pub add` or edit `pubspec.yaml` intentionally; allow `pubspec.lock`
  and plugin metadata to update through Flutter tooling rather than hand-editing.
- Do not edit `.dart_tool/`, `build/`, `.flutter-plugins-dependencies`, or generated
  launcher icon files by hand.
- `firebase_options.dart` is intentionally absent until an environment is
  configured; generate it with FlutterFire rather than inventing values.
- The launcher-icon source of truth is
  `assets/branding/nyumba-app-icon-production.png`; regenerate platform icons with
  `dart run flutter_launcher_icons` after an approved source change.
- Treat existing branding/listing images as approved assets. Preserve licensing and
  provenance, optimize additions, declare runtime assets in `pubspec.yaml`, and do
  not replace design references merely to match personal taste.

## Definition of done

A change is complete when:

- it respects layer boundaries and the offline/server-authority invariants above;
- local optimistic behavior and remote confirmation/rejection are distinguishable;
- relevant success, offline, retry, conflict/rejection, loading, empty, and
  permission-denied paths are handled;
- tests cover the changed policy or regression and all relevant checks pass;
- responsive and accessibility behavior is verified for UI changes;
- public web changes preserve the SEO, canonicalization, indexing, and
  non-disclosure invariants above, with raw-response and rendered-page checks;
- all new or changed user-facing copy is translated in English, Luganda,
  Kiswahili, and Arabic, with RTL behavior checked where layout changed;
- architecture, command contracts, Firebase rules/indexes, and user-facing docs are
  updated together when their shared behavior changes;
- no secrets, PII, generated build output, debug logging, or environment-specific
  project identifiers were introduced; and
- the handoff states what was verified and any remaining platform or production
  configuration limitation.
