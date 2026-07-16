import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_listing_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/demo_data_seeder.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_unit_repository.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:sembast/sembast_memory.dart';

UserSession _session({
  required AppRole role,
  bool isDemo = false,
  bool isAnonymous = false,
}) => UserSession(
  userId: 'user-1',
  displayName: 'Joshua Mugisha',
  email: 'joshua@example.ug',
  role: role,
  isDemo: isDemo,
  isAnonymous: isAnonymous,
);

void main() {
  group('demo data quarantine', () {
    test('every real role is refused seeded data', () {
      for (final role in AppRole.values) {
        expect(
          seedsDemoData(_session(role: role)),
          isFalse,
          reason:
              '$role is a real account and must never see invented records.',
        );
      }
    });

    test('an anonymous visitor browses the real catalogue', () {
      expect(
        seedsDemoData(null),
        isFalse,
        reason: 'Public browsing reads publicListings, not fixtures.',
      );
      expect(
        seedsDemoData(_session(role: AppRole.client, isAnonymous: true)),
        isFalse,
      );
    });

    test('only an explicitly chosen demo role is seeded', () {
      for (final role in AppRole.values) {
        expect(seedsDemoData(_session(role: role, isDemo: true)), isTrue);
      }
    });

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
        final seeded = await DemoDataSeeder(
          properties: properties,
          units: units,
          listings: listings,
        ).seedIfEmpty(landlordId: 'demo-landlord-001');
        expect(seeded.seeded, isTrue);

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
        expect(
          await properties.getAll(landlordId: 'demo-landlord-001'),
          isEmpty,
        );
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
        // every non-demo open.
        expect(await database.purgeDemoArtifacts(), 0);
      },
    );

    test('seeding never keys off Firebase being unavailable', () {
      // main() swallows Firebase initialisation failures on purpose so the
      // offline workspace still opens. If seeding were gated on "no Firebase"
      // instead of "is demo", a startup hiccup would silently hand a real
      // landlord a portfolio of invented properties. seedsDemoData takes only
      // the session, so that mistake cannot be reintroduced by accident.
      expect(seedsDemoData(_session(role: AppRole.landlord)), isFalse);
      expect(
        seedsDemoData(_session(role: AppRole.landlord, isDemo: true)),
        isTrue,
      );
    });
  });
}
