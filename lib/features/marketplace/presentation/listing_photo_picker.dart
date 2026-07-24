import 'dart:typed_data';

import '../../../core/config/market_config.dart';
import '../../../core/presentation/image_picking.dart';

export '../../../core/presentation/image_picking.dart'
    show ImagePickOutcome, PickedImage, supportedPhotoFormats;

const int listingPhotoLimit = NyumbaMarket.maxListingPhotos;
const int listingPhotoMaxBytes = NyumbaMarket.maxImageSizeBytes;

/// Listing photos are ordinary picked images; the alias keeps the marketplace
/// code reading in its own vocabulary.
typedef PickedListingPhoto = PickedImage;

Future<ImagePickOutcome> pickListingPhotos({required int remainingSlots}) =>
    pickImages(
      remainingSlots: remainingSlots,
      maxBytes: listingPhotoMaxBytes,
      limit: listingPhotoLimit,
      subject: 'listing',
    );

Uint8List? listingPhotoBytes(String value) => decodePhotoDataUri(value);
