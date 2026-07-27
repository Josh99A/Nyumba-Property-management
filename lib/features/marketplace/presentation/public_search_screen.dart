import 'dart:async';

import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nyumba_property_management/core/localization/app_localizations_adapter.dart';
import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/responsive.dart';
import '../../auth/application/session_controller.dart';
import '../domain/listing.dart';
import 'marketplace_navigation.dart';
import 'public/listing_query.dart';
import 'public/listing_results.dart';
import 'public/marketplace_filters.dart';
import 'public/marketplace_sections.dart';
import 'public/marketplace_top_bar.dart';

/// How long the search waits after the last keystroke before re-filtering.
const _searchSettleDelay = Duration(milliseconds: 250);

/// The dedicated browse surface: everything a renter needs to narrow a
/// catalogue down to the handful of homes worth opening.
///
/// Split out from the landing page because the two have opposite jobs. The
/// landing page argues that Nyumba is worth using and shows a sample; this one
/// assumes that argument is won and gets out of the way — filters first,
/// results high on the page, and no marketing between them.
class PublicSearchScreen extends ConsumerStatefulWidget {
  const PublicSearchScreen({required this.initialQuery, super.key});

  /// Parsed from the URL, so a search can be linked to, reloaded, and reached
  /// with the browser's back button.
  final ListingQuery initialQuery;

  @override
  ConsumerState<PublicSearchScreen> createState() => _PublicSearchScreenState();
}

class _PublicSearchScreenState extends ConsumerState<PublicSearchScreen> {
  final _scrollController = ScrollController();
  late ListingQuery _query = widget.initialQuery;
  late String _searchText = widget.initialQuery.text;
  Timer? _searchSettle;

  @override
  void dispose() {
    _searchSettle?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Mirrors the query into the address bar.
  ///
  /// `replace` rather than `go`: filtering is one continuous act of narrowing,
  /// and pushing a history entry per keystroke would turn the back button into
  /// an undo log nobody asked for. Back should leave the search, not rewind it
  /// one character.
  void _syncUrl(ListingQuery query) {
    final parameters = query.toQueryParameters();
    final uri = Uri(
      path: '/search',
      queryParameters: parameters.isEmpty ? null : parameters,
    );
    context.replace(uri.toString());
  }

  void _applyQuery(ListingQuery query) {
    _searchSettle?.cancel();
    setState(() {
      _query = query;
      _searchText = query.text;
    });
    _syncUrl(query);
  }

  void _changeSearchText(String text) {
    setState(() => _searchText = text);
    _searchSettle?.cancel();
    _searchSettle = Timer(_searchSettleDelay, () {
      if (!mounted) return;
      final next = _query.copyWith(text: text);
      setState(() => _query = next);
      _syncUrl(next);
    });
  }

  void _submitSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    _applyQuery(_query.copyWith(text: _searchText));
  }

  @override
  Widget build(BuildContext context) {
    final listingsValue = ref.watch(publicListingsProvider);
    final session = ref.watch(sessionControllerProvider);
    final navigationAction = marketplaceNavigationAction(session);
    final copy = appLocalizationsOf(context);
    final allListings = listingsValue.value ?? const <Listing>[];
    final unitTypes = ListingQuery.unitTypesIn(allListings);
    final query = _query.withinTypes(unitTypes.toSet());
    final inset = marketplaceBandInset(context);

    return Scaffold(
      backgroundColor: context.nyumba.surface,
      appBar: MarketplaceTopBar(
        signedIn: session != null,
        accountLabel: navigationAction.label,
        onAccount: () => context.go(navigationAction.path),
        onBrowseHomes: () => _scrollController.hasClients
            ? _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
              )
            : null,
        onForLandlords: () => context.go('/explore'),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: _SearchHeader(
              resultSummary: listingsValue.hasValue
                  ? _summaryFor(query, allListings)
                  : null,
              onBack: () => context.go('/explore'),
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
              onSearchSubmitted: _submitSearch,
              extent: MarketplaceFilterBar.extentFor(context),
            ),
          ),
          SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(inset, 20, inset, 0),
            sliver: SliverToBoxAdapter(
              child: ActiveFilterChips(query: query, onChanged: _applyQuery),
            ),
          ),
          ...listingsValue.when(
            loading: () => [
              _boxed(inset, const ListingResultsSkeleton(rows: 2)),
            ],
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
            child: MarketplaceFooter(
              onBrowseHomes: () => context.go('/explore'),
              onAccount: () => context.go(navigationAction.path),
              accountLabel: context.tr(navigationAction.label),
            ),
          ),
        ],
      ),
    );
  }

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
        sliver: ListingResultsSliver(
          listings: listings,
          onOpen: (listing) => context.go('/listing/${listing.id}'),
        ),
      ),
    ];
  }
}

/// A short navy band above the filter bar: where you are, how to get back, and
/// how many homes the current filters leave.
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.resultSummary, required this.onBack});

  final String? resultSummary;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final compact = context.isCompact;
    return MarketplaceBand(
      gradient: heroGradient,
      padding: EdgeInsets.only(
        top: compact ? 20 : 28,
        bottom: compact ? 22 : 30,
      ),
      child: OnHeroSurface(
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onBack,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 36),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(copy.backToHome),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                copy.searchHomesTitle,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontSize: compact ? 28 : 36,
                  height: 1.1,
                ),
              ),
              if (resultSummary != null) ...[
                const SizedBox(height: 8),
                Text(
                  resultSummary!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: NyumbaColors.navyOnDark,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
