import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/surface.dart';
import '../domain/listing.dart';
import 'listing_visuals.dart';

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
    return Scaffold(
      backgroundColor: NyumbaColors.softIvory,
      appBar: AppBar(
        toolbarHeight: 72,
        backgroundColor: NyumbaColors.surface,
        titleSpacing: context.isCompact ? 16 : 32,
        title: const NyumbaLogo(height: 42),
        actions: [
          if (!context.isCompact)
            TextButton(onPressed: () {}, child: const Text('Available homes')),
          const SizedBox(width: 8),
          Padding(
            padding: EdgeInsets.only(right: context.isCompact ? 12 : 30),
            child: OutlinedButton(
              onPressed: () => context.go('/sign-in'),
              child: const Text('Sign in'),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: NyumbaColors.midnightNavy,
              padding: EdgeInsets.fromLTRB(
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
                      Text(
                        'Find a place that feels like home.',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: Colors.white,
                              fontSize: context.isCompact ? 36 : 52,
                            ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Browse verified available units and contact landlords directly.',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFFDCE7F4),
                              fontWeight: FontWeight.w400,
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
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    24,
                    context.pageGutter,
                    8,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: NyumbaColors.sageTint,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCDE4D2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.offline_pin_outlined,
                            size: 19,
                            color: NyumbaColors.sageDark,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'These listings are cached for offline browsing · Updated just now',
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
                child: Text('Could not load cached listings: $error'),
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
                  'Under KES 25k' => rent < 25000,
                  'KES 25k–45k' => rent >= 25000 && rent <= 45000,
                  'Above KES 45k' => rent > 45000,
                  _ => true,
                };
                return matchesSearch && matchesPrice;
              }).toList();
              return SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
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
                                child: Text(
                                  '${listings.length} available ${listings.length == 1 ? 'home' : 'homes'}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                              ),
                              Text(
                                'Newest first',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          if (listings.isEmpty)
                            const NyumbaSurface(
                              child: Padding(
                                padding: EdgeInsets.all(28),
                                child: Center(
                                  child: Text(
                                    'No homes match those filters. Try a broader search.',
                                  ),
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
                                    for (final listing in listings)
                                      SizedBox(
                                        width: width,
                                        child: _ListingCard(listing: listing),
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
      decoration: const InputDecoration(
        hintText: 'Search by neighborhood or property',
        prefixIcon: Icon(Icons.search_rounded),
      ),
    );
  }
}

class _PriceFilter extends StatelessWidget {
  const _PriceFilter({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(prefixIcon: Icon(Icons.tune_rounded)),
      items: const [
        DropdownMenuItem(value: 'Any price', child: Text('Any price')),
        DropdownMenuItem(value: 'Under KES 25k', child: Text('Under KES 25k')),
        DropdownMenuItem(value: 'KES 25k–45k', child: Text('KES 25k–45k')),
        DropdownMenuItem(value: 'Above KES 45k', child: Text('Above KES 45k')),
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
      locale: 'en_KE',
      symbol: 'KES ',
      decimalDigits: 0,
    );
    return NyumbaSurface(
      padding: EdgeInsets.zero,
      onTap: () => context.go('/listing/${listing.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: Image.asset(
                listingAssetFor(listing),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
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
                    const Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: NyumbaColors.mutedInk,
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        currency.format(listing.monthlyRentMinor / 100),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: NyumbaColors.midnightNavy,
                        ),
                      ),
                    ),
                    Text(
                      '/ month',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    _Feature(icon: Icons.bed_outlined, label: '2 beds'),
                    SizedBox(width: 16),
                    _Feature(icon: Icons.bathtub_outlined, label: '2 baths'),
                    Spacer(),
                    Icon(Icons.arrow_forward_rounded, size: 19),
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

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: NyumbaColors.mutedInk),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
