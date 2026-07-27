import 'package:flutter/foundation.dart';

import '../../domain/listing.dart';
import '../listing_visuals.dart';

/// Monthly rent bands in UGX major units. [max] is exclusive so adjacent
/// bands never overlap.
enum PriceBand {
  any('Any price', null, null),
  under500k('Under UGX 500K', null, 500000),
  from500kTo1m('UGX 500K – 1M', 500000, 1000000),
  from1mTo2m('UGX 1M – 2M', 1000000, 2000000),
  above2m('Above UGX 2M', 2000000, null);

  const PriceBand(this.label, this.min, this.max);

  final String label;
  final int? min;
  final int? max;

  bool matches(int rent) =>
      (min == null || rent >= min!) && (max == null || rent < max!);
}

enum BedroomsFilter {
  any('Any bedrooms'),
  one('1 bedroom'),
  two('2 bedrooms'),
  threePlus('3+ bedrooms');

  const BedroomsFilter(this.label);

  final String label;

  bool matches(int? bedrooms) => switch (this) {
    any => true,
    one => bedrooms == 1,
    two => bedrooms == 2,
    threePlus => bedrooms != null && bedrooms >= 3,
  };
}

enum ListingSort {
  newest('Newest first'),
  priceLowToHigh('Price: low to high'),
  priceHighToLow('Price: high to low');

  const ListingSort(this.label);

  final String label;
}

/// Sentinel for "every unit type", so the dropdown value stays a plain
/// [String] alongside the landlord-entered types.
const String anyUnitType = 'all';

/// One removable filter shown to a visitor, so the results header can explain
/// exactly what is narrowing the list.
@immutable
class ListingFilterChip {
  const ListingFilterChip({
    required this.label,
    required this.removed,
    this.localize = true,
  });

  final String label;

  /// The query with only this filter reset.
  final ListingQuery removed;

  /// False for what a visitor typed and for landlord-entered unit types, which
  /// must never be pushed through the translation catalogue.
  final bool localize;
}

/// The complete public search state: what a visitor typed, the filters they
/// picked, and the order they want results in.
///
/// Filtering lives here rather than in the screen so the marketplace rules are
/// exercised by plain unit tests, and so the hero panel, the pinned filter
/// bar, and the mobile filter sheet all narrow results identically.
@immutable
class ListingQuery {
  const ListingQuery({
    this.text = '',
    this.price = PriceBand.any,
    this.bedrooms = BedroomsFilter.any,
    this.unitType = anyUnitType,
    this.sort = ListingSort.newest,
  });

  final String text;
  final PriceBand price;
  final BedroomsFilter bedrooms;
  final String unitType;
  final ListingSort sort;

  /// Sort order is a presentation preference, not a filter, so it is excluded
  /// here and survives "clear filters".
  bool get hasFilters => activeFilterCount > 0;

  int get activeFilterCount =>
      (text.trim().isEmpty ? 0 : 1) +
      (price == PriceBand.any ? 0 : 1) +
      (bedrooms == BedroomsFilter.any ? 0 : 1) +
      (unitType == anyUnitType ? 0 : 1);

  List<ListingFilterChip> get activeChips => [
    if (text.trim().isNotEmpty)
      ListingFilterChip(
        label: text.trim(),
        removed: copyWith(text: ''),
        localize: false,
      ),
    if (price != PriceBand.any)
      ListingFilterChip(
        label: price.label,
        removed: copyWith(price: PriceBand.any),
      ),
    if (bedrooms != BedroomsFilter.any)
      ListingFilterChip(
        label: bedrooms.label,
        removed: copyWith(bedrooms: BedroomsFilter.any),
      ),
    if (unitType != anyUnitType)
      ListingFilterChip(
        label: listingUnitTypeLabel(unitType),
        removed: copyWith(unitType: anyUnitType),
        localize: false,
      ),
  ];

  ListingQuery copyWith({
    String? text,
    PriceBand? price,
    BedroomsFilter? bedrooms,
    String? unitType,
    ListingSort? sort,
  }) => ListingQuery(
    text: text ?? this.text,
    price: price ?? this.price,
    bedrooms: bedrooms ?? this.bedrooms,
    unitType: unitType ?? this.unitType,
    sort: sort ?? this.sort,
  );

  ListingQuery cleared() => ListingQuery(sort: sort);

  /// Drops a unit type that no longer exists in the catalogue, so a filter a
  /// visitor cannot see or remove never silently empties the results.
  ListingQuery withinTypes(Set<String> availableTypes) =>
      unitType == anyUnitType || availableTypes.contains(unitType)
      ? this
      : copyWith(unitType: anyUnitType);

  List<Listing> apply(List<Listing> listings) {
    final query = text.trim().toLowerCase();
    final matched = listings.where((listing) {
      final matchesText =
          query.isEmpty ||
          listing.title.toLowerCase().contains(query) ||
          listing.description.toLowerCase().contains(query) ||
          listingLocationFor(listing).toLowerCase().contains(query) ||
          (listing.unitType?.toLowerCase().contains(query) ?? false);
      return matchesText &&
          price.matches(listing.monthlyRentMinor ~/ 100) &&
          bedrooms.matches(listing.bedrooms) &&
          (unitType == anyUnitType || listing.unitType == unitType);
    }).toList();
    matched.sort(switch (sort) {
      ListingSort.newest => _byNewest,
      ListingSort.priceLowToHigh => _byPriceAscending,
      ListingSort.priceHighToLow => _byPriceDescending,
    });
    return matched;
  }

  /// The neighbourhoods carrying the most homes, for the hero's one-tap
  /// shortcuts. Drawn from the catalogue so a shortcut never lands on an empty
  /// result, and capped because the hero has room for a row, not a directory.
  static List<String> popularLocationsIn(
    List<Listing> listings, {
    int limit = 8,
  }) {
    final counts = <String, int>{};
    for (final listing in listings) {
      final area = listing.neighborhood?.trim().isNotEmpty ?? false
          ? listing.neighborhood!.trim()
          : listing.district?.trim() ?? '';
      if (area.isEmpty) continue;
      counts[area] = (counts[area] ?? 0) + 1;
    }
    final areas = counts.keys.toList()
      ..sort((left, right) {
        final byCount = counts[right]!.compareTo(counts[left]!);
        return byCount != 0 ? byCount : left.compareTo(right);
      });
    return areas.take(limit).toList();
  }

  /// Unit types a visitor can actually pick, in a stable order.
  static List<String> unitTypesIn(List<Listing> listings) => (<String>{
    for (final listing in listings)
      if (listing.unitType?.trim().isNotEmpty ?? false) listing.unitType!,
  }.toList()..sort());

  static int _byNewest(Listing left, Listing right) =>
      _publishedAt(right).compareTo(_publishedAt(left));

  static int _byPriceAscending(Listing left, Listing right) =>
      left.monthlyRentMinor.compareTo(right.monthlyRentMinor);

  static int _byPriceDescending(Listing left, Listing right) =>
      right.monthlyRentMinor.compareTo(left.monthlyRentMinor);

  static DateTime _publishedAt(Listing listing) =>
      listing.publishedAt ?? listing.createdAt;

  @override
  bool operator ==(Object other) =>
      other is ListingQuery &&
      other.text == text &&
      other.price == price &&
      other.bedrooms == bedrooms &&
      other.unitType == unitType &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(text, price, bedrooms, unitType, sort);
}
