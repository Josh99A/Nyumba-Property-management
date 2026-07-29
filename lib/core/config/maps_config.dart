/// Google Maps Platform configuration for this build.
///
/// The key is supplied at build time and never committed:
///
/// ```sh
/// flutter build web --dart-define=MAPS_API_KEY=...
/// ```
///
/// Each platform also needs its own *separately restricted* key wired into its
/// native config — Android by package name and SHA-1, iOS by bundle ID, web by
/// HTTP referrer. The define here is what the Dart side checks; it is not the
/// key the Android and iOS SDKs read. See
/// `docs/architecture/maps-and-location-plan.md` for the procurement steps.
library;

abstract final class NyumbaMaps {
  /// Present only in builds that were given a key.
  ///
  /// Deliberately a compile-time constant: on iOS the Maps SDK throws when a
  /// map is created before `provideAPIKey`, and on web the JS bundle is absent
  /// entirely, so an unconfigured build must never construct a map at all.
  /// Every map surface checks [isConfigured] first and renders a fallback that
  /// says so, which is also what makes the feature safe to merge before the
  /// keys are provisioned.
  static const String apiKey = String.fromEnvironment('MAPS_API_KEY');

  static bool get isConfigured => apiKey.isNotEmpty;

  /// Where a picker opens when there is nothing else to centre on.
  ///
  /// Kampala, because Nyumba launches in Uganda only and an unplaced pin
  /// starting mid-Atlantic would make the landlord pan across the world before
  /// they could do anything useful.
  static const double defaultLatitude = 0.3476;
  static const double defaultLongitude = 32.5825;

  /// Metres of the privacy circle drawn around a published pin.
  ///
  /// The server coarsens a public coordinate to three decimal places (~110 m).
  /// The circle is drawn deliberately wider than that: a tight circle around a
  /// coarsened point still reads as "this house", and the radius is the only
  /// thing standing between an approximate location and an address.
  static const double publicPrivacyRadiusMetres = 250;

  /// Where a public advert's rendered location map is served from.
  ///
  /// A first-party path on the Nyumba origin, not a Google URL: the Static
  /// Maps key stays in Secret Manager, the handler rechecks the listing's
  /// public invariant on every request, and the deterministic URL lets the CDN
  /// collapse all traffic for one advert into roughly one upstream call a day.
  /// Kept in sync with `listingMapPath` in
  /// firebase/functions/src/http/static-map.ts.
  static String listingMapUrl(String listingId) =>
      '$publicOrigin/listing/$listingId/map';

  /// The canonical public origin, mirroring `APP_ORIGIN` on the backend.
  static const String publicOrigin = 'https://nyumba.online';

  /// A directions hand-off to whatever maps app the user already has.
  ///
  /// This universal URL opens the native Google Maps app on Android and iOS and
  /// the web map elsewhere, which is both free and better than an embedded map:
  /// it arrives with the user's own traffic data, saved places, and offline
  /// maps. Callers pass the exact pin for private surfaces (staff visiting a
  /// site) and the coarsened one for anything public.
  static Uri directionsTo(double latitude, double longitude) => Uri.https(
    'www.google.com',
    '/maps/dir/',
    <String, String>{'api': '1', 'destination': '$latitude,$longitude'},
  );
}
