import 'dart:typed_data';

import '../../../core/presentation/image_picking.dart';

export '../../../core/presentation/image_picking.dart'
    show ImagePickOutcome, PickedImage, supportedPhotoFormats;

const int propertyPhotoLimit = 5;
const int propertyPhotoMaxBytes = 5 * 1024 * 1024;

/// Property photos are ordinary picked images; the alias keeps the portfolio
/// code reading in its own vocabulary.
typedef PickedPropertyPhoto = PickedImage;

Future<ImagePickOutcome> pickPropertyPhotos({required int remainingSlots}) =>
    pickImages(
      remainingSlots: remainingSlots,
      maxBytes: propertyPhotoMaxBytes,
      limit: propertyPhotoLimit,
      subject: 'property',
    );

Uint8List? propertyPhotoBytes(String value) => decodePhotoDataUri(value);
