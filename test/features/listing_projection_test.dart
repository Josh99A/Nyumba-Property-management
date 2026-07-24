import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/sync_metadata_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_listing_repository.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/listing_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_unit_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('createDraft copies bedrooms and bathrooms from the unit', () async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase('listing-projection.db'),
    );
    addTearDown(database.close);
    await database.initialize();
    final properties = SembastPropertyRepository(database: database);
    final units = SembastUnitRepository(database: database);
    final repository = SembastListingRepository(
      database: database,
      properties: properties,
      units: units,
    );

    final property = await properties.create(
      const CreatePropertyInput(
        landlordId: 'landlord-1',
        name: 'Sunset Apartments',
        addressLine: 'Muthangari Drive',
        city: 'Kampala',
        description: 'Quiet apartment living with secure parking.',
      ),
    );

    final unit = await units.create(
      CreateUnitInput(
        propertyId: property.id,
        landlordId: 'landlord-1',
        label: 'C1',
        type: UnitType.apartment,
        status: UnitStatus.vacant,
        monthlyRentMinor: 150000000,
        bedrooms: 3,
        bathrooms: 2,
        amenities: const ['Secure parking', 'Backup water'],
      ),
    );

    final draft = await repository.createDraft(
      CreateListingInput(
        unitId: unit.id,
        propertyId: property.id,
        landlordId: 'landlord-1',
        title: 'C1 at Sunset Apartments',
        description: 'A bright three-bedroom apartment.',
        monthlyRentMinor: unit.monthlyRentMinor,
        city: property.city,
        neighborhood: 'Ntinda',
        contactPhone: '+256 772 000 100',
        imageUrls: const ['data:image/png;base64,AA=='],
      ),
    );

    expect(draft.bedrooms, 3);
    expect(draft.bathrooms, 2);
    expect(draft.unitType, 'apartment');
    expect(draft.amenities, ['Secure parking', 'Backup water']);
    expect(draft.city, 'Kampala');
    expect(draft.neighborhood, 'Ntinda');

    final reloaded = await repository.getById(draft.id);
    expect(reloaded?.bedrooms, 3);
    expect(reloaded?.bathrooms, 2);
    expect(reloaded?.amenities, draft.amenities);
    expect(reloaded?.imageUrls, draft.imageUrls);
    final queued = await database.readOutbox();
    final draftCommand = queued.singleWhere(
      (entry) => entry.entityId == draft.id,
    );
    expect(draftCommand.payload['imageUrls'], draft.imageUrls);
  });

  test('public projection includes only public-safe listing details', () {
    final publishedAt = DateTime.utc(2026, 7, 14);
    final listing = Listing(
      id: 'listing-1',
      unitId: 'private-unit-1',
      propertyId: 'private-property-1',
      landlordId: 'private-landlord-1',
      title: 'Two-bedroom apartment in Ntinda',
      description: 'Bright apartment with reliable water.',
      monthlyRentMinor: 150000000,
      currency: 'UGX',
      status: ListingStatus.published,
      bedrooms: 2,
      bathrooms: 2,
      unitType: 'apartment',
      amenities: const ['Backup water', 'Secure parking'],
      city: 'Kampala',
      district: 'Kampala',
      neighborhood: 'Ntinda',
      approximateLatitude: 0.357,
      approximateLongitude: 32.612,
      securityDepositMinor: 150000000,
      contactPhone: '+256700000000',
      contactEmail: 'private@example.com',
      publicContactToken: 'opaque-contact-token',
      imageUrls: const ['https://cdn.example.com/public/listing-1/cover.webp'],
      createdAt: publishedAt,
      updatedAt: publishedAt,
      publishedAt: publishedAt,
      expiresAt: publishedAt.add(const Duration(days: 30)),
      projectionVersion: 3,
      syncMetadata: SyncMetadata.synced(lastSyncedAt: publishedAt),
    );

    final projection = ListingMapper.toPublicProjection(listing);

    expect(projection['neighborhood'], 'Ntinda');
    expect(projection['publicContactToken'], 'opaque-contact-token');
    expect(projection['expiresAt'], isNotNull);
    for (final privateField in <String>[
      'unitId',
      'propertyId',
      'landlordId',
      'contactPhone',
      'contactEmail',
      'addressLine',
    ]) {
      expect(projection, isNot(contains(privateField)));
    }
  });

  test('public projection decodes with an opaque contact token', () {
    final publishedAt = DateTime.utc(2026, 7, 24, 8);
    final listing = ListingMapper.fromJson(<String, Object?>{
      'id': 'listing-public-1',
      'unitId': 'public_unit_listing-public-1',
      'propertyId': 'public_property_listing-public-1',
      'landlordId': 'opaque-landlord-token',
      'title': 'Two-bedroom apartment in Ntinda',
      'description': 'Bright apartment with reliable water.',
      'monthlyRentMinor': 150000000,
      'currency': 'UGX',
      'status': 'published',
      'bedrooms': 2,
      'bathrooms': 2,
      'unitType': 'apartment',
      'amenities': <String>['Backup water', 'Secure parking'],
      'city': 'Kampala',
      'district': 'Kampala',
      'neighborhood': 'Ntinda',
      'publicContactToken': 'opaque-contact-token',
      'imageUrls': <String>[],
      'createdAt': publishedAt.toIso8601String(),
      'updatedAt': publishedAt.toIso8601String(),
      'publishedAt': publishedAt.toIso8601String(),
      'expiresAt': publishedAt.add(const Duration(days: 30)).toIso8601String(),
      'syncMetadata': SyncMetadataMapper.toJson(
        SyncMetadata.synced(serverRevision: '2', lastSyncedAt: publishedAt),
      ),
    });

    expect(listing.contactPhone, isNull);
    expect(listing.contactEmail, isNull);
    expect(listing.publicContactToken, 'opaque-contact-token');
    expect(listing.isPublic, isTrue);
  });
}
