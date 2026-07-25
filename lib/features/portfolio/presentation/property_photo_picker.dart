import 'dart:typed_data';

import '../../../core/config/market_config.dart';
import '../../../core/presentation/image_picking.dart';

export '../../../core/presentation/image_picking.dart'
    show ImagePickOutcome, PickedImage, supportedPhotoFormats;

const int propertyPhotoLimit = NyumbaMarket.maxPropertyPhotos;
const int propertyPhotoMaxBytes = NyumbaMarket.maxImageSizeBytes;

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
