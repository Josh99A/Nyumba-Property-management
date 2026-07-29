# Support desk (landlord ↔ Nyumba)

Status: **Phase 1 implemented**; phases 2–3 planned. See
"What changed during implementation" at the end for where the built system
deviates from the plan below, and why.

A two-way, threaded conversation between a landlord and the Nyumba team, with a
status a landlord can see and a reply they can rely on.

## Why this is not `feedback.submit`

`platformFeedback` already exists and is deliberately one-way: it is telemetry
from a paying customer, never read back by its author, with no reply path and no
status. `commands/feedback.ts` says so explicitly, and `firestore.rules:345`
enforces it — not even the author can read their own submission.

A landlord whose payment did not reconcile does not want telemetry. They want an
answer, and they want to know whether anyone has seen the question. That is a
different aggregate with a different lifecycle, so it gets its own collection,
its own commands, and its own screens. The one thing the two share is the
entry-point copy, which must make the choice obvious:

- **Send feedback** — "Tell us what you think." No reply expected.
- **Contact support** — "Get help with something." A person replies.

The freeform feedback sheet's `bug` and `support` categories are the ones people
actually pick when they want help. Phase 1 adds a link from that sheet to the
support composer so the wrong door still leads to the right room.

Also not this: `notice.publish` (landlord → their tenants) and
`platform.broadcast` (admin → everyone). Both are one-way announcements.

---

## Constraints this plan is built around

Each one changed a decision below. Read them first.

| Constraint | Source | Consequence |
|---|---|---|
| Administrator identity is an Auth **custom claim**, granted only by an ops script. There is no queryable list of admins in Firestore. | `firebase/functions/scripts/grant-admin.mjs:35`, `shared/actor.ts:31` | "Notify every admin" cannot be a Firestore query. Resolved by having the ops script mirror each claim into `platformStaff/{uid}` as it grants it — a directory, never an authority. See [Alerting the team](#alerting-the-team). |
| A landlord pull reads either a canonical collection filtered by `landlordId`, or a `landlordPortals` projection — and only for types whose server shape the Dart mapper already accepts. | `lib/core/offline/remote_pull_gateway.dart:211` | `supportTickets` is greenfield on both sides, so the Firestore shape and the Dart mapper get written together in one commit, like `landlordReview` was. No projection needed. |
| `firestore.rules` ends in a fail-closed `match /{document=**}`. | `firebase/firestore.rules:372` | The new collection needs an explicit block or it is unreadable by anyone. |
| `_commandFor` keys on `(OfflineEntityType, OutboxOperation)`, and there are only five operations. | `lib/core/offline/firebase_remote_sync_gateway.dart:311` | Four support commands cannot each own an operation. Dispatch on a `pendingAction` payload discriminator, exactly like `reviewMutationCommand()` at line 411. |
| `job-registry.test.ts` asserts the **exact sorted list** of job types any command enqueues. | `firebase/functions/test/unit/job-registry.test.ts` | New jobs must be added to that array in the same commit or CI fails. |
| Firestore transactions require every read before any write. | every handler in `src/commands/` | Support handlers fetch ticket + landlord account up front in one `Promise.all`. |
| Admin console pulls run `administrativeScope: true` — the whole canonical collection, `.limit(200)`, unfiltered. | `remote_pull_gateway.dart:153`, `app_dependencies.dart:490` | Fine now; becomes the paging problem at ~200 lifetime tickets. Phase 3 note, not a Phase 1 blocker. |
| Widget tests must never register `NyumbaLocalizations.delegate` — it blanks the subtree. | existing test convention | Support widget tests follow the same rule as every other screen test. |

---

## Data model

### `supportTickets/{ticketId}` — one collection, canonical, no mirrors

```
{
  ...newAggregate(id, now),        // id, version, createdAt, updatedAt, isDeleted
  landlordId,                      // owner uid — the pull filter and the rules key
  openedByUid,                     // == landlordId in phase 1; distinct once staff can open
  subject,                         // shortText
  category,                        // billing | payments | tenants | listings | account | other
  status,                          // open | awaiting_landlord | in_progress | resolved | closed
  priority,                        // normal | high — SERVER-derived, never client-chosen
  messages: [                      // capped at 100, same shape/limit as maintenance comments
    { id, authorUid, authorRole: 'landlord' | 'support', body, createdAt,
      attachmentPaths: [] }
  ],
  lastMessageAt,
  lastMessageAuthorRole,           // drives "needs reply" on both sides without a scan
  firstResponseAt,                 // null until support replies — the SLA number that matters
  resolvedAt, closedAt,

  // Denormalized at open time, on purpose. Joining `subscriptions` weeks later
  // reads whatever tier they churned *to* — precisely the misleading value.
  // Same reasoning as platformFeedback.planTier (commands/feedback.ts:115).
  landlordName, landlordEmail, planTier, subscriptionStatus,
  appVersion, platform, locale,
}
```

**Messages as an array, not a subcollection.** The offline mirror stores whole
documents keyed by entity id and the sync engine merges document-at-a-time;
`maintenanceRequests.comments` already does exactly this with a 100-entry cap.
A subcollection would need its own pull, its own merge path, and its own rules
block to buy pagination nobody needs — support threads run to a dozen messages.

**No internal notes in this document.** An admin-only note field inside a
landlord-readable document is one rules edit away from leaking. If Phase 2 adds
internal notes they go in `supportTickets/{id}/internalNotes/{noteId}` with
`allow read, write: if false` (server-written, admin-read only) — a separate
document boundary, not a separate field.

### Status machine

Mirrors `maintenance.ts:74`, which is the house pattern for this.

```
open             → in_progress, awaiting_landlord, closed
in_progress      → awaiting_landlord, resolved, closed
awaiting_landlord→ in_progress, resolved, closed
resolved         → closed, in_progress          // reopen is a real transition
closed           → (terminal)
```

Transitions are admin-only, with two exceptions a landlord genuinely needs:
closing their own ticket ("this sorted itself out"), and reopening a `resolved`
one within 14 days. Landlord replies move `awaiting_landlord → in_progress`
automatically; admin replies move `open | in_progress → awaiting_landlord`.
Nobody should have to set a status to have a conversation.

### Offline entity

```dart
// lib/core/offline/offline_entity.dart
supportTicket('support_tickets', 99);
```

Registered in `remote_pull_gateway.dart` for both scopes:

- `_landlordCollection` → `'supportTickets'`
- `landlordReadSource` → `canonicalCollection` (shape designed with the mapper)
- `app_dependencies.dart`: owner-only landlord watch (`landlordId:`), and added
  to the admin `administrativeScope` list beside `platformFeedback`.

**Owner-only, not staff.** Support threads carry billing state, plan tier, and
account access questions. `staffMemberships` capabilities cover workspace
resources; none of them means "speak to Nyumba on the owner's behalf". Same call
as `landlordPortals/{id}/reviews` (`app_dependencies.dart:531`).

### Firestore rules

```
// A support thread is the landlord's own record of a conversation with us, so
// unlike platformFeedback they read it back. Staff are excluded: no workspace
// capability covers the owner's billing and account correspondence.
match /supportTickets/{ticketId} {
  allow read: if isPlatformAdmin() || ownsLandlordDocument(resource.data);
  allow write: if false;
}
```

Writes go through the callable command as everything else does.

---

## Commands

New file `firebase/functions/src/commands/support.ts`, registered in
`commands/index.ts`.

### `support.open`

```
aggregateIdMode: 'required'   expectedVersionMode: 'create'
payload: {
  subject: shortText,
  category: enum(billing, payments, tenants, listings, account, other),
  body: longText,
  stagedAttachmentPaths: string[].max(5),   // must start with `uploads/{actor.uid}/`
  appVersion: shortText,
  platform: enum(android, ios, web),
}
```

`requireActiveLandlord(tx, db, actor)` — the same gate `feedback.submit` uses, so
the account, tier, and subscription status all come from one read. Attachment
paths are validated against `uploads/${actor.uid}/` exactly as
`maintenance.ts:51` does.

**Rate limits**, on `landlordAccounts` via the local-extension pattern
`feedback.ts:20` established:

- 60s between ticket opens (`lastSupportOpenedAt`) → `RATE_LIMITED` with
  `retryAfterSeconds`.
- Max 3 non-terminal tickets per landlord → `VALIDATION_FAILED` with
  `reason: 'tooManyOpenTickets'`, so the client can say "reply on your existing
  conversation instead" rather than "error".

Priority is derived, never sent: `billing` and `account` open at `high`, and a
landlord whose subscription is `past_due` opens at `high` regardless of category.
A client-chosen priority field is a field where everyone picks urgent.

Enqueues `notifySupportTeam`.

### `support.reply`

```
aggregateIdMode: 'required'   expectedVersionMode: 'edit'
payload: { body: string.trim().min(1).max(2000), stagedAttachmentPaths: [] }
```

Author resolution mirrors `maintenanceAddComment`: `ticket.landlordId ===
actor.uid` → `landlord`; otherwise `requirePlatformAdmin(actor)` → `support`.
Anyone else is `PERMISSION_DENIED`. Rejected on `closed`. 100-message cap.
Sets `firstResponseAt` on the first `support` message. Enqueues
`notifyLandlordSupportReply` or `notifySupportTeam` depending on author — never
both, and never a self-notification.

### `support.updateStatus`

```
aggregateIdMode: 'required'   expectedVersionMode: 'edit'
payload: { status: enum(...), note: string.max(1000).optional() }
```

Admin-only, except the two landlord transitions named above. Validates against
the transition table and throws `VALIDATION_FAILED { reason:
'invalidSupportTransition' }` — same shape as maintenance.

### `support.rate` (Phase 2)

`{ score: 1..5, comment: optional }`, landlord-only, once per ticket, only on
`resolved` or `closed`. Kept separate from `feedback.submit`: this rates one
resolution, not the product.

### Client dispatch

`firebase_remote_sync_gateway.dart` gets a `supportMutationCommand()` beside
`reviewMutationCommand()`, switching on `payload['pendingAction']`
(`open` | `reply` | `updateStatus`) because four commands do not fit five
operations. The repository stamps `pendingAction` on the record it enqueues.

---

## Alerting the team

The hard part was that **administrator rights are not queryable**. They are Auth
custom claims set by `scripts/grant-admin.mjs`. `fanoutBroadcast` can resolve
`landlords` and `tenants` by querying `users`, but there is no equivalent for
admins, and `auth.listUsers()` paging over the whole directory on every ticket is
not a design, it is a workaround.

The fix is to write the answer down when it changes rather than derive it on
demand: the ops script now mirrors each claim into `platformStaff` at the moment
it grants one.

**Both channels, and the duplication is deliberate.** ✅ Implemented.

`notifySupportTeam` emails `SUPPORT_EMAIL` (`support@nyumba.online`, a constant
in `shared/config.ts`) through the existing Resend path, with the subject,
category, plan tier, and a deep link to `/admin/support/{ticketId}`. Idempotency
key `support_team_${ticketId}_${messageId}`, so a job retry cannot double-send.

It *also* fans out an in-app inbox item and push to every administrator, using
`platformStaff` as the audience. `scripts/grant-admin.mjs` writes
`platformStaff/{uid}` (`{ uid, email, displayName, level, updatedAt }`) beside
the claim it grants and deletes the row on revoke; rules are `allow read: if
isPlatformAdmin(); allow write: if false`.

The mailbox send is kept unconditionally rather than used as a fallback. An
empty roster and a quiet week look identical from the outside, and this is the
channel that carries "a paying customer is stuck" — a duplicate notification
costs an agent two seconds, a missed one costs a customer.

**The roster is a directory, never an authority.** Every rule still reads
`request.auth.token`; nothing consults `platformStaff` to decide access. The
mirror exists only because custom claims cannot be queried. `rules.test.ts`
seeds a `platformStaff` row claiming `superAdmin` for an ordinary landlord and
asserts they still cannot read feedback, reviews, audit logs, another landlord's
properties, or the roster itself — so if any rule ever starts consulting it, the
test fails rather than the boundary quietly moving.

**Migration:** administrators granted before the mirror existed have no row and
are invisible to the in-app fanout (the email still reaches them). Run
`node scripts/grant-admin.mjs --backfill` once per project; it pages the Auth
directory, derives each level from the claims themselves, and writes the rows.

**Landlord direction** works today with no new infrastructure:
`notifyLandlordSupportReply` calls `deliverUserNotification(ticket.landlordId,
{ kind: 'system', templateKey: 'support_reply', data: { route:
'/support/${ticketId}' } })` plus a courtesy email. Add `support_reply` to
`NotificationTemplateKey` in `shared/localization.ts` with all four locales
(en, lg, sw, ar) — the type is a closed union, so a missing locale is a compile
error, which is the intent.

Both jobs register in `workers/jobs.ts` and in the `job-registry.test.ts` array.

---

## Landlord UI

### Entry points

Support has to be findable at the moment something goes wrong, not only from a
menu someone remembers.

1. **Nav destination** `/support` — "Help & support", `Icons.support_agent`.
   Appended to `_landlordDestinations` after Reviews. The landlord bottom bar
   already overflows at 8 destinations, so on compact it lands in the **More**
   sheet, which is the right weight for it.
2. **Profile settings** — a row beside the existing feedback entry, with the
   one-line distinction between the two.
3. **Contextual, prefilled.** A "Contact support" action on the failure states
   that actually generate tickets: the subscription screen when status is
   `past_due` or `rejected` (`category: billing`), the sync-failure banner
   (`category: account`), and a permanently-failed outbox entry. Each opens the
   composer with the category chosen and a short factual line already in the
   body — "My subscription payment was rejected on 12 Aug." Prefill the facts,
   never the complaint.
4. **Feedback sheet cross-link** — under the `bug` / `support` chips: "Need a
   reply? Contact support instead."

### `/support` — Help & support

`SupportScreen`, `NyumbaSurface` sections on the standard page scaffold.

```
Help & support
Ask the Nyumba team anything about your account, billing, or the app.

┌─ Common questions ────────────────────────────────┐   ← self-serve first
│ ▸ Why is my subscription still pending?           │
│ ▸ How do I record a payment a tenant made by cash?│
│ ▸ Why can't my tenant sign in?                    │
│ ▸ How long does a listing stay published?         │
│ ▸ How do I add someone to my team?                │
│ ▸ Why did my photos fail to upload?               │      6–8, localized,
│                        [ Still need help? → ]     │      static, expandable
└───────────────────────────────────────────────────┘

┌─ Your conversations ──────────────────┬───────────┐
│ ● Payment not reconciling             │ Needs you │   ← unread dot
│   Billing · 2 messages · 3 hours ago  │           │
│   "Thanks — could you send the…"      │           │
├───────────────────────────────────────┼───────────┤
│   Tenant can't sign in                │ Resolved  │
│   Account · 5 messages · 12 Aug       │           │
└───────────────────────────────────────┴───────────┘

              [ Message support ]        ← FAB on compact, filled button on wide
```

A short answers list above the compose button is deliberate: the cheapest support
ticket is the one nobody had to open, and it costs one static localized list.

**Empty state:** "No conversations yet — we usually reply within one working
day," with the compose button. State the expectation once, where it is set.

**Status pills** reuse the palette convention (`context.nyumba.*`, never
`NyumbaColors` — adaptive colors only):

| Status | Landlord label | Tint |
|---|---|---|
| `open` | Sent | `neutralTint` |
| `in_progress` | Nyumba is looking into this | `goldTint` |
| `awaiting_landlord` | Needs you | `goldTint` + dot |
| `resolved` | Resolved | `sageTint` |
| `closed` | Closed | `neutralTint` |

Landlord-facing labels are the *state of their request*, not our workflow
vocabulary. "Awaiting landlord" is an internal phrase; "Needs you" is what they
need to know.

### Composer sheet

`showModalBottomSheet` on compact, `AlertDialog` at ≥ medium — same treatment as
the feedback sheet, which is the closest sibling.

```
Message support
We usually reply within one working day.

What is this about?
[ Billing ] [ Payments ] [ Tenants ] [ Listings ] [ Account ] [ Something else ]

Subject            [ ______________________________ ]
Message            [                                ]
                   [                                ]      max 5000

[ 📎 Add a screenshot ]   up to 5

Your plan, app version (1.4.2+31) and device (android) are attached so we can
look into it.                                     ← stated, never silent

                                    [ Send message ]
```

- Category chips before the text, so the first interaction is a tap not a blank
  field — the same reason the NPS sheet leads with the score.
- Attachments reuse the existing `uploads/{uid}/` staging path and the photo
  field widget; screenshots are what make a support ticket answerable.
- `AsyncActionButton.filled` per the house convention (press animation +
  double-tap guard).
- Errors render inline in `context.nyumba.danger`, never as a snackbar that
  takes the typed message with it. `RATE_LIMITED` and `tooManyOpenTickets` get
  specific copy: "You already have 3 open conversations — reply on one of them
  and we'll pick it up there."

### `/support/:ticketId` — the thread

```
← Payment not reconciling
  Billing · opened 12 Aug · [ Nyumba is looking into this ]

  ┌──────────────────────────────────────────┐
  │ My tenant paid on the 3rd but the…       │  you, aligned end, primary tint
  │                        12 Aug 09:14  ✓   │
  └──────────────────────────────────────────┘

  ⬤ ┌────────────────────────────────────────┐
  N │ Thanks — could you send the MTN…       │  Nyumba, aligned start, surface
    │ 12 Aug 11:02                           │
    └────────────────────────────────────────┘

  ┌──────────────────────────────────────────┐
  │ Here it is                               │
  │  ⟳ Sending…                              │  ← real outbox state
  └──────────────────────────────────────────┘

  [ Write a reply…                    ] [ ➤ ]
  [ Mark as resolved ]
```

- **Honest delivery state per message**, read from the outbox — `Sending…`,
  `✓` sent, or `Not sent · Retry` in `danger`. This repo has already paid for
  the lesson that a fake success indicator is worse than a slow one (see the
  listing publication state work). A support message that silently failed is the
  single worst bug this feature can have.
- Support messages carry the Nyumba mark; landlord messages carry no avatar.
- On `closed`, the composer is replaced by "This conversation is closed."
  plus **Start a new conversation** (prefilled subject `Re: {subject}`). On
  `resolved`, the composer stays live — a reply reopens it, because the honest
  read of someone replying to a resolution is that it was not resolved.
- **Mark as resolved** is offered to the landlord on `awaiting_landlord`, with
  a confirm. Letting people close their own ticket is respect, not deflection.

### Responsive

Compact: list → thread as full pages. Medium/expanded: the thread opens as a
right-hand pane beside the list (`Row`, list at 360dp), matching the sidebar
shell's density. `WindowSizeClass` already provides the breakpoints.

---

## Admin UI

### `/admin/support` — new destination

Added to `_adminDestinations` between "Landlord feedback" and "Review
moderation" (both are inbound landlord signal; keep them adjacent). Label
"Support", `Icons.support_agent`, with a **count badge of tickets where
`lastMessageAuthorRole == 'landlord'` and status is non-terminal** — the queue
depth, not the total.

```
Support                                             AdminPage

[ Needs reply 4 ] [ Open 9 ] [ Resolved ] [ All ]   [ Category ▾ ] [ Search ]

┌── Queue ─────────────────┬── Thread ─────────────────────────────────┐
│ ● Sarah N.      Billing  │ Payment not reconciling                   │
│   3h · Premium · high    │ Sarah Nakato · Premium · active            │
│   "My tenant paid on…"   │ android 1.4.2+31 · en · opened 12 Aug     │
│──────────────────────────│                                           │
│   Moses K.      Account  │  [ messages, same bubbles as landlord ]    │
│   1d · Starter           │                                           │
│──────────────────────────│  [ Reply…                            ][➤] │
│   Grace A.     Listings  │  [ In progress ][ Resolved ][ Close ]      │
│   3d · Growth   Resolved │                                           │
└──────────────────────────┴───────────────────────────────────────────┘
```

- **Sorted by "waiting longest for a first response", not newest.** A queue
  sorted newest-first is how the oldest ticket never gets answered.
- Each row shows plan tier and priority, because the whole reason those fields
  are denormalized onto the ticket is to be legible here without a join.
- The thread pane header carries the account context an agent would otherwise
  ask for — tier, subscription status, platform, app version, locale.
- Status buttons are explicit, but replying already advances the status, so an
  agent who only ever types still leaves a correct queue behind them.
- Compact: queue and thread are separate pages, same as the landlord side.

Phase 2 adds canned-reply chips above the composer and admin-only internal notes
(as the separate subcollection described above).

---

## Localization

Every user-visible string goes through `Text.localized` / `context.tr` and the
four ARB files (`app_en`, `app_lg`, `app_sw`, `app_ar`) plus regenerated
delegates. Two things need care:

- The static FAQ list is content, not chrome — it needs real translations, not
  placeholders, or it is worse than not shipping it.
- Notification templates (`support_reply`) are a closed union in
  `shared/localization.ts`, so all four locales are compile-enforced.

---

## Tests

| Area | Test |
|---|---|
| Commands | `test/unit/support.test.ts` — open, rate limits, open-ticket cap, author resolution on reply, every legal and illegal transition, attachment path validation, `firstResponseAt` set exactly once. |
| Job registry | Add `notifySupportTeam` and `notifyLandlordSupportReply` to the sorted array in `job-registry.test.ts`. |
| Rules | `test/emulator/rules.test.ts` — landlord reads own ticket, cannot read another's, staff member cannot read the owner's, admin reads all, nobody writes directly. |
| Projection contract | `support_ticket_mapper_test.dart` + a TS-side field-list test, the pair that stops the two sides drifting (the `reviews-projection` precedent). |
| Client dispatch | `firebase_remote_sync_gateway` test asserting each `pendingAction` maps to the right command and payload. |
| Widgets | Composer validation and error copy; thread rendering of each delivery state; closed-ticket composer replacement. No `NyumbaLocalizations.delegate` in any of them. |
| Router | `redirectForSession` — `/support` open to landlord, `/admin/support` gated on `userAccount` read. |

---

## Phasing

**Phase 1 — the conversation (ships alone, useful alone).** ✅ Done.
Collection, rules, `support.open` / `reply` / `updateStatus`, offline entity and
pulls, landlord list + composer + thread, admin queue + thread, email alert to
the support mailbox, landlord reply notifications, FAQ list, localization in all
four locales, tests. Attachments moved to Phase 2 — see note 5 below.

**Phase 2 — the desk.** Internal notes subcollection, canned replies,
`support.rate` CSAT, and attachments (for support and maintenance together,
since neither has a client upload path today). The `platformStaff` roster and
in-app admin notifications were pulled forward into Phase 1 — see
[Alerting the team](#alerting-the-team) — because leaving them out made an
unmonitored mailbox a single point of failure for the whole feature.

**Phase 3 — scale.** Admin queue paging (the `.limit(200)` administrative pull
is the ceiling), first-response-time reporting on the admin overview,
auto-close of `resolved` tickets after 14 days of silence.

## What changed during implementation

Five things the plan above did not anticipate. Each was a decision made against
the code rather than a preference.

**1. `support.open` cannot use `requireActiveLandlord`.** That helper — the
obvious gate, and the one `feedback.submit` uses — rejects any subscription that
is not `active`, which is precisely `past_due`, `pending_payment`, and every
suspended account. It would have closed the support channel for exactly the
people who need it. The command instead requires a live user account and an
existing landlord account, and records approval and subscription state on the
ticket as context for whoever answers.

**2. The same gap existed in the router**, one layer up and easier to miss:
`redirectForSession` sends an unconfirmed landlord to `/subscription` *before*
it evaluates route permissions, so "my payment was not confirmed" would have sat
behind the screen they cannot get past. `/support` is now cleared ahead of that
gate, alongside `/subscription` itself. Pinned by a router test.

**3. `job-registry.test.ts` rejected a conditional job type.** `support.reply`
originally chose its job with a ternary; the registry test scrapes the type out
of the source and a computed one is invisible to it — it would have reached
production unregistered and died in dead-letter without ever surfacing. Written
as two `createJob` calls with literal names instead. The test did its job.

**4. Status badges overflowed a phone at 2× text scale.** "Nyumba is looking
into this" beside a subject line is wider than 393dp once scaled, and an
intrinsic-width badge takes the row. All three headers (landlord card, thread,
admin queue row) now give the badge a bounded flex share. Pinned by
size × text-scale cases in `support_thread_view_test.dart`.

**5. Attachments are deferred to Phase 2.** The commands accept
`stagedAttachmentPaths` and validate them against `uploads/{uid}/`, but nothing
on the client populates them: `_stageImages` in `firebase_remote_sync_gateway`
is hard-wired to property and listing photos, and maintenance's identical field
has never been populated either. Wiring a third aggregate into that pipeline is
a change worth making on its own — for support and maintenance together —
rather than smuggled into this one. The composer does not offer the control, so
nothing promises a capability that is not there.

Also worth recording: `rejectIfWithin` moved from `commands/feedback.ts` into
`shared/handlers.ts`, since support needed the same per-actor cooldown and two
copies of a rate limiter is how they drift.

## Open questions

1. **Tenants.** Tenants have no support path at all today, and their landlord is
   the right first line for most of it — but not for "I can't sign in". The
   model above extends to them (`openedByUid` is already separate from
   `landlordId`); the product question of whether to route tenants to Nyumba or
   to their landlord is not answered here.
2. **Support mailbox address.** `support@nyumba.online` needs to exist and be
   monitored before Phase 1 alerting is real.
3. **Stated SLA.** "One working day" appears in the empty state and composer. It
   should be whatever we will actually meet — under-promising here costs
   nothing.
