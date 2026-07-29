# Maps and location — implementation plan

Status: **plan, not yet implemented.** This document is normative for the work
once it starts; update it with any decision that changes during
implementation.

Goal: let a prospective tenant understand *where* a home is and get *directions
to it*, let a landlord place that location without typing coordinates, and let
staff and tenants navigate to a property they are already entitled to visit —
without publishing anyone's exact address and without an unbounded Google Maps
bill.

## 1. Current state

The geo pipeline is roughly half built, and the half that exists does not
round-trip.

What already works:

- `Listing` carries `approximateLatitude` / `approximateLongitude`, validated to
  real coordinate ranges (`lib/features/marketplace/domain/listing.dart`).
- `FirebaseRemoteSyncGateway` already folds those two scalars into
  `approximateLocation: {lat, lng}` on `listing.saveDraft`
  (`lib/core/offline/firebase_remote_sync_gateway.dart`).
- `listingSaveDraft` accepts `approximateLocation` in its strict payload schema,
  and `listingPublish` **already coarsens it to three decimal places (~110 m)**
  before writing `publicListings` (`firebase/functions/src/commands/listings.ts`).
  The privacy decision was made and implemented; it just has no UI.

What is broken or missing:

1. **The pull round-trip is broken.** `RemotePullGateway._toLocalShape` returns
   `approximateLocation` as a nested map, but `ListingMapper.fromRecord` reads
   flat `approximateLatitude` / `approximateLongitude`. Coordinates therefore
   survive only on the device that authored them and are null everywhere else.
   Any map shipped before this is fixed renders empty for every other user.
2. **The landlord input is two raw decimal text fields**
   (`lib/features/marketplace/presentation/landlord_listings_screen.dart`).
   Nobody types a correct coordinate into a text box, so the field is
   effectively always null in real data.
3. **`Property` has no coordinates at all.** It has `addressLine`, `city`,
   `district` and nothing geospatial, so the landlord's own portfolio cannot be
   mapped and a listing cannot inherit a location from its property.
4. **The public JSON-LD has no `geo` node.** `public-seo.ts` emits a
   `PostalAddress` only, and its field allowlist does not include
   `approximateLocation`.
5. No `google_maps_flutter`, no `url_launcher`, no `geolocator` in
   `pubspec.yaml`.

## 2. Product decisions

### 2.1 Three rendering tiers

Google Maps Platform bills per map load. The public listing page is the
highest-traffic surface in the product, so an interactive map there is both the
most expensive thing we could build and the wrong answer to the user's actual
question. A visitor wants "roughly where is this" and "take me there"; neither
requires a pannable map.

| Tier | Surfaces | Billing | Rationale |
| --- | --- | --- | --- |
| **Deep link** — "Get directions" hands off to the Google Maps app | every surface that has a location | none | uses the app the user already has, with their own traffic data and offline maps |
| **Static map image** — marker/circle, tap to expand | listing detail, property detail, tenant home | Static Maps SKU, and see §2.2 — effectively one call per listing per day | renders inside the server-rendered HTML with no JavaScript, no layout shift, and caches for offline |
| **Interactive `GoogleMap`** | landlord pin picker, explore map view | full dynamic map load, low volume | panning is the point on exactly these two screens |

### 2.2 Static maps are proxied and CDN-cached, never called from the client

A Maps Static API key placed in an `<img src>` on a public page is a key handed
to the internet. Instead, add a `staticMap` HTTP Function behind a Hosting
rewrite:

```
/map/listing/{listingId}.png   ->  function staticMap (europe-west1)
```

The function:

- holds the Static Maps key as a Firebase secret (`defineSecret`), the same
  pattern as `RESEND_API_KEY` in `firebase/functions/src/shared/email.ts`;
- re-checks the public invariant at request time exactly as `publicSeo` does —
  `status == published`, `isDeleted != true`, `expiresAt` in the future —
  and returns `404`/`410` otherwise, with `X-Robots-Tag: noindex, nofollow`;
- renders **only** the coarsened `approximateLocation` from `publicListings`,
  never the canonical listing or property;
- returns `Cache-Control: public, max-age=86400, s-maxage=604800`.

Because the URL is deterministic and the coordinate is coarsened, Firebase
Hosting's CDN collapses all traffic for a listing into roughly one upstream
Google call per day regardless of how many people view it. This is the single
largest cost decision in the feature, and it also makes the image work in the
SEO HTML and cacheable by `cached_network_image` for offline viewing.

Private surfaces (property detail, tenant home, staff maintenance) use a
sibling authenticated route that renders the **exact** coordinate and is
`private, no-store`.

### 2.3 Privacy model

The exact pin is private property data. The coarsening already implemented
server-side is the boundary, and these rules make it hold in the UI too:

- **Public renders a circle, not a pin.** A marker on a coarsened point still
  reads as "this house". Draw a translucent circle of radius ≥ 250 m centred on
  the coarsened coordinate, with no marker and no Street View affordance.
- **The exact coordinate never enters `publicListings`, the SEO HTML, the
  sitemap, JSON-LD, or the public static-map proxy.** Extending the
  `public-seo.ts` allowlist to include `approximateLocation` is a deliberate,
  reviewed change and must add only the already-coarsened field.
- **`addressLine` stays private.** It is canonical property data today and this
  work must not surface it publicly, in metadata, or in a directions label.
- **A visitor's own location never leaves the device.** "Near me" sorting runs
  on-device against the already-downloaded catalogue. No location is sent to
  Firestore, a Function, or Google.
- **The landlord is shown what the public sees.** The picker renders the
  privacy circle over their own precise pin with copy explaining it. Landlords
  under-share when they cannot see what publishing costs them.
- Staff and tenant surfaces use the **exact** coordinate — they are already
  entitled to the address — and must not reuse the public proxy.

## 3. Data model changes

### 3.1 Client

- `Listing`: no schema change. The two existing scalars stay; only the input
  affordance and the pull mapping change.
- `Property`: add `latitude` / `longitude` (nullable doubles, same validation
  helper as `Listing._coordinateError`), plus `copyWith` clear flags matching
  the file's existing convention. Update `CreatePropertyInput`,
  `PropertyMapper`, and the sembast repository.
- A small shared value object is worth extracting rather than passing pairs of
  nullable doubles through four layers — put it in `lib/core/domain/` since both
  `portfolio` and `marketplace` need it and neither may import the other's data
  layer.

### 3.2 Server

- `propertyCreateSchema` and the property update schema in
  `firebase/functions/src/commands/portfolio.ts` gain an optional
  `location: {lat, lng}` object, mirroring the shape `listingSaveDraft` already
  uses. Both are `strictPayload`, so **the server change must deploy before the
  client sends the field** or every property write is rejected.
- `FirebaseRemoteSyncGateway` gains the same fold-to-`location` mapping for
  property create/update that it already has for listings.
- No Firestore rules change: `properties` is landlord-private already, and
  `publicListings` already permits `approximateLocation` because `listingPublish`
  writes it.
- No new index: nothing queries by coordinate. Geo *filtering* is on-device.

### 3.3 Documentation to update in the same change

`docs/architecture/backend-command-contracts.md` (new payload fields),
`docs/architecture/firebase-data-and-security.md` (the static-map proxy and its
public-invariant recheck), and this file.

## 4. Procurement and platform configuration

Enable on the existing GCP project: **Maps SDK for Android**, **Maps SDK for
iOS**, **Maps JavaScript API**, **Maps Static API**, **Places API (New)**,
**Geocoding API**.

Create **four separately restricted keys** — this is the step that is usually
got wrong:

| Key | Restriction | Where it lives |
| --- | --- | --- |
| Android | package name + release and debug SHA-1 | `android/local.properties`, CI secret |
| iOS | bundle ID | `--dart-define`, CI secret |
| Web (JS) | HTTP referrer `nyumba.online/*` | build-time define, CI secret |
| Server | none needed; never leaves the backend | Firebase secret, used by `staticMap` and geocoding |

Per `AGENTS.md`, none of these are committed. Set a **billing budget with
alerts and per-API quota caps** before the first key is created: an
unrestricted maps key on a public marketplace is a way to lose real money to a
stranger.

Google's per-SKU free tiers changed in 2025. Confirm current figures against
the live pricing page before committing to the Phase 3 explore map, which is
the only genuinely volume-sensitive surface.

Packages: `google_maps_flutter` (with `google_maps_flutter_web`),
`url_launcher`, `geolocator`. Android needs the manifest key meta-data and
`ACCESS_COARSE_LOCATION`; iOS needs `NSLocationWhenInUseUsageDescription`. Both
permission strings are user-facing and therefore need localizing.

## 5. Phases

### Phase 0 — unblock — **done**

Nothing renders correctly until this lands. Shipped:

1. `FirestoreRemotePullGateway.toLocalShape` (renamed from `_toLocalShape` so
   the shape contract is directly assertable) flattens `approximateLocation`
   into `approximateLatitude` / `approximateLongitude` for `listing` and
   `publicListing`. Accepts both `{lat, lng}` — what `listingPublish` writes —
   and `{latitude, longitude}`, which is what `_normalize` produces from a
   Firestore `GeoPoint`, so migrating the field to a real `GeoPoint` later
   cannot silently break it again. Applies both or neither axis.
2. Six regression tests in `test/features/listing_projection_test.dart`,
   covering the flattening, a full decode to a `Listing`, the GeoPoint key
   spelling, integer coordinates, an absent pin, and a half-written pair.
3. `public-seo.ts` emits
   `geo: {'@type': 'GeoCoordinates', latitude, longitude}` on the listing's
   `itemOffered`, sourced only from the already-coarsened projection field,
   which is added to the `toPublicSeoListing` allowlist through a validating
   parser that rejects non-numeric, non-finite, and out-of-range pairs.
4. Four SEO tests: the pin survives while `exactLocation` / `addressLine` do
   not, malformed pins degrade to no map, the JSON-LD is parsed and asserted
   rather than substring-matched, and the `geo` node is absent with no
   `streetAddress` anywhere when no pin was set.

Verified: `flutter analyze` clean, `dart format` clean, the functions
`npm run typecheck` and all 77 unit tests green. No UI shipped in this phase,
so there is nothing to verify in a browser yet.

### Phase 1 — the landlord pin picker — **done, pending API keys**

Shipped:

- `Coordinates` in `lib/core/domain/`, shared by both aggregates so they cannot
  drift into two spellings of a pin. Carries the same `coarsened()` rounding
  `listingPublish` applies, so the landlord's privacy preview shows the point
  the server will actually publish.
- `Property` gained `location`, end to end: domain, `PropertyMapper`, the
  sembast repository, the outbox payload, and the pull shape. The server's
  `propertyCreate`/`propertyUpdate` schemas gained an optional `location`, and
  the shared `coordinateSchema` now backs both property and listing pins.
- Pins are **clearable**. `location` is nullable on the update schemas and the
  gateway sends an explicit null on an edit, because an omitted key cannot
  distinguish "unchanged" from "removed" — a cleared pin previously synced as a
  no-op and came back on the next pull.
- `LocationPickerField` + a full-screen picker replace the two raw
  latitude/longitude text boxes on the property create form, the property edit
  form, and the advert form. Fixed crosshair rather than a draggable marker, so
  the point is never under the landlord's finger; "use my current location";
  and the privacy circle with the "not your gate" copy on advert pins.
- A new advert inherits its property's pin, with an explicitly placed pin
  winning. The draft owns its copy from creation, so moving a property later
  never silently moves a live advert.
- 18 strings across all four ARB catalogues, the Android and iOS permission
  strings, and the Android manifest key wired through an untracked
  `android/maps.properties` placeholder.

Verified: `flutter analyze` and `dart format` clean, **605** Flutter tests,
**77** functions tests, `flutter build web --release` and
`flutter build apk --debug` both succeed with the new dependencies.

**Not done, and blocking real use:** the Google Cloud API keys (§4). Every map
surface is gated on `NyumbaMaps.isConfigured`, so today every build takes the
fallback path — which still lets a landlord capture a pin from where they are
standing, since `geolocator` needs no Maps key.

**Deferred from this phase:** Places Autocomplete search in the picker, and
reverse-geocoding the pin back into the `city`/`district`/`neighborhood`
fields. Both need the Places and Geocoding APIs enabled and a server-side key,
so they belong with the same procurement step. The crosshair and "use my
current location" cover the core need without them.

### Phase 1 (original plan) — the landlord pin picker

Good data enters the system here. Everything downstream is worthless without it.

- Replace the two coordinate text fields with a **"Set location on map"** row
  showing the current pin state, opening a full-screen picker sheet.
- Picker contents: Places Autocomplete search, a draggable centre pin
  (crosshair-style, so the pin never hides under a finger), "Use my current
  location", and reverse-geocoding that fills `city` / `district` /
  `neighborhood` back into the form rather than making the landlord retype them.
- Render the **privacy circle** over the precise pin with plain copy:
  *"Tenants see this circle, roughly 200 m across — not your gate."*
- Add coordinates to `Property` (§3), a pin picker on the property form, and
  **default a new listing's pin to its property's pin**. This turns a
  per-listing chore into one-time setup and is the difference between a feature
  landlords use and one they skip.
- The picker needs a connection. Offline it must degrade honestly — show the
  stored pin read-only with "Setting a location needs a connection", consistent
  with the app's existing rule against implying state it cannot prove.

### Phase 2 — "Where you'll live" — **done, pending the Static Maps key**

Shipped:

- **`/listing/{id}/map`** on the existing `publicSeo` function. No new function
  and **no `firebase.json` change** — the deployed `/listing/**` rewrite
  already routes it, and serving it here means the public invariant is
  rechecked by the same code path guarding every other public response.
  `404` for an unknown listing, `410` for one that is unpublished, deleted, or
  expired, `noindex` headers and `no-store` on every error path.
- The **Static Maps key stays in Secret Manager** (`MAPS_STATIC_API_KEY`),
  declared on the function's `secrets`. It never reaches a page.
- `Cache-Control: public, max-age=86400, s-maxage=604800` on the rendered
  image. The URL is deterministic per listing and the coordinate is coarsened,
  so a stale copy cannot leak newer information — this one header is what
  collapses all traffic for an advert into roughly one upstream Google call a
  day. A failed render is `no-store`, so a hole is never cached.
- The map is a **circle, never a marker**, drawn as an encoded path polygon at
  `MAPS_PUBLIC_PRIVACY_RADIUS_METRES` (250 m, mirrored in
  `lib/core/config/maps_config.dart`).
- **`ListingLocationSection`** on the advert page, between the amenities and
  "Costs and terms": the cached static map, the "approximate location, landlord
  shares the exact address" caveat, and a full-width **Get directions** button
  that hands off to the reader's own maps app. Renders nothing at all when the
  advert has no pin. The directions button stays enabled offline, because the
  Maps app carries its own offline maps.
- The same section is in the **server-rendered HTML**, so it works with
  JavaScript disabled: a first-party `<img>` with intrinsic dimensions (no
  layout shift) and a plain crawlable `<a>` for directions.

Verified: **614** Flutter tests, **84** functions tests, `flutter analyze` and
`dart format` clean, `flutter build web --release` and `flutter build apk
--debug` both succeed.

**Keys and deployment — done (2026-07-29).** Four restricted keys exist on
`nyumba-property-management`, each carrying both an application *and* an API
restriction: `nyumba-android` (package + debug SHA-1), `nyumba-ios` (bundle id),
`nyumba-web` (referrers), `nyumba-server` (Static Maps, no application
restriction). `MAPS_STATIC_API_KEY` holds the server key, and the deploy granted
the runtime service account `secretAccessor` on it.

`publicSeo` is deployed with the route. Verified live: `/listing/{id}/map`
answers from its own handler (`404`, `no-store`, `noindex` for a listing with no
pin), while an unmatched path still falls through to the HTML 404 page — so the
route is matching rather than being swallowed by the catch-all.

**Not yet exercised:** the upstream Static Maps call itself. No listing in the
catalogue has a pin, because the picker is new and the old text fields were
never filled in. Placing a pin on a property or advert and republishing is what
will produce the first real render.

**Before release:** the Android key holds the *debug* SHA-1 only. A Play Store
build is signed with a different key and will render a blank map until that
fingerprint is added — take it from the Play Console under App Signing, not
from a local keystore.

### Phase 2 (original plan) — "Where you'll live" on the listing detail

Placement: a new section in `_ListingDescription`, **between the
amenities/accessibility blocks and "Costs and terms"** — after photos and price
have done their job, before the reader hits the money table and stalls. Not at
the top; not buried under the reviews.

Contents:

- Static map (the `/map/listing/{id}.png` proxy) showing the privacy circle,
  with the neighbourhood name and a one-line explanation that the location is
  approximate;
- a full-width **Get directions** button →
  `https://www.google.com/maps/dir/?api=1&destination={lat},{lng}` via
  `url_launcher` with `LaunchMode.externalApplication`;
- tap-to-expand into a larger interactive map for the people who want it, so
  the dynamic map load is paid only on demand.

On the compact layout the bottom bar is already the Apply action, so directions
must be a real button inside the section rather than a small icon competing
with it.

When a listing has no coordinate, render nothing — not an empty grey box. The
existing `listingLocationFor` text stays as the fallback.

### Phase 3 — explore map view — **done (2026-07-29)**

- **`ListingSort.nearest`**, ordered by an on-device haversine
  (`Coordinates.distanceMetresTo`). No Distance Matrix call — a billable
  request per listing per sort would be slower and no more useful for ordering
  a list. Straight-line distance, honest for "what is near me" and never
  presented as a journey.
- The visitor's position is an **argument to `apply`, never a field on the
  query**, precisely so it cannot end up inside a shareable URL. The
  permission prompt is deferred to the moment the sort is chosen; a
  marketplace that asks on arrival gets refused. Declining withdraws the option
  rather than erroring, and a shared `sort=nearest` link opened by someone
  without a position falls back to `newest`.
- **`ListingView` + `centre` + `zoom` in the URL** (`view`, `c`, `z`), kept out
  of `hasFilters`, `activeFilterCount`, `activeChips`, and `cleared()`. Someone
  who pans to a neighbourhood and then clears a price filter still sees that
  neighbourhood, on the map, in their chosen order.
- **On-device grid clustering** (`listing_map.dart`) — not a package: the
  launch catalogue is small and this runs in microseconds over it. Grid rather
  than distance-based so grouping is *stable* and pins do not reshuffle under
  the visitor's finger while panning. Cell size halves per zoom step, clamped
  at both ends.
- **"Search this area" never fires automatically**, and only appears once the
  camera has drifted more than a third of the visible span — a nudge is
  ignored, a real pan always offers. Auto-search on pan is the most disliked
  interaction in map search UIs.
- Tapping a single pin opens the **existing `ListingResultCard`** in a sheet, so
  list and map can never drift into describing the same advert differently. A
  group pin zooms in instead — cheaper than a sheet to dismiss.
- The map view states plainly when adverts are missing from it: an advert with
  no pin cannot be drawn, so the map never claims to be the whole catalogue.
- iOS `NSLocationWhenInUseUsageDescription` was rewritten: it previously
  described only the landlord picker, and Apple requires the purpose string to
  match actual use now that visitors sort by proximity.

Verified: **683** Flutter tests, analyze and format clean, web release and
debug APK both build.

**Cost posture.** The map is opt-in behind the List/Map control rather than the
default view, and never re-queries on its own — the two decisions that keep the
Dynamic Maps SKU bounded. "Nearest to me" costs nothing at all. Before this
goes to real traffic, confirm current per-SKU pricing and set a daily cap on
the Maps JavaScript SDK as well as Static Maps.

**Not verifiable here:** every map surface is gated on `NyumbaMaps.isConfigured`
and no build in this environment carries `--dart-define=MAPS_API_KEY`, so the
clustering, drift, and ordering logic is covered by tests while the rendered
`GoogleMap` itself has not been exercised. First run with a key should check
marker taps, the sheet, and "Search this area" on a real device.

### Phase 3 (original plan) — explore map view (largest and most cost-sensitive)

- A `List | Map` segmented control in the results header on
  `public_listings_screen` / `public_search_screen`.
- Markers labelled with rent; grid-based clustering computed on-device (the
  launch catalogue is small enough that a clustering dependency is not yet
  earned). Tapping a marker opens the existing result card in a bottom sheet so
  the two views share one card component.
- **"Search this area" appears after a pan and never fires automatically.**
  Auto-search on pan is the most disliked interaction in map search UIs.
- View state goes in the URL: `view=map`, `c={lat},{lng}`, `z={zoom}`.
  `ListingQuery` already treats a search as a shareable place via
  `toQueryParameters`, and a map view that breaks the back button would be a
  regression against that. Like `sort`, the view and viewport are **not**
  filters: keep them out of `hasFilters`, `activeFilterCount`, `activeChips`,
  and `cleared()`.
- **"Near me" sort** (`ListingSort.nearest`) using `geolocator` and an on-device
  haversine. Cheaper than the map, ships faster, and on a phone is arguably more
  useful than the map itself. Must degrade gracefully when permission is denied
  — the option disappears rather than erroring, and the sort falls back to
  `newest`.

### Phase 4 — private navigation surfaces — **staff half done, tenant half blocked**

Shipped (2026-07-29):

- **`DirectionsButton`** (`lib/core/presentation/directions_button.dart`), a
  deep-link-only hand-off carrying the **exact** pin. No Maps SDK, no API key,
  no per-tap cost, and it arrives in the user's own Maps app with their traffic
  data and offline maps. Renders *nothing* without a pin rather than a disabled
  control that invites a tap and explains nothing.
- **Property detail**: directions sit with the address line, where someone
  working out how to get there is already looking.
- **Maintenance work orders**: directions in the existing per-request action
  menu, offered only when that request's property carries a pin. This is the
  surface that most justifies the feature in the whole product — a contractor
  is being dispatched somewhere they have never been. The pin map is resolved
  once per table, not once per row.

Verified: 619 Flutter tests (+5), analyze and format clean.

**Deliberately not built — the tenant half.** "Directions to their own home,
plus a small static map on the home card" cannot work today, and building it
would have produced a control that renders nothing on every real device:

- Tenant-side sync does not deliver property data at all. Per
  `app_dependencies.dart`, every `tenantPortals` projection except reviews is
  still unread, because the projections and the Dart mappers disagree — "a
  tenant sees only locally recorded data." A tenant's device therefore holds no
  property record, no coordinate, and no address.
- `TENANT_LEASE_FIELDS` and `TENANT_MAINTENANCE_FIELDS` carry no property
  location, so even once those projections are pulled the coordinate still has
  to be denormalized onto them deliberately.
- That reconciliation is called out in the code as "a product and security
  decision, not a mechanical reshape" — tenant models demand `landlordId`,
  which these projections withhold from tenants on purpose. It is a
  pre-existing blocker, not a maps problem, and it should not be resolved
  incidentally inside a maps change.

The static map on the tenant home card carries a second, independent problem:
it needs the **exact** coordinate, so it cannot reuse the Phase 2 proxy, which
only ever serves coarsened pins for *public* listings. Serving it would mean a
new authenticated image endpoint returning private location data — a new public
attack surface that deserves its own review rather than being bundled into this
phase. It is also the weakest item in the plan on merit: a tenant already knows
where they live, so the map is decorative while the directions link is the
useful part.

### Phase 4 (original plan) — private navigation surfaces

- **Maintenance / staff**: "Get directions" on a request, using the **exact**
  property coordinate. Staff are dispatched to a site; the coarsened public
  point is the wrong data here.
- **Tenant portal**: directions to their own home, plus a small static map on
  the home card. Also exact.
- Both are deep-link-only where possible; neither justifies an interactive map.

## 6. Offline behaviour

Maps are the one part of this product that genuinely cannot work offline, and
the app's invariants require being honest about that rather than showing a
hopeful spinner.

- Static map images cache via CDN headers and `cached_network_image` (already a
  dependency), so a listing viewed once keeps its map offline.
- Interactive maps get an explicit "Map needs a connection" placeholder, never
  an indefinite loader.
- The **Get directions button stays enabled offline** — the Google Maps app has
  its own offline maps, and refusing the tap would be worse than handing off.

## 7. Localization

Every new string lands in all four `assets/l10n/app_*.arb` catalogs in the same
change, including the Android/iOS location permission rationale strings. The
map picker, the segmented control, and the directions button all need an Arabic
RTL pass — map control clusters and icon-plus-label buttons are exactly what
breaks under RTL. Use `AlignmentDirectional` / `EdgeInsetsDirectional`
throughout, per the existing convention.

## 8. Testing

- Domain: property coordinate validation, including the reject cases.
- Mapper: the Phase 0 round-trip regression, both key shapes.
- Repository: property write/read with coordinates through sembast.
- Sync: the property `location` payload fold, and that a pull cannot clobber an
  unsynced local pin.
- SEO: `geo` emission, allowlist non-disclosure, and that no canonical field
  rides along.
- Function: `staticMap` returns `404`/`410` for missing, unpublished, deleted,
  and expired listings, carries `noindex` headers on every error path, and never
  reads the canonical collection.
- Widget: the picker's offline state, the "Where you'll live" section's
  no-coordinate case, and the map/list toggle preserving query parameters.
- Emulator: the extended property command schemas, allowed and denied actors.

## 9. Risks

- **Cost.** Mitigated by the proxy in §2.2 and hard quota caps, but the Phase 3
  explore map is the surface to watch. Ship it behind a flag if traffic is
  uncertain.
- **Strict payload schemas.** Server deploys before client for both the
  property `location` field and anything added to `listing.saveDraft`.
- **Coarsening is not anonymity.** Three decimal places is ~110 m; in a sparse
  rural area that can still identify a single compound. The ≥ 250 m circle and
  the no-marker rule are what make it defensible. If Nyumba later lists rural
  property at scale, revisit the coarsening factor rather than the UI.
- **iOS builds** still need a paid Apple Developer team (see `AGENTS.md`), so
  the iOS map key cannot be verified end-to-end until that exists.
