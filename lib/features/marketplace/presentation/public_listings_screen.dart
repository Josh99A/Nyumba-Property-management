import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/cloud_status_badge.dart';
import '../../../core/presentation/language_menu_button.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../domain/listing.dart';
import 'listing_visuals.dart';
import 'marketplace_navigation.dart';

/// Monthly rent bands in UGX major units. [max] is exclusive so adjacent
/// bands never overlap.
enum _PriceBand {
  any('Any price', null, null),
  under500k('Under UGX 500K', null, 500000),
  from500kTo1m('UGX 500K – 1M', 500000, 1000000),
  from1mTo2m('UGX 1M – 2M', 1000000, 2000000),
  above2m('Above UGX 2M', 2000000, null);

  const _PriceBand(this.label, this.min, this.max);

  final String label;
  final int? min;
  final int? max;

  bool matches(int rent) =>
      (min == null || rent >= min!) && (max == null || rent < max!);
}

enum _BedroomsFilter {
  any('Any bedrooms'),
  one('1 bedroom'),
  two('2 bedrooms'),
  threePlus('3+ bedrooms');

  const _BedroomsFilter(this.label);

  final String label;

  bool matches(int? bedrooms) => switch (this) {
    any => true,
    one => bedrooms == 1,
    two => bedrooms == 2,
    threePlus => bedrooms != null && bedrooms >= 3,
  };
}

enum _SortOrder {
  newest('Newest first'),
  priceLowToHigh('Price: low to high'),
  priceHighToLow('Price: high to low');

  const _SortOrder(this.label);

  final String label;
}

/// Sentinel for the unit-type filter's "everything" option, kept out of the
/// real unit-type namespace (`Unit.type.name` values are all lowercase words).
const String _allUnitTypes = 'all';

class PublicListingsScreen extends ConsumerStatefulWidget {
  const PublicListingsScreen({super.key});

  @override
  ConsumerState<PublicListingsScreen> createState() =>
      _PublicListingsScreenState();
}

class _PublicListingsScreenState extends ConsumerState<PublicListingsScreen> {
  final _searchController = TextEditingController();
  _PriceBand _priceBand = _PriceBand.any;
  _BedroomsFilter _bedrooms = _BedroomsFilter.any;
  String _unitType = _allUnitTypes;
  _SortOrder _sort = _SortOrder.newest;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _searchController.text.trim().isNotEmpty ||
      _priceBand != _PriceBand.any ||
      _bedrooms != _BedroomsFilter.any ||
      _unitType != _allUnitTypes;

  void _clearFilters() => setState(() {
    _searchController.clear();
    _priceBand = _PriceBand.any;
    _bedrooms = _BedroomsFilter.any;
    _unitType = _allUnitTypes;
  });

  List<Listing> _applyFiltersAndSort(List<Listing> all) {
    final query = _searchController.text.trim().toLowerCase();
    final listings = all.where((listing) {
      final matchesSearch =
          query.isEmpty ||
          listing.title.toLowerCase().contains(query) ||
          listing.description.toLowerCase().contains(query) ||
          listingLocationFor(listing).toLowerCase().contains(query);
      final matchesPrice = _priceBand.matches(listing.monthlyRentMinor ~/ 100);
      final matchesBedrooms = _bedrooms.matches(listing.bedrooms);
      final matchesType =
          _unitType == _allUnitTypes || listing.unitType == _unitType;
      return matchesSearch && matchesPrice && matchesBedrooms && matchesType;
    }).toList();
    switch (_sort) {
      case _SortOrder.newest:
        break; // The repository already returns newest first.
      case _SortOrder.priceLowToHigh:
        listings.sort(
          (a, b) => a.monthlyRentMinor.compareTo(b.monthlyRentMinor),
        );
      case _SortOrder.priceHighToLow:
        listings.sort(
          (a, b) => b.monthlyRentMinor.compareTo(a.monthlyRentMinor),
        );
    }
    return listings;
  }

  @override
  Widget build(BuildContext context) {
    final listingsValue = ref.watch(publicListingsProvider);
    // Signed-in actors explore the same public catalogue. Accounts whose role
    // is not resolved yet return to onboarding instead of seeing a sign-in
    // prompt despite already having a session.
    final session = ref.watch(sessionControllerProvider);
    final navigationAction = marketplaceNavigationAction(session);
    final allListings = listingsValue.value ?? const <Listing>[];
    // Only advertise types that actually exist in the catalogue, so the
    // dropdown never offers a filter guaranteed to return nothing.
    final availableUnitTypes = <String>{
      for (final listing in allListings)
        if (listing.unitType?.trim().isNotEmpty ?? false) listing.unitType!,
    }.toList()..sort();
    if (_unitType != _allUnitTypes && !availableUnitTypes.contains(_unitType)) {
      _unitType = _allUnitTypes;
    }
    return Scaffold(
      backgroundColor: context.nyumba.softIvory,
      appBar: AppBar(
        toolbarHeight: 72,
        backgroundColor: context.nyumba.surface,
        titleSpacing: context.isCompact ? 16 : 32,
        // On compact widths the full wordmark plus the cloud/language/CTA
        // actions overflow the bar, so collapse to the mark-only lockup there.
        title: NyumbaLogo(compact: context.isCompact, height: 42),
        actions: [
          const CloudStatusBadge(),
          SizedBox(width: context.isCompact ? 8 : 14),
          const LanguageMenuButton(compact: true),
          SizedBox(width: context.isCompact ? 8 : 12),
          Padding(
            padding: EdgeInsetsDirectional.only(
              end: context.isCompact ? 12 : 30,
            ),
            child: session == null
                ? OutlinedButton(
                    onPressed: () => context.go(navigationAction.path),
                    child: Text.localized(navigationAction.label),
                  )
                : OutlinedButton.icon(
                    onPressed: () => context.go(navigationAction.path),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text.localized(navigationAction.label),
                  ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [NyumbaColors.midnightNavy, NyumbaColors.navyDark],
                ),
              ),
              padding: EdgeInsetsDirectional.fromSTEB(
                context.pageGutter,
                context.isCompact ? 42 : 58,
                context.pageGutter,
                context.isCompact ? 44 : 62,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FadeSlideIn(
                        child: Text.localized(
                          'Find a place that feels like home.',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: context.isCompact ? 36 : 52,
                              ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        delay: NyumbaMotion.stagger(1),
                        child: Text.localized(
                          'Browse verified available rental spaces and contact landlords directly.',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFFDCE7F4),
                                fontWeight: FontWeight.w400,
                              ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 780),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const gap = 10.0;
                            // Two dropdowns per row on phones, three plus the
                            // clear action on wider screens.
                            final columns = context.isCompact ? 2 : 3;
                            final itemWidth =
                                (constraints.maxWidth - gap * (columns - 1)) /
                                columns;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SearchField(
                                  controller: _searchController,
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: gap),
                                Wrap(
                                  spacing: gap,
                                  runSpacing: gap,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: itemWidth,
                                      child: _FilterDropdown<_PriceBand>(
                                        key: ValueKey(_priceBand),
                                        value: _priceBand,
                                        icon: Icons.payments_outlined,
                                        items: [
                                          for (final band in _PriceBand.values)
                                            DropdownMenuItem(
                                              value: band,
                                              child: Text.localized(
                                                band.label,
                                              ),
                                            ),
                                        ],
                                        onChanged: (value) => setState(
                                          () => _priceBand = value,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: itemWidth,
                                      child: _FilterDropdown<_BedroomsFilter>(
                                        key: ValueKey(_bedrooms),
                                        value: _bedrooms,
                                        icon: Icons.bed_outlined,
                                        items: [
                                          for (final option
                                              in _BedroomsFilter.values)
                                            DropdownMenuItem(
                                              value: option,
                                              child: Text.localized(
                                                option.label,
                                              ),
                                            ),
                                        ],
                                        onChanged: (value) => setState(
                                          () => _bedrooms = value,
                                        ),
                                      ),
                                    ),
                                    if (availableUnitTypes.isNotEmpty)
                                      SizedBox(
                                        width: itemWidth,
                                        child: _FilterDropdown<String>(
                                          key: ValueKey(_unitType),
                                          value: _unitType,
                                          icon: Icons.home_work_outlined,
                                          items: [
                                            const DropdownMenuItem(
                                              value: _allUnitTypes,
                                              child: Text.localized(
                                                'All types',
                                              ),
                                            ),
                                            for (final type
                                                in availableUnitTypes)
                                              DropdownMenuItem(
                                                value: type,
                                                child: Text.localized(
                                                  _unitTypeLabel(type),
                                                ),
                                              ),
                                          ],
                                          onChanged: (value) => setState(
                                            () => _unitType = value,
                                          ),
                                        ),
                                      ),
                                    if (_hasActiveFilters)
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: _clearFilters,
                                        icon: const Icon(
                                          Icons.filter_alt_off_outlined,
                                          size: 18,
                                        ),
                                        label: const Text.localized(
                                          'Clear filters',
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (listingsValue.hasValue && allListings.isNotEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      context.pageGutter,
                      24,
                      context.pageGutter,
                      8,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.nyumba.sageTint,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.nyumba.sageBorder),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.offline_pin_outlined,
                              size: 19,
                              color: context.nyumba.sageDark,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text.localized(
                                'These listings are saved on your device, so you can keep browsing offline.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          listingsValue.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 44,
                        color: context.nyumba.mutedInk,
                      ),
                      const SizedBox(height: 14),
                      Text.localized(
                        'We could not load the listings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text.localized(
                        'Something went wrong reading the saved catalogue. Try again in a moment.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.invalidate(publicListingsProvider),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text.localized('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            data: (all) {
              final listings = _applyFiltersAndSort(all);
              return SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        context.pageGutter,
                        22,
                        context.pageGutter,
                        60,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (all.isNotEmpty) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _hasActiveFilters
                                        ? context.tr('matchingHomesCount', {'matched': listings.length, 'total': all.length})
                                        : context.tr('availableHomesCount', {'count': listings.length}),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ),
                                _SortControl(
                                  value: _sort,
                                  onChanged: (value) =>
                                      setState(() => _sort = value),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (all.isEmpty)
                            _EmptyState(
                              icon: Icons.home_outlined,
                              title: 'No homes are listed right now',
                              message:
                                  'Landlords add new rental spaces regularly — check back soon.',
                            )
                          else if (listings.isEmpty)
                            _EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No homes match those filters',
                              message:
                                  'Try a broader search or a different price range.',
                              action: OutlinedButton.icon(
                                onPressed: _clearFilters,
                                icon: const Icon(
                                  Icons.filter_alt_off_outlined,
                                  size: 18,
                                ),
                                label: const Text.localized('Clear filters'),
                              ),
                            )
                          else
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final columns = constraints.maxWidth >= 1000
                                    ? 3
                                    : constraints.maxWidth >= 620
                                    ? 2
                                    : 1;
                                const gap = 18.0;
                                final width =
                                    (constraints.maxWidth -
                                        gap * (columns - 1)) /
                                    columns;
                                return Wrap(
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    for (final (index, listing)
                                        in listings.indexed)
                                      FadeSlideIn(
                                        delay: NyumbaMotion.stagger(index),
                                        child: SizedBox(
                                          width: width,
                                          child: _ListingCard(listing: listing),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: context.nyumba.surface,
                border: Border(top: BorderSide(color: context.nyumba.outline)),
              ),
              child: Column(
                children: [
                  const NyumbaLogo(height: 34),
                  const SizedBox(height: 10),
                  Text.localized(
                    'Nyumba Property Management · Kampala, Uganda',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text.localized(
                    'Landlords list verified rental spaces; you contact them directly.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 'bedsitter' -> 'Bedsitter'. Unit types are single lowercase words from
/// [UnitType.name], so capitalising the first letter is enough for display.
String _unitTypeLabel(String unitType) => unitType.isEmpty
    ? unitType
    : '${unitType[0].toUpperCase()}${unitType.substring(1)}';

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: context.tr('Search by neighborhood or property'),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: context.tr('Clear search'),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.icon,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final T value;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(prefixIcon: Icon(icon)),
      items: items,
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({required this.value, required this.onChanged});

  final _SortOrder value;
  final ValueChanged<_SortOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<_SortOrder>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(10),
      icon: const Icon(Icons.sort_rounded, size: 18),
      items: [
        for (final order in _SortOrder.values)
          DropdownMenuItem(
            value: order,
            child: Text.localized(
              order.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
      onChanged: (order) {
        if (order != null) onChanged(order);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          children: [
            Icon(icon, size: 44, color: context.nyumba.mutedInk),
            const SizedBox(height: 14),
            Text.localized(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text.localized(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'en_UG',
      symbol: 'UGX ',
      decimalDigits: 0,
    );
    return NyumbaSurface(
      padding: EdgeInsets.zero,
      onTap: () => context.go('/listing/${listing.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Hero(
            tag: 'listing-image-${listing.id}',
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
              child: AspectRatio(
                aspectRatio: 3 / 2,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    listingImage(
                      listing,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      child: _PhotoChip(
                        background: Colors.white,
                        foreground: NyumbaColors.sageDark,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: NyumbaColors.sageDark,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text.localized(
                              listing.availableFrom == null
                                  ? 'Available now'
                                  : 'Available ${DateFormat('d MMM').format(listing.availableFrom!)}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      bottom: 10,
                      start: 10,
                      child: _PhotoChip(
                        background: const Color(0xE60B294F),
                        foreground: Colors.white,
                        child: Text(
                          '${currency.format(listing.monthlyRentMinor / 100)} / mo',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: context.nyumba.mutedInk,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        listingLocationFor(listing),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (listing.bedrooms != null) ...[
                      _Feature(
                        icon: Icons.bed_outlined,
                        label:
                            '${listing.bedrooms} bed${listing.bedrooms == 1 ? '' : 's'}',
                      ),
                      const SizedBox(width: 16),
                    ],
                    if (listing.bathrooms != null)
                      _Feature(
                        icon: Icons.bathtub_outlined,
                        label:
                            '${listing.bathrooms} bath${listing.bathrooms == 1 ? '' : 's'}',
                      ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_rounded, size: 19),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoChip extends StatelessWidget {
  const _PhotoChip({
    required this.background,
    required this.foreground,
    required this.child,
  });

  final Color background;
  final Color foreground;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style:
            Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ) ??
            TextStyle(color: foreground),
        child: child,
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: context.nyumba.mutedInk),
        const SizedBox(width: 5),
        Text.localized(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
