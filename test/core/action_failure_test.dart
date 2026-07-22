import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/presentation/action_failure.dart';

void main() {
  test('validation failures name the field the way the form does', () {
    final failure = describeActionFailure(
      DomainValidationException(<String, String>{
        'imageUrls': 'must contain at most 5 images',
      }),
      action: 'save this property',
    );

    expect(failure.message, 'Photos must contain at most 5 images.');
    // The raw error stays available, just not in the sentence.
    expect(failure.message, isNot(contains('imageUrls')));
    expect(failure.message, isNot(contains('DomainValidationException')));
    expect(failure.details, contains('imageUrls'));
  });

  test('every failing field is reported, not just the first', () {
    final failure = describeActionFailure(
      DomainValidationException(<String, String>{
        'name': 'is required',
        'city': 'is required',
      }),
      action: 'save this property',
    );

    expect(failure.message, contains('The name is required.'));
    expect(failure.message, contains('The city or town is required.'));
  });

  test('a field with no hand-written label still reads as English', () {
    final failure = describeActionFailure(
      DomainValidationException(<String, String>{
        'floorAreaSquareMetres': 'must be greater than zero',
      }),
      action: 'save this listing draft',
    );

    expect(
      failure.message,
      'The floor area square metres must be greater than zero.',
    );
  });

  test('a missing permission explains who can fix it', () {
    final failure = describeActionFailure(
      StateError('create permission is required.'),
      action: 'save this property',
    );

    expect(failure.message, contains('not allowed to save this property'));
    expect(failure.message, contains('account owner'));
  });

  test('a full device blames the photos, which is what fills it', () {
    final failure = describeActionFailure(
      Exception('QuotaExceededError: the quota has been exceeded'),
      action: 'save this property',
    );

    expect(failure.message, contains('run out of space'));
    expect(failure.message, contains('Photos'));
  });

  test('being offline is reported as safe, because the draft is kept', () {
    final failure = describeActionFailure(
      Exception('SocketException: Failed host lookup'),
      action: 'save this listing draft',
    );

    expect(failure.message, contains('kept on this device'));
  });

  test('an unrecognised error still says nothing was changed', () {
    final failure = describeActionFailure(
      Exception('something nobody has classified'),
      action: 'save this property',
    );

    expect(failure.message, contains('Nothing was changed'));
    expect(failure.details, contains('something nobody has classified'));
  });

  test('a missing entity names the thing in the words the app uses', () {
    final failure = describeActionFailure(
      const EntityNotFoundException('unit', 'unit-1'),
      action: 'save this listing draft',
    );

    expect(failure.message, contains('rental space'));
    expect(failure.message, isNot(contains('unit-1')));
  });
}
