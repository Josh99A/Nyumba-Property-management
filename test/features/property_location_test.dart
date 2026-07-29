import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/coordinates.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/remote_pull_gateway.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_listing_repository.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/data/mappers/property_mapper.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_unit_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:sembast/sembast_memory.dart';

/// Kampala city centre, to roughly four decimal places.
final kampala = Coordinates(latitude: 0.3476, longitude: 32.5825);

void main() {
  group('Coordinates', () {
    test('rejects an axis outside the world', () {
      expect(
        () => Coordinates(latitude: 91, longitude: 32.5825),
        throwsArgumentError,
      );
      expect(
        () => Coordinates(latitude: 0.3476, longitude: 181),
        throwsArgumentError,
      );
      expect(
        () => Coordinates(latitude: double.nan, longitude: 32.5825),
        throwsArgumentError,
      );
    });

    // Both or neither, everywhere: a lone axis cannot be placed on a map, and
    // a half-pair that decoded cleanly would render an empty map instead of an
    // honest "no location".
    test('tryFrom returns null for a missing or unusable axis', () {
      expect(Coordinates.tryFrom(null, 32.5825), isNull);
      expect(Coordinates.tryFrom(0.3476, null), isNull);
      expect(Coordinates.tryFrom(91, 32.5825), isNull);
      expect(Coordinates.tryFrom(double.infinity, 32.5825), isNull);
      expect(Coordinates.tryFrom(0.3476, 32.5825), kampala);
    });

    // Mirrors the rounding `listingPublish` applies before writing
    // publicListings, so the landlord's "what tenants see" preview shows the
    // point the server will actually publish.
    test('coarsened rounds to the published precision', () {
      expect(
        Coordinates(latitude: 0.34765, longitude: 32.58249).coarsened(),
        Coordinates(latitude: 0.348, longitude: 32.582),
      );
      // Already coarse, so publication is a no-op on it.
      expect(kampala.coarsened().coarsened(), kampala.coarsened());
    });
  });

  group('a property carries its pin through storage', () {
    Property propertyWith(Coordinates? location) => Property(
      id: 'property-1',
      landlordId: 'landlord-1',
      name: 'Acacia Court',
      addressLine: 'Plot 14, Acacia Avenue',
      city: 'Kampala',
      country: 'Uganda',
      location: location,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      syncMetadata: const SyncMetadata.pending(),
    );

    test('round-trips through the mapper', () {
      final restored = PropertyMapper.fromJson(
        PropertyMapper.toJson(propertyWith(kampala)),
      );

      expect(restored.location, kampala);
    });

    test('a property with no pin round-trips without one', () {
      final json = PropertyMapper.toJson(propertyWith(null));

      expect(json['latitude'], isNull);
      expect(PropertyMapper.fromJson(json).location, isNull);
    });

    // A record that cannot decode disappears from the landlord's portfolio,
    // which is a far worse outcome than a property with no map.
    test('a corrupt pin degrades to no pin rather than an unreadable row', () {
      final json = PropertyMapper.toJson(propertyWith(kampala))
        ..['longitude'] = 999.0;

      expect(PropertyMapper.fromJson(json).location, isNull);
    });

    test('the server nests the pin and the pull flattens it', () {
      final shaped = FirestoreRemotePullGateway.toLocalShape(
        OfflineEntityType.property,
        'property-1',
        <String, dynamic>{
          'landlordId': 'landlord-1',
          'name': 'Acacia Court',
          'addressLine': 'Plot 14, Acacia Avenue',
          'city': 'Kampala',
          'country': 'Uganda',
          'location': <String, Object?>{'lat': 0.3476, 'lng': 32.5825},
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
        publicOnly: false,
      );

      expect(shaped['latitude'], 0.3476);
      expect(shaped['longitude'], 32.5825);
    });
  });

  group('a new advert starts from its property', () {
    Future<
      (SembastListingRepository, SembastPropertyRepository, OfflineDatabase)
    >
    open(String name) async {
      final database = OfflineDatabase(
        await databaseFactoryMemory.openDatabase(name),
      );
      await database.initialize();
      final properties = SembastPropertyRepository(database: database);
      final units = SembastUnitRepository(database: database);
      return (
        SembastListingRepository(
          database: database,
          properties: properties,
          units: units,
        ),
        properties,
        database,
      );
    }

    Future<Listing> draftFor(
      SembastListingRepository listings,
      SembastPropertyRepository properties,
      OfflineDatabase database, {
      required Coordinates? propertyPin,
      Coordinates? explicitPin,
    }) async {
      final property = await properties.create(
        CreatePropertyInput(
          landlordId: 'landlord-1',
          name: 'Acacia Court',
          addressLine: 'Plot 14, Acacia Avenue',
          city: 'Kampala',
          location: propertyPin,
        ),
      );
      final units = SembastUnitRepository(database: database);
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
      return listings.createDraft(
        CreateListingInput(
          unitId: unit.id,
          propertyId: property.id,
          landlordId: 'landlord-1',
          title: 'C1 at Acacia Court',
          description: 'A bright apartment.',
          monthlyRentMinor: unit.monthlyRentMinor,
          city: property.city,
          neighborhood: 'Ntinda',
          contactPhone: '+256 772 000 100',
          approximateLatitude: explicitPin?.latitude,
          approximateLongitude: explicitPin?.longitude,
        ),
      );
    }

    // Pinning a property once is what makes this usable: asking a landlord to
    // place a pin again for every unit in a block is how the field ends up
    // permanently empty.
    test('an advert with no pin inherits the property pin', () async {
      final (listings, properties, database) = await open('inherit-pin.db');
      addTearDown(database.close);

      final draft = await draftFor(
        listings,
        properties,
        database,
        propertyPin: kampala,
      );

      expect(draft.approximateLatitude, kampala.latitude);
      expect(draft.approximateLongitude, kampala.longitude);
    });

    test('an explicitly placed pin wins over the property pin', () async {
      final (listings, properties, database) = await open('explicit-pin.db');
      addTearDown(database.close);
      final placed = Coordinates(latitude: 0.3136, longitude: 32.5811);

      final draft = await draftFor(
        listings,
        properties,
        database,
        propertyPin: kampala,
        explicitPin: placed,
      );

      expect(draft.approximateLatitude, placed.latitude);
      expect(draft.approximateLongitude, placed.longitude);
    });

    test('an unpinned property leaves the advert unpinned', () async {
      final (listings, properties, database) = await open('no-pin.db');
      addTearDown(database.close);

      final draft = await draftFor(
        listings,
        properties,
        database,
        propertyPin: null,
      );

      expect(draft.approximateLatitude, isNull);
      expect(draft.approximateLongitude, isNull);
    });
  });
}
