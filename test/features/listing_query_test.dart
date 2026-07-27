import 'package:flutter_test/flutter_test.dart';
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

    test('unitTypesIn lists each published type once, sorted', () {
      final types = ListingQuery.unitTypesIn([
        _listing(id: 'a', unitType: 'house'),
        _listing(id: 'b', unitType: 'apartment'),
        _listing(id: 'c', unitType: 'house'),
      ]);

      expect(types, ['apartment', 'house']);
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
  publicContactToken: 'public-contact-$id',
  createdAt: _published.subtract(const Duration(days: 2)),
  updatedAt: _published,
  publishedAt: publishedAt ?? _published,
  syncMetadata: SyncMetadata.synced(lastSyncedAt: _published),
);
