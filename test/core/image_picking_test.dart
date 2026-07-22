import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/presentation/image_picking.dart';

const int _fiveMegabytes = 5 * 1024 * 1024;

ImagePickOutcome _validate(
  List<PickedFile> files, {
  int remainingSlots = 5,
  int limit = 5,
}) => validatePickedFiles(
  files,
  remainingSlots: remainingSlots,
  maxBytes: _fiveMegabytes,
  limit: limit,
  subject: 'property',
);

PickedFile _file(String name, {int bytes = 32}) =>
    PickedFile(name: name, bytes: Uint8List(bytes));

void main() {
  test('an accepted photo keeps its name and gets the right media type', () {
    final outcome = _validate([_file('front.JPG')]);

    expect(outcome.problems, isEmpty);
    expect(outcome.cancelled, isFalse);
    expect(outcome.images.single.name, 'front.JPG');
    expect(outcome.images.single.mimeType, 'image/jpeg');
    expect(
      outcome.images.single.dataUri,
      startsWith('data:image/jpeg;base64,'),
    );
  });

  test('a rejected file is named, so the landlord knows which one', () {
    final outcome = _validate([_file('deed.pdf'), _file('front.png')]);

    expect(outcome.images.single.name, 'front.png');
    expect(outcome.problems.single, contains('"deed.pdf"'));
    expect(outcome.problems.single, contains('JPEG, PNG, or WebP'));
  });

  test('an oversized photo is told its own size and the limit', () {
    final outcome = _validate([_file('huge.png', bytes: 7 * 1024 * 1024)]);

    expect(outcome.images, isEmpty);
    expect(outcome.problems.single, contains('7.0 MB'));
    expect(outcome.problems.single, contains('5.0 MB'));
    expect(outcome.problems.single, contains('Resize'));
  });

  test('an empty file is rejected rather than stored as a blank photo', () {
    final outcome = _validate([_file('empty.png', bytes: 0)]);

    expect(outcome.images, isEmpty);
    expect(outcome.problems.single, contains('the file is empty'));
  });

  test('a file the platform could not read carries the platform reason', () {
    final outcome = _validate([
      const PickedFile(name: 'locked.png', readError: 'it is on a locked disk'),
    ]);

    expect(outcome.images, isEmpty);
    expect(outcome.problems.single, contains('"locked.png"'));
    expect(outcome.problems.single, contains('it is on a locked disk'));
  });

  test(
    'photos beyond the remaining slots are counted, not dropped quietly',
    () {
      final outcome = _validate([
        _file('a.png'),
        _file('b.png'),
        _file('c.png'),
      ], remainingSlots: 1);

      expect(outcome.images, hasLength(1));
      expect(outcome.problems.single, contains('2 photos were left out'));
      expect(outcome.problems.single, contains('only 5 photos'));
    },
  );

  test('one photo over the limit is described in the singular', () {
    final outcome = _validate([
      _file('a.png'),
      _file('b.png'),
    ], remainingSlots: 1);

    expect(outcome.problems.single, startsWith('1 photo was left out'));
  });

  test('a full draft explains what to do instead of just refusing', () async {
    final outcome = await pickImages(
      remainingSlots: 0,
      maxBytes: _fiveMegabytes,
      limit: 5,
      subject: 'property',
    );

    expect(outcome.cancelled, isFalse);
    expect(outcome.images, isEmpty);
    expect(outcome.problems.single, contains('maximum of 5 photos'));
    expect(outcome.problems.single, contains('Remove one'));
  });

  test('a data reference survives the round trip back to bytes', () {
    final original = Uint8List.fromList(<int>[0, 1, 2, 253, 254, 255]);
    final image = PickedImage(
      name: 'home.webp',
      mimeType: 'image/webp',
      bytes: original,
    );

    expect(decodePhotoDataUri(image.dataUri), orderedEquals(original));
    expect(decodePhotoDataUri('https://example.com/home.png'), isNull);
    expect(decodePhotoDataUri('data:image/png;base64,not-base64'), isNull);
  });
}
