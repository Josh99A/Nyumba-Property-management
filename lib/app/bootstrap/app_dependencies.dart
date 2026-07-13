import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/documents/nyumba_document_service.dart';
import '../../core/offline/offline_database.dart';
import '../../core/offline/remote_sync_gateway.dart';
import '../../core/offline/sync_engine.dart';
import '../../features/marketplace/data/sembast_application_repository.dart';
import '../../features/marketplace/data/sembast_listing_repository.dart';
import '../../features/marketplace/domain/application_repository.dart';
import '../../features/marketplace/domain/application.dart';
import '../../features/marketplace/domain/listing.dart';
import '../../features/marketplace/domain/listing_repository.dart';
import '../../features/portfolio/data/demo_data_seeder.dart';
import '../../features/portfolio/data/sembast_property_repository.dart';
import '../../features/portfolio/data/sembast_unit_repository.dart';
import '../../features/portfolio/domain/property.dart';
import '../../features/portfolio/domain/property_repository.dart';
import '../../features/portfolio/domain/unit.dart';
import '../../features/portfolio/domain/unit_repository.dart';
import '../bootstrap/local_database_opener.dart';

class AppDependencies {
  const AppDependencies({
    required this.database,
    required this.properties,
    required this.units,
    required this.listings,
    required this.applications,
    required this.syncEngine,
    required this.documents,
  });

  final OfflineDatabase database;
  final PropertyRepository properties;
  final UnitRepository units;
  final ListingRepository listings;
  final ApplicationRepository applications;
  final SyncEngine syncEngine;
  final DocumentService documents;
}

final appDependenciesProvider = Provider<AppDependencies>((ref) {
  throw StateError('AppDependencies must be overridden during bootstrap.');
});

final portfolioPropertiesProvider = StreamProvider<List<Property>>((ref) {
  return ref.watch(appDependenciesProvider).properties.watchAll();
});

final portfolioUnitsProvider = StreamProvider<List<Unit>>((ref) {
  return ref.watch(appDependenciesProvider).units.watchAll();
});

final landlordListingsProvider = StreamProvider<List<Listing>>((ref) {
  return ref.watch(appDependenciesProvider).listings.watchAll();
});

final publicListingsProvider = StreamProvider<List<Listing>>((ref) {
  return ref.watch(appDependenciesProvider).listings.watchAll(publicOnly: true);
});

final rentalApplicationsProvider = StreamProvider<List<RentalApplication>>((
  ref,
) {
  return ref.watch(appDependenciesProvider).applications.watchAll();
});

final outboxEntriesProvider = StreamProvider((ref) {
  return ref.watch(appDependenciesProvider).database.watchOutbox();
});

Future<AppDependencies> createAppDependencies() async {
  final database = await openScopedOfflineDatabase('workspace_v1');
  final properties = SembastPropertyRepository(database: database);
  final units = SembastUnitRepository(database: database);
  final listings = SembastListingRepository(database: database, units: units);
  final applications = SembastApplicationRepository(database: database);
  final gateway = _DemoRemoteSyncGateway();
  final syncEngine = SyncEngine(database: database, gateway: gateway);

  await _seedPortfolioIfNeeded(
    properties: properties,
    units: units,
    listings: listings,
  );
  // The demo gateway behaves like an idempotent callable backend. Real Firebase
  // composition replaces only this boundary; feature repositories stay local.
  await syncEngine.syncPending(maxMutations: 200);

  return AppDependencies(
    database: database,
    properties: properties,
    units: units,
    listings: listings,
    applications: applications,
    syncEngine: syncEngine,
    documents: const PdfDocumentService(),
  );
}

Future<void> _seedPortfolioIfNeeded({
  required PropertyRepository properties,
  required UnitRepository units,
  required ListingRepository listings,
}) async {
  const landlordId = 'demo-landlord-001';
  final existing = await properties.getAll(landlordId: landlordId);
  if (existing.isNotEmpty) return;

  await DemoDataSeeder(
    properties: properties,
    units: units,
    listings: listings,
  ).seedIfEmpty(landlordId: landlordId);

  final seeds = <_PropertySeed>[
    const _PropertySeed(
      name: 'Sunset Apartments',
      address: 'Muthangari Drive',
      city: 'Nairobi',
      description: 'Quiet apartment living with secure parking in Westlands.',
      units: [
        _UnitSeed('B4', UnitType.apartment, UnitStatus.occupied, 4500000, 2, 2),
        _UnitSeed('B5', UnitType.apartment, UnitStatus.vacant, 4500000, 2, 2),
        _UnitSeed('C1', UnitType.apartment, UnitStatus.occupied, 5200000, 3, 2),
      ],
    ),
    const _PropertySeed(
      name: 'Riverside Heights',
      address: 'Riverside Drive',
      city: 'Nairobi',
      description:
          'Bright homes close to offices, schools, and everyday services.',
      units: [
        _UnitSeed('D1', UnitType.apartment, UnitStatus.occupied, 5000000, 2, 2),
        _UnitSeed('D2', UnitType.apartment, UnitStatus.vacant, 5000000, 2, 2),
      ],
    ),
    const _PropertySeed(
      name: 'Nyumbani Gardens',
      address: 'Kiambu Road',
      city: 'Nairobi',
      description: 'Family homes with green shared spaces and reliable water.',
      units: [
        _UnitSeed('C2', UnitType.house, UnitStatus.occupied, 4750000, 3, 2),
        _UnitSeed('C3', UnitType.house, UnitStatus.occupied, 4750000, 3, 2),
      ],
    ),
  ];

  for (final seed in seeds) {
    final property = await properties.create(
      CreatePropertyInput(
        landlordId: landlordId,
        name: seed.name,
        addressLine: seed.address,
        city: seed.city,
        description: seed.description,
      ),
    );
    for (final unitSeed in seed.units) {
      final unit = await units.create(
        CreateUnitInput(
          propertyId: property.id,
          landlordId: landlordId,
          label: unitSeed.label,
          type: unitSeed.type,
          status: unitSeed.status,
          monthlyRentMinor: unitSeed.rentMinor,
          bedrooms: unitSeed.bedrooms,
          bathrooms: unitSeed.bathrooms,
          amenities: const ['Secure parking', 'Backup water'],
        ),
      );
      if (!unit.canBeAdvertised) continue;
      final draft = await listings.createDraft(
        CreateListingInput(
          unitId: unit.id,
          propertyId: property.id,
          landlordId: landlordId,
          title: '${unit.label} at ${property.name}',
          description: '${seed.description} Available now in ${seed.city}.',
          monthlyRentMinor: unit.monthlyRentMinor,
          contactPhone: '+254 712 000 100',
        ),
      );
      await listings.publish(draft.id);
    }
  }
}

class _DemoRemoteSyncGateway implements RemoteSyncGateway {
  final Set<String> _applied = <String>{};

  @override
  Future<RemoteWriteResult> push(RemoteMutation mutation) async {
    await Future<void>.delayed(const Duration(milliseconds: 8));
    final duplicate = !_applied.add(mutation.idempotencyKey);
    return RemoteWriteResult(
      committedAt: DateTime.now().toUtc(),
      serverRevision: 'demo-${mutation.mutationId}',
      wasAlreadyApplied: duplicate,
    );
  }
}

class _PropertySeed {
  const _PropertySeed({
    required this.name,
    required this.address,
    required this.city,
    required this.description,
    required this.units,
  });

  final String name;
  final String address;
  final String city;
  final String description;
  final List<_UnitSeed> units;
}

class _UnitSeed {
  const _UnitSeed(
    this.label,
    this.type,
    this.status,
    this.rentMinor,
    this.bedrooms,
    this.bathrooms,
  );

  final String label;
  final UnitType type;
  final UnitStatus status;
  final int rentMinor;
  final int bedrooms;
  final int bathrooms;
}
