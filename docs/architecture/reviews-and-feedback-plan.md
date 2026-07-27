# Reviews & Feedback

Status: **implemented** (all four phases). This document is kept as the design
record; see "What changed during implementation" at the end for the places the
built system deviates from the plan below, and why.

Two separate systems:

1. **Tenant → landlord reviews** — public, adversarial, reputational. Needs eligibility
   proof, aggregates, moderation, right of reply.
2. **Landlord → platform feedback** — private product telemetry. No adversary, no
   moderation, no public surface.

They share no collections, no commands, and no UI. Conflating them is the main design
risk: the second is a two-day job, the first is not, and bundling them delays the easy
win behind the hard one.

Deliberately out of scope: **landlord → tenant ratings**. There is no public tenant
profile to attach them to, and a tenant score doubles as a screening blacklist with
real discrimination exposure.

---

## Constraints this plan is built around

Read these before touching anything; each one changed a decision below.

| Constraint | Source | Consequence |
|---|---|---|
| Tenant and client remote pulls are **deliberately empty** — every existing portal projection mismatches its Dart mapper | `lib/app/bootstrap/app_dependencies.dart:491` | Reviews are greenfield on both sides, so this is the first tenant pull that can actually work. The projection and the mapper must be written together, in one commit. |
| Public listings expose an opaque `landlordToken = sha256(landlordId).slice(0,24)`, never the uid | `firebase/functions/src/commands/listings.ts:136` | Public review and rating documents must be keyed by `landlordToken`, not `landlordId`. Keying them by uid would leak it to anonymous browsers. |
| `firestore.rules` ends in a fail-closed `match /{document=**}` | `firebase/firestore.rules:324` | Every new collection needs an explicit block or it is unreadable. |
| `_commandFor` keys on `(OfflineEntityType, OutboxOperation)` and there are only five operations | `lib/core/offline/firebase_remote_sync_gateway.dart:311` | Six review commands cannot each own an operation. Dispatch on a payload discriminator, following the `noticePublicationCommand()` precedent in the same switch. |
| `job-registry.test.ts` asserts the **exact sorted list** of job types any command enqueues | `firebase/functions/test/unit/job-registry.test.ts:45` | Adding a job means updating that array in the same commit or CI fails. |
| Firestore transactions require all reads before any write | existing handlers use one `Promise.all([tx.get(...)])` | Review handlers must fetch review + lease + ratings doc up front. |
| Projections are explicit field whitelists, never wholesale copies | `firebase/functions/src/shared/projections.ts:1` | Add named `*_FIELDS` arrays; do not spread canonical docs. |

---

## Phase 1 — Platform feedback (landlord → Nyumba)

Smallest useful slice, no adversary, ships independently. Do this first so real
feedback starts accumulating while phases 2–4 are built.

### Backend

**`firebase/functions/src/commands/feedback.ts`** (new) — one handler:

```
feedback.submit
  aggregateIdMode: 'required'
  expectedVersionMode: 'create'
  payload: {
    kind: 'nps' | 'freeform',
    score: int 0..10          // required when kind == 'nps', forbidden otherwise
    comment: longText.optional(),
    category: enum(easeOfUse, valueForMoney, support, bug, featureRequest).optional(),
    appVersion: shortText,
    platform: enum(android, ios, web),
  }
```

`apply` writes `platformFeedback/{id}` with `newAggregate(...)` plus `actorUid`,
`role`, and — read from `subscriptions/{uid}` inside the transaction — `planTier` and
`subscriptionStatus`. Denormalizing the tier at write time is the point of the whole
feature: a detractor on the UGX 300k tier is a churn alert, and joining it later
against a subscription that has since changed tells you nothing.

Throttle: reject a second `nps` submission from the same actor within 90 days
(`DomainError('RATE_LIMITED', { retryAfterSeconds })`). Freeform is unthrottled —
never suppress a bug report.

Also write `lastFeedbackPromptAt` / `lastFeedbackSubmittedAt` onto
`landlordAccounts/{uid}` so the prompt schedule is server-owned. A client-side
schedule resets on reinstall and re-nags.

Register `['feedback.submit', feedbackSubmit]` in `commands/index.ts`.

No background job, no email, no projection — the admin reads the canonical collection.

### Rules

```
match /platformFeedback/{feedbackId} {
  allow read: if isPlatformAdmin();
  allow write: if false;
}
```

### Client

- `lib/features/feedback/` — full slice: `domain/platform_feedback.dart`,
  `domain/feedback_repository.dart`, `data/mappers/platform_feedback_mapper.dart`,
  `data/sembast_feedback_repository.dart`, `application/feedback_providers.dart`.
- New `OfflineEntityType.platformFeedback('platform_feedback', 96)`.
- `_commandFor`: `(platformFeedback, create) → 'feedback.submit'`.
- Write-only locally — nothing pulls it back. The tenant/client pull gap does not
  apply because there is nothing to read.
- **NPS prompt**: a sheet triggered off `lastFeedbackPromptAt` from the session, shown
  after a milestone (30 days on a plan, or 10 payments recorded), never on launch.
  Snooze must persist.
- **"Send feedback"** in landlord settings — always available, free-form, auto-attaches
  version/platform. This is the entry point that produces actionable bugs; NPS only
  produces a number.
- Strings into all four ARB files (`en`, `sw`, `lg`, `ar`).

### Admin

A list screen in `lib/features/admin/` filtered by tier, score, and date, with rolling
NPS on the dashboard. Admin already pulls via `administrativeScope`, but that path
reads canonical collections whose shape the mapper must accept — since we design both
sides here, keep the canonical `platformFeedback` document shape identical to the Dart
mapper's expectations and add `platformFeedback` to the admin pull list in
`app_dependencies.dart`.

### Tests

- `test/features/platform_feedback_test.dart` — repository enqueues the right outbox
  entry; NPS requires a score, freeform forbids one.
- Backend unit test for the 90-day NPS throttle and tier denormalization.

---

## Phase 2 — Review core (private to landlord)

Ship reviews collecting and visible to the reviewed landlord only. No public surface
yet. This accumulates real data and lets you see the tone before anything is
irreversible.

### The key modelling decision: `aggregateId == leaseId`

One review per lease, keyed by the lease. This gives four things for free:

- Uniqueness with no duplicate query (contrast `applicationSubmit`, which fetches ten
  docs and filters in code to enforce one-per-listing).
- Idempotent outbox retries — `requireAbsent` absorbs the replay.
- A natural eligibility proof: the id *is* the evidence.
- `dependsOn` ordering behind the lease aggregate when a tenant writes offline.

A tenant with two leases from the same landlord can review twice. That is correct —
they are two separate tenancies.

### Collections

| Collection | Contents | Read access |
|---|---|---|
| `landlordReviews/{leaseId}` | canonical: `reviewerUid`, `landlordId`, `propertyId`, scores, body, `status`, `landlordResponse`, moderation fields | admin only |
| `landlordRatings/{landlordId}` | `count`, `sum`, per-dimension sums, distribution `[1..5]`, `average`, `rankScore` | landlord self + admin |
| `landlordPortals/{uid}/reviews/{leaseId}` | landlord's copy for reading and responding offline | self |
| `tenantPortals/{uid}/reviews/{leaseId}` | reviewer's own copy, including hidden ones | self |

`reviewerUid` stays on the canonical document permanently, even when display is
anonymous. You will need it for a defamation complaint.

### Eligibility gate

In `review.submit`, load `leases/{cmd.aggregateId}` and require:

- `tenantUserUid === actor.uid`
- `activatedAt` present
- `status` is `active` or `ended`
- if `active`: `now - activatedAt >= 30 days` — blocks week-one revenge reviews
- if `ended`: `now - endedAt <= 90 days` — blocks stale ones

`landlordId` comes off the lease, never off the payload. Anything else lets a client
review a landlord it never rented from.

### Score shape

`overall` 1–5 required, plus optional `responsiveness`, `maintenance`,
`listingAccuracy`, `depositFairness`, each 1–5. Sub-scores are what make the review
useful before you have enough volume for a trustworthy average, and they give the
landlord something specific to act on.

### Aggregate maintenance

Recompute `landlordRatings/{landlordId}` inside the same transaction — read it in the
opening `Promise.all`, write the new totals alongside the review. Exact, no
`FieldValue.increment` races, and `review.update` can subtract the old scores because
it has the prior document in hand.

Store two derived numbers:

- `average = sum / count` — for display.
- `rankScore = (C * m + sum) / (C + count)` with `m` = platform mean (a constant in
  `shared/config.ts`, revisited manually) and `C ≈ 5` — for sorting. Without shrinkage
  one 5-star review outranks a landlord with fifty at 4.7. Firestore cannot compute it
  at query time, so it must be a stored field.

### Commands

All in `firebase/functions/src/commands/reviews.ts`, registered in `commands/index.ts`:

| Command | Actor | Notes |
|---|---|---|
| `review.submit` | tenant | `expectedVersionMode: 'create'`, eligibility gate above |
| `review.update` | tenant (author) | 14-day edit window from `createdAt`; recomputes aggregate |
| `review.withdraw` | tenant (author) | sets `status: 'withdrawn'`, subtracts from aggregate |
| `review.respond` | landlord (subject) | one public response, `longText`; may be edited |
| `review.flag` | landlord (subject) | sets `flagState: 'pending'`, **does not hide** |
| `review.moderate` | admin | `publish` / `hide` / `remove` + `AdminActionRecord` |

**Flagging must not hide.** If it did, every negative review would be flagged on day
one and the system would be worthless. The review stays visible while an admin
adjudicates.

### Notifications

`createJob(tx, db, \`${cmd.commandId}_notify\`, 'notifyLandlordReview', ...)` on submit,
and `notifyTenantReviewResponse` on respond. Both need:

- processors in `workers/notifications.ts`,
- entries in the `processors` map in `workers/jobs.ts`,
- **the expected-list array in `job-registry.test.ts:45` updated**,
- `NotificationTemplateKey` entries in `shared/localization.ts` in all four locales
  (`localization.test.ts` enforces completeness).

### Client wiring

- `OfflineEntityType.landlordReview('landlord_reviews', 97)`.
- `lib/features/reviews/` — standard slice, mirroring `lib/features/maintenance/`:
  domain entity + repository interface, `data/mappers/landlord_review_mapper.dart`
  (`JsonReader`, `SyncMetadataMapper`), `data/sembast_review_repository.dart` using
  `putEntityAndEnqueue`, `application/review_providers.dart`.
- `_commandFor` — following `noticePublicationCommand()` in the same switch:
  - `(landlordReview, create) → review.submit`
  - `(landlordReview, update) → ` dispatch on `payload['pendingAction']` ∈
    `{edit, withdraw, respond, flag, moderate}`, throwing a non-retryable
    `RemoteSyncException` on an unknown value.
- **First working tenant pull**: add `landlordReview → 'reviews'` to `_tenantSection`,
  `landlordReview → 'reviews'` to `_landlordPortalSection`, and
  `LandlordReadSource.portalProjection` for it in `landlordReadSource`. Then enable the
  pull in `app_dependencies.dart` for both the tenant branch (currently empty — replace
  the comment, keep the explanation of why the *other* types are still absent) and the
  landlord branch.
- Projection field names in `projections.ts` must match the Dart mapper exactly. This
  is the failure mode that killed every previous tenant projection; write the mapper
  and the whitelist in one sitting and assert the contract in a test.

### UI

- Tenant: a review prompt on the tenant home screen when an eligible lease has no
  review, plus a "My reviews" entry in the tenant portal.
- Landlord: a reviews tab showing received reviews with a respond action.
- Both go through `AsyncActionButton` and show `SyncStateBadge` for pending state.
- Anonymity: display as "Tenant at Kireka Heights". Tell the tenant plainly at submit
  time that a landlord with a handful of units will likely know who wrote it — do not
  imply protection the model cannot deliver.

### Rules

```
match /landlordReviews/{reviewId} {
  allow read: if isPlatformAdmin();
  allow write: if false;
}
match /landlordRatings/{landlordId} {
  allow read: if isSelf(landlordId) || isPlatformAdmin();
  allow write: if false;
}
```

Portal subcollections follow the existing `tenantPortals` / `landlordPortals` blocks.
Add coverage to `test/emulator/rules.test.ts`.

---

## Phase 3 — Go public

Only after phase 2 has produced real reviews.

### Public read models

Keyed by `landlordToken`, never by uid:

- `publicLandlordRatings/{landlordToken}` — `count`, `average`, `rankScore`,
  distribution, per-dimension averages.
- `publicReviews/{reviewId}` — `landlordToken`, scores, body, `landlordResponse`,
  `createdAt`, `displayLabel` (property name, no reviewer identity, no email).

Written in the same transaction as the canonical review; the token is
`sha256(landlordId).slice(0,24)`, derivable without a lookup.

### Suppression until volume

`publicLandlordRatings` gets `isDisplayable: count >= 3`. Below three, the marketplace
shows "New on Nyumba" instead of a star average. A single review is noise and a
single bad one is a weapon.

### Listing badges

The card badge has to live on the listing document — Firestore cannot join. But a
landlord can have many listings, so **do not** update them inside the review
transaction; the write count is unbounded. Enqueue `refreshLandlordRatingBadges`,
following the existing `unpublishLandlordListings` worker, to fan out over that
landlord's published listings and stamp `ratingAverage` / `ratingCount`. Eventual
consistency is fine for a badge.

`listing.publish` must also stamp the current badge at publish time so a new listing
is not blank until the next review lands.

### Rules and indexes

```
match /publicReviews/{reviewId} {
  allow get: if resource.data.status == 'published';
  allow list: if resource.data.status == 'published'
    && request.query.limit != null && request.query.limit <= 50;
  allow write: if false;
}
match /publicLandlordRatings/{token} {
  allow get: if true;
  allow write: if false;
}
```

Composite index: `publicReviews(status ASC, landlordToken ASC, createdAt DESC)`. The
client query in `remote_pull_gateway.dart` must match it exactly — see the comment on
the `publicListing` query about matching the deployed index.

Add `OfflineEntityType.publicReview('public_reviews', 98)` as a **separate** store from
`landlordReview`, for the same reason `publicListing` is separate from `listing`: same
ids, different shapes, and whichever listener arrives second would otherwise clobber
the first.

**Do not add rating sort to the marketplace query in this phase.** It needs another
composite index on `publicListings` and changes the ranking users already know. Badge
first, sort later, once you can see whether the distribution is worth sorting on.

### UI

Rating badge on listing cards, a ratings section on the listing detail screen, and a
public landlord profile page reachable from a listing showing the distribution and
recent reviews with responses.

---

## Phase 4 — Moderation

Needed before volume, not before launch.

- Admin queue over `landlordReviews` where `flagState == 'pending'`, sorted oldest
  first.
- `review.moderate` writes an append-only `AdminActionRecord` like every other admin
  command in `commands/admin.ts`.
- Hiding removes the review from `publicReviews` and subtracts it from both the
  private and public aggregates in the same transaction.
- A "report this review" path for anyone reading a public review, rate-limited by uid,
  writing to the same flag queue.
- Terms acknowledgement recorded on the review document at submit time.

---

## Sequencing and risk

| Phase | Depends on | Main risk |
|---|---|---|
| 1 Platform feedback | nothing | none — isolated slice |
| 2 Review core | 1 (only for convention) | **projection/mapper mismatch**, the failure that broke every prior tenant projection |
| 3 Go public | 2 | index/query drift; unbounded writes if badges are stamped in the review transaction |
| 4 Moderation | 3 | none technical; needed before review volume grows |

The one thing worth extra care is the phase-2 projection contract. Every previous
tenant projection was written against a Dart mapper that already existed and did not
fit, and the result was a `FormatException` on a screen far from the cause. Here both
sides are new, so add a test that round-trips the exact projection output through
`LandlordReviewMapper.fromJson` and keep it passing.

## Open decisions

1. **Edit window** — 14 days is a guess. Longer is friendlier to tenants, shorter is
   friendlier to landlords who have already responded.
2. **Platform mean `m`** — needs a real value once phase 2 has data; start at 4.0 and
   revisit rather than computing it live.
3. **Landlord response editing** — allow indefinitely, or lock after a window like the
   review itself? Locking is more symmetric; not locking is more forgiving.
4. **Legal review** — Uganda-only defamation exposure on public reviews is worth an
   actual opinion before phase 3, not after.

---

## What changed during implementation

Six deviations from the plan above, each because building it surfaced something
the design did not account for.

**1. Public documents are keyed by `landlordToken`, and so is everything that
joins to them.** The plan said this for `publicReviews`; implementation extended
it to `publicLandlordRatings/{token}` and to the badge-refresh worker, which
queries `publicListings` by token rather than deriving IDs from
`privateListings`. Targeting the collection being written removes any chance of
resurrecting a retired public projection as a badge-only document.
`landlordPublicToken` now lives in `shared/canonical.ts` so `listings.ts` and
`reviews.ts` cannot drift.

**2. There is no client pull for `publicLandlordRatings` or the landlord's own
`landlordRatings`.** Both turned out to be arithmetic over data the client
already holds: a landlord holds every review written about them, and a public
reader holds the listing's denormalized badge plus the reviews fetched for that
token. `RatingSummary.from` computes count, average, distribution, and dimension
averages locally. The server documents still exist and remain authoritative —
they are what the badge is stamped from — but nothing pulls them.

**3. Public reviews are fetched on demand, not watched.** `RemotePullGateway`
gained `fetchPublicReviews(token)` rather than a bootstrap watch. The token to
filter by is not known until a listing is open, so a workspace-lifetime
subscription would have to pull the platform's most recent reviews (almost never
the ones on screen) or leak a stream per listing visited.

**4. `feedback.dismissPrompt` was dropped.** The cadence that matters — how soon
a landlord can be asked again after answering — is already enforced server-side
against `lastNpsSubmittedAt`. A command whose only job was recording "shown and
declined" would have cost a Firestore write per dismissal to shorten a snooze
the device tracks perfectly well. `FeedbackPromptStore` handles it locally.

**5. Five review commands share one outbox operation.** `_commandFor` keys on
`(entityType, operation)` and there are only five operations, so
`(landlordReview, update)` dispatches on a `pendingAction` payload discriminator
— the same shape as the existing `noticePublicationCommand`. Pinned by
`gateway_command_coverage_test.dart`.

**6. A `review.report` command was added.** The plan deferred reader reporting to
phase 4; it cost little to add alongside `review.flag` and closes the obvious
gap where only the reviewed landlord could raise a problem. Rate-limited per
actor, and like a flag it never hides anything.

### Prompt timing, as built

The plan did not specify when to ask. The implemented policy
(`review_prompt_policy.dart`) is:

| Moment | Kind | Why |
|---|---|---|
| A maintenance request the tenant filed is resolved | Interruptive | Direct, fresh evidence of the landlord's conduct; the tenant is already looking at it |
| The tenancy ends | Interruptive | The only point at which deposit handling is knowable, and the last time the tenant opens the app |
| Tenant home card, "Your reviews" screen | Always available | The deliberate route, exempt from the dismissal budget |

Never on launch, never after recording a payment, never after an error. Capped
at one interruption per lease per 30 days, and permanently after two dismissals
— but the card and the screen survive the opt-out, because declining an
interruption means "not now", not "hide the feature".

Landlord NPS follows the same shape: after a milestone (ten payments recorded, a
listing's first application, or 30 days of activity), never on launch, 30-day
snooze on the device and a 90-day cooldown on the server.
