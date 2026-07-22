import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/documents/nyumba_document_service.dart';
import '../../core/offline/offline_database.dart';
import '../../core/offline/in_memory_sync_gateway.dart';
import '../../core/offline/firebase_remote_sync_gateway.dart';
import '../../core/offline/offline_entity.dart';
import '../../core/offline/network_status.dart';
import '../../core/offline/reconnect_sync_trigger.dart';
import '../../core/offline/remote_pull_gateway.dart';
import '../../core/offline/sync_engine.dart';
import '../../features/auth/application/session_controller.dart';
import '../../features/auth/domain/user_session.dart';
import '../../features/documents/data/sembast_lease_document_repository.dart';
import '../../features/documents/domain/lease_document_repository.dart';
import '../../features/finance/data/sembast_rent_payment_repository.dart';
import '../../features/finance/domain/rent_payment_repository.dart';
import '../../features/maintenance/data/sembast_maintenance_repository.dart';
import '../../features/maintenance/domain/maintenance_repository.dart';
import '../../features/tenants/data/sembast_tenancy_repository.dart';
import '../../features/tenants/domain/tenancy_repository.dart';
import '../../features/notices/data/sembast_notice_repository.dart';
import '../../features/notices/domain/notice_repository.dart';
import '../../features/notifications/data/sembast_app_notification_repository.dart';
import '../../features/notifications/domain/app_notification_repository.dart';
import '../../features/marketplace/data/mappers/listing_mapper.dart';
import '../../features/marketplace/data/sembast_application_repository.dart';
import '../../features/marketplace/data/sembast_listing_repository.dart';
import '../../features/marketplace/domain/application_repository.dart';
import '../../features/marketplace/domain/application.dart';
import '../../features/marketplace/domain/listing.dart';
import '../../features/marketplace/domain/listing_repository.dart';
import '../../features/portfolio/data/sembast_property_repository.dart';
import '../../features/portfolio/data/sembast_unit_repository.dart';
import '../../features/portfolio/domain/property.dart';
import '../../features/portfolio/domain/property_repository.dart';
import '../../features/portfolio/domain/unit.dart';
import '../../features/portfolio/domain/unit_repository.dart';
import '../../features/staff/domain/staff_permission.dart';
import '../../features/staff/data/sembast_staff_repository.dart';
import '../../features/staff/domain/staff_repository.dart';
import '../../features/subscriptions/data/sembast_subscription_plan_repository.dart';
import '../../features/subscriptions/domain/subscription_plan_repository.dart';
import '../../features/profile/data/sembast_user_settings_repository.dart';
import '../../features/profile/domain/user_settings.dart';
import '../../features/profile/domain/user_settings_repository.dart';
import '../bootstrap/local_database_opener.dart';
import '../bootstrap/resume_sync_trigger.dart';

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
    required this.notifications,
    required this.subscriptionPlans,
    required this.staff,
    this.remotePullCoordinator,
    this.reconnectSyncTrigger,
    this.resumeSyncTrigger,
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
  final AppNotificationRepository notifications;
  final SubscriptionPlanRepository subscriptionPlans;
  final StaffRepository staff;
  final RemotePullCoordinator? remotePullCoordinator;
  final ReconnectSyncTrigger? reconnectSyncTrigger;
  final ResumeSyncTrigger? resumeSyncTrigger;

  /// Closing quarantines the workspace: the database file and its unsynced
  /// outbox stay on disk untouched for the next sign-in of this account.
  Future<void> close() async {
    // Both triggers stop listening immediately and then quiesce: closing may
    // wait on the same in-flight engine run, so start both before awaiting
    // either. The database must not close under an active sync pass.
    final resumeClosed = resumeSyncTrigger?.close();
    final reconnectClosed = reconnectSyncTrigger?.close();
    await resumeClosed;
    await reconnectClosed;
    await remotePullCoordinator?.close();
    await database.close();
  }
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
    final dependencies = await createAppDependencies(
      scope: scope,
      session: session,
    );
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

/// Workspace-level view of the server link, for the top-bar indicator.
enum CloudStatus { connecting, live, failed, local }

/// Reports whether this workspace is genuinely reading from the server.
///
/// A workspace with no pull coordinator is not cloud-backed at all (a build
/// without Firebase configuration), which must read as [CloudStatus.local]
/// rather than a misleading offline state. While the workspace itself is still
/// opening, the honest answer is [connecting].
final cloudStatusProvider = StreamProvider<CloudStatus>((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  final coordinator = deps.remotePullCoordinator;
  if (coordinator == null) {
    yield CloudStatus.local;
    return;
  }
  yield _cloudStatus(coordinator.linkState);
  yield* coordinator.linkStates.map(_cloudStatus);
});

CloudStatus _cloudStatus(CloudLinkState state) => switch (state) {
  CloudLinkState.connecting => CloudStatus.connecting,
  CloudLinkState.live => CloudStatus.live,
  CloudLinkState.failed => CloudStatus.failed,
};

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
  UserSession? session,
}) async {
  await _previousWorkspaceClosed;
  final database = await openScopedOfflineDatabase('workspace_v3_$scope');
  // Older builds seeded demo fixtures into the anonymous workspace, and remote
  // pulls never delete, so returning visitors would keep seeing "Kololo Garden
  // Court" forever. Real workspaces hold only real data.
  await database.purgeDemoArtifacts();
  // Listings pulled by older builds lack fields the current mapper requires
  // (the public projection once arrived without propertyId/unitId/landlordId),
  // and the merge never repairs a record whose projection version has not
  // advanced. Drop what this build cannot read; the next server snapshot
  // rewrites those records in the current shape.
  await database.purgeUndecodable(
    OfflineEntityType.listing,
    ListingMapper.canDecode,
  );
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
  final notifications = SembastAppNotificationRepository(database: database);
  final subscriptionPlans = SembastSubscriptionPlanRepository(
    database: database,
  );
  final staff = SembastStaffRepository(database);
  // Public browsing is unauthenticated but still server-backed: `publicListings`
  // is world-readable, so an anonymous visitor reads the real catalogue.
  final usesFirebase = Firebase.apps.isNotEmpty;
  final isAuthenticated = session != null;
  final usesRemoteGateway = usesFirebase && isAuthenticated;
  final gateway = usesRemoteGateway
      ? await FirebaseRemoteSyncGateway.create()
      : InMemorySyncGateway();
  // Connectivity gating and reconnect-triggered flushes only make sense when
  // pushes actually cross the network. The in-memory gateway works offline;
  // gating it on connectivity would strand outbox entries for no reason.
  final NetworkStatus networkStatus = usesRemoteGateway
      ? ConnectivityNetworkStatus()
      : const AlwaysOnlineNetworkStatus();
  final syncEngine = SyncEngine(
    database: database,
    gateway: gateway,
    networkStatus: networkStatus,
  );
  final reconnectSyncTrigger = usesRemoteGateway
      ? ReconnectSyncTrigger(
          syncEngine: syncEngine,
          networkStatus: networkStatus,
        )
      : null;
  final resumeSyncTrigger = usesRemoteGateway
      ? ResumeSyncTrigger(syncEngine: syncEngine)
      : null;
  RemotePullCoordinator? remotePullCoordinator;

  if (usesFirebase) {
    remotePullCoordinator = RemotePullCoordinator(
      database: database,
      gateway: FirestoreRemotePullGateway(),
    );
    remotePullCoordinator.watch(OfflineEntityType.listing, publicOnly: true);
    remotePullCoordinator.watch(
      OfflineEntityType.planCatalog,
      publicOnly: true,
    );
    if (session == null) {
      // Anonymous visitor: the public catalogue is the only readable scope.
    } else {
      // Every authenticated actor reads the same UID-scoped, server-owned
      // notification shape. This is deliberately independent of the divergent
      // landlord/tenant/client aggregate projections below.
      remotePullCoordinator.watch(
        OfflineEntityType.notification,
        userUid: session.userId,
      );
    }
    if (session == null) {
      // Anonymous visitor has no private inbox.
    } else if (session.role == AppRole.superAdmin ||
        session.role == AppRole.admin) {
      // Same constraint as the landlord scope: an administrative pull reads the
      // canonical collection unfiltered, so it is limited to types whose server
      // document the client's mapper can actually parse. tenancy, payment,
      // invoice, maintenance, document, and notice were all pulled here and all
      // threw on read — `tenantRecords` has no lease term, `payments` has no
      // tenant or property names, and so on.
      //
      // Restoring them needs an administrative read model, the same shape the
      // landlordPortals projections publish but unscoped by owner.
      for (final type in const [
        OfflineEntityType.property,
        OfflineEntityType.unit,
        OfflineEntityType.listing,
      ]) {
        remotePullCoordinator.watch(type, administrativeScope: true);
      }
    } else if (session.role == AppRole.landlord ||
        session.role == AppRole.staff) {
      // Only types with a landlord read source; see
      // FirestoreRemotePullGateway.landlordReadSource. Tenancies and payments
      // come from server-owned landlordPortals projections because no canonical
      // collection can rebuild them. Maintenance, notices, and documents still
      // have no landlord read shape and are therefore not pulled — a landlord
      // sees only what this device recorded until those projections exist.
      //
      // A staff member reads the OWNER's workspace, so the pull is keyed to the
      // owner's uid (effectiveWorkspaceId), and Firestore Rules authorize it
      // through the membership doc.
      //
      // Each pull is keyed to the capability that opens it in Firestore Rules,
      // so a staff member granted only part of the workspace never fires a read
      // the server would deny. An owner holds every capability.
      const workspacePulls = <OfflineEntityType, StaffPermission>{
        OfflineEntityType.property: StaffPermission.manageProperties,
        OfflineEntityType.unit: StaffPermission.manageProperties,
        OfflineEntityType.listing: StaffPermission.manageListings,
        OfflineEntityType.tenancy: StaffPermission.manageTenants,
        OfflineEntityType.payment: StaffPermission.manageBilling,
      };
      if (session.isWorkspaceOwner) {
        remotePullCoordinator.watch(
          OfflineEntityType.staffInvite,
          landlordId: session.effectiveWorkspaceId,
        );
      }
      for (final pull in workspacePulls.entries) {
        if (!session.can(pull.value)) continue;
        remotePullCoordinator.watch(
          pull.key,
          landlordId: session.effectiveWorkspaceId,
        );
      }
    } else if (session.role == AppRole.tenant) {
      // Deliberately empty. The tenantPortals projections are security
      // whitelists over single canonical documents, and none of them carries
      // the shape its Dart mapper demands: MaintenanceRequestMapper requires
      // reference/landlordId/location/reporterName, NoticeMapper requires
      // reference/audience/status against a projection that has publishState,
      // and a tenant Tenancy would need fields spread across leases and
      // tenantRecords. Pulling them wrote raw server JSON into the local stores
      // and the next read threw a FormatException, so this never worked — it
      // only looked like it did.
      //
      // Landlord tenancies/payments are fixed by the landlordPortals read
      // models above. The tenant equivalent is not a copy of that work: the
      // client's tenant-side models demand landlordId, which these projections
      // withhold from tenants on purpose. Reconciling that is a product and
      // security decision, not a mechanical reshape.
      //
      // Until then a tenant sees only locally recorded data, which is honest
      // rather than a crash. See docs/architecture/offline-sync.md.
    } else if (session.role == AppRole.client) {
      // Also empty, for the same reason: clientApplicationProjection publishes
      // displayName/email/phone, while ApplicationMapper requires
      // applicantName/applicantEmail/applicantPhone plus unitId, propertyId,
      // and applicantId — fields the projection does not carry and, for the
      // unit and property IDs, deliberately withholds from a prospect who has
      // only ever seen a public listing.
      //
      // A prospect still sees applications this device submitted; they just do
      // not follow them to another device yet.
    }
    await syncEngine.syncPending(maxMutations: 200);
  }

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
    notifications: notifications,
    subscriptionPlans: subscriptionPlans,
    staff: staff,
    remotePullCoordinator: remotePullCoordinator,
    reconnectSyncTrigger: reconnectSyncTrigger,
    resumeSyncTrigger: resumeSyncTrigger,
  );
}
