import 'dart:math' as math;

import '../../../../core/domain/coordinates.dart';
import '../../domain/listing.dart';

/// One pin on the results map: a single advert, or a group standing in for
/// several that would otherwise overlap into an unreadable pile.
class ListingCluster {
  ListingCluster({required this.centre, required List<Listing> listings})
    : listings = List.unmodifiable(listings);

  final Coordinates centre;
  final List<Listing> listings;

  bool get isGroup => listings.length > 1;
  int get count => listings.length;

  /// The advert a single pin stands for.
  Listing get only => listings.single;

  /// The cheapest rent in the group, in minor units — what a group pin
  /// labels itself with, because "from X" is the number a renter scans for.
  int get lowestRentMinor => listings
      .map((listing) => listing.monthlyRentMinor)
      .reduce((a, b) => a < b ? a : b);
}

/// Groups adverts that sit too close together to be distinguishable.
///
/// A fixed grid in degrees, sized by zoom, computed on-device. Deliberately
/// not a clustering package: the launch catalogue is small, this runs in
/// microseconds over it, and a dependency that has to be kept in step with the
/// maps SDK is not yet earned. Revisit if the catalogue reaches thousands.
///
/// Grid rather than distance-based clustering because it is stable: panning
/// the map does not reshuffle which adverts group together, so pins do not
/// dance around under the visitor's finger.
List<ListingCluster> clusterListings(
  List<Listing> listings, {
  required double zoom,
}) {
  final buckets = <String, List<Listing>>{};
  for (final listing in listings) {
    final pin = Coordinates.tryFrom(
      listing.approximateLatitude,
      listing.approximateLongitude,
    );
    // An advert with no pin cannot appear on a map at all. The list view
    // still carries it, which is why the map view never claims to be the
    // complete catalogue.
    if (pin == null) continue;
    final cell = _cellSizeDegrees(zoom);
    final key =
        '${(pin.latitude / cell).floor()}:${(pin.longitude / cell).floor()}';
    (buckets[key] ??= <Listing>[]).add(listing);
  }

  final clusters = <ListingCluster>[];
  for (final group in buckets.values) {
    // A group pin sits at the mean of its members rather than the cell centre,
    // so it lands on the homes it represents instead of floating on a grid.
    final latitude =
        group
            .map((listing) => listing.approximateLatitude!)
            .reduce((a, b) => a + b) /
        group.length;
    final longitude =
        group
            .map((listing) => listing.approximateLongitude!)
            .reduce((a, b) => a + b) /
        group.length;
    clusters.add(
      ListingCluster(
        centre: Coordinates(latitude: latitude, longitude: longitude),
        listings: group,
      ),
    );
  }
  // Stable order so the marker set does not churn between rebuilds.
  clusters.sort((left, right) {
    final byLatitude = right.centre.latitude.compareTo(left.centre.latitude);
    return byLatitude != 0
        ? byLatitude
        : left.centre.longitude.compareTo(right.centre.longitude);
  });
  return clusters;
}

/// Grid cell size in degrees for a zoom level.
///
/// Halves with each zoom step, which is exactly how the map's own scale
/// behaves, so a cluster covers roughly the same number of screen pixels at
/// every zoom. Clamped at both ends: without a floor, a deep zoom produces
/// cells so small that every advert is its own cluster and the grouping stops
/// doing anything; without a ceiling, a world view collapses everything into
/// one pin.
double _cellSizeDegrees(double zoom) {
  final clamped = zoom.clamp(1.0, 21.0);
  return (_baseCellDegrees / math.pow(2, clamped - _baseZoom)).clamp(
    0.0005,
    20.0,
  );
}

/// At zoom 12 — roughly a city — group anything within ~1.1 km.
const double _baseZoom = 12;
const double _baseCellDegrees = 0.01;

/// The viewport that frames every pinned advert in [listings].
///
/// Returned as a centre and a span so the caller can turn it into whatever the
/// maps SDK wants. Null when nothing is pinned, which is the caller's cue to
/// fall back to the default city view rather than point at the ocean.
({Coordinates centre, double latitudeSpan, double longitudeSpan})? boundsOf(
  List<Listing> listings,
) {
  final pins = <Coordinates>[
    for (final listing in listings)
      ?Coordinates.tryFrom(
        listing.approximateLatitude,
        listing.approximateLongitude,
      ),
  ];
  if (pins.isEmpty) return null;
  var minimumLatitude = pins.first.latitude;
  var maximumLatitude = pins.first.latitude;
  var minimumLongitude = pins.first.longitude;
  var maximumLongitude = pins.first.longitude;
  for (final pin in pins.skip(1)) {
    minimumLatitude = math.min(minimumLatitude, pin.latitude);
    maximumLatitude = math.max(maximumLatitude, pin.latitude);
    minimumLongitude = math.min(minimumLongitude, pin.longitude);
    maximumLongitude = math.max(maximumLongitude, pin.longitude);
  }
  return (
    centre: Coordinates(
      latitude: (minimumLatitude + maximumLatitude) / 2,
      longitude: (minimumLongitude + maximumLongitude) / 2,
    ),
    // A floor so a single advert, or several at the same address, does not
    // produce a zero-sized viewport the map would zoom to its maximum.
    latitudeSpan: math.max(maximumLatitude - minimumLatitude, 0.01),
    longitudeSpan: math.max(maximumLongitude - minimumLongitude, 0.01),
  );
}

/// How far the map has moved from the viewport the current results were drawn
/// for, as a fraction of the visible span.
///
/// This is what decides whether "Search this area" is worth offering: a nudge
/// should not, a deliberate pan to another neighbourhood should. Offering it
/// constantly is as bad as searching automatically — both make the visitor
/// feel the map is arguing with them.
double viewportDrift({
  required Coordinates from,
  required Coordinates to,
  required double visibleSpanDegrees,
}) {
  if (visibleSpanDegrees <= 0) return 0;
  final latitudeDelta = (to.latitude - from.latitude).abs();
  final longitudeDelta = (to.longitude - from.longitude).abs();
  return math.max(latitudeDelta, longitudeDelta) / visibleSpanDegrees;
}

/// Drift past which the map is showing somewhere else.
///
/// A third of the visible span: enough that a small correction is ignored,
/// small enough that a real pan to the next neighbourhood always offers.
const double searchThisAreaDriftThreshold = 1 / 3;
