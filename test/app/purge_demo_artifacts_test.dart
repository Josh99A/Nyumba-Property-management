import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_listing_repository.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_unit_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  group('purge demo artifacts', () {
    test(
      'purge removes stale demo fixtures an old build left behind',
      () async {
        // Reproduces the real situation: an older deployed build seeded the
        // anonymous browser workspace through the normal repository path (so
        // entities AND outbox intents exist), the workspace name never changed,
        // and remote pulls only merge — nothing ever removed the fixtures. A
        // returning visitor's public page kept listing "Kololo Garden Court".
        final database = OfflineDatabase(
          await databaseFactoryMemory.openDatabase('stale-anonymous.db'),
        );
        await database.initialize();
        addTearDown(database.close);

        final properties = SembastPropertyRepository(database: database);
        final units = SembastUnitRepository(database: database);
        final listings = SembastListingRepository(
          database: database,
          properties: properties,
          units: units,
        );

        // Build the stale fixtures directly, owned by the tell-tale
        // `demo-landlord-001` id that the sweep keys off.
        const demoLandlordId = 'demo-landlord-001';
        final demoProperty = await properties.create(
          const CreatePropertyInput(
            landlordId: demoLandlordId,
            name: 'Kololo Garden Court',
            addressLine: 'Argwings Kodhek Road',
            city: 'Kampala',
          ),
        );
        final demoUnit = await units.create(
          CreateUnitInput(
            propertyId: demoProperty.id,
            landlordId: demoLandlordId,
            label: 'Apartment A1',
            type: UnitType.apartment,
            status: UnitStatus.vacant,
            monthlyRentMinor: 120000000,
          ),
        );
        final draft = await listings.createDraft(
          CreateListingInput(
            unitId: demoUnit.id,
            propertyId: demoProperty.id,
            landlordId: demoLandlordId,
            title: 'Apartment A1 at Kololo Garden Court',
            description: 'A well maintained apartment in Kampala.',
            monthlyRentMinor: demoUnit.monthlyRentMinor,
            city: 'Kampala',
            contactPhone: '+256 700 000 000',
          ),
        );
        await listings.publish(draft.id);

        // A real record in the same workspace must survive the sweep.
        final real = await properties.create(
          const CreatePropertyInput(
            landlordId: 'x7Qm2LpV9aRt4KcW8bZnE5yGdJ1u',
            name: 'Ntinda Rise Apartments',
            addressLine: 'Plot 12 Ntinda Road',
            city: 'Kampala',
          ),
        );

        final removed = await database.purgeDemoArtifacts();
        expect(removed, greaterThan(0));

        expect(
          await listings.getAll(publicOnly: true),
          isEmpty,
          reason: 'the public catalogue must never show invented listings',
        );
        expect(await properties.getAll(landlordId: demoLandlordId), isEmpty);
        final survivors = await properties.getAll(
          landlordId: 'x7Qm2LpV9aRt4KcW8bZnE5yGdJ1u',
        );
        expect(survivors.map((p) => p.id), [real.id]);

        // The fixtures' sync intents must go with them: left behind they would
        // retry commands forever for aggregates that no longer exist. The real
        // property's intent must remain.
        final outbox = await database.readOutbox();
        expect(outbox.map((entry) => entry.entityId), [real.id]);

        // Re-running on a clean workspace is a no-op, since this executes on
        // every workspace open.
        expect(await database.purgeDemoArtifacts(), 0);
      },
    );
  });
}
