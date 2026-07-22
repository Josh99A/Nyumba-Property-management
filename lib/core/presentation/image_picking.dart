import 'dart:convert';
import 'dart:typed_data';

export 'picked_file.dart';

import 'picked_file.dart';

import 'image_picking_stub.dart'
    if (dart.library.io) 'image_picking_io.dart'
    if (dart.library.js_interop) 'image_picking_web.dart'
    as platform;

/// File extensions Nyumba accepts for property and listing photos.
const List<String> supportedPhotoExtensions = ['jpg', 'jpeg', 'png', 'webp'];

/// Human-readable list of the accepted formats, for copy that explains a
/// rejection.
const String supportedPhotoFormats = 'JPEG, PNG, or WebP';

/// One image the landlord chose, held in memory until the surrounding draft is
/// saved.
final class PickedImage {
  const PickedImage({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  String get dataUri => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

/// Everything one trip to the file chooser produced.
///
/// The three fields are deliberately separate, because the screens have to be
/// able to tell three outcomes apart that all used to look identical: photos
/// arrived, nothing arrived because the landlord backed out, and nothing
/// arrived because something went wrong. Only the last one is an error, and
/// only the last one should be shown as one.
final class ImagePickOutcome {
  const ImagePickOutcome({
    this.images = const [],
    this.problems = const [],
    this.cancelled = false,
  });

  /// Images that passed every check and are ready to attach.
  final List<PickedImage> images;

  /// Plain-language reasons individual files were left out. Each entry is a
  /// complete sentence the landlord can act on.
  final List<String> problems;

  /// True when the chooser closed without a selection. Not a failure — the
  /// screen should say nothing at all.
  final bool cancelled;

  bool get hasImages => images.isNotEmpty;
  bool get hasProblems => problems.isNotEmpty;
}

/// Opens the platform file chooser and returns the images that survived
/// validation, alongside a plain-language reason for every file that did not.
///
/// [remainingSlots] is how many more photos the draft can hold, [limit] the
/// total it allows, and [subject] the thing being photographed ("property",
/// "listing") so the copy reads naturally.
Future<ImagePickOutcome> pickImages({
  required int remainingSlots,
  required int maxBytes,
  required int limit,
  required String subject,
}) async {
  if (remainingSlots <= 0) {
    return ImagePickOutcome(
      problems: [
        'You have already added the maximum of $limit photos for this '
            '$subject. Remove one before adding another.',
      ],
    );
  }

  final List<PickedFile>? files;
  try {
    files = await platform.pickImageFiles(
      extensions: supportedPhotoExtensions,
      allowMultiple: remainingSlots > 1,
    );
  } on Object catch (error) {
    return ImagePickOutcome(
      problems: [
        'Nyumba could not open the file chooser on this device. '
            'Technical detail: $error',
      ],
    );
  }

  if (files == null) return const ImagePickOutcome(cancelled: true);
  if (files.isEmpty) return const ImagePickOutcome(cancelled: true);

  return validatePickedFiles(
    files,
    remainingSlots: remainingSlots,
    maxBytes: maxBytes,
    limit: limit,
    subject: subject,
  );
}

/// Decides which of [files] Nyumba will accept, and writes a plain-language
/// reason for each one it will not.
///
/// Separate from [pickImages] so the rules — and the sentences they produce,
/// which are the part a landlord actually reads — can be exercised without a
/// file chooser.
ImagePickOutcome validatePickedFiles(
  List<PickedFile> files, {
  required int remainingSlots,
  required int maxBytes,
  required int limit,
  required String subject,
}) {
  final accepted = <PickedImage>[];
  final problems = <String>[];
  var skippedForSpace = 0;

  for (final file in files) {
    if (accepted.length >= remainingSlots) {
      skippedForSpace++;
      continue;
    }

    final readError = file.readError;
    if (readError != null || file.bytes == null) {
      problems.add(
        '"${file.name}" was not added because '
        '${readError ?? 'its contents could not be read'}.',
      );
      continue;
    }

    final bytes = file.bytes!;
    if (bytes.isEmpty) {
      problems.add('"${file.name}" was not added because the file is empty.');
      continue;
    }

    final mimeType = _mimeTypeFor(file.name);
    if (mimeType == null) {
      problems.add(
        '"${file.name}" was not added because it is not a '
        '$supportedPhotoFormats image.',
      );
      continue;
    }

    if (bytes.lengthInBytes > maxBytes) {
      problems.add(
        '"${file.name}" is ${_megabytes(bytes.lengthInBytes)} — too large. '
        'Photos must be under ${_megabytes(maxBytes)}. Resize it and try '
        'again.',
      );
      continue;
    }

    accepted.add(
      PickedImage(name: file.name, mimeType: mimeType, bytes: bytes),
    );
  }

  if (skippedForSpace > 0) {
    problems.add(
      skippedForSpace == 1
          ? '1 photo was left out because this $subject can hold only $limit '
                'photos.'
          : '$skippedForSpace photos were left out because this $subject can '
                'hold only $limit photos.',
    );
  }

  return ImagePickOutcome(
    images: List.unmodifiable(accepted),
    problems: List.unmodifiable(problems),
  );
}

/// Decodes an image reference stored as a `data:` URI back into bytes, or null
/// when the reference points somewhere else (an https URL, say) or is
/// malformed.
Uint8List? decodePhotoDataUri(String value) {
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

String? _mimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (fileName.substring(dot + 1).toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => null,
  };
}

String _megabytes(int bytes) {
  final value = bytes / (1024 * 1024);
  return '${value < 10 ? value.toStringAsFixed(1) : value.round()} MB';
}
