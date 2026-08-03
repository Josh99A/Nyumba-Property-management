import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/perf_trace.dart';
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
import '../../features/finance/data/cloud_rent_payment_repository.dart';
import '../../features/finance/domain/rent_payment_repository.dart';
import '../../features/feedback/data/sembast_feedback_repository.dart';
import '../../features/support/data/sembast_support_repository.dart';
import '../../features/support/domain/support_repository.dart';
import '../../features/maintenance/data/sembast_maintenance_repository.dart';
import '../../features/maintenance/domain/maintenance_repository.dart';
import '../../features/reviews/data/sembast_review_repository.dart';
import '../../features/reviews/domain/review_repository.dart';
import '../../features/tenants/data/cloud_tenancy_repository.dart';
import '../../features/tenants/domain/tenancy_repository.dart';
import '../../features/notices/data/sembast_notice_repository.dart';
import '../../features/notices/domain/notice_repository.dart';
import '../../features/notifications/data/sembast_app_notification_repository.dart';
import '../../features/notifications/domain/app_notification_repository.dart';
import '../../features/marketplace/data/mappers/listing_mapper.dart';
import '../../features/marketplace/data/sembast_application_repository.dart';
import '../../features/marketplace/data/cloud_listing_repository.dart';
import '../../features/marketplace/domain/application_repository.dart';
import '../../features/marketplace/domain/application.dart';
import '../../features/marketplace/domain/listing.dart';
import '../../features/marketplace/domain/listing_repository.dart';
import '../../core/cloud/cloud_cache.dart';
import '../../core/cloud/cloud_data.dart';
import '../../core/cloud/cloud_read_gateway.dart';
import '../../core/cloud/cloud_reader.dart';
import '../../core/cloud/command_dispatcher.dart';
import '../../core/cloud/connection_status.dart';
import '../../core/cloud/firebase_command_gateway.dart';
import '../../core/cloud/unavailable_gateways.dart';
import '../../features/portfolio/data/cloud_property_repository.dart';
import '../../features/portfolio/data/cloud_unit_repository.dart';
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

/// Resolves a storage reference to a URL an image widget can fetch.
///
/// Media used to be pulled down as raw bytes through the Storage SDK. That put
/// every photo outside both the browser's HTTP cache and any on-device disk
/// cache, so a cold start re-downloaded the whole gallery over mobile data and
/// the only thing standing between a user and that cost was an in-memory map
/// that a profile switch discarded. Handing the image layer a URL instead lets
/// the platform's own caches do their job.
typedef PropertyMediaUrlResolver = Future<String?> Function(String reference);

class AppDependencies {
  const AppDependencies({
    required this.database,
    required this.properties,
    required this.units,
    required this.listings,
    required this.publicListings,
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
    required this.reviews,
    required this.feedback,
    required this.support,
    this.remotePullCoordinator,
    this.reconnectSyncTrigger,
    this.resumeSyncTrigger,
    this.propertyMediaUrlResolver,
  });

  final OfflineDatabase database;
  final PropertyRepository properties;
  final UnitRepository units;
  final ListingRepository listings;
  final ListingRepository publicListings;
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
  final ReviewRepository reviews;
  final FeedbackRepository feedback;
  final SupportRepository support;
  final RemotePullCoordinator? remotePullCoordinator;
  final ReconnectSyncTrigger? reconnectSyncTrigger;
  final ResumeSyncTrigger? resumeSyncTrigger;
  final PropertyMediaUrlResolver? propertyMediaUrlResolver;

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

/// One offline mirror per account AND active profile: an admin's
/// platform-wide pulls must never surface in the same user's landlord views,
/// so each role opens its own database. Tenants keep the legacy unsuffixed
/// scope because their data is locally recorded and has no server pull to
/// rebuild it from; every other role re-syncs on first open of its own scope.
@visibleForTesting
String workspaceScopeFor(UserSession? session) {
  if (session == null) return 'anonymous';
  if (session.role == AppRole.tenant) return 'account-${session.userId}';

  final roleScope = 'account-${session.userId}--${session.role.name}';
  if (session.role != AppRole.staff) return roleScope;
  final workspaceId =
      session.activeProfile.workspaceId?.trim() ?? session.workspaceId?.trim();
  return workspaceId == null || workspaceId.isEmpty
      ? roleScope
      : '$roleScope--workspace-$workspaceId';
}

/// Which authorized projection this session reads from.
///
/// This names the read Firestore Rules will actually allow, not a filter the
/// client picked for convenience. An anonymous visitor gets exactly one scope,
/// and it is the world-readable catalogue.
@visibleForTesting
CloudScope cloudScopeFor(UserSession? session) {
  if (session == null) return const PublicScope();
  return switch (session.role) {
    AppRole.superAdmin || AppRole.admin => const AdministrativeScope(),
    // Staff read the owner's workspace; Rules authorize it through the
    // membership document, so the key is the owner's uid either way.
    AppRole.landlord ||
    AppRole.staff => LandlordScope(session.effectiveWorkspaceId),
    AppRole.tenant => TenantScope(session.userId),
    AppRole.client => ProspectScope(session.userId),
  };
}

/// Serializes workspace shutdown so a scope that is re-opened immediately
/// after sign-out never races its predecessor's close.
Future<void> _previousWorkspaceClosed = Future<void>.value();

final appDependenciesProvider =
    AsyncNotifierProvider<AppDependenciesController, AppDependencies>(
      AppDependenciesController.new,
    );

final propertyMediaUrlResolverProvider = Provider<PropertyMediaUrlResolver?>((
  ref,
) {
  final dependencies = ref.watch(appDependenciesProvider);
  if (dependencies.isLoading || dependencies.hasError) return null;
  return dependencies.value?.propertyMediaUrlResolver;
});

final _propertyMediaUrlCacheProvider = Provider<PropertyMediaUrlCache?>((ref) {
  final resolver = ref.watch(propertyMediaUrlResolverProvider);
  return resolver == null ? null : PropertyMediaUrlCache(resolver);
});

/// The fetchable URL for a storage reference, or null when there is not one.
final propertyMediaUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, reference) {
      final cache = ref.watch(_propertyMediaUrlCacheProvider);
      return cache == null ? Future<String?>.value() : cache.resolve(reference);
    });

/// Remembers what Storage answered so a rebuild never re-asks for the same
/// reference — including when the answer was "there is no such object".
///
/// This holds URL strings rather than image bytes. The bytes themselves are now
/// cached by the image layer — in memory and, on mobile, on disk across app
/// launches — which is both far larger and far longer-lived than the 24 MB
/// in-memory buffer this replaced.
///
/// Misses are cached too, for [missTtl]. A reference whose object is genuinely
/// absent — a listing whose media never delivered, a row pointing at something
/// deleted — used to cost the full retry ladder *every* time its tile scrolled
/// back into view, which is what turned one broken listing into a session-long
/// stream of Storage 404s. Caching the miss makes it cost one ladder; the TTL
/// keeps it from becoming permanent, so backfilling the object still shows up
/// without restarting the app.
@visibleForTesting
final class PropertyMediaUrlCache {
  PropertyMediaUrlCache(
    this._resolver, {
    this.clock = _defaultClock,
    this.graceWindow = defaultGraceWindow,
  });

  static DateTime _defaultClock() => DateTime.now();

  /// How long a resolved miss is trusted before Storage is asked again.
  static const missTtl = Duration(minutes: 10);

  /// The delays between attempts before an absent object is called absent.
  static const defaultGraceWindow = <Duration>[
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
    Duration(milliseconds: 2400),
  ];

  final PropertyMediaUrlResolver _resolver;
  final DateTime Function() clock;
  final List<Duration> graceWindow;
  final Map<String, String> _values = <String, String>{};
  final Map<String, _SettledMiss> _misses = <String, _SettledMiss>{};
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};

  Future<String?> resolve(String reference) {
    final cached = _values[reference];
    if (cached != null) return Future<String?>.value(cached);
    final missed = _misses[reference];
    if (missed != null) {
      if (clock().difference(missed.at) < missTtl) return missed.replay();
      _misses.remove(reference);
    }
    return _inFlight.putIfAbsent(reference, () async {
      try {
        final url = await resolveMediaUrlWithRetry(
          _resolver,
          reference,
          retryDelays: graceWindow,
        );
        if (url != null) {
          _values[reference] = url;
        } else {
          // Only a settled absence reaches here: a failure that might still
          // resolve itself throws out of the ladder instead.
          _misses[reference] = _SettledMiss(at: clock());
        }
        return url;
      } on Object catch (error, stackTrace) {
        // A rejected reference is as settled as a missing one, and replaying it
        // keeps the two distinguishable in the log — an unauthorized read and
        // an undelivered photo are different problems wearing the same tile.
        if (isPermanentMediaError(error)) {
          _misses[reference] = _SettledMiss(
            at: clock(),
            error: error,
            stackTrace: stackTrace,
          );
        }
        rethrow;
      } finally {
        _inFlight.remove(reference);
      }
    });
  }
}

/// A settled non-answer for one reference: either no object, or a refusal.
final class _SettledMiss {
  _SettledMiss({required this.at, this.error, this.stackTrace});

  final DateTime at;
  final Object? error;
  final StackTrace? stackTrace;

  Future<String?> replay() => error == null
      ? Future<String?>.value()
      : Future<String?>.error(error!, stackTrace);
}

/// Storage failures that asking again cannot fix.
///
/// `object-not-found` is deliberately absent: publication commits the public
/// projection before its media worker finishes, so a missing object is
/// legitimately transient for the length of the retry ladder — and permanent
/// only once the ladder is exhausted. Everything here is a wrong question
/// rather than an early one, so retrying it just multiplies the failure by
/// four. An error this does not recognise is treated as transient, which keeps
/// the benefit of the doubt on the side of eventually showing the photo.
const _permanentMediaErrorCodes = <String>{
  'unauthorized',
  'unauthenticated',
  'invalid-argument',
  'invalid-url',
  'invalid-root-operation',
  'no-default-bucket',
  'bucket-not-found',
  'project-not-found',
};

@visibleForTesting
bool isPermanentMediaError(Object error) =>
    error is FirebaseException &&
    _permanentMediaErrorCodes.contains(error.code);

bool _isMissingObject(Object error) =>
    error is FirebaseException && error.code == 'object-not-found';

/// Gives an asynchronously delivered listing image a short window to appear.
///
/// Publication commits the public projection before its media worker finishes.
/// A single Storage lookup therefore races that worker and used to leave the
/// mounted card failed until the whole page was reloaded.
///
/// Returns null — rather than throwing — when the object is simply not there
/// once that window has passed, because that is a settled answer the caller can
/// remember. A failure that might still resolve itself throws, so nothing
/// memoises it.
@visibleForTesting
Future<String?> resolveMediaUrlWithRetry(
  PropertyMediaUrlResolver resolver,
  String reference, {
  List<Duration> retryDelays = PropertyMediaUrlCache.defaultGraceWindow,
  Future<void> Function(Duration delay) wait = Future<void>.delayed,
}) async {
  Object? lastError;
  StackTrace? lastStackTrace;
  for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
    if (attempt > 0) await wait(retryDelays[attempt - 1]);
    try {
      final url = await resolver(reference);
      if (url != null) return url;
      // A resolver that answered null answered; it did not fail.
      lastError = null;
      lastStackTrace = null;
    } on Object catch (error, stackTrace) {
      if (isPermanentMediaError(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      lastError = error;
      lastStackTrace = stackTrace;
    }
  }
  if (lastError != null && !_isMissingObject(lastError)) {
    Error.throwWithStackTrace(lastError, lastStackTrace!);
  }
  return null;
}

/// Builds one offline workspace per signed-in account (plus one anonymous
/// workspace for public browsing) and swaps it when the session changes.
/// Data belonging to the previous account is never deleted or read across
/// accounts; its workspace is simply closed.
class AppDependenciesController extends AsyncNotifier<AppDependencies> {
  @override
  Future<AppDependencies> build() async {
    final session = ref.watch(sessionControllerProvider);
    final scope = workspaceScopeFor(session);
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

/// The landlord's portfolio, carrying its own freshness.
///
/// A screen reading this can tell current server data from a cached copy being
/// validated, an empty portfolio from a refused read, and a dropped connection
/// from a rejected one. `CloudDataView` renders all of those.
final portfolioPropertiesProvider = StreamProvider<CloudData<List<Property>>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.properties.watchAll();
});

final portfolioUnitsProvider = StreamProvider<CloudData<List<Unit>>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.units.watchAll();
});

final landlordListingsProvider = StreamProvider<CloudData<List<Listing>>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.listings.watchAll();
});

/// The portfolio streams with archived records retained, for the platform
/// screens only. A landlord's own views deliberately hide what they retired;
/// an administrator investigating an account needs to see it, and a super
/// admin purging it needs something to select.
final adminPropertiesProvider = StreamProvider<CloudData<List<Property>>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.properties.watchAll(includeArchived: true);
});

final adminUnitsProvider = StreamProvider<CloudData<List<Unit>>>((ref) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.units.watchAll(includeArchived: true);
});

final publicListingsProvider = StreamProvider<CloudData<List<Listing>>>((
  ref,
) async* {
  final deps = await ref.watch(appDependenciesProvider.future);
  yield* deps.publicListings.watchAll(publicOnly: true);
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

/// Application-level pull-to-refresh action for an authenticated workspace.
///
/// Current cloud repositories already stream live server changes. A deliberate
/// refresh therefore pushes the durable outbox, reconnects the older
/// Sembast-backed projection listeners, and recreates the workspace streams so
/// a failed subscription gets a fresh server attempt.
final workspaceRefreshProvider = Provider<WorkspaceRefresh>(
  WorkspaceRefresh.new,
);

class WorkspaceRefresh {
  WorkspaceRefresh(this._ref);

  final Ref _ref;
  Future<void>? _activeRefresh;

  Future<void> call() {
    final active = _activeRefresh;
    if (active != null) return active;

    late final Future<void> refresh;
    refresh = _run().whenComplete(() {
      if (identical(_activeRefresh, refresh)) _activeRefresh = null;
    });
    _activeRefresh = refresh;
    return refresh;
  }

  Future<void> _run() async {
    final deps = await _ref.read(appDependenciesProvider.future);
    await deps.syncEngine.syncPending(maxMutations: 200);
    await deps.remotePullCoordinator?.refresh();

    _ref
      ..invalidate(portfolioPropertiesProvider)
      ..invalidate(portfolioUnitsProvider)
      ..invalidate(landlordListingsProvider)
      ..invalidate(adminPropertiesProvider)
      ..invalidate(adminUnitsProvider)
      ..invalidate(rentalApplicationsProvider)
      ..invalidate(outboxEntriesProvider)
      ..invalidate(cloudStatusProvider);
  }
}

/// A forced server read for the anonymous/public catalogue.
final publicListingsRefreshProvider = Provider<PublicListingsRefresh>(
  PublicListingsRefresh.new,
);

class PublicListingsRefresh {
  PublicListingsRefresh(this._ref);

  final Ref _ref;
  Future<void>? _activeRefresh;

  Future<void> call() {
    final active = _activeRefresh;
    if (active != null) return active;

    late final Future<void> refresh;
    refresh = _run().whenComplete(() {
      if (identical(_activeRefresh, refresh)) _activeRefresh = null;
    });
    _activeRefresh = refresh;
    return refresh;
  }

  Future<void> _run() async {
    final deps = await _ref.read(appDependenciesProvider.future);
    await deps.publicListings.getAll(publicOnly: true, forceRefresh: true);
    _ref.invalidate(publicListingsProvider);
  }
}

/// Re-queues one mutation the server permanently refused, then pushes.
///
/// A permanently failed entry is never claimed again by [SyncEngine], which is
/// what stops a doomed command from being retried forever. The cost of that is
/// that recovery has to be explicit: without this, a rejected publication is
/// stuck for good and the only way out is deleting the advert.
final retryMutationProvider = Provider<RetryMutation>(RetryMutation.new);

class RetryMutation {
  const RetryMutation(this._ref);

  final Ref _ref;

  /// Returns false when the entry has already gone — a pull may have resolved
  /// it, in which case there is nothing to retry and nothing to report.
  Future<bool> call(String mutationId) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    if (!await deps.database.retryMutation(mutationId)) return false;
    await deps.syncEngine.syncPending();
    return true;
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
  await database.purgeUndecodable(
    OfflineEntityType.publicListing,
    ListingMapper.canDecode,
  );
  // Cloud plumbing. Built before the repositories because the migrated ones
  // take it by construction; the features still on the local mirror below will
  // move onto the same three objects as each is converted.
  final usesFirebase = Firebase.apps.isNotEmpty;
  final environment = usesFirebase
      ? Firebase.app().options.projectId
      : 'unconfigured';
  // Partitioned by project, account, role, and workspace, so an admin session
  // never inherits the same person's landlord reads and the next account on a
  // shared browser starts empty.
  final cachePartition = session == null
      ? CachePartition.public(environment: environment)
      : CachePartition(
          environment: environment,
          userId: session.userId,
          role: session.role.name,
          workspaceId: session.role == AppRole.staff
              ? session.effectiveWorkspaceId
              : null,
        );
  final cloudCache = CloudCache();
  final cloudReader = CloudReader(
    cache: cloudCache,
    gateway: usesFirebase
        ? FirestoreCloudReadGateway()
        : const UnavailableCloudReadGateway(),
    partition: cachePartition,
  );
  final connection = usesFirebase
      ? DeviceConnectionStatus()
      : const AlwaysOnlineConnectionStatus();
  // An anonymous visitor gets a gateway that refuses every command rather than
  // one that fakes a local acknowledgement. They may read the public catalogue;
  // nothing they do is ever reported as saved, because nothing is.
  final commandDispatcher = CommandDispatcher(
    gateway: usesFirebase && session != null
        ? await FirebaseCommandGateway.create(actorUid: session.userId)
        : const UnavailableCommandGateway(),
    connection: connection,
  );
  final cloudScope = cloudScopeFor(session);

  final properties = CloudPropertyRepository(
    reader: cloudReader,
    commands: commandDispatcher,
    scope: cloudScope,
  );
  final units = CloudUnitRepository(
    reader: cloudReader,
    commands: commandDispatcher,
    scope: cloudScope,
  );
  final listings = CloudListingRepository(
    reader: cloudReader,
    commands: commandDispatcher,
    scope: cloudScope,
    units: units,
    properties: properties,
  );
  // Reads the world-readable projection and refuses every write. An anonymous
  // visitor may browse the real catalogue; nothing they do is ever reported as
  // saved, because nothing they do reaches a server.
  final publicListings = CloudListingRepository.publicCatalog(
    reader: cloudReader,
  );
  final applications = SembastApplicationRepository(database: database);
  final userSettings = SembastUserSettingsRepository(database: database);
  final maintenance = SembastMaintenanceRepository(database: database);
  final tenancies = CloudTenancyRepository(
    reader: cloudReader,
    commands: commandDispatcher,
    scope: cloudScope,
  );
  final payments = CloudRentPaymentRepository(
    reader: cloudReader,
    commands: commandDispatcher,
    scope: cloudScope,
  );
  final leaseDocuments = SembastLeaseDocumentRepository(database: database);
  final notices = SembastNoticeRepository(database: database);
  final notifications = SembastAppNotificationRepository(database: database);
  final subscriptionPlans = SembastSubscriptionPlanRepository(
    database: database,
  );
  final staff = SembastStaffRepository(database);
  final feedback = SembastFeedbackRepository(database: database);
  final support = SembastSupportRepository(database: database);
  // Built here rather than inside the pull block below because the review
  // repository needs it too: public reviews are fetched per landlord on demand
  // rather than watched for the workspace lifetime. Null in demo builds, where
  // the repository falls back to whatever the local mirror already holds.
  final pullGateway = usesFirebase ? FirestoreRemotePullGateway() : null;
  final reviews = SembastReviewRepository(
    database: database,
    pullGateway: pullGateway,
  );
  final isAuthenticated = session != null;
  final usesRemoteGateway = usesFirebase && isAuthenticated;
  final gateway = usesRemoteGateway
      ? await FirebaseRemoteSyncGateway.create(actorUid: session.userId)
      : InMemorySyncGateway();
  // Always let Storage mint the URL, including for the public listing prefix.
  // A hand-built `?alt=media` URL looks equivalent and is not: that endpoint
  // serves an object only to a request carrying the object's download token or
  // an SDK call the rules authorise, and a constructed URL has neither — every
  // such fetch came back 403, so no photo rendered. The round trip this costs
  // is paid once per distinct reference, because the result is memoised, while
  // the bytes behind the URL still land in the platform's HTTP and disk caches.
  final PropertyMediaUrlResolver? propertyMediaUrlResolver = usesFirebase
      ? (reference) => traceAsync(PerfNames.mediaUrlResolve, () async {
          final storage = FirebaseStorage.instance;
          final object = reference.startsWith('gs://')
              ? storage.refFromURL(reference)
              : storage.ref(reference);
          return object.getDownloadURL();
        })
      : null;
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
      gateway: pullGateway!,
    );
    remotePullCoordinator.watch(
      OfflineEntityType.publicListing,
      publicOnly: true,
    );
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
        // These are readable unfiltered here because their canonical document
        // shape *is* what the Dart mapper expects — they were designed that way
        // rather than reshaped afterwards, which is what excluded the types
        // named in the comment above.
        OfflineEntityType.landlordReview,
        OfflineEntityType.platformFeedback,
        // The support queue. Unfiltered like the rest of this list, which is
        // also its ceiling: the administrative pull is `.limit(200)` with no
        // ordering, so past roughly two hundred lifetime tickets the queue reads
        // an arbitrary subset. Paging is the fix, not a larger number.
        OfflineEntityType.supportTicket,
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
        // Owner-only, and not in `workspacePulls` above because no staff
        // permission opens it: the reviews section of landlordPortals is closed
        // to staff in Firestore Rules. A public reply is the owner's voice about
        // their own reputation, not a delegable workspace task.
        remotePullCoordinator.watch(
          OfflineEntityType.landlordReview,
          landlordId: session.effectiveWorkspaceId,
        );
        // Owner-only for a different reason than reviews: no staff capability
        // covers the owner's correspondence with Nyumba, which routinely names
        // billing state and account access. Firestore Rules deny it to staff
        // outright, so a staff pull would fire a read the server refuses.
        remotePullCoordinator.watch(
          OfflineEntityType.supportTicket,
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
      // Reviews are the one tenant projection this client can read, and the
      // reason is worth stating: its Firestore shape and its Dart mapper were
      // designed together, in one change, with a test on each side pinning the
      // field list (`reviews-projection.test.ts` and
      // `landlord_review_mapper_test.dart`). Nothing was reshaped after the
      // fact, so nothing mismatches.
      //
      // It is also the projection a tenant most needs pulled: a review written
      // on a phone that is later replaced would otherwise be invisible to its
      // own author, who would then write a second one — except the server keys
      // reviews by lease and would reject it as a duplicate, leaving them
      // unable to see or edit what they wrote.
      remotePullCoordinator.watch(
        OfflineEntityType.landlordReview,
        tenantUid: session.userId,
      );

      // Everything else is still deliberately absent. The tenantPortals
      // projections are security
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
    publicListings: publicListings,
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
    reviews: reviews,
    feedback: feedback,
    support: support,
    remotePullCoordinator: remotePullCoordinator,
    reconnectSyncTrigger: reconnectSyncTrigger,
    resumeSyncTrigger: resumeSyncTrigger,
    propertyMediaUrlResolver: propertyMediaUrlResolver,
  );
}
