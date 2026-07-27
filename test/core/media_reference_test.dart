import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/media/media_reference.dart';

void main() {
  // The exact object name the backend writes. If `deliveryObjectPath` in
  // firebase/functions/src/workers/media-publication.ts ever changes shape,
  // this is the assertion that should fail first — silently losing the match
  // would only show up as every grid quietly serving full-size photos again.
  const full = 'public/listings/listing_1/0-abcdef0123456789-full.webp';
  const thumb = 'public/listings/listing_1/0-abcdef0123456789-thumb.webp';

  group('delivery variants', () {
    test('a full delivery copy maps to its thumbnail sibling', () {
      expect(isDeliveryReference(full), isTrue);
      expect(thumbnailReferenceFor(full), thumb);
    });

    test('a thumbnail maps to itself', () {
      expect(thumbnailReferenceFor(thumb), thumb);
    });

    test('a grid prefers the thumbnail, a detail view keeps the full copy', () {
      expect(mediaReferenceFor(full, preferThumbnail: true), thumb);
      expect(mediaReferenceFor(full, preferThumbnail: false), full);
    });

    test('references the pipeline never produced fall back to themselves', () {
      for (final reference in const <String>[
        'uploads/landlord/command/property-0.jpg',
        'public/listings/listing_1/0.webp',
        'data:image/jpeg;base64,AA==',
        'https://cdn.example.test/photo.webp',
        'private/landlords/l1/documents/lease.pdf',
        // A digest of the wrong length is not the contract's shape.
        'public/listings/listing_1/0-abcdef-full.webp',
      ]) {
        expect(
          thumbnailReferenceFor(reference),
          isNull,
          reason: '$reference is not a delivery object',
        );
        expect(mediaReferenceFor(reference, preferThumbnail: true), reference);
      }
    });
  });

  group('addressing', () {
    test('storage references are told apart from URLs and staged data', () {
      expect(isStorageReference(full), isTrue);
      expect(isStorageReference('uploads/l/c/p.jpg'), isTrue);
      expect(isStorageReference('private/landlords/l/p.webp'), isTrue);
      expect(isStorageReference('gs://bucket/object.webp'), isTrue);
      expect(isStorageReference('https://example.test/p.webp'), isFalse);
      expect(isStorageReference('data:image/jpeg;base64,AA=='), isFalse);
    });
  });
}
