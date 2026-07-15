import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/clock.dart';
import 'package:nyumba_property_management/core/domain/id_generator.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_listing_repository.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_unit_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 12);

  test(
    'unit archive remains visible until its delete command is acknowledged',
    () async {
      final database = OfflineDatabase(
        await databaseFactoryMemory.openDatabase('unit-archive.db'),
      );
      addTearDown(database.close);
      await database.initialize();
      final ids = _SequenceIdGenerator('unit-archive');
      final properties = SembastPropertyRepository(
        database: database,
        idGenerator: ids,
        clock: FixedClock(now),
      );
      final units = SembastUnitRepository(
        database: database,
        idGenerator: ids,
        clock: FixedClock(now),
      );
      final property = await properties.create(
        const CreatePropertyInput(
          landlordId: 'landlord-1',
          name: 'Archive Court',
          addressLine: '1 Archive Road',
          city: 'Kampala',
        ),
      );
      final unit = await units.create(
        CreateUnitInput(
          propertyId: property.id,
          landlordId: property.landlordId,
          label: 'A1',
          type: UnitType.apartment,
          status: UnitStatus.vacant,
          monthlyRentMinor: 150000000,
        ),
      );
      await _acknowledgeAll(database, now);

      final archived = await units.archive(unit.id);

      expect(archived.isArchived, isTrue);
      expect(archived.archivedAt, now);
      expect((await units.getAll()).map((item) => item.id), contains(unit.id));
      final archiveCommand = (await database.readOutbox()).single;
      expect(archiveCommand.entityType, OfflineEntityType.unit);
      expect(archiveCommand.operation, OutboxOperation.delete);
      expect(archiveCommand.payload['isDeleted'], isTrue);
      expect(archiveCommand.payload['deletedAt'], now.toIso8601String());

      await database.acknowledgeMutation(
        mutationId: archiveCommand.id,
        syncedAt: now,
        serverRevision: '2',
      );

      expect(await units.getAll(), isEmpty);
      expect(
        (await units.getAll(includeArchived: true)).single.isArchived,
        isTrue,
      );
      expect((await units.getById(unit.id))?.isArchived, isTrue);
    },
  );

  test(
    'unpublish queues a server-bound command and pauses visibility',
    () async {
      final database = OfflineDatabase(
        await databaseFactoryMemory.openDatabase('listing-unpublish.db'),
      );
      addTearDown(database.close);
      await database.initialize();
      final ids = _SequenceIdGenerator('listing-unpublish');
      final properties = SembastPropertyRepository(
        database: database,
        idGenerator: ids,
        clock: FixedClock(now),
      );
      final units = SembastUnitRepository(
        database: database,
        idGenerator: ids,
        clock: FixedClock(now),
      );
      final listings = SembastListingRepository(
        database: database,
        properties: properties,
        units: units,
        idGenerator: ids,
        clock: FixedClock(now),
      );
      final property = await properties.create(
        const CreatePropertyInput(
          landlordId: 'landlord-1',
          name: 'Listing Court',
          addressLine: '2 Listing Road',
          city: 'Kampala',
        ),
      );
      final unit = await units.create(
        CreateUnitInput(
          propertyId: property.id,
          landlordId: property.landlordId,
          label: 'B1',
          type: UnitType.apartment,
          status: UnitStatus.vacant,
          monthlyRentMinor: 175000000,
        ),
      );
      final draft = await listings.createDraft(
        CreateListingInput(
          unitId: unit.id,
          propertyId: property.id,
          landlordId: property.landlordId,
          title: 'B1 at Listing Court',
          description: 'A bright rental space in Kampala.',
          monthlyRentMinor: unit.monthlyRentMinor,
          city: property.city,
          neighborhood: 'Ntinda',
          contactPhone: '+256700000001',
        ),
      );
      await _acknowledgeAll(database, now);
      await listings.publish(draft.id);
      await _acknowledgeAll(database, now);
      expect((await listings.getById(draft.id))?.isPublic, isTrue);

      final unpublished = await listings.unpublish(draft.id);

      expect(unpublished.status, ListingStatus.paused);
      expect(unpublished.syncMetadata.state, EntitySyncState.pending);
      expect(await listings.getAll(publicOnly: true), isEmpty);
      final unpublishCommand = (await database.readOutbox()).single;
      expect(unpublishCommand.entityType, OfflineEntityType.listing);
      expect(unpublishCommand.operation, OutboxOperation.delete);

      await database.acknowledgeMutation(
        mutationId: unpublishCommand.id,
        syncedAt: now,
        serverRevision: '3',
      );
      final confirmed = await listings.getById(draft.id);
      expect(confirmed?.status, ListingStatus.paused);
      expect(confirmed?.syncMetadata.state, EntitySyncState.synced);
    },
  );
}

Future<void> _acknowledgeAll(OfflineDatabase database, DateTime now) async {
  for (final mutation in await database.readOutbox()) {
    await database.acknowledgeMutation(
      mutationId: mutation.id,
      syncedAt: now,
      serverRevision: '1',
    );
  }
}

final class _SequenceIdGenerator implements IdGenerator {
  _SequenceIdGenerator(this.prefix);

  final String prefix;
  int _value = 0;

  @override
  String generate() => '$prefix-${_value++}';
}
