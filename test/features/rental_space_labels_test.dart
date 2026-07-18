import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/features/portfolio/application/rental_space_labels.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';

void main() {
  test('rental space display name includes the specific type', () {
    final now = DateTime.utc(2026, 7, 14);
    final unit = Unit(
      id: 'space-1',
      propertyId: 'property-1',
      landlordId: 'landlord-1',
      label: 'B4',
      type: UnitType.apartment,
      status: UnitStatus.vacant,
      monthlyRentMinor: 120000000,
      currency: 'UGX',
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );

    expect(unit.displayName, 'Apartment B4');
  });

  test('other types fall back to the generic rental-space label', () {
    expect(UnitType.other.displayLabel, 'Rental space');
  });

  test('does not repeat a type already included in the space label', () {
    final now = DateTime.utc(2026, 7, 14);
    final unit = Unit(
      id: 'space-2',
      propertyId: 'property-1',
      landlordId: 'landlord-1',
      label: 'Apartment A1',
      type: UnitType.apartment,
      status: UnitStatus.vacant,
      monthlyRentMinor: 120000000,
      currency: 'UGX',
      createdAt: now,
      updatedAt: now,
      syncMetadata: const SyncMetadata.pending(),
    );

    expect(unit.displayName, 'Apartment A1');
  });
}
