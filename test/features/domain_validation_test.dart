import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/domain_exception.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/listing_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/notices/data/mappers/notice_mapper.dart';
import 'package:nyumba_property_management/features/notices/domain/notice.dart';
import 'package:nyumba_property_management/features/notifications/domain/app_notification.dart';
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
        unitType: 'apartment',
        city: 'Kampala',
        neighborhood: 'Ntinda',
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
          unitType: 'apartment',
          city: 'Kampala',
          neighborhood: 'Ntinda',
          createdAt: now,
          updatedAt: now,
          publishedAt: now,
          syncMetadata: const SyncMetadata.pending(),
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });

    test('published listing requires a public-safe location', () {
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
          unitType: 'apartment',
          city: 'Kampala',
          contactPhone: '+256700000000',
          createdAt: now,
          updatedAt: now,
          publishedAt: now,
          syncMetadata: const SyncMetadata.pending(),
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });

    test('listing limits public photo references to five', () {
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
          status: ListingStatus.draft,
          unitType: 'apartment',
          city: 'Kampala',
          neighborhood: 'Ntinda',
          imageUrls: List<String>.generate(
            6,
            (index) => 'https://example.com/$index.webp',
          ),
          createdAt: now,
          updatedAt: now,
          syncMetadata: const SyncMetadata.pending(),
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });

    test('locally selected photos cannot be published as public media', () {
      expect(
        () => Listing(
          id: 'listing-local-photo',
          unitId: 'unit-id',
          propertyId: 'property-id',
          landlordId: 'landlord-id',
          title: 'Apartment A1',
          description: 'A bright two-bedroom apartment.',
          monthlyRentMinor: 4500000,
          currency: 'UGX',
          status: ListingStatus.published,
          unitType: 'apartment',
          city: 'Kampala',
          neighborhood: 'Ntinda',
          contactPhone: '+256700000000',
          imageUrls: const ['data:image/png;base64,AA=='],
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
        unitType: 'apartment',
        city: 'Kampala',
        neighborhood: 'Ntinda',
        contactPhone: '+256700000000',
        createdAt: now,
        updatedAt: now,
        syncMetadata: const SyncMetadata.pending(),
      );
      final json = ListingMapper.toJson(draft)..['status'] = 'live';

      expect(() => ListingMapper.fromJson(json), throwsFormatException);
    });

    test('notice audience type and ID combinations fail closed', () {
      final base = <String, Object?>{
        'id': 'notice-id',
        'reference': 'NTC-2026-001',
        'landlordId': 'landlord-id',
        'title': 'Water interruption',
        'body': 'Water will be unavailable on Saturday morning.',
        'audience': 'All tenants',
        'audienceType': 'unsupported',
        'audienceId': null,
        'status': 'queued',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'syncMetadata': const <String, Object?>{
          'state': 'pending',
          'serverRevision': null,
          'lastSyncedAt': null,
          'lastError': null,
        },
      };
      expect(() => NoticeMapper.fromJson(base), throwsFormatException);

      expect(
        () => Notice(
          id: 'notice-id',
          reference: 'NTC-2026-001',
          landlordId: 'landlord-id',
          title: 'Water interruption',
          body: 'Water will be unavailable on Saturday morning.',
          audience: 'All tenants',
          audienceType: NoticeAudienceType.allActiveTenants,
          audienceId: 'property-id',
          status: NoticeStatus.queued,
          createdAt: now,
          updatedAt: now,
          syncMetadata: const SyncMetadata.pending(),
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });

    test('unread notifications cannot carry a read timestamp', () {
      expect(
        () => AppNotification(
          id: 'notification-id',
          kind: AppNotificationKind.system,
          title: 'Account update',
          body: 'Your account was updated.',
          route: '/settings',
          createdAt: now,
          updatedAt: now,
          isRead: false,
          readAt: now,
          syncMetadata: const SyncMetadata.synced(),
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });
  });
}
