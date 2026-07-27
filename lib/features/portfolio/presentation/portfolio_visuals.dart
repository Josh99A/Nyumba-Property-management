import 'package:flutter/material.dart';

import '../../../core/media/media_reference.dart';
import '../../../core/presentation/media_placeholder.dart';
import '../../../core/presentation/remote_media_image.dart';
import '../domain/property.dart';
import 'property_photo_picker.dart';

/// Renders a property photo at the size the caller will actually display.
///
/// [cacheWidth] is a decode budget in device pixels, and [preferThumbnail] asks
/// for the server's grid-sized delivery copy where one exists. A card that
/// leaves both at their detail-view defaults downloads and decodes several
/// times the pixels it can show.
Widget propertyImage(
  Property property, {
  int index = 0,
  BoxFit fit = BoxFit.cover,
  FilterQuality filterQuality = FilterQuality.medium,
  int cacheWidth = 1600,
  bool preferThumbnail = false,
}) {
  final reference = index >= 0 && index < property.imageUrls.length
      ? property.imageUrls[index]
      : null;
  if (reference == null) return const MediaPlaceholder.unavailable();

  final localBytes = propertyPhotoBytes(reference);
  if (localBytes != null) {
    return Image.memory(
      localBytes,
      fit: fit,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      semanticLabel: property.name,
      errorBuilder: (_, _, _) => const MediaPlaceholder.unavailable(),
    );
  }

  final uri = Uri.tryParse(reference);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    return networkMediaImage(
      url: reference,
      semanticLabel: property.name,
      fit: fit,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
    );
  }

  if (isStorageReference(reference)) {
    return RemoteMediaImage(
      reference: mediaReferenceFor(reference, preferThumbnail: preferThumbnail),
      semanticLabel: property.name,
      fit: fit,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
    );
  }
  return const MediaPlaceholder.unavailable();
}
