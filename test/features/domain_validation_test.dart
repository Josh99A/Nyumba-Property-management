import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/listing_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/unit_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13);

  group('money and enum validation', () {
    test('unit rejects non-positive monthly rent', () {
      expect(
        () => Unit(
          id: 'unit-id',
          propertyId: 'property-id',
          landlordId: 'landlord-id',
          label: 'A1',
          type: UnitType.apartment,
          status: UnitStatus.vacant,
          monthlyRentMinor: 0,
          currency: 'UGX',
          createdAt: now,
          updatedAt: now,
          syncMetadata: const SyncMetadata.pending(),
        ),
        throwsA(
          isA<DomainValidationException>().having(
            (error) => error.errors,
            'errors',
            contains('monthlyRentMinor'),
          ),
        ),
      );
    });

    test('unit mapper refuses floating-point minor units', () {
      final valid = Unit(
        id: 'unit-id',
        propertyId: 'property-id',
        landlordId: 'landlord-id',
        label: 'A1',
        type: UnitType.apartment,
        status: UnitStatus.vacant,
        monthlyRentMinor: 4500000,
        currency: 'UGX',
        createdAt: now,
        updatedAt: now,
        syncMetadata: const SyncMetadata.pending(),
      );
      final json = UnitMapper.toJson(valid)..['monthlyRentMinor'] = 45000.50;

      expect(() => UnitMapper.fromJson(json), throwsFormatException);
    });

    test('unit mapper refuses unknown status values', () {
      final valid = Unit(
        id: 'unit-id',
        propertyId: 'property-id',
        landlordId: 'landlord-id',
        label: 'A1',
        type: UnitType.apartment,
        status: UnitStatus.vacant,
        monthlyRentMinor: 4500000,
        currency: 'UGX',
        createdAt: now,
        updatedAt: now,
        syncMetadata: const SyncMetadata.pending(),
      );
      final json = UnitMapper.toJson(valid)..['status'] = 'available-ish';

      expect(() => UnitMapper.fromJson(json), throwsFormatException);
    });
  });

  group('listing publication', () {
    test('pending publication is not exposed publicly', () {
      final pending = Listing(
        id: 'listing-id',
        unitId: 'unit-id',
        propertyId: 'property-id',
        landlordId: 'landlord-id',
        title: 'Apartment A1',
        description: 'A bright two-bedroom apartment.',
        monthlyRentMinor: 4500000,
        currency: 'UGX',
        status: ListingStatus.published,
        contactPhone: '+256700000000',
        createdAt: now,
        updatedAt: now,
        publishedAt: now,
        syncMetadata: const SyncMetadata.pending(),
      );
      final acknowledged = pending.copyWith(
        syncMetadata: SyncMetadata.synced(lastSyncedAt: now),
      );

      expect(pending.isPublic, isFalse);
      expect(acknowledged.isPublic, isTrue);
    });

    test('published listing requires contact details', () {
      expect(
        () => Listing(
          id: 'listing-id',
          unitId: 'unit-id',
          propertyId: 'property-id',
          landlordId: 'landlord-id',
          title: 'Apartment A1',
          description: 'A bright two-bedroom apartment.',
          monthlyRentMinor: 4500000,
          currency: 'UGX',
          status: ListingStatus.published,
          createdAt: now,
          updatedAt: now,
          publishedAt: now,
          syncMetadata: const SyncMetadata.pending(),
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });

    test('listing mapper validates listing status', () {
      final draft = Listing(
        id: 'listing-id',
        unitId: 'unit-id',
        propertyId: 'property-id',
        landlordId: 'landlord-id',
        title: 'Apartment A1',
        description: 'A bright two-bedroom apartment.',
        monthlyRentMinor: 4500000,
        currency: 'UGX',
        status: ListingStatus.draft,
        contactPhone: '+256700000000',
        createdAt: now,
        updatedAt: now,
        syncMetadata: const SyncMetadata.pending(),
      );
      final json = ListingMapper.toJson(draft)..['status'] = 'live';

      expect(() => ListingMapper.fromJson(json), throwsFormatException);
    });
  });
}
