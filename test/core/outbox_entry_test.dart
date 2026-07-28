import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';

void main() {
  OutboxEntry entry({String? lastError, String? errorReason}) => OutboxEntry(
    id: 'mutation-1',
    entityType: OfflineEntityType.listing,
    entityId: 'listing-1',
    operation: OutboxOperation.publish,
    payload: const <String, Object?>{},
    createdAt: DateTime.utc(2026, 7, 28),
    lastError: lastError,
    errorReason: errorReason,
    errorFields: errorReason == null ? const <String>[] : const ['title'],
  );

  test('a new lastError replaces the previous reason and fields', () {
    final refused = entry(
      lastError: 'VALIDATION_FAILED',
      errorReason: 'listingMissingPhotos',
    );

    final replaced = refused.copyWith(lastError: 'OTHER_CODE');

    // The reason and fields belong to the code they arrived with. Carrying
    // the old reason forward would attribute a stale explanation to a
    // failure it never described.
    expect(replaced.lastError, 'OTHER_CODE');
    expect(replaced.errorReason, isNull);
    expect(replaced.errorFields, isEmpty);
  });

  test('omitting lastError keeps the existing reason and fields', () {
    final refused = entry(
      lastError: 'VALIDATION_FAILED',
      errorReason: 'listingMissingPhotos',
    );

    final unchanged = refused.copyWith(attemptCount: 2);

    expect(unchanged.lastError, 'VALIDATION_FAILED');
    expect(unchanged.errorReason, 'listingMissingPhotos');
    expect(unchanged.errorFields, ['title']);
  });

  test('clearing lastError also clears the reason and fields', () {
    final refused = entry(
      lastError: 'VALIDATION_FAILED',
      errorReason: 'listingMissingPhotos',
    );

    final cleared = refused.copyWith(clearLastError: true);

    expect(cleared.lastError, isNull);
    expect(cleared.errorReason, isNull);
    expect(cleared.errorFields, isEmpty);
  });
}
