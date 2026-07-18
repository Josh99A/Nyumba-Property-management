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

class PublicListingsScreen extends ConsumerStatefulWidget {
  const PublicListingsScreen({super.key});

  @override
  ConsumerState<PublicListingsScreen> createState() =>
      _PublicListingsScreenState();
}

class _PublicListingsScreenState extends ConsumerState<PublicListingsScreen> {
  final _searchController = TextEditingController();
  String _priceFilter = 'Any price';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listingsValue = ref.watch(publicListingsProvider);
    // Signed-in actors explore the same public catalogue. Accounts whose role
    // is not resolved yet return to onboarding instead of seeing a sign-in
    // prompt despite already having a session.
    final session = ref.watch(sessionControllerProvider);
    final navigationAction = marketplaceNavigationAction(session);
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
                        child: context.isCompact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _SearchField(
                                    controller: _searchController,
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  const SizedBox(height: 10),
                                  _PriceFilter(
                                    key: ValueKey(_priceFilter),
                                    value: _priceFilter,
                                    onChanged: (value) =>
                                        setState(() => _priceFilter = value),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: _SearchField(
                                      controller: _searchController,
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 190,
                                    child: _PriceFilter(
                                      key: ValueKey(_priceFilter),
                                      value: _priceFilter,
                                      onChanged: (value) =>
                                          setState(() => _priceFilter = value),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
                child: Text.localized('Could not load cached listings: $error'),
              ),
            ),
            data: (allListings) {
              final query = _searchController.text.trim().toLowerCase();
              final listings = allListings.where((listing) {
                final matchesSearch =
                    query.isEmpty ||
                    listing.title.toLowerCase().contains(query) ||
                    listing.description.toLowerCase().contains(query) ||
                    listingLocationFor(listing).toLowerCase().contains(query);
                final rent = listing.monthlyRentMinor ~/ 100;
                final matchesPrice = switch (_priceFilter) {
                  'Under UGX 1M' => rent < 1000000,
                  'UGX 1M–1.4M' => rent >= 1000000 && rent <= 1400000,
                  'Above UGX 1.4M' => rent > 1400000,
                  _ => true,
                };
                return matchesSearch && matchesPrice;
              }).toList();
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
                          Row(
                            children: [
                              Expanded(
                                child: Text.localized(
                                  '${listings.length} available ${listings.length == 1 ? 'home' : 'homes'}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                              ),
                              Text.localized(
                                'Newest first',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          if (listings.isEmpty)
                            NyumbaSurface(
                              child: Padding(
                                padding: const EdgeInsets.all(36),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 44,
                                      color: context.nyumba.mutedInk,
                                    ),
                                    const SizedBox(height: 14),
                                    Text.localized(
                                      'No homes match those filters',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text.localized(
                                      'Try a broader search or a different price range.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 18),
                                    OutlinedButton.icon(
                                      onPressed: () => setState(() {
                                        _searchController.clear();
                                        _priceFilter = 'Any price';
                                      }),
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

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: context.tr('Search by neighborhood or property'),
        prefixIcon: Icon(Icons.search_rounded),
      ),
    );
  }
}

class _PriceFilter extends StatelessWidget {
  const _PriceFilter({required this.value, required this.onChanged, super.key});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(prefixIcon: Icon(Icons.tune_rounded)),
      items: const [
        DropdownMenuItem(
          value: 'Any price',
          child: Text.localized('Any price'),
        ),
        DropdownMenuItem(
          value: 'Under UGX 1M',
          child: Text.localized('Under UGX 1M'),
        ),
        DropdownMenuItem(
          value: 'UGX 1M–1.4M',
          child: Text.localized('UGX 1M–1.4M'),
        ),
        DropdownMenuItem(
          value: 'Above UGX 1.4M',
          child: Text.localized('Above UGX 1.4M'),
        ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
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
