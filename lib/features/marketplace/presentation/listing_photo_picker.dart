import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

const int listingPhotoLimit = 10;
const int listingPhotoMaxBytes = 5 * 1024 * 1024;

final class PickedListingPhoto {
  const PickedListingPhoto({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  String get dataUri => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

final class ListingPhotoPickResult {
  const ListingPhotoPickResult({
    required this.photos,
    required this.rejectedMessages,
  });

  final List<PickedListingPhoto> photos;
  final List<String> rejectedMessages;
}

Future<ListingPhotoPickResult> pickListingPhotos({
  required int remainingSlots,
}) async {
  if (remainingSlots <= 0) {
    return const ListingPhotoPickResult(
      photos: [],
      rejectedMessages: ['A listing can contain at most 10 photos.'],
    );
  }
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    allowMultiple: true,
    withData: true,
  );
  if (result == null) {
    return const ListingPhotoPickResult(photos: [], rejectedMessages: []);
  }

  final accepted = <PickedListingPhoto>[];
  final rejected = <String>[];
  for (final file in result.files) {
    if (accepted.length >= remainingSlots) {
      rejected.add(
        'Only the first $remainingSlots selected photos were added.',
      );
      break;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      rejected.add('${file.name} could not be read.');
      continue;
    }
    if (bytes.lengthInBytes > listingPhotoMaxBytes) {
      rejected.add('${file.name} is larger than 5 MB.');
      continue;
    }
    final mimeType = _mimeTypeFor(file.extension);
    if (mimeType == null) {
      rejected.add('${file.name} is not a JPEG, PNG, or WebP image.');
      continue;
    }
    accepted.add(
      PickedListingPhoto(name: file.name, mimeType: mimeType, bytes: bytes),
    );
  }
  return ListingPhotoPickResult(
    photos: List.unmodifiable(accepted),
    rejectedMessages: List.unmodifiable(rejected),
  );
}

String? _mimeTypeFor(String? extension) => switch (extension?.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => null,
};

Uint8List? listingPhotoBytes(String value) {
  final match = RegExp(
    r'^data:image\/(?:jpeg|png|webp);base64,(.+)$',
  ).firstMatch(value);
  if (match == null) return null;
  try {
    return base64Decode(match.group(1)!);
  } on FormatException {
    return null;
  }
}
