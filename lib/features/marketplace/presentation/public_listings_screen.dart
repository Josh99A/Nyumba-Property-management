import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nyumba_property_management/core/localization/app_localizations_adapter.dart';
import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/config/market_config.dart';
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

const String _allUnitTypes = 'all';

class PublicListingsScreen extends ConsumerStatefulWidget {
  const PublicListingsScreen({super.key});

  @override
  ConsumerState<PublicListingsScreen> createState() =>
      _PublicListingsScreenState();
}

class _PublicListingsScreenState extends ConsumerState<PublicListingsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _resultsKey = GlobalKey();
  final _landlordKey = GlobalKey();
  _PriceBand _priceBand = _PriceBand.any;
  _BedroomsFilter _bedrooms = _BedroomsFilter.any;
  String _unitType = _allUnitTypes;
  _SortOrder _sort = _SortOrder.newest;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
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

  Future<void> _scrollTo(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: NyumbaMotion.reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 520),
      curve: NyumbaMotion.easeOut,
      alignment: .04,
    );
  }

  void _activateSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    _scrollTo(_resultsKey);
  }

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
        break;
      case _SortOrder.priceLowToHigh:
        listings.sort(
          (left, right) =>
              left.monthlyRentMinor.compareTo(right.monthlyRentMinor),
        );
      case _SortOrder.priceHighToLow:
        listings.sort(
          (left, right) =>
              right.monthlyRentMinor.compareTo(left.monthlyRentMinor),
        );
    }
    return listings;
  }

  @override
  Widget build(BuildContext context) {
    final listingsValue = ref.watch(publicListingsProvider);
    final session = ref.watch(sessionControllerProvider);
    final navigationAction = marketplaceNavigationAction(session);
    final allListings = listingsValue.value ?? const <Listing>[];
    final availableUnitTypes = <String>{
      for (final listing in allListings)
        if (listing.unitType?.trim().isNotEmpty ?? false) listing.unitType!,
    }.toList()..sort();
    if (_unitType != _allUnitTypes && !availableUnitTypes.contains(_unitType)) {
      _unitType = _allUnitTypes;
    }
    final copy = appLocalizationsOf(context);

    return Scaffold(
      backgroundColor: context.nyumba.surface,
      appBar: AppBar(
        toolbarHeight: 76,
        backgroundColor: context.nyumba.surface,
        titleSpacing: context.isCompact ? 16 : 32,
        title: NyumbaLogo(compact: context.isCompact, height: 42),
        actions: [
          if (context.isExpanded) ...[
            TextButton(
              onPressed: () => _scrollTo(_resultsKey),
              child: Text(copy.browseHomesNav),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => _scrollTo(_landlordKey),
              child: Text(copy.forLandlords),
            ),
            const SizedBox(width: 10),
          ],
          const CloudStatusBadge(),
          SizedBox(width: context.isCompact ? 8 : 12),
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
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: _MarketplaceHero(
              listing: allListings.isEmpty ? null : allListings.first,
              searchController: _searchController,
              priceBand: _priceBand,
              bedrooms: _bedrooms,
              unitType: _unitType,
              availableUnitTypes: availableUnitTypes,
              hasActiveFilters: _hasActiveFilters,
              onSearchChanged: (_) => setState(() {}),
              onSearch: _activateSearch,
              onPriceChanged: (value) => setState(() => _priceBand = value),
              onBedroomsChanged: (value) => setState(() => _bedrooms = value),
              onUnitTypeChanged: (value) => setState(() => _unitType = value),
              onClearFilters: _clearFilters,
            ),
          ),
          const SliverToBoxAdapter(child: _MarketplaceTrustRail()),
          listingsValue.when(
            loading: () => SliverToBoxAdapter(
              child: _MarketplaceResultsSection(
                key: _resultsKey,
                child: const SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
            error: (error, stack) => SliverToBoxAdapter(
              child: _MarketplaceResultsSection(
                key: _resultsKey,
                child: _EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: copy.publicListingsLoadErrorTitle,
                  message: copy.publicListingsLoadErrorMessage,
                  action: FilledButton.icon(
                    onPressed: () => ref.invalidate(publicListingsProvider),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(copy.retry),
                  ),
                ),
              ),
            ),
            data: (all) {
              final listings = _applyFiltersAndSort(all);
              final resultSummary = _hasActiveFilters
                  ? copy.matchingHomesCount(listings.length, all.length)
                  : copy.availableHomesCount(listings.length);
              return SliverToBoxAdapter(
                child: _MarketplaceResultsSection(
                  key: _resultsKey,
                  resultSummary: resultSummary,
                  sort: all.isEmpty
                      ? null
                      : _SortControl(
                          value: _sort,
                          onChanged: (value) => setState(() => _sort = value),
                        ),
                  child: all.isEmpty
                      ? const _EmptyState(
                          icon: Icons.home_outlined,
                          title: 'No homes are listed right now',
                          message:
                              'Landlords add new rental spaces regularly — check back soon.',
                        )
                      : listings.isEmpty
                      ? _EmptyState(
                          icon: Icons.search_off_rounded,
                          title: copy.noHomesMatch,
                          message: copy.tryBroaderSearch,
                          action: OutlinedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(
                              Icons.filter_alt_off_outlined,
                              size: 18,
                            ),
                            label: Text(copy.clearFilters),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 1000
                                ? 3
                                : constraints.maxWidth >= 620
                                ? 2
                                : 1;
                            const gap = 22.0;
                            final width = gridItemWidth(
                              constraints.maxWidth,
                              columns: columns,
                              gap: gap,
                            );
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final (index, listing) in listings.indexed)
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
                ),
              );
            },
          ),
          SliverToBoxAdapter(
            child: _MarketplaceAudienceSection(
              key: _landlordKey,
              onBrowseHomes: () => _scrollTo(_resultsKey),
              onListSpace: () => context.go(navigationAction.path),
              listSpaceLabel: session == null
                  ? copy.signInToListSpace
                  : context.tr(navigationAction.label),
            ),
          ),
          SliverToBoxAdapter(
            child: _MarketplaceFooter(
              onBrowseHomes: () => _scrollTo(_resultsKey),
              onAccount: () => context.go(navigationAction.path),
              accountLabel: context.tr(navigationAction.label),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketplaceHero extends StatelessWidget {
  const _MarketplaceHero({
    required this.listing,
    required this.searchController,
    required this.priceBand,
    required this.bedrooms,
    required this.unitType,
    required this.availableUnitTypes,
    required this.hasActiveFilters,
    required this.onSearchChanged,
    required this.onSearch,
    required this.onPriceChanged,
    required this.onBedroomsChanged,
    required this.onUnitTypeChanged,
    required this.onClearFilters,
  });

  final Listing? listing;
  final TextEditingController searchController;
  final _PriceBand priceBand;
  final _BedroomsFilter bedrooms;
  final String unitType;
  final List<String> availableUnitTypes;
  final bool hasActiveFilters;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearch;
  final ValueChanged<_PriceBand> onPriceChanged;
  final ValueChanged<_BedroomsFilter> onBedroomsChanged;
  final ValueChanged<String> onUnitTypeChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlideIn(
          child: Text.localized(
            'Find a place that feels like home.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontSize: compact ? 38 : 58,
              height: 1.04,
              letterSpacing: compact ? -1 : -1.7,
            ),
          ),
        ),
        SizedBox(height: compact ? 16 : 20),
        FadeSlideIn(
          delay: NyumbaMotion.stagger(1),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              appLocalizationsOf(context).browseVerifiedHomes,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: NyumbaColors.navyOnDark,
                fontSize: compact ? 18 : 20,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );

    final media = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: compact ? 16 / 9 : 4 / 3,
        child: listing == null
            ? Image.asset(
                'assets/listings/generated-modern-apartment-exterior.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              )
            : listingImage(
                listing!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                cacheWidth: 1280,
              ),
      ),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [NyumbaColors.navyDark, NyumbaColors.midnightNavy],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.pageGutter,
              compact ? 38 : 52,
              context.pageGutter,
              compact ? 22 : 0,
            ),
            child: Column(
              children: [
                if (compact) ...[
                  content,
                  const SizedBox(height: 28),
                  media,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: content),
                      const SizedBox(width: 56),
                      Expanded(child: media),
                    ],
                  ),
                Transform.translate(
                  offset: Offset(0, compact ? 22 : 50),
                  child: _SearchPanel(
                    controller: searchController,
                    priceBand: priceBand,
                    bedrooms: bedrooms,
                    unitType: unitType,
                    availableUnitTypes: availableUnitTypes,
                    hasActiveFilters: hasActiveFilters,
                    onSearchChanged: onSearchChanged,
                    onSearch: onSearch,
                    onPriceChanged: onPriceChanged,
                    onBedroomsChanged: onBedroomsChanged,
                    onUnitTypeChanged: onUnitTypeChanged,
                    onClearFilters: onClearFilters,
                  ),
                ),
                SizedBox(height: compact ? 22 : 50),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.controller,
    required this.priceBand,
    required this.bedrooms,
    required this.unitType,
    required this.availableUnitTypes,
    required this.hasActiveFilters,
    required this.onSearchChanged,
    required this.onSearch,
    required this.onPriceChanged,
    required this.onBedroomsChanged,
    required this.onUnitTypeChanged,
    required this.onClearFilters,
  });

  final TextEditingController controller;
  final _PriceBand priceBand;
  final _BedroomsFilter bedrooms;
  final String unitType;
  final List<String> availableUnitTypes;
  final bool hasActiveFilters;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearch;
  final ValueChanged<_PriceBand> onPriceChanged;
  final ValueChanged<_BedroomsFilter> onBedroomsChanged;
  final ValueChanged<String> onUnitTypeChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 980),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.nyumba.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.nyumba.outline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24123A6F),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(context.isCompact ? 14 : 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final compact = constraints.maxWidth < 660;
              final searchRow = compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SearchField(
                          controller: controller,
                          onChanged: onSearchChanged,
                          onSubmitted: (_) => onSearch(),
                        ),
                        const SizedBox(height: gap),
                        FilledButton.icon(
                          onPressed: onSearch,
                          icon: const Icon(Icons.search_rounded, size: 19),
                          label: Text(appLocalizationsOf(context).searchAction),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _SearchField(
                            controller: controller,
                            onChanged: onSearchChanged,
                            onSubmitted: (_) => onSearch(),
                          ),
                        ),
                        const SizedBox(width: gap),
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: onSearch,
                            icon: const Icon(Icons.search_rounded, size: 19),
                            label: Text(
                              appLocalizationsOf(context).searchAction,
                            ),
                          ),
                        ),
                      ],
                    );
              final columns = constraints.maxWidth >= 720 ? 3 : 2;
              final itemWidth = gridItemWidth(
                constraints.maxWidth,
                columns: columns,
                gap: gap,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchRow,
                  const SizedBox(height: gap),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: _FilterDropdown<_PriceBand>(
                          key: ValueKey(priceBand),
                          value: priceBand,
                          icon: Icons.payments_outlined,
                          items: [
                            for (final band in _PriceBand.values)
                              DropdownMenuItem(
                                value: band,
                                child: Text.localized(band.label),
                              ),
                          ],
                          onChanged: onPriceChanged,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _FilterDropdown<_BedroomsFilter>(
                          key: ValueKey(bedrooms),
                          value: bedrooms,
                          icon: Icons.bed_outlined,
                          items: [
                            for (final option in _BedroomsFilter.values)
                              DropdownMenuItem(
                                value: option,
                                child: Text.localized(option.label),
                              ),
                          ],
                          onChanged: onBedroomsChanged,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _FilterDropdown<String>(
                          key: ValueKey(unitType),
                          value: unitType,
                          icon: Icons.home_work_outlined,
                          items: [
                            const DropdownMenuItem(
                              value: _allUnitTypes,
                              child: Text.localized('All types'),
                            ),
                            for (final type in availableUnitTypes)
                              DropdownMenuItem(
                                value: type,
                                child: Text(_unitTypeLabel(type)),
                              ),
                          ],
                          onChanged: onUnitTypeChanged,
                        ),
                      ),
                      if (hasActiveFilters)
                        TextButton.icon(
                          onPressed: onClearFilters,
                          icon: const Icon(
                            Icons.filter_alt_off_outlined,
                            size: 18,
                          ),
                          label: const Text.localized('Clear filters'),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MarketplaceTrustRail extends StatelessWidget {
  const _MarketplaceTrustRail();

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    const items = [
      (Icons.home_outlined, 'active'),
      (Icons.person_outline_rounded, 'contact'),
      (Icons.offline_pin_outlined, 'offline'),
    ];
    String label(String value) => switch (value) {
      'active' => copy.trustActiveListings,
      'contact' => copy.trustDirectLandlordContact,
      _ => copy.trustWorksOffline,
    };

    return ColoredBox(
      color: context.nyumba.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.pageGutter,
              context.isCompact ? 54 : 76,
              context.pageGutter,
              context.isCompact ? 34 : 48,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760 ? 3 : 1;
                const gap = 18.0;
                final width = gridItemWidth(
                  constraints.maxWidth,
                  columns: columns,
                  gap: gap,
                );
                return Wrap(
                  spacing: gap,
                  runSpacing: 14,
                  children: [
                    for (final (index, item) in items.indexed)
                      SizedBox(
                        width: width,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: columns == 1 || index == 0
                                ? null
                                : BorderDirectional(
                                    start: BorderSide(
                                      color: context.nyumba.divider,
                                    ),
                                  ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: context.nyumba.sageTint,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    item.$1,
                                    color: context.nyumba.sageDark,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 13),
                                Flexible(
                                  child: Text(
                                    label(item.$2),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketplaceResultsSection extends StatelessWidget {
  const _MarketplaceResultsSection({
    required this.child,
    this.resultSummary,
    this.sort,
    super.key,
  });

  final Widget child;
  final String? resultSummary;
  final Widget? sort;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    return ColoredBox(
      color: context.nyumba.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.pageGutter,
              34,
              context.pageGutter,
              context.isCompact ? 58 : 82,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 24,
                  runSpacing: 18,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 660),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            copy.availableHomes,
                            style: Theme.of(
                              context,
                            ).textTheme.headlineLarge?.copyWith(fontSize: 38),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            copy.publicFreshSpaces,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          if (resultSummary != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              resultSummary!,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: context.nyumba.sageDark),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 16,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_done_outlined,
                              size: 20,
                              color: context.nyumba.sageDark,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              copy.savedForOfflineBrowsing,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: context.nyumba.sageDark),
                            ),
                          ],
                        ),
                        ?sort,
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketplaceAudienceSection extends StatelessWidget {
  const _MarketplaceAudienceSection({
    required this.onBrowseHomes,
    required this.onListSpace,
    required this.listSpaceLabel,
    super.key,
  });

  final VoidCallback onBrowseHomes;
  final VoidCallback onListSpace;
  final String listSpaceLabel;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final left = ColoredBox(
      color: context.nyumba.sageTint,
      child: Padding(
        padding: EdgeInsets.all(context.isCompact ? 24 : 38),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.lookingForHomeTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              copy.lookingForHomeDescription,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: context.nyumba.sageGreen,
              ),
              onPressed: onBrowseHomes,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 19),
              label: Text(copy.browseAvailableHomes),
            ),
            const SizedBox(height: 28),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 8,
                child: Image.asset(
                  'assets/listings/generated-upscale-living-room.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final right = ColoredBox(
      color: context.nyumba.goldTint,
      child: Padding(
        padding: EdgeInsets.all(context.isCompact ? 24 : 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 112,
              height: 90,
              child: Stack(
                children: [
                  Icon(
                    Icons.other_houses_outlined,
                    size: 78,
                    color: context.nyumba.terracottaGold,
                  ),
                  PositionedDirectional(
                    end: 0,
                    bottom: 2,
                    child: Icon(
                      Icons.vpn_key_outlined,
                      size: 46,
                      color: context.nyumba.terracottaDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              copy.haveRentalSpaceTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              copy.haveRentalSpaceDescription,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: context.nyumba.terracottaGold,
              ),
              onPressed: onListSpace,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 19),
              label: Text(listSpaceLabel),
            ),
          ],
        ),
      ),
    );

    return ColoredBox(
      color: context.nyumba.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.pageGutter,
              0,
              context.pageGutter,
              context.isCompact ? 56 : 88,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 860
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: left),
                            Expanded(child: right),
                          ],
                        ),
                      )
                    : Column(children: [left, right]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketplaceFooter extends StatelessWidget {
  const _MarketplaceFooter({
    required this.onBrowseHomes,
    required this.onAccount,
    required this.accountLabel,
  });

  final VoidCallback onBrowseHomes;
  final VoidCallback onAccount;
  final String accountLabel;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final footerText = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: NyumbaColors.navyOnDark);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [NyumbaColors.midnightNavy, NyumbaColors.navyDark],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.pageGutter,
              44,
              context.pageGutter,
              30,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 64,
                  runSpacing: 32,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: [
                    SizedBox(
                      width: 340,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const NyumbaLogo(height: 42, onDarkSurface: true),
                          const SizedBox(height: 16),
                          Text(copy.publicFooterDescription, style: footerText),
                        ],
                      ),
                    ),
                    _FooterLinkGroup(
                      title: copy.availableHomes,
                      children: [
                        TextButton(
                          onPressed: onBrowseHomes,
                          child: Text(copy.browseHomesNav),
                        ),
                      ],
                    ),
                    _FooterLinkGroup(
                      title: copy.dashboard,
                      children: [
                        TextButton(
                          onPressed: onAccount,
                          child: Text(accountLabel),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: NyumbaColors.sageOnDark,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text.localized('Kampala, Uganda', style: footerText),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                const Divider(color: Color(0x4DDCE7F4)),
                const SizedBox(height: 18),
                Text.localized(
                  'Nyumba Property Management · Kampala, Uganda',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFAFC0D5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterLinkGroup extends StatelessWidget {
  const _FooterLinkGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style:
          Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.white) ??
          const TextStyle(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          for (final child in children)
            TextButtonTheme(
              data: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: NyumbaColors.navyOnDark,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: const Size(0, 36),
                ),
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

String _unitTypeLabel(String unitType) => unitType.isEmpty
    ? unitType
    : '${unitType[0].toUpperCase()}${unitType.substring(1)}';

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: context.tr('Search by neighborhood or property'),
        prefixIcon: const Icon(Icons.location_on_outlined),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.nyumba.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 12, end: 6),
        child: DropdownButton<_SortOrder>(
          value: value,
          isDense: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(10),
          icon: const Icon(Icons.unfold_more_rounded, size: 18),
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
        ),
      ),
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
    final copy = appLocalizationsOf(context);
    final currency = NumberFormat.currency(
      locale: copy.localeName,
      name: NyumbaMarket.currencyCode,
      symbol: NyumbaMarket.currencySymbol,
      decimalDigits: 0,
    );
    final rent = currency.format(listing.monthlyRentMinor ~/ 100);
    final availableFrom = listing.availableFrom;
    final availability = availableFrom == null
        ? copy.listingAvailableNow
        : copy.listingAvailableFromDate(
            DateFormat('d MMM', copy.localeName).format(availableFrom),
          );
    return NyumbaSurface(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      onTap: () => context.go('/listing/${listing.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Hero(
            tag: 'listing-image-${listing.id}',
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
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
                      cacheWidth: 960,
                    ),
                    PositionedDirectional(
                      bottom: 12,
                      start: 12,
                      child: _PhotoChip(
                        background: context.nyumba.sageGreen,
                        foreground: Colors.white,
                        child: Text(availability),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: context.nyumba.sageDark,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        listingLocationFor(listing),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 14),
                Text(
                  copy.monthlyRentDisplay(rent),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.nyumba.terracottaDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    if (listing.bedrooms != null)
                      _Feature(
                        icon: Icons.bed_outlined,
                        label: copy.bedroomsCount(listing.bedrooms!),
                      ),
                    if (listing.bathrooms != null)
                      _Feature(
                        icon: Icons.bathtub_outlined,
                        label: copy.bathroomsCount(listing.bathrooms!),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      copy.viewHome,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: context.nyumba.midnightNavy,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: context.nyumba.midnightNavy,
                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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
        Icon(icon, size: 19, color: context.nyumba.sageDark),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
