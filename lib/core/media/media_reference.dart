/// Naming and addressing rules for server-rendered delivery media.
///
/// The backend writes two copies of every published photo — a grid-sized
/// thumbnail and a detail-sized full copy — under a content-addressed name.
/// This file is the client half of that contract; the server half is
/// `deliveryObjectPath` in
/// `firebase/functions/src/workers/media-publication.ts`. The two must agree,
/// so both sides carry a test pinning the exact shape.
library;

/// Suffix of the grid-sized delivery copy.
const String mediaThumbSuffix = 'thumb';

/// Suffix of the detail-sized delivery copy.
const String mediaFullSuffix = 'full';

/// Width of the detail-sized delivery copy, in device pixels.
///
/// Mirrors `MAX_PUBLIC_LISTING_IMAGE_WIDTH` in
/// `firebase/functions/src/shared/config.ts`. A decode budget above this only
/// upsamples, so it is the ceiling every caller sizing itself from layout
/// clamps to.
const int mediaFullImageWidth = 1920;

/// `{index}-{16 hex digest}-{variant}.webp`, anchored at the end of the path.
final RegExp _deliveryObject = RegExp(
  r'^(?<prefix>.*/)(?<index>\d+)-(?<digest>[0-9a-f]{16})-'
  r'(?<variant>thumb|full)\.webp$',
);

/// Whether [reference] names a server-rendered delivery object.
bool isDeliveryReference(String reference) =>
    _deliveryObject.hasMatch(reference);

/// The thumbnail sibling of [reference], or null when there is not one.
///
/// Returns null for anything the delivery pipeline did not produce: a staged
/// `uploads/…` original, a `data:` URI still waiting to sync, an external URL,
/// or a legacy object published before variants existed. Callers fall back to
/// the reference they already had, which is exactly the behaviour those records
/// had before thumbnails existed.
String? thumbnailReferenceFor(String reference) {
  final match = _deliveryObject.firstMatch(reference);
  if (match == null) return null;
  if (match.namedGroup('variant') == mediaThumbSuffix) return reference;
  return '${match.namedGroup('prefix')}${match.namedGroup('index')}-'
      '${match.namedGroup('digest')}-$mediaThumbSuffix.webp';
}

/// The reference to actually fetch for a given display size.
///
/// [preferThumbnail] is the caller stating that it is rendering a grid tile or
/// similar small surface. A detail view passes false and keeps the full copy.
String mediaReferenceFor(String reference, {required bool preferThumbnail}) {
  if (!preferThumbnail) return reference;
  return thumbnailReferenceFor(reference) ?? reference;
}

/// Whether [reference] points at a storage object rather than a URL or a
/// locally staged `data:` URI.
bool isStorageReference(String reference) =>
    reference.startsWith('uploads/') ||
    reference.startsWith('public/') ||
    reference.startsWith('private/') ||
    reference.startsWith('gs://');
