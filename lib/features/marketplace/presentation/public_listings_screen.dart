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
import 'public/listing_results.dart';
import 'public/marketplace_filters.dart';
import 'public/marketplace_sections.dart';
import 'public/marketplace_top_bar.dart';

/// Homes shown on the landing page before the visitor is sent to the full
/// catalogue.
///
/// Six fills two rows at the widest layout and one on a phone. The number is
/// deliberately small: this section exists to show that real homes are here,
/// not to be browsed — browsing has its own screen, which does it properly.
const _featuredCount = 6;

/// The public landing page.
///
/// Its job is to answer "is there anything here for me, and can I trust it"
/// and then hand off. Every search affordance on this page — the hero pill,
/// the location shortcuts, the featured strip's CTA — routes to
/// [PublicSearchScreen] rather than filtering in place, so there is exactly
/// one surface that owns browsing.
class PublicListingsScreen extends ConsumerStatefulWidget {
  const PublicListingsScreen({super.key});

  @override
  ConsumerState<PublicListingsScreen> createState() =>
      _PublicListingsScreenState();
}

class _PublicListingsScreenState extends ConsumerState<PublicListingsScreen> {
  final _scrollController = ScrollController();
  final _featuredKey = GlobalKey();
  final _landlordKey = GlobalKey();

  /// Only ever the hero's text. The landing page holds no filters — they
  /// belong to the search screen, which owns them in its URL.
  String _searchText = '';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  void _openSearch([String? text]) {
    FocusManager.instance.primaryFocus?.unfocus();
    final query = ListingQuery(text: text ?? _searchText);
    final parameters = query.toQueryParameters();
    final uri = Uri(
      path: '/search',
      queryParameters: parameters.isEmpty ? null : parameters,
    );
    context.go(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final listingsValue = ref.watch(publicListingsProvider);
    final session = ref.watch(sessionControllerProvider);
    final navigationAction = marketplaceNavigationAction(session);
    final copy = appLocalizationsOf(context);
    final allListings = listingsValue.value ?? const <Listing>[];
    final featured = const ListingQuery()
        .apply(allListings)
        .take(_featuredCount)
        .toList();

    return Scaffold(
      backgroundColor: context.nyumba.surface,
      appBar: MarketplaceTopBar(
        signedIn: session != null,
        accountLabel: navigationAction.label,
        onAccount: () => context.go(navigationAction.path),
        onBrowseHomes: _openSearch,
        onForLandlords: () => _scrollTo(_landlordKey),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: MarketplaceHero(
              searchBar: HeroSearchBar(
                value: _searchText,
                onChanged: (text) => setState(() => _searchText = text),
                onSearch: _openSearch,
              ),
              assurances: [
                if (listingsValue.hasValue)
                  copy.availableHomesCount(allListings.length),
              ],
              quickLocations: ListingQuery.popularLocationsIn(allListings),
              onLocationSelected: (location) => _openSearch(location),
            ),
          ),
          const SliverToBoxAdapter(child: MarketplaceAssuranceBand()),
          SliverToBoxAdapter(
            child: MarketplaceBand(
              key: _featuredKey,
              padding: EdgeInsets.only(
                top: context.isCompact ? 48 : 72,
                bottom: context.isCompact ? 52 : 76,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MarketplaceFeaturedHeader(
                    resultSummary: listingsValue.hasValue
                        ? copy.availableHomesCount(allListings.length)
                        : null,
                    onBrowseAll: _openSearch,
                  ),
                  const SizedBox(height: 28),
                  listingsValue.when(
                    loading: () => const ListingResultsSkeleton(),
                    error: (error, stack) => MarketplaceEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: copy.publicListingsLoadErrorTitle,
                      message: copy.publicListingsLoadErrorMessage,
                      action: FilledButton.icon(
                        onPressed: () => ref.invalidate(publicListingsProvider),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(copy.retry),
                      ),
                    ),
                    data: (_) => featured.isEmpty
                        ? const MarketplaceEmptyState(
                            icon: Icons.home_outlined,
                            title: 'No homes are listed right now',
                            message:
                                'Landlords add new rental spaces regularly — '
                                'check back soon.',
                          )
                        : ListingResultsGrid(
                            listings: featured,
                            onOpen: (listing) =>
                                context.go('/listing/${listing.id}'),
                          ),
                  ),
                  if (featured.length >= _featuredCount) ...[
                    const SizedBox(height: 28),
                    Align(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: context.nyumba.sageGreen,
                        ),
                        onPressed: _openSearch,
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                        label: Text(copy.browseAllHomes),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: MarketplaceFeatureRow(
              eyebrow: copy.forTenants,
              title: copy.lookingForHomeTitle,
              description: copy.lookingForHomeDescription,
              bullets: [
                copy.benefitVerifiedLandlords,
                copy.benefitNoAgentFees,
                copy.benefitRealTenantReviews,
              ],
              imageAsset: 'assets/listings/generated-upscale-living-room.png',
              imageFirst: true,
              background: context.nyumba.softIvory,
              action: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.nyumba.sageGreen,
                ),
                onPressed: _openSearch,
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
              onBrowseHomes: _openSearch,
              onAccount: () => context.go(navigationAction.path),
              accountLabel: context.tr(navigationAction.label),
            ),
          ),
        ],
      ),
    );
  }
}
