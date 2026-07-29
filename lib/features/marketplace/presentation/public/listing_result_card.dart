import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:intl/intl.dart';

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/config/market_config.dart';
import '../../../../core/localization/app_localizations_adapter.dart';
import '../../../../core/localization/localized_material.dart';
import '../../../../core/presentation/surface.dart';
import '../../domain/listing.dart';
import '../../../reviews/presentation/review_visuals.dart';
import '../listing_visuals.dart';

/// A single result in the public grid.
///
/// Rent leads the card because it is the first thing a renter filters on;
/// title, location, and the feature row follow so a column of cards can be
/// compared by scanning down one edge.
class ListingResultCard extends StatelessWidget {
  const ListingResultCard({
    required this.listing,
    required this.onOpen,
    super.key,
  });

  final Listing listing;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final palette = context.nyumba;
    final rent = NumberFormat.currency(
      locale: copy.numberLocale,
      name: NyumbaMarket.currencyCode,
      symbol: NyumbaMarket.currencySymbol,
      decimalDigits: 0,
    ).format(listing.monthlyRentMinor ~/ 100);
    final availableFrom = listing.availableFrom;
    final availability = availableFrom == null
        ? copy.listingAvailableNow
        : copy.listingAvailableFromDate(
            DateFormat('d MMM', copy.localeName).format(availableFrom),
          );

    return NyumbaSurface(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardMedia(listing: listing, availability: availability),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.monthlyRentDisplay(rent),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: palette.terracottaDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  listing.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: palette.mutedInk,
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
                    // Denormalized onto the listing itself: a rating lookup per
                    // card would be fifty extra reads on every scroll of the
                    // grid. See ratingBadge in functions/src/shared/ratings.ts.
                    if (listing.ratingCount > 0 ||
                        listing.ratingAverage != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: RatingBadge(
                          average: listing.ratingAverage,
                          count: listing.ratingCount,
                          compact: true,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (listing.bedrooms != null)
                      _ListingFeature(
                        icon: Icons.bed_outlined,
                        label: copy.bedroomsCount(listing.bedrooms!),
                      ),
                    if (listing.bathrooms != null)
                      _ListingFeature(
                        icon: Icons.bathtub_outlined,
                        label: copy.bathroomsCount(listing.bathrooms!),
                      ),
                    if (listing.unitType?.trim().isNotEmpty ?? false)
                      _ListingFeature(
                        icon: Icons.home_work_outlined,
                        label: listingUnitTypeLabel(listing.unitType!),
                      ),
                    if (listing.furnished)
                      const _ListingFeature(
                        icon: Icons.chair_outlined,
                        label: 'Furnished',
                        localize: true,
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

class _CardMedia extends StatelessWidget {
  const _CardMedia({required this.listing, required this.availability});

  final Listing listing;
  final String availability;

  @override
  Widget build(BuildContext context) {
    final photoCount = listing.imageUrls.length;
    return Hero(
      tag: 'listing-image-${listing.id}',
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            fit: StackFit.expand,
            children: [
              listingImage(
                listing,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                cacheWidth: 960,
                preferThumbnail: true,
              ),
              PositionedDirectional(
                top: 12,
                start: 12,
                child: _CardBadge(
                  background: context.nyumba.sageGreen,
                  foreground: Colors.white,
                  child: Text(availability),
                ),
              ),
              if (photoCount > 1)
                PositionedDirectional(
                  top: 12,
                  end: 12,
                  child: Semantics(
                    label: appLocalizationsOf(context).photoCount(photoCount),
                    child: ExcludeSemantics(
                      child: _CardBadge(
                        background: Colors.black54,
                        foreground: Colors.white,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library_outlined,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text('$photoCount'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardBadge extends StatelessWidget {
  const _CardBadge({
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

class _ListingFeature extends StatelessWidget {
  const _ListingFeature({
    required this.icon,
    required this.label,
    this.localize = false,
  });

  final IconData icon;
  final String label;

  /// Application copy goes through the catalogue; landlord-entered values such
  /// as a unit type are shown exactly as they were written.
  final bool localize;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: context.nyumba.sageDark),
        const SizedBox(width: 6),
        if (localize)
          Text.localized(label, style: style)
        else
          Text(label, style: style),
      ],
    );
  }
}

/// Grid-shaped stand-in shown while the catalogue loads, so the results area
/// keeps its final layout instead of collapsing to a spinner and jumping.
class ListingCardSkeleton extends StatelessWidget {
  const ListingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.nyumba;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: palette.neutralTint,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );

    return ExcludeSemantics(
      child: NyumbaSurface(
        padding: EdgeInsets.zero,
        borderRadius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: ColoredBox(color: palette.neutralTint),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  bar(.5, 22),
                  const SizedBox(height: 12),
                  bar(.85, 16),
                  const SizedBox(height: 8),
                  bar(.6, 14),
                  const SizedBox(height: 18),
                  bar(.7, 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
