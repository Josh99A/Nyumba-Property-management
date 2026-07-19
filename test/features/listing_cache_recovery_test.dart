import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/listing_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_listing_repository.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_unit_repository.dart';
import 'package:sembast/sembast_memory.dart';

/// Older builds pulled public listings without propertyId/unitId/landlordId,
/// and the remote merge never repairs a record whose projection version has
/// not advanced. A visitor with such a cached record must still see the rest
/// of the catalogue, and the workspace-open sweep must drop the unreadable
/// record so the next server snapshot can rewrite it.
void main() {
  late OfflineDatabase database;
  final now = DateTime.utc(2026, 7, 19);
  var _databaseId = 0;

  setUp(() async {
    database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase(
        'listing-cache-recovery-${_databaseId++}.db',
      ),
    );
    await database.initialize();
  });

  tearDown(() => database.close());

  Future<void> seedRecords() async {
    final valid = _publishedListing(id: 'valid-listing', now: now);
    await database.putRemoteEntityIfUnmodified(
      entityType: OfflineEntityType.listing,
      entityId: valid.id,
      entity: ListingMapper.toJson(valid),
    );
    // The legacy pull shape: a public projection cached without the scope
    // identifiers the mapper requires.
    final corrupt = ListingMapper.toJson(valid)
      ..remove('propertyId')
      ..['id'] = 'legacy-listing';
    await database.putLocalEntity(
      entityType: OfflineEntityType.listing,
      entityId: 'legacy-listing',
      entity: corrupt,
      reason: LocalOnlyReason.serverDerived,
    );
  }

  test('an unreadable cached record does not blank the catalogue', () async {
    await seedRecords();
    final repository = SembastListingRepository(
      database: database,
      properties: SembastPropertyRepository(database: database),
      units: SembastUnitRepository(database: database),
    );

    expect(
      (await repository.getAll(publicOnly: true)).map((l) => l.id),
      <String>['valid-listing'],
    );
    expect(
      (await repository.watchAll(publicOnly: true).first).map((l) => l.id),
      <String>['valid-listing'],
    );
  });

  test('the workspace-open sweep drops only unreadable records', () async {
    await seedRecords();

    final removed = await database.purgeUndecodable(
      OfflineEntityType.listing,
      ListingMapper.canDecode,
    );

    expect(removed, 1);
    expect(
      await database.readEntity(OfflineEntityType.listing, 'legacy-listing'),
      isNull,
    );
    expect(
      await database.readEntity(OfflineEntityType.listing, 'valid-listing'),
      isNotNull,
    );
  });
}

Listing _publishedListing({required String id, required DateTime now}) =>
    Listing(
      id: id,
      unitId: 'unit-$id',
      propertyId: 'property-1',
      landlordId: 'landlord-1',
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
      syncMetadata: SyncMetadata.synced(lastSyncedAt: now),
    );
