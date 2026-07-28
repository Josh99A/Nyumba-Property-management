import 'package:flutter/material.dart';

import '../../../core/localization/nyumba_localizations.dart';
import '../../../core/media/media_reference.dart';
import '../../../core/presentation/media_placeholder.dart';
import '../../../core/presentation/remote_media_image.dart';
import '../domain/listing.dart';
import 'listing_photo_picker.dart';

String listingLocationFor(Listing listing) {
  final parts = <String>[
    if (listing.neighborhood?.trim().isNotEmpty ?? false)
      listing.neighborhood!.trim(),
    if ((listing.district?.trim().isNotEmpty ?? false) &&
        listing.district!.trim() != listing.neighborhood?.trim())
      listing.district!.trim(),
    if (listing.city.trim().isNotEmpty &&
        listing.city.trim() != listing.district?.trim())
      listing.city.trim(),
  ];
  return parts.isEmpty ? 'Location available on request' : parts.join(', ');
}

/// Reader-facing label for a stored unit type token, which reaches the public
/// screens either as a camelCase enum name (`selfContained`) or as free text a
/// landlord typed.
String listingUnitTypeLabel(String unitType) {
  final spaced = unitType.trim().replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? unitType
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

/// Renders a listing photo at the size the caller will actually display.
///
/// [cacheWidth] is a decode budget in device pixels, and [preferThumbnail] asks
/// for the server's grid-sized delivery copy where one exists. A card that
/// leaves both at their detail-view defaults downloads and decodes several
/// times the pixels it can show.
Widget listingImage(
  Listing listing, {
  int index = 0,
  BoxFit fit = BoxFit.cover,
  FilterQuality filterQuality = FilterQuality.medium,
  int cacheWidth = 1600,
  bool preferThumbnail = false,
}) {
  // An advert with no photos is empty, not broken. Only a reference that exists
  // and then fails to resolve earns the "unavailable" treatment.
  if (!listing.hasPhotos) return const MediaPlaceholder.none();

  final reference = index >= 0 && index < listing.imageUrls.length
      ? listing.imageUrls[index]
      : null;
  if (reference == null) return const MediaPlaceholder.unavailable();

  final localBytes = listingPhotoBytes(reference);
  if (localBytes != null) {
    return Image.memory(
      localBytes,
      fit: fit,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      semanticLabel: listing.title,
      errorBuilder: (_, _, _) => const MediaPlaceholder.unavailable(),
    );
  }

  final uri = Uri.tryParse(reference);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    return networkMediaImage(
      url: reference,
      semanticLabel: listing.title,
      fit: fit,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
    );
  }

  if (isStorageReference(reference)) {
    return RemoteMediaImage(
      reference: mediaReferenceFor(reference, preferThumbnail: preferThumbnail),
      semanticLabel: listing.title,
      fit: fit,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
    );
  }
  return const MediaPlaceholder.unavailable();
}

/// Responsive listing gallery used by the public advert detail experience.
///
/// The first landlord-selected photo remains the cover image. Additional
/// photos are swipeable, directly selectable, and keyboard reachable through
/// the standard Material buttons.
class ListingPhotoCarousel extends StatefulWidget {
  const ListingPhotoCarousel({
    required this.listing,
    required this.aspectRatio,
    super.key,
  });

  final Listing listing;
  final double aspectRatio;

  @override
  State<ListingPhotoCarousel> createState() => _ListingPhotoCarouselState();
}

class _ListingPhotoCarouselState extends State<ListingPhotoCarousel> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  int get _imageCount =>
      widget.listing.imageUrls.isEmpty ? 1 : widget.listing.imageUrls.length;

  @override
  void didUpdateWidget(covariant ListingPhotoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listing.id != widget.listing.id ||
        _currentIndex >= _imageCount) {
      _currentIndex = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: _imageCount,
              allowImplicitScrolling: true,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) => Semantics(
                image: true,
                label: context.tr('Photo ${index + 1} of $_imageCount'),
                child: ExcludeSemantics(
                  child: KeyedSubtree(
                    key: ValueKey('listing-photo-${widget.listing.id}-$index'),
                    child: listingImage(
                      widget.listing,
                      index: widget.listing.imageUrls.isEmpty ? -1 : index,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      cacheWidth: 1920,
                    ),
                  ),
                ),
              ),
            ),
            if (_imageCount > 1) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _CarouselButton(
                  tooltip: context.tr('Previous photo'),
                  icon: isRtl
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                  onPressed: () =>
                      _goTo((_currentIndex - 1 + _imageCount) % _imageCount),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _CarouselButton(
                  tooltip: context.tr('Next photo'),
                  icon: isRtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  onPressed: () => _goTo((_currentIndex + 1) % _imageCount),
                ),
              ),
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: 28,
                      bottom: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var index = 0; index < _imageCount; index++)
                          Semantics(
                            button: true,
                            selected: index == _currentIndex,
                            label: context.tr(
                              'Photo ${index + 1} of $_imageCount',
                            ),
                            child: InkResponse(
                              key: ValueKey('listing-photo-indicator-$index'),
                              onTap: () => _goTo(index),
                              radius: 18,
                              child: SizedBox.square(
                                dimension: 30,
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOut,
                                    width: index == _currentIndex ? 20 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: index == _currentIndex
                                          ? Colors.white
                                          : Colors.white70,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                end: 12,
                top: 12,
                child: Container(
                  key: const ValueKey('listing-photo-counter'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${_currentIndex + 1}/$_imageCount',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _goTo(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

class _CarouselButton extends StatelessWidget {
  const _CarouselButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: IconButton.filled(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black54,
          foregroundColor: Colors.white,
          minimumSize: const Size.square(48),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
