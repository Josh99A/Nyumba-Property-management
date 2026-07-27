import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;

import '../config/market_config.dart';

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

  final validated = validatePickedFiles(
    files,
    remainingSlots: remainingSlots,
    maxBytes: maxBytes,
    limit: limit,
    subject: subject,
  );
  return optimizePickedImages(validated, maxBytes: maxBytes);
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
      problems.add(_unsupportedImageProblem(file.name));
      continue;
    }

    if (bytes.lengthInBytes > maxBytes) {
      problems.add(
        _oversizedImageProblem(
          file.name,
          bytes: bytes.lengthInBytes,
          maxBytes: maxBytes,
        ),
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

/// Resizes and recompresses accepted photos before they enter the offline
/// aggregate. Every outbox retry therefore reuses the same smaller payload.
Future<ImagePickOutcome> optimizePickedImages(
  ImagePickOutcome outcome, {
  required int maxBytes,
}) async {
  if (outcome.images.isEmpty) return outcome;

  final optimized = <PickedImage>[];
  final problems = <String>[...outcome.problems];
  for (final source in outcome.images) {
    final image = await optimizePickedImage(source);
    if (image == null) {
      problems.add(_unsupportedImageProblem(source.name));
      continue;
    }
    if (image.bytes.lengthInBytes > maxBytes) {
      problems.add(
        _oversizedImageProblem(
          source.name,
          bytes: image.bytes.lengthInBytes,
          maxBytes: maxBytes,
        ),
      );
      continue;
    }
    optimized.add(image);
  }

  return ImagePickOutcome(
    images: List.unmodifiable(optimized),
    problems: List.unmodifiable(problems),
    cancelled: outcome.cancelled,
  );
}

/// Produces a consistently small, correctly oriented JPEG and removes source
/// metadata before the bytes are persisted or uploaded.
Future<PickedImage?> optimizePickedImage(PickedImage source) async {
  try {
    final bytes = await compute(
      _optimizeImageBytes,
      source.bytes,
      debugLabel: 'optimize-${source.name}',
    );
    if (bytes == null) return null;
    return PickedImage(
      name: _jpegName(source.name),
      mimeType: 'image/jpeg',
      bytes: bytes,
    );
  } on Object {
    return null;
  }
}

Uint8List? _optimizeImageBytes(Uint8List bytes) {
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) return null;

  var optimized = image_lib.bakeOrientation(decoded);
  final scale = math.min(
    NyumbaMarket.maxOptimizedImageWidth / optimized.width,
    NyumbaMarket.maxOptimizedImageHeight / optimized.height,
  );
  if (scale < 1) {
    optimized = image_lib.copyResize(
      optimized,
      width: math.max(1, (optimized.width * scale).round()),
      height: math.max(1, (optimized.height * scale).round()),
      interpolation: image_lib.Interpolation.average,
    );
  }

  optimized
    ..exif = image_lib.ExifData()
    ..iccProfile = null
    ..textData = null
    ..extraChannels = null
    ..backgroundColor = image_lib.ColorRgb8(255, 255, 255);

  return image_lib.encodeJpg(
    optimized,
    quality: NyumbaMarket.optimizedImageJpegQuality,
    chroma: image_lib.JpegChroma.yuv420,
  );
}

final RegExp _photoDataUri = RegExp(
  r'^data:image\/(?:jpeg|png|webp);base64,(.+)$',
);

/// Decoded staged photos, keyed by the exact `data:` URI they came from.
///
/// This is called from `build`, so without memoisation every rebuild re-ran the
/// regex and allocated a fresh byte list. A fresh list is a fresh `MemoryImage`
/// identity, which means Flutter's image cache misses and the JPEG is decoded
/// again — on every frame, for every staged photo, exactly while a landlord is
/// working through the photo picker.
final Map<String, Uint8List> _decodedPhotoCache = <String, Uint8List>{};
int _decodedPhotoBytes = 0;

/// Staged photos are bounded by the picker (five per listing, two per
/// property), so this only has to survive an editing session, not a catalogue.
const int _decodedPhotoCacheMaxBytes = 32 * 1024 * 1024;

/// Decodes an image reference stored as a `data:` URI back into bytes, or null
/// when the reference points somewhere else (an https URL, say) or is
/// malformed.
///
/// Repeated calls for the same URI return the *same* list instance, which is
/// what lets the image cache recognise it as already decoded.
Uint8List? decodePhotoDataUri(String value) {
  final cached = _decodedPhotoCache.remove(value);
  if (cached != null) {
    // Reinserting promotes this entry to most-recently-used: a Dart map
    // preserves insertion order, so the eviction below drops the coldest first.
    _decodedPhotoCache[value] = cached;
    return cached;
  }

  final match = _photoDataUri.firstMatch(value);
  if (match == null) return null;
  final Uint8List bytes;
  try {
    bytes = base64Decode(match.group(1)!);
  } on FormatException {
    return null;
  }

  if (bytes.lengthInBytes <= _decodedPhotoCacheMaxBytes) {
    while (_decodedPhotoBytes + bytes.lengthInBytes >
            _decodedPhotoCacheMaxBytes &&
        _decodedPhotoCache.isNotEmpty) {
      final coldest = _decodedPhotoCache.keys.first;
      _decodedPhotoBytes -= _decodedPhotoCache.remove(coldest)!.lengthInBytes;
    }
    _decodedPhotoCache[value] = bytes;
    _decodedPhotoBytes += bytes.lengthInBytes;
  }
  return bytes;
}

/// Drops every memoised staged photo. For tests and sign-out.
@visibleForTesting
void clearDecodedPhotoCache() {
  _decodedPhotoCache.clear();
  _decodedPhotoBytes = 0;
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

String _jpegName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final stem = dot <= 0 ? fileName : fileName.substring(0, dot);
  return '$stem.jpg';
}

String _unsupportedImageProblem(String name) =>
    '"$name" was not added because it is not a '
    '$supportedPhotoFormats image.';

String _oversizedImageProblem(
  String name, {
  required int bytes,
  required int maxBytes,
}) =>
    '"$name" is ${_megabytes(bytes)} — too large. '
    'Photos must be under ${_megabytes(maxBytes)}. Resize it and try again.';

String _megabytes(int bytes) {
  final value = bytes / (1024 * 1024);
  return '${value < 10 ? value.toStringAsFixed(1) : value.round()} MB';
}
