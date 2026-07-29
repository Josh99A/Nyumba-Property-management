import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/coordinates.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public/listing_query.dart';

final _published = DateTime.utc(2026, 7, 20);

void main() {
  group('ListingQuery filtering', () {
    final catalogue = [
      _listing(
        id: 'cheap-studio',
        title: 'Compact studio',
        rentMajor: 400000,
        bedrooms: 1,
        unitType: 'studio',
        neighborhood: 'Ntinda',
        publishedAt: _published,
      ),
      _listing(
        id: 'family-house',
        title: 'Family house with garden',
        rentMajor: 1500000,
        bedrooms: 3,
        unitType: 'house',
        neighborhood: 'Muyenga',
        publishedAt: _published.add(const Duration(days: 2)),
      ),
      _listing(
        id: 'mid-apartment',
        title: 'Two-bedroom apartment',
        rentMajor: 800000,
        bedrooms: 2,
        unitType: 'apartment',
        neighborhood: 'Kololo',
        publishedAt: _published.add(const Duration(days: 1)),
      ),
    ];

    test('an empty query keeps every home, newest first', () {
      final results = const ListingQuery().apply(catalogue);

      expect(results.map((listing) => listing.id), [
        'family-house',
        'mid-apartment',
        'cheap-studio',
      ]);
    });

    test('search matches title, location, and unit type', () {
      List<String> idsFor(String text) => const ListingQuery()
          .copyWith(text: text)
          .apply(catalogue)
          .map((listing) => listing.id)
          .toList();

      expect(idsFor('garden'), ['family-house']);
      expect(idsFor('kololo'), ['mid-apartment']);
      expect(idsFor('STUDIO'), ['cheap-studio']);
      expect(idsFor('nowhere'), isEmpty);
    });

    test('price bands do not overlap at their boundary', () {
      final under = const ListingQuery(
        price: PriceBand.under500k,
      ).apply(catalogue);
      final band = const ListingQuery(
        price: PriceBand.from500kTo1m,
      ).apply(catalogue);

      expect(under.map((listing) => listing.id), ['cheap-studio']);
      expect(band.map((listing) => listing.id), ['mid-apartment']);
    });

    test('bedroom filter treats three or more as one band', () {
      final results = const ListingQuery(
        bedrooms: BedroomsFilter.threePlus,
      ).apply(catalogue);

      expect(results.map((listing) => listing.id), ['family-house']);
    });

    test('sorting by price runs in both directions', () {
      final ascending = const ListingQuery(
        sort: ListingSort.priceLowToHigh,
      ).apply(catalogue);
      final descending = const ListingQuery(
        sort: ListingSort.priceHighToLow,
      ).apply(catalogue);

      expect(ascending.first.id, 'cheap-studio');
      expect(descending.first.id, 'family-house');
    });
  });

  group('ListingQuery state', () {
    test('sort is a preference and survives clearing the filters', () {
      const query = ListingQuery(
        text: 'ntinda',
        price: PriceBand.under500k,
        sort: ListingSort.priceHighToLow,
      );

      final cleared = query.cleared();

      expect(cleared.hasFilters, isFalse);
      expect(cleared.sort, ListingSort.priceHighToLow);
    });

    test('active chips remove exactly one filter each', () {
      const query = ListingQuery(
        text: 'ntinda',
        price: PriceBand.under500k,
        bedrooms: BedroomsFilter.one,
        unitType: 'selfContained',
      );

      expect(query.activeFilterCount, 4);
      expect(query.activeChips.map((chip) => chip.label), [
        'ntinda',
        'Under UGX 500K',
        '1 bedroom',
        'Self Contained',
      ]);

      final withoutPrice = query.activeChips[1].removed;
      expect(withoutPrice.price, PriceBand.any);
      expect(withoutPrice.text, 'ntinda');
      expect(withoutPrice.bedrooms, BedroomsFilter.one);
    });

    test('a unit type that left the catalogue is dropped', () {
      const query = ListingQuery(unitType: 'bungalow');

      expect(query.withinTypes({'apartment'}).unitType, anyUnitType);
      expect(query.withinTypes({'bungalow'}).unitType, 'bungalow');
    });

    test('survives a round trip through URL parameters', () {
      const query = ListingQuery(
        text: 'ntinda',
        price: PriceBand.from500kTo1m,
        bedrooms: BedroomsFilter.two,
        unitType: 'apartment',
        sort: ListingSort.priceHighToLow,
      );

      final restored = ListingQuery.fromQueryParameters(
        query.toQueryParameters(),
      );

      expect(restored, query);
    });

    test('a default query writes no parameters at all', () {
      expect(const ListingQuery().toQueryParameters(), isEmpty);
      expect(
        ListingQuery.fromQueryParameters(const <String, String>{}),
        const ListingQuery(),
      );
    });

    test('an unreadable parameter falls back rather than failing', () {
      // These arrive from a URL a stranger may have edited, or from a link
      // that outlived the enum value it names.
      final restored = ListingQuery.fromQueryParameters(const {
        'q': '  ntinda  ',
        'price': 'nonsense',
        'beds': '',
        'sort': 'byVibes',
      });

      expect(restored.text, 'ntinda');
      expect(restored.price, PriceBand.any);
      expect(restored.bedrooms, BedroomsFilter.any);
      expect(restored.sort, ListingSort.newest);
    });

    test('popularLocationsIn ranks by listing count and caps the row', () {
      final locations = ListingQuery.popularLocationsIn([
        _listing(id: 'a', neighborhood: 'Kololo'),
        _listing(id: 'b', neighborhood: 'Ntinda'),
        _listing(id: 'c', neighborhood: 'Ntinda'),
        _listing(id: 'd', neighborhood: 'Ntinda'),
        _listing(id: 'e', neighborhood: 'Bugolobi'),
        _listing(id: 'f', neighborhood: 'Bugolobi'),
      ], limit: 2);

      expect(locations, ['Ntinda', 'Bugolobi']);
    });

    test('unitTypesIn lists each published type once, sorted', () {
      final types = ListingQuery.unitTypesIn([
        _listing(id: 'a', unitType: 'house'),
        _listing(id: 'b', unitType: 'apartment'),
        _listing(id: 'c', unitType: 'house'),
      ]);

      expect(types, ['apartment', 'house']);
    });
  });

  group('nearest to me', () {
    // Kampala city centre, and three adverts at increasing distance from it.
    final origin = Coordinates(latitude: 0.3476, longitude: 32.5825);
    final near = _listing(id: 'near', latitude: 0.3480, longitude: 32.5830);
    final middle = _listing(id: 'middle', latitude: 0.3600, longitude: 32.6000);
    final far = _listing(id: 'far', latitude: 0.4500, longitude: 32.7000);

    test('orders by straight-line distance from the visitor', () {
      const query = ListingQuery(sort: ListingSort.nearest);

      final ordered = query.apply([far, near, middle], origin: origin);

      expect(ordered.map((listing) => listing.id), ['near', 'middle', 'far']);
    });

    // A visitor who declined the permission, or opened someone else's shared
    // `sort=nearest` link, gets the ordinary marketplace rather than an
    // arbitrary order or an error.
    test('falls back to newest when there is no origin', () {
      const query = ListingQuery(sort: ListingSort.nearest);

      final ordered = query.apply([far, near, middle]);
      final byNewest = const ListingQuery().apply([far, near, middle]);

      expect(
        ordered.map((listing) => listing.id),
        byNewest.map((listing) => listing.id),
      );
    });

    // Dropping them would silently hide adverts from someone who only changed
    // the sort order.
    test('keeps unpinned adverts, ordered last', () {
      final unpinned = _listing(id: 'unpinned');
      const query = ListingQuery(sort: ListingSort.nearest);

      final ordered = query.apply([unpinned, far, near], origin: origin);

      expect(ordered.map((listing) => listing.id), ['near', 'far', 'unpinned']);
      expect(ordered, hasLength(3));
    });

    test('a visitor position never travels in a shareable link', () {
      const query = ListingQuery(sort: ListingSort.nearest);

      final parameters = query.toQueryParameters();

      expect(parameters['sort'], 'nearest');
      expect(parameters.values.join(' '), isNot(contains('0.34')));
    });
  });

  group('the view and viewport are not filters', () {
    final centre = Coordinates(latitude: 0.3476, longitude: 32.5825);

    test('map view and a viewport leave the filter count alone', () {
      final query = ListingQuery(
        view: ListingView.map,
        centre: centre,
        zoom: 14,
        sort: ListingSort.priceLowToHigh,
      );

      expect(query.hasFilters, isFalse);
      expect(query.activeFilterCount, 0);
      expect(query.activeChips, isEmpty);
    });

    // Someone who panned to a neighbourhood and then cleared a price filter
    // expects to still be looking at that neighbourhood, on the map.
    test('clearing filters keeps the view, viewport, and sort', () {
      final query = ListingQuery(
        text: 'Ntinda',
        price: PriceBand.under500k,
        view: ListingView.map,
        centre: centre,
        zoom: 14,
        sort: ListingSort.priceLowToHigh,
      );

      final cleared = query.cleared();

      expect(cleared.hasFilters, isFalse);
      expect(cleared.text, isEmpty);
      expect(cleared.view, ListingView.map);
      expect(cleared.centre, centre);
      expect(cleared.zoom, 14);
      expect(cleared.sort, ListingSort.priceLowToHigh);
    });

    test('a map viewport survives a round trip through the URL', () {
      final query = ListingQuery(
        view: ListingView.map,
        centre: Coordinates(latitude: 0.34761, longitude: 32.58254),
        zoom: 14.5,
      );

      final restored = ListingQuery.fromQueryParameters(
        query.toQueryParameters(),
      );

      expect(restored.view, ListingView.map);
      expect(restored.centre, query.centre);
      expect(restored.zoom, 14.5);
      expect(restored, query);
    });

    test('the list view and an unmoved map stay out of the URL', () {
      expect(const ListingQuery().toQueryParameters(), isNot(contains('view')));
      expect(
        const ListingQuery(view: ListingView.map).toQueryParameters().keys,
        isNot(contains('c')),
      );
    });

    // These arrive from a URL a stranger may have edited. The right answer is
    // the unfiltered marketplace, never an error.
    test('nonsense viewport values are ignored', () {
      final restored = ListingQuery.fromQueryParameters(const {
        'view': 'hologram',
        'c': 'not,a,coordinate',
        'z': '999',
      });

      expect(restored.view, ListingView.list);
      expect(restored.centre, isNull);
      expect(restored.zoom, isNull);
    });

    test('an out-of-range coordinate is rejected, not clamped', () {
      final restored = ListingQuery.fromQueryParameters(const {
        'c': '91.0,200.0',
      });

      expect(restored.centre, isNull);
    });
  });
}

Listing _listing({
  required String id,
  String title = 'A home',
  int rentMajor = 500000,
  int? bedrooms = 2,
  String unitType = 'apartment',
  String neighborhood = 'Ntinda',
  DateTime? publishedAt,
  double? latitude,
  double? longitude,
}) => Listing(
  id: id,
  unitId: 'unit_$id',
  propertyId: 'property_$id',
  landlordId: 'landlord_1',
  title: title,
  description: 'A bright, well-kept home.',
  monthlyRentMinor: rentMajor * 100,
  currency: 'UGX',
  status: ListingStatus.published,
  bedrooms: bedrooms,
  bathrooms: 1,
  unitType: unitType,
  city: 'Kampala',
  district: 'Kampala',
  neighborhood: neighborhood,
  approximateLatitude: latitude,
  approximateLongitude: longitude,
  publicContactToken: 'public-contact-$id',
  createdAt: _published.subtract(const Duration(days: 2)),
  updatedAt: _published,
  publishedAt: publishedAt ?? _published,
  syncMetadata: SyncMetadata.synced(lastSyncedAt: _published),
);
