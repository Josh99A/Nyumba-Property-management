import 'package:flutter/material.dart';

import '../domain/listing.dart';

String listingAssetFor(Listing listing) {
  final title = listing.title.toLowerCase();
  if (title.contains('sunset')) {
    return 'assets/listings/sunset-apartments.png';
  }
  if (title.contains('riverside')) {
    return 'assets/listings/riverside-heights.png';
  }
  if (title.contains('nyumbani')) {
    return 'assets/listings/nyumbani-gardens.png';
  }
  return 'assets/listings/kilimani-garden-court.png';
}

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

Widget listingImage(
  Listing listing, {
  BoxFit fit = BoxFit.cover,
  FilterQuality filterQuality = FilterQuality.medium,
}) {
  final firstImage = listing.imageUrls.isEmpty ? null : listing.imageUrls.first;
  final uri = firstImage == null ? null : Uri.tryParse(firstImage);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    return Image.network(
      firstImage!,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: (context, error, stackTrace) => Image.asset(
        listingAssetFor(listing),
        fit: fit,
        filterQuality: filterQuality,
      ),
    );
  }
  return Image.asset(
    listingAssetFor(listing),
    fit: fit,
    filterQuality: filterQuality,
  );
}
