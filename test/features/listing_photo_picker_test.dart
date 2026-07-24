import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/listing_photo_picker.dart';

void main() {
  test('listing uploads allow five images of at most 5 MB each', () {
    expect(listingPhotoLimit, 5);
    expect(listingPhotoMaxBytes, 5 * 1024 * 1024);
  });

  test('picked listing photos round-trip through durable data references', () {
    final original = Uint8List.fromList(<int>[0, 1, 2, 3, 254, 255]);
    final photo = PickedListingPhoto(
      name: 'home.png',
      mimeType: 'image/png',
      bytes: original,
    );

    expect(listingPhotoBytes(photo.dataUri), orderedEquals(original));
  });

  test('non-image and malformed references are rejected', () {
    expect(listingPhotoBytes('https://example.com/home.png'), isNull);
    expect(listingPhotoBytes('data:image/png;base64,not-base64'), isNull);
  });
}
