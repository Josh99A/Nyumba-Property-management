import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/documents/nyumba_document_service.dart';
import '../../core/offline/offline_database.dart';
import '../../core/offline/remote_sync_gateway.dart';
import '../../core/offline/sync_engine.dart';
import '../../features/auth/application/session_controller.dart';
import '../../features/documents/data/sembast_lease_document_repository.dart';
import '../../features/documents/domain/lease_document.dart';
import '../../features/documents/domain/lease_document_repository.dart';
import '../../features/finance/data/sembast_rent_payment_repository.dart';
import '../../features/finance/domain/rent_payment.dart';
import '../../features/finance/domain/rent_payment_repository.dart';
import '../../features/maintenance/data/sembast_maintenance_repository.dart';
import '../../features/maintenance/domain/maintenance_request.dart';
import '../../features/maintenance/domain/maintenance_repository.dart';
import '../../features/tenants/data/sembast_tenancy_repository.dart';
import '../../features/tenants/domain/tenancy.dart';
import '../../features/tenants/domain/tenancy_repository.dart';
import '../../features/notices/data/sembast_notice_repository.dart';
import '../../features/notices/domain/notice.dart';
import '../../features/notices/domain/notice_repository.dart';
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
import '../../features/profile/data/sembast_user_settings_repository.dart';
import '../../features/profile/domain/user_settings.dart';
import '../../features/profile/domain/user_settings_repository.dart';
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
    required this.userSettings,
    required this.maintenance,
    required this.tenancies,
    required this.payments,
    required this.leaseDocuments,
    required this.notices,
  });

  final OfflineDatabase database;
  final PropertyRepository properties;
  final UnitRepository units;
  final ListingRepository listings;
  final ApplicationRepository applications;
  final SyncEngine syncEngine;
  final DocumentService documents;
  final UserSettingsRepository userSettings;
  final MaintenanceRepository maintenance;
  final TenancyRepository tenancies;
  final RentPaymentRepository payments;
  final LeaseDocumentRepository leaseDocuments;
  final NoticeRepository notices;

  /// Closing quarantines the workspace: the database file and its unsynced
  /// outbox stay on disk untouched for the next sign-in of this account.
  Future<void> close() => database.close();
}

/// Serializes workspace shutdown so a scope that is re-opened immediately
/// after sign-out never races its predecessor's close.
Future<void> _previousWorkspaceClosed = Future<void>.value();

final appDependenciesProvider =
    AsyncNotifierProvider<AppDependenciesController, AppDependencies>(
      AppDependenciesController.new,
    );

/// Builds one offline workspace per signed-in account (plus one anonymous
/// workspace for public browsing) and swaps it when the session changes.
/// Data belonging to the previous account is never deleted or read across
/// accounts; its workspace is simply closed.
class AppDependenciesController extends AsyncNotifier<AppDependencies> {
  @override
  Future<AppDependencies> build() async {
    final session = ref.watch(sessionControllerProvider);
    final scope = session == null ? 'anonymous' : 'account-${session.userId}';
    final dependencies = await createAppDependencies(scope: scope);
    ref.onDispose(() {
      _previousWorkspaceClosed = dependencies.close();
    });
    return dependencies;
  }
}

final portfolioPropertiesProvider = StreamProvider<List<Property>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.properties.watchAll();
});

final portfolioUnitsProvider = StreamProvider<List<Unit>>((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.units.watchAll();
});

final landlordListingsProvider = StreamProvider<List<Listing>>((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.listings.watchAll();
});

final publicListingsProvider = StreamProvider<List<Listing>>((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.listings.watchAll(publicOnly: true);
});

final rentalApplicationsProvider = StreamProvider<List<RentalApplication>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.applications.watchAll();
});

final outboxEntriesProvider = StreamProvider((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.database.watchOutbox();
});

final userSettingsProvider = StreamProvider.family<UserSettings?, String>((
  ref,
  userId,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.userSettings.watchByUserId(userId);
});

/// Application-level trigger for an immediate sync pass, used by screens
/// that offer a manual "sync now" affordance.
final manualSyncProvider = Provider<ManualSync>(ManualSync.new);

class ManualSync {
  const ManualSync(this._ref);

  final Ref _ref;

  Future<SyncRunReport> call() async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.syncEngine.syncPending();
  }
}

Future<AppDependencies> createAppDependencies({
  String scope = 'anonymous',
}) async {
  await _previousWorkspaceClosed;
  final database = await openScopedOfflineDatabase('workspace_v3_$scope');
  final properties = SembastPropertyRepository(database: database);
  final units = SembastUnitRepository(database: database);
  final listings = SembastListingRepository(
    database: database,
    properties: properties,
    units: units,
  );
  final applications = SembastApplicationRepository(database: database);
  final userSettings = SembastUserSettingsRepository(database: database);
  final maintenance = SembastMaintenanceRepository(database: database);
  final tenancies = SembastTenancyRepository(database: database);
  final payments = SembastRentPaymentRepository(database: database);
  final leaseDocuments = SembastLeaseDocumentRepository(database: database);
  final notices = SembastNoticeRepository(database: database);
  final gateway = _DemoRemoteSyncGateway();
  final syncEngine = SyncEngine(database: database, gateway: gateway);

  await _seedPortfolioIfNeeded(
    properties: properties,
    units: units,
    listings: listings,
  );
  await _seedMaintenanceIfNeeded(maintenance);
  await _seedTenanciesIfNeeded(tenancies);
  await _seedPaymentsIfNeeded(tenancies: tenancies, payments: payments);
  await _seedDocumentsIfNeeded(leaseDocuments);
  await _seedNoticesIfNeeded(notices);
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
    userSettings: userSettings,
    maintenance: maintenance,
    tenancies: tenancies,
    payments: payments,
    leaseDocuments: leaseDocuments,
    notices: notices,
  );
}

Future<void> _seedDocumentsIfNeeded(LeaseDocumentRepository documents) async {
  const landlordId = 'demo-landlord-001';
  final existing = await documents.getAll(landlordId: landlordId);
  if (existing.isNotEmpty) return;

  const seeds = <CreateLeaseDocumentInput>[
    CreateLeaseDocumentInput(
      landlordId: landlordId,
      type: LeaseDocumentType.receipt,
      recipient: 'Brian Okello',
      propertyName: 'Sunset Apartments',
      unitLabel: 'B5',
      amountMinor: 120000000,
      statusLabel: 'Paid',
    ),
    CreateLeaseDocumentInput(
      landlordId: landlordId,
      type: LeaseDocumentType.invoice,
      recipient: 'Peter Ssemwanga',
      propertyName: 'Greenview Court',
      unitLabel: 'A1',
      amountMinor: 110000000,
      statusLabel: 'Due',
    ),
    CreateLeaseDocumentInput(
      landlordId: landlordId,
      type: LeaseDocumentType.receipt,
      recipient: 'Grace Namuli',
      propertyName: 'Riverside Heights',
      unitLabel: 'D1',
      amountMinor: 140000000,
      statusLabel: 'Paid',
    ),
    CreateLeaseDocumentInput(
      landlordId: landlordId,
      type: LeaseDocumentType.invoice,
      recipient: 'Mary Nansubuga',
      propertyName: 'Nyumbani Gardens',
      unitLabel: 'C2',
      amountMinor: 130000000,
      statusLabel: 'Part paid',
    ),
    CreateLeaseDocumentInput(
      landlordId: landlordId,
      type: LeaseDocumentType.lease,
      recipient: 'Amina Kamau',
      tenantId: 'demo-tenant-001',
      propertyName: 'Sunset Apartments',
      unitLabel: 'B4',
      statusLabel: 'Signed',
    ),
  ];
  for (final seed in seeds) {
    await documents.create(seed);
  }
}

Future<void> _seedNoticesIfNeeded(NoticeRepository notices) async {
  const landlordId = 'demo-landlord-001';
  final existing = await notices.getAll(landlordId: landlordId);
  if (existing.isNotEmpty) return;

  await notices.create(
    const CreateNoticeInput(
      landlordId: landlordId,
      title: 'Planned water maintenance',
      body:
          'Water supply will be interrupted on Saturday between 09:00 and '
          '13:00 while the storage tanks are cleaned. Please store enough '
          'water for the morning.',
      audience: 'All tenants',
    ),
  );
}

Future<void> _seedPaymentsIfNeeded({
  required TenancyRepository tenancies,
  required RentPaymentRepository payments,
}) async {
  const landlordId = 'demo-landlord-001';
  final existing = await payments.getAll(landlordId: landlordId);
  if (existing.isNotEmpty) return;
  final ledger = await tenancies.getAll(landlordId: landlordId);
  if (ledger.isEmpty) return;

  Tenancy? byName(String name) {
    for (final tenancy in ledger) {
      if (tenancy.tenantName == name) return tenancy;
    }
    return null;
  }

  final seeds = <(String, int, String, String)>[
    ('Amina Kamau', 120000000, 'MTN Mobile Money', 'June 2026'),
    ('Brian Okello', 120000000, 'MTN Mobile Money', 'July 2026'),
    ('Grace Namuli', 140000000, 'Airtel Money', 'July 2026'),
    ('Mary Nansubuga', 95000000, 'Cash', 'July 2026'),
    ('Brian Okello', 120000000, 'Card (Bank)', 'June 2026'),
  ];
  for (final (name, amountMinor, method, period) in seeds) {
    final tenancy = byName(name);
    if (tenancy == null) continue;
    await payments.record(
      tenancy: tenancy,
      input: RecordRentPaymentInput(
        tenancyId: tenancy.id,
        amountMinor: amountMinor,
        method: method,
        period: period,
      ),
    );
  }
}

Future<void> _seedTenanciesIfNeeded(TenancyRepository tenancies) async {
  const landlordId = 'demo-landlord-001';
  final existing = await tenancies.getAll(landlordId: landlordId);
  if (existing.isNotEmpty) return;

  final seeds = <CreateTenancyInput>[
    CreateTenancyInput(
      landlordId: landlordId,
      tenantUserId: 'demo-tenant-001',
      tenantName: 'Amina Kamau',
      email: 'amina@demo.nyumba.ug',
      phone: '+256 772 000 200',
      unitLabel: 'B4',
      propertyName: 'Sunset Apartments',
      monthlyRentMinor: 120000000,
      openingBalanceMinor: 120000000,
      leaseStart: DateTime.utc(2026, 1, 1),
      leaseEnd: DateTime.utc(2027, 1, 1),
    ),
    CreateTenancyInput(
      landlordId: landlordId,
      tenantName: 'Brian Okello',
      email: 'brian.okello@example.com',
      phone: '+256 772 345 678',
      unitLabel: 'B5',
      propertyName: 'Sunset Apartments',
      monthlyRentMinor: 120000000,
      leaseStart: DateTime.utc(2026, 3, 1),
      leaseEnd: DateTime.utc(2027, 2, 28),
    ),
    CreateTenancyInput(
      landlordId: landlordId,
      tenantName: 'Grace Namuli',
      email: 'grace.namuli@example.com',
      phone: '+256 704 113 886',
      unitLabel: 'D1',
      propertyName: 'Riverside Heights',
      monthlyRentMinor: 140000000,
      leaseStart: DateTime.utc(2025, 12, 1),
      leaseEnd: DateTime.utc(2026, 11, 30),
    ),
    CreateTenancyInput(
      landlordId: landlordId,
      tenantName: 'Peter Ssemwanga',
      email: 'peter.ssemwanga@example.com',
      phone: '+256 753 902 118',
      unitLabel: 'A1',
      propertyName: 'Greenview Court',
      monthlyRentMinor: 110000000,
      openingBalanceMinor: 110000000,
      leaseStart: DateTime.utc(2026, 1, 1),
      leaseEnd: DateTime.utc(2026, 12, 31),
    ),
    CreateTenancyInput(
      landlordId: landlordId,
      tenantName: 'Mary Nansubuga',
      email: 'mary.nansubuga@example.com',
      phone: '+256 771 822 470',
      unitLabel: 'C2',
      propertyName: 'Nyumbani Gardens',
      monthlyRentMinor: 130000000,
      openingBalanceMinor: 35000000,
      leaseStart: DateTime.utc(2026, 5, 1),
      leaseEnd: DateTime.utc(2027, 4, 30),
    ),
  ];
  for (final seed in seeds) {
    await tenancies.create(seed);
  }
}

Future<void> _seedMaintenanceIfNeeded(MaintenanceRepository maintenance) async {
  const landlordId = 'demo-landlord-001';
  final existing = await maintenance.getAll(landlordId: landlordId);
  if (existing.isNotEmpty) return;

  const seeds = <CreateMaintenanceRequestInput>[
    CreateMaintenanceRequestInput(
      landlordId: landlordId,
      title: 'Leaking tap in kitchen',
      description:
          'The kitchen mixer tap drips continuously, even when fully closed.',
      location: 'Unit A2 · Greenview Court',
      reporterName: 'Alice Namutebi',
      category: 'Plumbing',
      priority: MaintenancePriority.urgent,
      tenantId: 'demo-tenant-001',
      allowAccess: true,
      photoCount: 2,
    ),
    CreateMaintenanceRequestInput(
      landlordId: landlordId,
      title: 'No power in the living room',
      description: 'Sockets on the living-room wall stopped working overnight.',
      location: 'Unit D3 · Riverside Heights',
      reporterName: 'John M.',
      category: 'Electrical',
      priority: MaintenancePriority.high,
    ),
    CreateMaintenanceRequestInput(
      landlordId: landlordId,
      title: 'Water not draining in bathroom',
      description: 'The shower drain backs up after a few minutes of use.',
      location: 'Unit B1 · Sunset Apartments',
      reporterName: 'Sarah W.',
      category: 'Plumbing',
      priority: MaintenancePriority.high,
    ),
    CreateMaintenanceRequestInput(
      landlordId: landlordId,
      title: 'Bedroom door lock is loose',
      description: 'The lock barrel turns without engaging; needs refitting.',
      location: 'Unit C1 · Nyumbani Gardens',
      reporterName: 'David Kato',
      category: 'Carpentry',
      priority: MaintenancePriority.normal,
      tenantId: 'demo-tenant-001',
    ),
  ];
  final created = <MaintenanceRequest>[];
  for (final seed in seeds) {
    created.add(await maintenance.create(seed));
  }
  await maintenance.transition(
    TransitionMaintenanceInput(
      requestId: created[1].id,
      status: MaintenanceStatus.inProgress,
      assignee: 'Kato Electricals',
    ),
  );
  await maintenance.transition(
    TransitionMaintenanceInput(
      requestId: created[3].id,
      status: MaintenanceStatus.scheduled,
      assignee: 'Jenga Fixers',
      appointment: 'Tomorrow • 10:00–12:00',
    ),
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
      city: 'Kampala',
      description: 'Quiet apartment living with secure parking in Ntinda.',
      units: [
        _UnitSeed(
          'B4',
          UnitType.apartment,
          UnitStatus.occupied,
          120000000,
          2,
          2,
        ),
        _UnitSeed('B5', UnitType.apartment, UnitStatus.vacant, 120000000, 2, 2),
        _UnitSeed(
          'C1',
          UnitType.apartment,
          UnitStatus.occupied,
          150000000,
          3,
          2,
        ),
      ],
    ),
    const _PropertySeed(
      name: 'Riverside Heights',
      address: 'Riverside Drive',
      city: 'Kampala',
      description:
          'Bright homes close to offices, schools, and everyday services.',
      units: [
        _UnitSeed(
          'D1',
          UnitType.apartment,
          UnitStatus.occupied,
          140000000,
          2,
          2,
        ),
        _UnitSeed('D2', UnitType.apartment, UnitStatus.vacant, 140000000, 2, 2),
      ],
    ),
    const _PropertySeed(
      name: 'Nyumbani Gardens',
      address: 'Ggaba Road',
      city: 'Kampala',
      description: 'Family homes with green shared spaces and reliable water.',
      units: [
        _UnitSeed('C2', UnitType.house, UnitStatus.occupied, 130000000, 3, 2),
        _UnitSeed('C3', UnitType.house, UnitStatus.occupied, 130000000, 3, 2),
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
          city: property.city,
          neighborhood: seed.name.startsWith('Sunset')
              ? 'Ntinda'
              : seed.name.startsWith('Riverside')
              ? 'Riverside'
              : 'Ggaba',
          minimumLeaseMonths: 12,
          securityDepositMinor: unit.monthlyRentMinor,
          utilitiesIncluded: const ['Water'],
          parkingSpaces: 1,
          viewingInstructions: 'Request a viewing through Nyumba.',
          contactPhone: '+256 772 000 100',
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
