import 'package:flutter/foundation.dart';

import '../../../../core/domain/coordinates.dart';
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
  priceHighToLow('Price: high to low'),

  /// Ordered by straight-line distance from the visitor.
  ///
  /// Only offered once the device has actually given up a position. Without an
  /// origin this silently orders by [newest] instead, so a shared link
  /// carrying `sort=nearest` opens as an ordinary marketplace for someone who
  /// declined the permission rather than an empty or arbitrary list.
  nearest('Nearest to me');

  const ListingSort(this.label);

  final String label;

  /// Whether this ordering needs the visitor's position to mean anything.
  bool get needsOrigin => this == ListingSort.nearest;
}

/// Whether results are drawn as a list of cards or on a map.
///
/// A view, not a filter: it changes how the same results are drawn and must
/// stay out of [ListingQuery.hasFilters], [ListingQuery.activeFilterCount],
/// [ListingQuery.activeChips] and [ListingQuery.cleared], exactly as `sort`
/// does. "Clear filters" should never throw a visitor back to the list.
enum ListingView { list, map }

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
    this.view = ListingView.list,
    this.centre,
    this.zoom,
  });

  final String text;
  final PriceBand price;
  final BedroomsFilter bedrooms;
  final String unitType;
  final ListingSort sort;

  /// List or map. See [ListingView] — not a filter.
  final ListingView view;

  /// Where the map is pointed, once a visitor has moved it.
  ///
  /// Null until they pan or zoom, so a first visit frames itself around the
  /// results rather than a hard-coded viewport. Carried in the URL so a map
  /// someone shares opens where they left it.
  final Coordinates? centre;
  final double? zoom;

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
    ListingView? view,
    Coordinates? centre,
    double? zoom,
    bool clearViewport = false,
  }) => ListingQuery(
    text: text ?? this.text,
    price: price ?? this.price,
    bedrooms: bedrooms ?? this.bedrooms,
    unitType: unitType ?? this.unitType,
    sort: sort ?? this.sort,
    view: view ?? this.view,
    centre: clearViewport ? null : (centre ?? this.centre),
    zoom: clearViewport ? null : (zoom ?? this.zoom),
  );

  /// Clears the filters and nothing else.
  ///
  /// Sort, view, and viewport all survive: someone who has panned to a
  /// neighbourhood and then clears a price filter expects to still be looking
  /// at that neighbourhood, on the map, in the order they chose.
  ListingQuery cleared() =>
      ListingQuery(sort: sort, view: view, centre: centre, zoom: zoom);

  /// The query as URL parameters, omitting anything left at its default.
  ///
  /// A search is a place, not a mode: it should survive a reload, come back
  /// intact from the browser's back button, and be shareable as a link. That
  /// requires the state to live in the address bar rather than only in the
  /// widget, and omitting defaults keeps the shared URL readable.
  Map<String, String> toQueryParameters() => <String, String>{
    if (text.trim().isNotEmpty) _textParam: text.trim(),
    if (price != PriceBand.any) _priceParam: price.name,
    if (bedrooms != BedroomsFilter.any) _bedroomsParam: bedrooms.name,
    if (unitType != anyUnitType) _unitTypeParam: unitType,
    if (sort != ListingSort.newest) _sortParam: sort.name,
    if (view != ListingView.list) _viewParam: view.name,
    // Five decimal places is about a metre — far finer than a map viewport
    // needs, and enough to keep the shared URL short.
    if (centre != null)
      _centreParam:
          '${centre!.latitude.toStringAsFixed(5)},'
          '${centre!.longitude.toStringAsFixed(5)}',
    if (zoom != null) _zoomParam: zoom!.toStringAsFixed(2),
  };

  /// Rebuilds a query from URL parameters, ignoring anything unrecognised.
  ///
  /// Lenient by design: these values arrive from a URL a stranger may have
  /// edited or a link that outlived the enum value it named, and the right
  /// answer to `?price=nonsense` is the unfiltered marketplace, not an error
  /// page.
  factory ListingQuery.fromQueryParameters(Map<String, String> parameters) {
    T? byName<T extends Enum>(List<T> values, String? name) {
      if (name == null) return null;
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    final type = parameters[_unitTypeParam]?.trim();
    final zoom = double.tryParse(parameters[_zoomParam]?.trim() ?? '');
    return ListingQuery(
      text: parameters[_textParam]?.trim() ?? '',
      price: byName(PriceBand.values, parameters[_priceParam]) ?? PriceBand.any,
      bedrooms:
          byName(BedroomsFilter.values, parameters[_bedroomsParam]) ??
          BedroomsFilter.any,
      unitType: type == null || type.isEmpty ? anyUnitType : type,
      sort:
          byName(ListingSort.values, parameters[_sortParam]) ??
          ListingSort.newest,
      view:
          byName(ListingView.values, parameters[_viewParam]) ??
          ListingView.list,
      centre: _parseCentre(parameters[_centreParam]),
      // A zoom outside what any map can render is treated as absent rather
      // than clamped: the viewport then reframes around the results, which is
      // the same thing a first visit does.
      zoom: zoom != null && zoom.isFinite && zoom >= 1 && zoom <= 21
          ? zoom
          : null,
    );
  }

  /// Parses `lat,lng`, or null for anything unusable.
  static Coordinates? _parseCentre(String? value) {
    final parts = value?.split(',');
    if (parts == null || parts.length != 2) return null;
    return Coordinates.tryFrom(
      double.tryParse(parts.first.trim()),
      double.tryParse(parts.last.trim()),
    );
  }

  static const _textParam = 'q';
  static const _priceParam = 'price';
  static const _bedroomsParam = 'beds';
  static const _unitTypeParam = 'type';
  static const _sortParam = 'sort';
  static const _viewParam = 'view';
  static const _centreParam = 'c';
  static const _zoomParam = 'z';

  /// Drops a unit type that no longer exists in the catalogue, so a filter a
  /// visitor cannot see or remove never silently empties the results.
  ListingQuery withinTypes(Set<String> availableTypes) =>
      unitType == anyUnitType || availableTypes.contains(unitType)
      ? this
      : copyWith(unitType: anyUnitType);

  /// Filters and orders the catalogue.
  ///
  /// [origin] is the visitor's own position, supplied only when the device has
  /// actually given one up. It is the one input that cannot come from the URL,
  /// which is why it is an argument rather than a field: a link is shareable,
  /// and somebody else's location must never travel inside one.
  List<Listing> apply(List<Listing> listings, {Coordinates? origin}) {
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
      // Falls back rather than failing: a shared `sort=nearest` link opened by
      // someone who declined the location permission gets the ordinary
      // marketplace, not an arbitrary order or an error.
      ListingSort.nearest =>
        origin == null
            ? _byNewest
            : (left, right) => _byDistanceFrom(origin, left, right),
    });
    return matched;
  }

  /// Orders by distance, with unpinned adverts last.
  ///
  /// An advert whose landlord never placed a pin cannot be ranked by distance
  /// at all. Sorting those to the end keeps them reachable — dropping them
  /// would silently hide listings from a visitor who only changed the order.
  static int _byDistanceFrom(Coordinates origin, Listing left, Listing right) {
    final leftPin = _pinOf(left);
    final rightPin = _pinOf(right);
    if (leftPin == null && rightPin == null) return _byNewest(left, right);
    if (leftPin == null) return 1;
    if (rightPin == null) return -1;
    return origin
        .distanceMetresTo(leftPin)
        .compareTo(origin.distanceMetresTo(rightPin));
  }

  static Coordinates? _pinOf(Listing listing) => Coordinates.tryFrom(
    listing.approximateLatitude,
    listing.approximateLongitude,
  );

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
      other.sort == sort &&
      other.view == view &&
      other.centre == centre &&
      other.zoom == zoom;

  @override
  int get hashCode =>
      Object.hash(text, price, bedrooms, unitType, sort, view, centre, zoom);
}
