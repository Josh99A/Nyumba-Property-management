import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/remote_pull_gateway.dart';
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
  test('createDraft copies unit facts and ordered property photos', () async {
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
        imageUrls: <String>[
          'uploads/landlord-1/property-command/0_primary.webp',
          'uploads/landlord-1/property-command/1_kitchen.webp',
        ],
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
      ),
    );

    expect(draft.bedrooms, 3);
    expect(draft.bathrooms, 2);
    expect(draft.unitType, 'apartment');
    expect(draft.amenities, ['Secure parking', 'Backup water']);
    expect(draft.city, 'Kampala');
    expect(draft.neighborhood, 'Ntinda');
    expect(draft.imageUrls, property.imageUrls);

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

  test('listing-specific photos override inherited property media', () async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(
        'listing-photo-override-projection.db',
      ),
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
        imageUrls: <String>[
          'uploads/landlord-1/property-command/0_primary.webp',
        ],
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
        imageUrls: const <String>[
          'uploads/landlord-1/listing-command/0_listing-cover.webp',
        ],
      ),
    );

    expect(draft.imageUrls, <String>[
      'uploads/landlord-1/listing-command/0_listing-cover.webp',
    ]);
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

  group('a pulled listing keeps its map pin', () {
    /// A `publicListings/{id}` document as `listingPublish` in
    /// firebase/functions/src/commands/listings.ts writes it, after
    /// FirestoreRemotePullGateway has normalized Timestamps to ISO strings.
    ///
    /// Hand-written for the same reason as the landlord projection fixtures:
    /// the point is to fail when the TypeScript writer and the Dart reader
    /// drift apart, which a fixture derived from either side could not do.
    Map<String, dynamic> publishedDocument() => <String, dynamic>{
      'version': 4,
      'title': 'Two-bedroom apartment in Ntinda',
      'description': 'Bright apartment with reliable water.',
      'monthlyRentMinor': 150000000,
      'currency': 'UGX',
      'unitType': 'apartment',
      'city': 'Kampala',
      'neighborhood': 'Ntinda',
      'district': 'Kampala',
      'bedrooms': 2,
      'bathrooms': 2,
      'amenities': <String>['Backup water'],
      'approximateLocation': <String, Object?>{'lat': 0.357, 'lng': 32.612},
      'landlordToken': 'opaque-landlord-token',
      'imagePaths': <String>['public/listings/listing-1/0-abc-full.webp'],
      'status': 'published',
      'publishedAt': '2026-07-14T00:00:00.000Z',
      'expiresAt': '2026-08-13T00:00:00.000Z',
      'createdAt': '2026-07-14T00:00:00.000Z',
      'updatedAt': '2026-07-14T00:00:00.000Z',
      'isDeleted': false,
    };

    Map<String, Object?> shape(Map<String, dynamic> document) =>
        FirestoreRemotePullGateway.toLocalShape(
          OfflineEntityType.publicListing,
          'listing-1',
          document,
          publicOnly: true,
        );

    // The regression this group exists for. The server nests the pin under
    // `approximateLocation`; the aggregate reads two flat scalars. While those
    // two disagreed the coordinate survived only on the device that authored
    // it, so every other device saw a listing with no location at all.
    test('the nested server location becomes the flat client scalars', () {
      final shaped = shape(publishedDocument());

      expect(shaped['approximateLatitude'], 0.357);
      expect(shaped['approximateLongitude'], 32.612);
    });

    test('a pulled listing decodes with its coordinates intact', () {
      final shaped = shape(publishedDocument())
        ..['syncMetadata'] = SyncMetadataMapper.toJson(
          SyncMetadata.synced(
            serverRevision: '4',
            lastSyncedAt: DateTime.utc(2026, 7, 14),
          ),
        );

      final listing = ListingMapper.fromJson(shaped);

      expect(listing.approximateLatitude, 0.357);
      expect(listing.approximateLongitude, 32.612);
      expect(listing.neighborhood, 'Ntinda');
    });

    // Guards the migration path: if the field ever becomes a real Firestore
    // GeoPoint, `_normalize` hands back these key names instead.
    test('a normalized GeoPoint is read the same way', () {
      final shaped = shape(
        publishedDocument()
          ..['approximateLocation'] = <String, Object?>{
            'latitude': 0.357,
            'longitude': 32.612,
          },
      );

      expect(shaped['approximateLatitude'], 0.357);
      expect(shaped['approximateLongitude'], 32.612);
    });

    test('a whole-number coordinate survives JSON integer typing', () {
      final shaped = shape(
        publishedDocument()
          ..['approximateLocation'] = <String, Object?>{'lat': 0, 'lng': 32},
      );

      // Type-sensitive on purpose: `0 == 0.0` in Dart, so a value assertion
      // alone would pass on an unconverted int and the mapper's
      // `optionalDouble` would then reject it at decode time.
      expect(shaped['approximateLatitude'], isA<double>());
      expect(shaped['approximateLongitude'], isA<double>());
      expect(shaped['approximateLatitude'], 0.0);
      expect(shaped['approximateLongitude'], 32.0);
    });

    // `listingPublish` writes an explicit null when the landlord never set a
    // pin, so this is the ordinary case today, not an edge case.
    test('a listing with no pin decodes without one', () {
      final shaped = shape(publishedDocument()..['approximateLocation'] = null)
        ..['syncMetadata'] = SyncMetadataMapper.toJson(
          const SyncMetadata.pending(),
        );

      expect(shaped, isNot(contains('approximateLatitude')));
      expect(ListingMapper.fromJson(shaped).approximateLatitude, isNull);
    });

    test('a half-written pair is dropped rather than half-applied', () {
      final shaped = shape(
        publishedDocument()
          ..['approximateLocation'] = <String, Object?>{'lat': 0.357},
      );

      expect(shaped, isNot(contains('approximateLatitude')));
      expect(shaped, isNot(contains('approximateLongitude')));
    });
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
