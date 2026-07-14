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

The checked-in app is an implementation baseline using Sembast and local demo
identities/data. Firebase packages, rules, indexes, and command contracts exist,
but no project credentials, generated `firebase_options.dart`, production Cloud
Functions, or real payment integration are committed. Do not present demo behavior
as server-confirmed production behavior.

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

## Tests and verification

Add tests at the lowest useful layer:

- domain tests for validation and invariants;
- repository/database tests for atomic entity-plus-outbox writes and local streams;
- sync tests for ordering, idempotency, retry/backoff, rejection, and blocking;
- widget/router tests for roles, responsive states, and critical interactions;
- Firebase Emulator tests for every allowed and denied actor/query before changing
  rules or implementing remote adapters.

Run from the repository root:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
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
- architecture, command contracts, Firebase rules/indexes, and user-facing docs are
  updated together when their shared behavior changes;
- no secrets, PII, generated build output, debug logging, or environment-specific
  project identifiers were introduced; and
- the handoff states what was verified and any remaining platform or production
  configuration limitation.
