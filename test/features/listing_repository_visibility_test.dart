import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/features/marketplace/data/mappers/listing_mapper.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_listing_repository.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_unit_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('public listing reads exclude unacknowledged publications', () async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase('listing-visibility.db'),
    );
    addTearDown(database.close);
    await database.initialize();
    final now = DateTime.utc(2026, 7, 13);
    final pending = _publishedListing(
      id: 'pending-listing',
      now: now,
      syncMetadata: const SyncMetadata.pending(),
    );
    final acknowledged = _publishedListing(
      id: 'acknowledged-listing',
      now: now,
      syncMetadata: SyncMetadata.synced(lastSyncedAt: now),
    );
    for (final listing in <Listing>[pending, acknowledged]) {
      await database.putRemoteEntityIfUnmodified(
        entityType: OfflineEntityType.listing,
        entityId: listing.id,
        entity: ListingMapper.toJson(listing),
      );
    }
    final repository = SembastListingRepository(
      database: database,
      properties: SembastPropertyRepository(database: database),
      units: SembastUnitRepository(database: database),
    );

    final publicListings = await repository.getAll(publicOnly: true);

    expect(publicListings.map((listing) => listing.id), <String>[
      'acknowledged-listing',
    ]);
  });
}

Listing _publishedListing({
  required String id,
  required DateTime now,
  required SyncMetadata syncMetadata,
}) => Listing(
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
  syncMetadata: syncMetadata,
);
