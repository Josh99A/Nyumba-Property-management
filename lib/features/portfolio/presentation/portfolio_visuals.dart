import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
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
  int cacheWidth = 1600,
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
      cacheWidth: cacheWidth,
      semanticLabel: property.name,
      errorBuilder: (_, _, _) => _fallback(property, fit, filterQuality),
    );
  }
  final uri = reference == null ? null : Uri.tryParse(reference);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    return Image.network(
      reference!,
      fit: fit,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      semanticLabel: property.name,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : _loadingPlaceholder(property, fit, filterQuality, progress),
      errorBuilder: (_, _, _) => _fallback(property, fit, filterQuality),
    );
  }
  if (reference != null && _isStorageReference(reference)) {
    return _StoragePropertyImage(
      property: property,
      reference: reference,
      fit: fit,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
    );
  }
  return _fallback(property, fit, filterQuality);
}

bool _isStorageReference(String reference) =>
    reference.startsWith('uploads/') ||
    reference.startsWith('private/landlords/') ||
    reference.startsWith('gs://');

class _StoragePropertyImage extends ConsumerWidget {
  const _StoragePropertyImage({
    required this.property,
    required this.reference,
    required this.fit,
    required this.filterQuality,
    required this.cacheWidth,
  });

  final Property property;
  final String reference;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final int cacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(propertyMediaBytesProvider(reference));
    return bytes.when(
      data: (value) => value == null
          ? _fallback(property, fit, filterQuality)
          : Image.memory(
              value,
              fit: fit,
              filterQuality: filterQuality,
              cacheWidth: cacheWidth,
              semanticLabel: property.name,
              errorBuilder: (_, _, _) =>
                  _fallback(property, fit, filterQuality),
            ),
      error: (_, _) => _fallback(property, fit, filterQuality),
      loading: () => _loadingPlaceholder(property, fit, filterQuality, null),
    );
  }
}

Widget _loadingPlaceholder(
  Property property,
  BoxFit fit,
  FilterQuality filterQuality,
  ImageChunkEvent? progress,
) => Stack(
  fit: StackFit.expand,
  children: [
    ExcludeSemantics(child: _fallback(property, fit, filterQuality)),
    Align(
      alignment: Alignment.bottomCenter,
      child: LinearProgressIndicator(
        minHeight: 3,
        value: progress?.expectedTotalBytes == null
            ? null
            : progress!.cumulativeBytesLoaded / progress.expectedTotalBytes!,
        backgroundColor: Colors.transparent,
      ),
    ),
  ],
);

Widget _fallback(Property property, BoxFit fit, FilterQuality filterQuality) =>
    Image.asset(
      propertyAssetForName(property.name),
      fit: fit,
      filterQuality: filterQuality,
    );
