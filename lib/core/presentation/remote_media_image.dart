import 'dart:developer' as developer;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap/app_dependencies.dart';
import '../media/media_reference.dart';
import 'media_placeholder.dart';

/// One storage-backed photo, fetched by URL and cached by the platform.
///
/// Resolving the reference to a URL and fetching it are deliberately separate
/// steps: the URL resolution is memoised per reference, while the bytes behind
/// it are cached by [CachedNetworkImage] in memory and, on mobile, on disk
/// across app launches. Loading bytes through the Storage SDK — as this used to
/// — sat outside both caches, so every cold start paid for the whole gallery
/// again.
class RemoteMediaImage extends ConsumerWidget {
  const RemoteMediaImage({
    required this.reference,
    required this.semanticLabel,
    required this.fit,
    required this.filterQuality,
    required this.cacheWidth,
    super.key,
  });

  final String reference;
  final String semanticLabel;
  final BoxFit fit;
  final FilterQuality filterQuality;

  /// Decode width in device pixels.
  ///
  /// Flutter's image cache is bounded in *decoded* bytes, so this is what
  /// decides how many photos fit in it. A grid tile decoded at detail-view
  /// resolution costs roughly nine times its own area and evicts its
  /// neighbours, which is what made scrolling re-decode continuously.
  final int cacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(propertyMediaUrlProvider(reference));
    return url.when(
      data: (value) {
        if (value == null) {
          // Not an error as far as the provider is concerned, but from here it
          // is indistinguishable from one: the caller asked for a photo and is
          // getting a grey box. Named so the two causes can be told apart in a
          // log — a null URL means no resolver (Firebase absent, or
          // dependencies still failing), not a rejected fetch.
          _logMediaFailure(reference, 'no download URL resolved', null);
          return const MediaPlaceholder.unavailable();
        }
        return networkMediaImage(
          url: value,
          semanticLabel: semanticLabel,
          fit: fit,
          filterQuality: filterQuality,
          cacheWidth: cacheWidth,
        );
      },
      // Storage refusing or failing to mint a URL used to render a placeholder
      // and say nothing anywhere, which makes "images are blank" impossible to
      // diagnose from a running app: an unauthorized read, a missing object,
      // and an offline device all look identical on screen.
      error: (error, stackTrace) {
        _logMediaFailure(reference, 'download URL lookup failed', error);
        return const MediaPlaceholder.unavailable();
      },
      loading: () => const MediaPlaceholder.loading(),
    );
  }
}

void _logMediaFailure(String reference, String reason, Object? error) {
  developer.log(
    '$reason for "$reference"',
    name: 'remote_media_image',
    error: error,
  );
}

/// A cached network image wearing the app's neutral loading and error states.
Widget networkMediaImage({
  required String url,
  required String semanticLabel,
  required BoxFit fit,
  required FilterQuality filterQuality,
  required int cacheWidth,
}) => CachedNetworkImage(
  imageUrl: url,
  fit: fit,
  filterQuality: filterQuality,
  memCacheWidth: cacheWidth,
  maxWidthDiskCache: cacheWidth,
  fadeInDuration: const Duration(milliseconds: 180),
  imageBuilder: (context, provider) => Image(
    image: provider,
    fit: fit,
    filterQuality: filterQuality,
    semanticLabel: semanticLabel,
    errorBuilder: (_, _, _) => const MediaPlaceholder.unavailable(),
  ),
  // `progress` is null until the response declares a content length. Showing an
  // empty determinate bar rather than an indeterminate one keeps this honest
  // (nothing has arrived yet) and, unlike an indeterminate indicator, does not
  // schedule a frame forever — which would leave the widget tree permanently
  // unsettled for anything rendering an image.
  progressIndicatorBuilder: (context, _, progress) =>
      MediaPlaceholder.loading(progress: progress.progress ?? 0),
  // The URL resolved but its bytes did not arrive: a 403/404 on the object, or
  // — on web specifically — a cross-origin fetch the bucket never allowed.
  // Distinct from the resolution failure above and worth telling apart.
  errorWidget: (_, failedUrl, error) {
    _logMediaFailure(failedUrl, 'image fetch failed', error);
    return const MediaPlaceholder.unavailable();
  },
);

/// Whether [reference] is something [RemoteMediaImage] can fetch.
bool isRemoteMediaReference(String reference) {
  final uri = Uri.tryParse(reference);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    return true;
  }
  return isStorageReference(reference);
}
