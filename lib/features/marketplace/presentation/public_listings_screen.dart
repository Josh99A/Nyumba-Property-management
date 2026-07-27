import 'dart:async';

import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nyumba_property_management/core/localization/app_localizations_adapter.dart';
import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/responsive.dart';
import '../../auth/application/session_controller.dart';
import '../domain/listing.dart';
import 'marketplace_navigation.dart';
import 'public/listing_query.dart';
import 'public/listing_result_card.dart';
import 'public/marketplace_filters.dart';
import 'public/marketplace_sections.dart';
import 'public/marketplace_top_bar.dart';

/// How long the search waits after the last keystroke before re-filtering.
///
/// Re-running the grid on every character makes a phone keyboard feel like it
/// is dragging; the field itself is never held back, only the filtering is.
const _searchSettleDelay = Duration(milliseconds: 250);

/// Gap between result cards, both across a row and between rows.
const _resultsGap = 22.0;

/// Public marketplace: a search-led hero, the results grid under a pinned
/// filter bar, and the tenant and landlord stories beneath it.
///
/// The screen owns the search state and every control on the page reads and
/// replaces it, so the hero search, the pinned bar, the filter sheet, and the
/// active-filter chips can never disagree.
class PublicListingsScreen extends ConsumerStatefulWidget {
  const PublicListingsScreen({super.key});

  @override
  ConsumerState<PublicListingsScreen> createState() =>
      _PublicListingsScreenState();
}

class _PublicListingsScreenState extends ConsumerState<PublicListingsScreen> {
  final _scrollController = ScrollController();
  final _resultsKey = GlobalKey();
  final _landlordKey = GlobalKey();

  /// The filters currently narrowing the grid.
  ListingQuery _query = const ListingQuery();

  /// What the search fields show. It runs ahead of [_query] while a visitor is
  /// still typing.
  String _searchText = '';
  Timer? _searchSettle;

  @override
  void dispose() {
    _searchSettle?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Applies a finished decision — a dropdown, a chip, a cleared filter —
  /// straight away, and abandons any keystroke still waiting to land.
  void _applyQuery(ListingQuery query) {
    _searchSettle?.cancel();
    setState(() {
      _query = query;
      _searchText = query.text;
    });
  }

  void _changeSearchText(String text) {
    setState(() => _searchText = text);
    _searchSettle?.cancel();
    _searchSettle = Timer(_searchSettleDelay, () {
      if (mounted) setState(() => _query = _query.copyWith(text: text));
    });
  }

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
    _applyQuery(_query.copyWith(text: _searchText));
    _scrollTo(_resultsKey);
  }

  void _searchLocation(String location) {
    _applyQuery(_query.copyWith(text: location));
    _scrollTo(_resultsKey);
  }

  @override
  Widget build(BuildContext context) {
    final listingsValue = ref.watch(publicListingsProvider);
    final session = ref.watch(sessionControllerProvider);
    final navigationAction = marketplaceNavigationAction(session);
    final copy = appLocalizationsOf(context);
    final allListings = listingsValue.value ?? const <Listing>[];
    final unitTypes = ListingQuery.unitTypesIn(allListings);
    // A landlord can unpublish the last home of a type while a visitor still
    // has it selected; dropping it here keeps the results honest rather than
    // empty for a reason nothing on screen explains.
    final query = _query.withinTypes(unitTypes.toSet());
    final inset = marketplaceBandInset(context);

    return Scaffold(
      backgroundColor: context.nyumba.surface,
      appBar: MarketplaceTopBar(
        signedIn: session != null,
        accountLabel: navigationAction.label,
        onAccount: () => context.go(navigationAction.path),
        onBrowseHomes: () => _scrollTo(_resultsKey),
        onForLandlords: () => _scrollTo(_landlordKey),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: MarketplaceHero(
              searchBar: HeroSearchBar(
                value: _searchText,
                onChanged: _changeSearchText,
                onSearch: _activateSearch,
              ),
              assurances: [
                if (listingsValue.hasValue)
                  copy.availableHomesCount(allListings.length),
              ],
              quickLocations: ListingQuery.popularLocationsIn(allListings),
              onLocationSelected: _searchLocation,
            ),
          ),
          const SliverToBoxAdapter(child: MarketplaceAssuranceBand()),
          SliverToBoxAdapter(
            child: MarketplaceBand(
              key: _resultsKey,
              padding: EdgeInsets.only(
                top: context.isCompact ? 48 : 72,
                bottom: 18,
              ),
              child: MarketplaceResultsHeader(
                resultSummary: listingsValue.hasValue
                    ? _summaryFor(query, allListings)
                    : null,
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: MarketplaceFilterBar(
              query: query,
              searchText: _searchText,
              listings: allListings,
              availableUnitTypes: unitTypes,
              onChanged: _applyQuery,
              onSearchChanged: _changeSearchText,
              extent: MarketplaceFilterBar.extentFor(context),
            ),
          ),
          SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(inset, 24, inset, 0),
            sliver: SliverToBoxAdapter(
              child: ActiveFilterChips(query: query, onChanged: _applyQuery),
            ),
          ),
          ...listingsValue.when(
            loading: () => [_boxed(inset, const _ResultsSkeleton())],
            error: (error, stack) => [
              _boxed(
                inset,
                MarketplaceEmptyState(
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
            ],
            data: (all) => _resultSlivers(query, all, inset),
          ),
          SliverToBoxAdapter(
            child: MarketplaceFeatureRow(
              eyebrow: copy.forTenants,
              title: copy.lookingForHomeTitle,
              description: copy.lookingForHomeDescription,
              bullets: [
                copy.benefitVerifiedLandlords,
                copy.benefitNoAgentFees,
                copy.benefitBrowseOffline,
              ],
              imageAsset: 'assets/listings/generated-upscale-living-room.png',
              imageFirst: true,
              background: context.nyumba.softIvory,
              action: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.nyumba.sageGreen,
                ),
                onPressed: () => _scrollTo(_resultsKey),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                label: Text(copy.browseAvailableHomes),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: MarketplaceFeatureRow(
              key: _landlordKey,
              eyebrow: copy.forLandlords,
              title: copy.haveRentalSpaceTitle,
              description: copy.haveRentalSpaceDescription,
              bullets: [
                copy.benefitPublishInMinutes,
                copy.benefitRoutedEnquiries,
                copy.benefitOneWorkspace,
              ],
              imageAsset: 'assets/listings/generated-open-plan-kitchen.png',
              imageFirst: false,
              action: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.nyumba.terracottaGold,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.go(navigationAction.path),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                label: Text(
                  session == null
                      ? copy.listYourSpace
                      : context.tr(navigationAction.label),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: MarketplaceFooter(
              onBrowseHomes: () => _scrollTo(_resultsKey),
              onAccount: () => context.go(navigationAction.path),
              accountLabel: context.tr(navigationAction.label),
            ),
          ),
        ],
      ),
    );
  }

  /// One-off box content — a skeleton, an empty state — inset to the same
  /// column as the grid.
  Widget _boxed(double inset, Widget child) => SliverPadding(
    padding: EdgeInsetsDirectional.fromSTEB(
      inset,
      24,
      inset,
      context.isCompact ? 56 : 80,
    ),
    sliver: SliverToBoxAdapter(child: child),
  );

  String _summaryFor(ListingQuery query, List<Listing> all) {
    final copy = appLocalizationsOf(context);
    final matched = query.apply(all).length;
    return query.hasFilters
        ? copy.matchingHomesCount(matched, all.length)
        : copy.availableHomesCount(matched);
  }

  List<Widget> _resultSlivers(
    ListingQuery query,
    List<Listing> all,
    double inset,
  ) {
    final copy = appLocalizationsOf(context);
    if (all.isEmpty) {
      return [
        _boxed(
          inset,
          const MarketplaceEmptyState(
            icon: Icons.home_outlined,
            title: 'No homes are listed right now',
            message:
                'Landlords add new rental spaces regularly — check back soon.',
          ),
        ),
      ];
    }
    final listings = query.apply(all);
    if (listings.isEmpty) {
      return [
        _boxed(
          inset,
          MarketplaceEmptyState(
            icon: Icons.search_off_rounded,
            title: copy.noHomesMatch,
            message: copy.tryBroaderSearch,
            action: OutlinedButton.icon(
              onPressed: () => _applyQuery(query.cleared()),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: Text(copy.clearFilters),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsetsDirectional.fromSTEB(
          inset,
          24,
          inset,
          context.isCompact ? 56 : 80,
        ),
        sliver: _ResultsSliver(
          listings: listings,
          onOpen: (listing) => context.go('/listing/${listing.id}'),
        ),
      ),
    ];
  }
}

int _columnsFor(double width) => width >= 1000
    ? 3
    : width >= 620
    ? 2
    : 1;

/// The results grid, built a row at a time.
///
/// A single [Wrap] would lay out every card on first paint, which starts a
/// photo download for homes the visitor has not scrolled anywhere near. Rows
/// in a [SliverList] keep the same layout and only build what is on screen.
class _ResultsSliver extends StatelessWidget {
  const _ResultsSliver({required this.listings, required this.onOpen});

  final List<Listing> listings;
  final ValueChanged<Listing> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.crossAxisExtent);
        final rows = (listings.length + columns - 1) ~/ columns;
        return SliverList.builder(
          itemCount: rows,
          itemBuilder: (context, row) {
            final first = row * columns;
            final last = (first + columns).clamp(0, listings.length);
            return Padding(
              padding: EdgeInsets.only(
                bottom: row == rows - 1 ? 0 : _resultsGap,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = first; index < last; index++) ...[
                    if (index > first) const SizedBox(width: _resultsGap),
                    Expanded(
                      child: FadeSlideIn(
                        delay: NyumbaMotion.stagger(index - first),
                        child: ListingResultCard(
                          listing: listings[index],
                          onOpen: () => onOpen(listings[index]),
                        ),
                      ),
                    ),
                  ],
                  // Keeps the cards in a part-filled final row the same width
                  // as every row above it.
                  for (var slot = last - first; slot < columns; slot++) ...[
                    const SizedBox(width: _resultsGap),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Grid-shaped stand-in while the catalogue loads, so the results area keeps
/// its final layout instead of collapsing to a spinner and jumping.
class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < columns; index++) ...[
              if (index > 0) const SizedBox(width: _resultsGap),
              const Expanded(child: ListingCardSkeleton()),
            ],
          ],
        );
      },
    );
  }
}
