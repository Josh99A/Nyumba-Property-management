import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/config/maps_config.dart';
import '../../../core/domain/coordinates.dart';
import '../../../core/localization/app_localizations_adapter.dart';
import '../../../core/presentation/async_action_button.dart';
import '../domain/listing.dart';
import 'listing_visuals.dart';

/// "Where you will live" — the map teaser and directions hand-off on a public
/// advert.
///
/// Deliberately a **static image plus a link**, not an interactive map. A
/// visitor wants "roughly where is this" and "take me there"; neither needs a
/// pannable map, and an embedded one on the highest-traffic page in the
/// product is the most expensive thing this app could render. The image comes
/// from a first-party path that holds the Static Maps key server-side and
/// caches hard, so all traffic for one advert collapses into roughly one
/// upstream call per day.
class ListingLocationSection extends StatelessWidget {
  const ListingLocationSection({required this.listing, super.key});

  final Listing listing;

  /// The advert's published pin, or null when the landlord never placed one.
  Coordinates? get _pin => Coordinates.tryFrom(
    listing.approximateLatitude,
    listing.approximateLongitude,
  );

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    // No pin means no section at all. An empty grey box would be worse than
    // the location line the page already carries.
    if (pin == null) return const SizedBox.shrink();
    final copy = appLocalizationsOf(context);
    final area = listingLocationFor(listing);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.localized(
          copy.whereYouWillLive,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 2,
            child: _MapImage(listingId: listing.id, area: area),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 17,
              color: context.nyumba.mutedInk,
            ),
            const SizedBox(width: 7),
            Expanded(
              // The area name is landlord-authored, so it crosses as a
              // placeholder rather than being pushed through the catalogue.
              child: Text(
                '${copy.approximateLocationIn(area)} '
                '${copy.exactAddressSharedByLandlord}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.nyumba.mutedInk),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Full width rather than a small icon: on a phone the bottom bar is
        // already the Apply action, so directions needs its own real target
        // instead of competing for the same corner.
        AsyncActionButton.outlined(
          onPressed: () => _openDirections(context, pin),
          icon: const Icon(Icons.directions_outlined),
          child: Text.localized(copy.getDirections),
        ),
      ],
    );
  }

  /// Hands off to whatever maps app the visitor already has.
  ///
  /// Left enabled offline on purpose: the Google Maps app carries its own
  /// offline maps, so refusing the tap would be worse than handing over.
  Future<void> _openDirections(BuildContext context, Coordinates pin) async {
    final opened = await openMapsDirections(pin);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appLocalizationsOf(context).couldNotOpenMapsApp),
        ),
      );
    }
  }
}

class _MapImage extends StatelessWidget {
  const _MapImage({required this.listingId, required this.area});

  final String listingId;
  final String area;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: NyumbaMaps.listingMapUrl(listingId),
      fit: BoxFit.cover,
      // A previously viewed advert keeps its map offline. The image is a pure
      // function of a coarsened coordinate, so a cached copy can never be
      // misleading — only older.
      placeholder: (context, _) => ColoredBox(color: context.nyumba.sageTint),
      errorWidget: (context, _, _) => _MapUnavailable(area: area),
    );
  }
}

/// Shown when the map cannot be fetched — offline, or a deployment whose
/// Static Maps key is not provisioned yet.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.area});

  final String area;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.nyumba.sageTint,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                color: context.nyumba.mutedInk,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text.localized(
                appLocalizationsOf(context).mapUnavailableOffline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
