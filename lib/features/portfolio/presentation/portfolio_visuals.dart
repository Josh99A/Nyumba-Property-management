import 'package:flutter/material.dart';

import '../domain/property.dart';
import 'property_photo_picker.dart';

String propertyAssetForName(String name) {
  final normalized = name.toLowerCase();
  if (normalized.contains('sunset')) {
    return 'assets/listings/sunset-apartments.png';
  }
  if (normalized.contains('riverside')) {
    return 'assets/listings/riverside-heights.png';
  }
  if (normalized.contains('nyumbani')) {
    return 'assets/listings/nyumbani-gardens.png';
  }
  return 'assets/listings/kilimani-garden-court.png';
}

Widget propertyImage(
  Property property, {
  int index = 0,
  BoxFit fit = BoxFit.cover,
  FilterQuality filterQuality = FilterQuality.medium,
}) {
  final reference = index >= 0 && index < property.imageUrls.length
      ? property.imageUrls[index]
      : null;
  final localBytes = reference == null ? null : propertyPhotoBytes(reference);
  if (localBytes != null) {
    return Image.memory(
      localBytes,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: (_, _, _) => _fallback(property, fit, filterQuality),
    );
  }
  final uri = reference == null ? null : Uri.tryParse(reference);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    return Image.network(
      reference!,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: (_, _, _) => _fallback(property, fit, filterQuality),
    );
  }
  return _fallback(property, fit, filterQuality);
}

Widget _fallback(Property property, BoxFit fit, FilterQuality filterQuality) =>
    Image.asset(
      propertyAssetForName(property.name),
      fit: fit,
      filterQuality: filterQuality,
    );
