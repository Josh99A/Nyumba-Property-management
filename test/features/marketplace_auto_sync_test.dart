import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/core/documents/nyumba_document_service.dart';
import 'package:nyumba_property_management/core/offline/firebase_remote_sync_gateway.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:nyumba_property_management/core/offline/sync_engine.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/documents/data/sembast_lease_document_repository.dart';
import 'package:nyumba_property_management/features/finance/data/sembast_rent_payment_repository.dart';
import 'package:nyumba_property_management/features/maintenance/data/sembast_maintenance_repository.dart';
import 'package:nyumba_property_management/features/marketplace/application/marketplace_use_cases.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_application_repository.dart';
import 'package:nyumba_property_management/features/marketplace/data/sembast_listing_repository.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/notices/data/sembast_notice_repository.dart';
import 'package:nyumba_property_management/features/notifications/data/sembast_app_notification_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_property_repository.dart';
import 'package:nyumba_property_management/features/portfolio/data/sembast_unit_repository.dart';
import 'package:nyumba_property_management/features/portfolio/application/portfolio_use_cases.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:nyumba_property_management/features/profile/data/sembast_user_settings_repository.dart';
import 'package:nyumba_property_management/features/subscriptions/data/sembast_subscription_plan_repository.dart';
import 'package:nyumba_property_management/features/tenants/data/sembast_tenancy_repository.dart';
import 'package:sembast/sembast_memory.dart';

/// Session stub that never touches Firebase.
class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final UserSession? _session;

  @override
  UserSession? build() => _session;
}

/// Serves a pre-built workspace instead of opening one per session change.
class _FixedDependenciesController extends AppDependenciesController {
  _FixedDependenciesController(this._dependencies);

  final AppDependencies _dependencies;

  @override
  Future<AppDependencies> build() async => _dependencies;
}

void main() {
  const landlord = UserSession(
    userId: 'landlord-1',
    displayName: 'Sandra Nakato',
    email: 'sandra@acaciahomes.ug',
    role: AppRole.landlord,
  );

  test('publishing a listing pushes the outbox without a manual sync', () async {
    final database = OfflineDatabase(
      await databaseFactoryMemory.openDatabase('marketplace-auto-sync.db'),
    );
    addTearDown(database.close);
    await database.initialize();

    final properties = SembastPropertyRepository(database: database);
    final units = SembastUnitRepository(database: database);
    final listings = SembastListingRepository(
      database: database,
      properties: properties,
      units: units,
    );

    // Records every envelope the app would send; per-aggregate versions mimic
    // the server so publish gets the expectedVersion of the acknowledged draft.
    final sent = <Map<String, Object?>>[];
    final versions = <String, int>{};
    final gateway = FirebaseRemoteSyncGateway(
      installationId: 'test-install',
      appVersion: '1.0.0',
      platform: 'test',
      invoke: (envelope) async {
        sent.add(envelope);
        final aggregateId = envelope['aggregateId'].toString();
        final version = (versions[aggregateId] ?? 0) + 1;
        versions[aggregateId] = version;
        return <String, Object?>{
          'status': 'applied',
          'serverVersion': version,
          'serverUpdatedAt': DateTime.utc(2026, 7, 15, 9).toIso8601String(),
        };
      },
    );

    final dependencies = AppDependencies(
      database: database,
      properties: properties,
      units: units,
      listings: listings,
      applications: SembastApplicationRepository(database: database),
      syncEngine: SyncEngine(database: database, gateway: gateway),
      documents: const PdfDocumentService(),
      userSettings: SembastUserSettingsRepository(database: database),
      maintenance: SembastMaintenanceRepository(database: database),
      tenancies: SembastTenancyRepository(database: database),
      payments: SembastRentPaymentRepository(database: database),
      leaseDocuments: SembastLeaseDocumentRepository(database: database),
      notices: SembastNoticeRepository(database: database),
      notifications: SembastAppNotificationRepository(database: database),
      subscriptionPlans: SembastSubscriptionPlanRepository(database: database),
    );

    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _FixedSessionController(landlord),
        ),
        appDependenciesProvider.overrideWith(
          () => _FixedDependenciesController(dependencies),
        ),
      ],
    );
    addTearDown(container.dispose);

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
        amenities: const ['Secure parking'],
      ),
    );

    final draft = await container.read(createListingDraftProvider)(
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
    await _drainOutbox(database);
    expect(_commandTypes(sent), contains('listing.saveDraft'));

    await container.read(publishListingProvider)(draft.id);
    await _drainOutbox(database);
    expect(_commandTypes(sent), contains('listing.publish'));

    // Server acknowledgement is what makes a listing public; the whole point
    // of the automatic push is that this happens without the manual sync
    // button ever being pressed.
    final publicListings = await listings.getAll(publicOnly: true);
    expect(publicListings.map((listing) => listing.id), [draft.id]);

    final availabilityResult = await container.read(updateUnitProvider)(
      unit.copyWith(status: UnitStatus.maintenance),
    );
    expect(availabilityResult.unpublishedListing?.id, draft.id);
    expect(await listings.getAll(publicOnly: true), isEmpty);
    await _drainOutbox(database);

    final commandTypes = _commandTypes(sent).toList(growable: false);
    expect(
      commandTypes,
      containsAllInOrder(['listing.unpublish', 'unit.update']),
    );
    expect((await units.getById(unit.id))?.status, UnitStatus.maintenance);
  });
}

Iterable<String> _commandTypes(List<Map<String, Object?>> sent) =>
    sent.map((envelope) => envelope['type'].toString());

/// Waits for the fire-and-forget sync kicked off by the use case to finish.
Future<void> _drainOutbox(OfflineDatabase database) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (await database.outboxCount() == 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Outbox was not drained by the automatic sync.');
}
