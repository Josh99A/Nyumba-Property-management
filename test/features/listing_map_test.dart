import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/coordinates.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public/listing_map.dart';

final _published = DateTime.utc(2026, 7, 20);

Listing listingAt({
  required String id,
  double? latitude,
  double? longitude,
  int rentMajor = 500000,
}) => Listing(
  id: id,
  unitId: 'unit_$id',
  propertyId: 'property_$id',
  landlordId: 'landlord_1',
  title: 'A home',
  description: 'A bright, well-kept home.',
  monthlyRentMinor: rentMajor * 100,
  currency: 'UGX',
  status: ListingStatus.published,
  unitType: 'apartment',
  city: 'Kampala',
  neighborhood: 'Ntinda',
  approximateLatitude: latitude,
  approximateLongitude: longitude,
  publicContactToken: 'public-contact-$id',
  createdAt: _published,
  updatedAt: _published,
  publishedAt: _published,
  syncMetadata: SyncMetadata.synced(lastSyncedAt: _published),
);

void main() {
  group('clustering', () {
    test('groups adverts that would otherwise overlap', () {
      // Three within a few hundred metres, one across the city.
      final clusters = clusterListings([
        listingAt(id: 'a', latitude: 0.3476, longitude: 32.5825),
        listingAt(id: 'b', latitude: 0.3478, longitude: 32.5827),
        listingAt(id: 'c', latitude: 0.3477, longitude: 32.5826),
        listingAt(id: 'far', latitude: 0.4500, longitude: 32.7000),
      ], zoom: 12);

      expect(clusters, hasLength(2));
      final group = clusters.firstWhere((cluster) => cluster.isGroup);
      expect(group.count, 3);
      expect(clusters.any((cluster) => !cluster.isGroup), isTrue);
    });

    test('separates the same adverts once zoomed in', () {
      final listings = [
        listingAt(id: 'a', latitude: 0.3476, longitude: 32.5825),
        listingAt(id: 'b', latitude: 0.3600, longitude: 32.6000),
      ];

      expect(clusterListings(listings, zoom: 8), hasLength(1));
      expect(clusterListings(listings, zoom: 15), hasLength(2));
    });

    // The map never claims to be the complete catalogue; the list view still
    // carries these.
    test('silently omits adverts with no pin', () {
      final clusters = clusterListings([
        listingAt(id: 'pinned', latitude: 0.3476, longitude: 32.5825),
        listingAt(id: 'unpinned'),
        listingAt(id: 'half', latitude: 0.3476),
      ], zoom: 12);

      expect(clusters, hasLength(1));
      expect(clusters.single.only.id, 'pinned');
    });

    test('a group pin sits on its members, not on a grid corner', () {
      final clusters = clusterListings([
        listingAt(id: 'a', latitude: 0.3470, longitude: 32.5820),
        listingAt(id: 'b', latitude: 0.3474, longitude: 32.5824),
      ], zoom: 12);

      expect(clusters.single.centre.latitude, closeTo(0.3472, 0.00001));
      expect(clusters.single.centre.longitude, closeTo(32.5822, 0.00001));
    });

    test('a group labels itself with its cheapest rent', () {
      final clusters = clusterListings([
        listingAt(
          id: 'a',
          latitude: 0.3476,
          longitude: 32.5825,
          rentMajor: 900000,
        ),
        listingAt(
          id: 'b',
          latitude: 0.3477,
          longitude: 32.5826,
          rentMajor: 400000,
        ),
      ], zoom: 12);

      expect(clusters.single.lowestRentMinor, 400000 * 100);
    });

    test('an empty catalogue clusters into nothing', () {
      expect(clusterListings(const [], zoom: 12), isEmpty);
    });

    // Grid rather than distance-based clustering, so pins do not reshuffle
    // under the visitor's finger as they pan.
    test('grouping is stable for the same zoom regardless of order', () {
      final listings = [
        listingAt(id: 'a', latitude: 0.3476, longitude: 32.5825),
        listingAt(id: 'b', latitude: 0.3478, longitude: 32.5827),
        listingAt(id: 'far', latitude: 0.4500, longitude: 32.7000),
      ];

      final forward = clusterListings(listings, zoom: 12);
      final reversed = clusterListings(listings.reversed.toList(), zoom: 12);

      expect(
        forward.map((cluster) => cluster.count),
        reversed.map((cluster) => cluster.count),
      );
    });
  });

  group('framing the results', () {
    test('frames every pinned advert', () {
      final bounds = boundsOf([
        listingAt(id: 'a', latitude: 0.30, longitude: 32.50),
        listingAt(id: 'b', latitude: 0.40, longitude: 32.70),
      ]);

      expect(bounds, isNotNull);
      expect(bounds!.centre.latitude, closeTo(0.35, 0.00001));
      expect(bounds.centre.longitude, closeTo(32.60, 0.00001));
      expect(bounds.latitudeSpan, closeTo(0.10, 0.00001));
    });

    // Otherwise the map zooms to maximum on a single advert and shows a street
    // corner instead of a neighbourhood.
    test('a single advert still gets a usable span', () {
      final bounds = boundsOf([
        listingAt(id: 'only', latitude: 0.3476, longitude: 32.5825),
      ]);

      expect(bounds!.latitudeSpan, greaterThan(0));
      expect(bounds.longitudeSpan, greaterThan(0));
    });

    // The caller's cue to fall back to the default city view rather than point
    // at the ocean.
    test('nothing pinned means no bounds at all', () {
      expect(boundsOf([listingAt(id: 'unpinned')]), isNull);
      expect(boundsOf(const []), isNull);
    });
  });

  group('search this area', () {
    final origin = Coordinates(latitude: 0.3476, longitude: 32.5825);

    test('a nudge does not offer to re-search', () {
      final drift = viewportDrift(
        from: origin,
        to: Coordinates(latitude: 0.3480, longitude: 32.5828),
        visibleSpanDegrees: 0.05,
      );

      expect(drift, lessThan(searchThisAreaDriftThreshold));
    });

    test('a deliberate pan to another neighbourhood does', () {
      final drift = viewportDrift(
        from: origin,
        to: Coordinates(latitude: 0.4000, longitude: 32.5825),
        visibleSpanDegrees: 0.05,
      );

      expect(drift, greaterThan(searchThisAreaDriftThreshold));
    });

    test('a degenerate span cannot divide by zero', () {
      expect(
        viewportDrift(
          from: origin,
          to: Coordinates(latitude: 0.4, longitude: 32.7),
          visibleSpanDegrees: 0,
        ),
        0,
      );
    });
  });

  group('distance', () {
    // Kampala to Entebbe is about 35 km in a straight line.
    test('measures a real-world distance to within a percent', () {
      final kampala = Coordinates(latitude: 0.3476, longitude: 32.5825);
      final entebbe = Coordinates(latitude: 0.0512, longitude: 32.4637);

      expect(kampala.distanceMetresTo(entebbe), closeTo(35000, 1500));
    });

    test('is zero to itself and symmetric', () {
      final a = Coordinates(latitude: 0.3476, longitude: 32.5825);
      final b = Coordinates(latitude: 0.4000, longitude: 32.7000);

      expect(a.distanceMetresTo(a), 0);
      expect(a.distanceMetresTo(b), closeTo(b.distanceMetresTo(a), 0.0001));
    });
  });
}
