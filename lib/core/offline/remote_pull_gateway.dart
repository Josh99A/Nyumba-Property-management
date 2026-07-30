import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/market_config.dart';
import 'offline_database.dart';
import 'offline_entity.dart';

List<String> propertyImageReferencesFromRemote(Map<String, Object?> record) {
  for (final field in const [
    'imagePaths',
    'publicImagePaths',
    'stagedImagePaths',
    'imageUrls',
  ]) {
    final value = record[field];
    if (value is! List) continue;
    final references = value
        .whereType<String>()
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toList(growable: false);
    if (references.isNotEmpty) return references;
  }
  return const <String>[];
}

final class RemoteRecord {
  RemoteRecord({
    required this.entityType,
    required this.id,
    required Map<String, Object?> data,
  }) : data = Map.unmodifiable(data);

  final OfflineEntityType entityType;
  final String id;
  final Map<String, Object?> data;
}

/// How a pulled entity type is read back.
///
/// Not every type has a server collection the client can read directly: a
/// `Tenancy` spans leases + tenantRecords + units + properties, so the server
/// publishes a joined read model instead. Naming the source per type keeps the
/// distinction explicit rather than implied by which argument was passed.
enum LandlordReadSource {
  /// A canonical collection filtered by `landlordId`, whose document shape the
  /// client's mapper accepts directly.
  canonicalCollection,

  /// A server-owned `landlordPortals/{uid}/...` read model.
  portalProjection,
}

abstract interface class RemotePullGateway {
  Stream<List<RemoteRecord>> watchCollection(
    OfflineEntityType entityType, {
    String? landlordId,
    String? tenantUid,
    String? clientUid,
    String? userUid,
    bool publicOnly = false,
    bool administrativeScope = false,
  });

  /// One-shot read of the public reviews written about one landlord.
  ///
  /// Deliberately not a bootstrap watch. Public reviews are only ever read while
  /// looking at a particular landlord's listing or profile, and the token to
  /// filter by is not known until then — a workspace-lifetime subscription would
  /// either have to pull the platform's most recent reviews (almost never the
  /// ones on screen) or open a new stream per listing visited and never close
  /// them. Results are merged into the mirror, so a revisit renders offline.
  Future<List<RemoteRecord>> fetchPublicReviews(
    String landlordToken, {
    int limit = 20,
  });
}

/// A ceiling on a single scoped collection pull, not a page size.
///
/// These queries were unbounded, so one pathological workspace could stream an
/// arbitrary number of documents into a client that has to decode and mirror
/// every one. The bound is set well above the largest plan entitlement (1000
/// units, 1000 active listings) precisely so it can never truncate a legitimate
/// workspace: a landlord silently missing properties would be a far worse bug
/// than a slow sync. If a real workspace ever approaches this, the fix is
/// cursor pagination, not a bigger number.
const int _maximumScopedDocuments = 2000;

final class FirestoreRemotePullGateway implements RemotePullGateway {
  FirestoreRemotePullGateway({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Stream<List<RemoteRecord>> watchCollection(
    OfflineEntityType entityType, {
    String? landlordId,
    String? tenantUid,
    String? clientUid,
    String? userUid,
    bool publicOnly = false,
    bool administrativeScope = false,
  }) {
    Query<Map<String, dynamic>> query;
    if (userUid != null) {
      if (entityType != OfflineEntityType.notification) {
        throw ArgumentError('Only notifications use the common user inbox.');
      }
      query = _firestore
          .collection('notificationInboxes')
          .doc(userUid)
          .collection('items')
          .orderBy('createdAt', descending: true)
          .limit(100);
    } else if (publicOnly) {
      query = switch (entityType) {
        OfflineEntityType.publicListing =>
          _firestore
              .collection('publicListings')
              .where('status', isEqualTo: 'published')
              // The list rule rechecks `expiresAt > request.time`. A cutoff
              // captured at the client can be a few milliseconds behind the
              // server by the time the query arrives, so use a small future
              // safety window. Listings remain live for 30 days; omitting the
              // final five minutes prevents an expired row from ever leaking.
              .where(
                'expiresAt',
                isGreaterThan: Timestamp.fromDate(
                  DateTime.now().toUtc().add(const Duration(minutes: 5)),
                ),
              )
              // Match the deployed composite index exactly:
              // status ASC, expiresAt ASC, publishedAt DESC.
              .orderBy('expiresAt')
              .orderBy('publishedAt', descending: true)
              .limit(50),
        OfflineEntityType.planCatalog =>
          _firestore
              .collection('planCatalog')
              .where('isPublic', isEqualTo: true)
              .limit(20),
        // publicReview is deliberately absent: it is fetched per landlord token
        // by [fetchPublicReviews], not watched for the workspace lifetime.
        _ => throw ArgumentError(
          'Only listings and the plan catalog have public read models.',
        ),
      };
    } else if (administrativeScope) {
      query = _firestore.collection(_landlordCollection(entityType)).limit(200);
    } else if (landlordId != null) {
      query = switch (landlordReadSource(entityType)) {
        LandlordReadSource.portalProjection =>
          _firestore
              .collection('landlordPortals')
              .doc(landlordId)
              .collection(_landlordPortalSection(entityType))
              .limit(_maximumScopedDocuments),
        LandlordReadSource.canonicalCollection =>
          _firestore
              .collection(_landlordCollection(entityType))
              .where('landlordId', isEqualTo: landlordId)
              .limit(_maximumScopedDocuments),
      };
    } else if (tenantUid != null) {
      query = _firestore
          .collection('tenantPortals')
          .doc(tenantUid)
          .collection(_tenantSection(entityType))
          .limit(_maximumScopedDocuments);
    } else if (clientUid != null) {
      query = _firestore
          .collection('clientPortals')
          .doc(clientUid)
          .collection(_clientSection(entityType))
          .limit(_maximumScopedDocuments);
    } else {
      throw ArgumentError(
        'A user, landlord, tenant, client, administrative, or public scope is required.',
      );
    }

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map(
            (document) => RemoteRecord(
              entityType: entityType,
              id: document.id,
              data: toLocalShape(
                entityType,
                document.id,
                document.data(),
                publicOnly: publicOnly,
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Where a landlord reads [type] from.
  ///
  /// Only the types listed here are safe for a landlord to pull. Everything
  /// else throws below rather than defaulting to the canonical collection:
  /// [toLocalShape] translates only what it names, so an unlisted type would
  /// land raw server JSON in the local store and its mapper would throw on the
  /// next read — a crash on a screen far from this decision.
  static LandlordReadSource landlordReadSource(
    OfflineEntityType type,
  ) => switch (type) {
    // Canonical shapes the client's mappers already accept.
    OfflineEntityType.property ||
    OfflineEntityType.unit ||
    OfflineEntityType.listing ||
    OfflineEntityType.staffInvite ||
    // Greenfield on both sides: the Firestore document `supportOpen` writes and
    // `SupportTicketMapper` reads were designed together, in one change, so the
    // canonical shape *is* what the mapper expects and no projection is needed.
    OfflineEntityType.supportTicket => LandlordReadSource.canonicalCollection,
    // Joined read models: no single collection can rebuild these.
    OfflineEntityType.tenancy ||
    OfflineEntityType.payment ||
    // Reviews are written about a landlord but authored by someone else, so
    // there is no `landlordId`-filtered canonical collection they could read:
    // `landlordReviews` names the reviewer and is admin-only.
    OfflineEntityType.landlordReview => LandlordReadSource.portalProjection,
    _ => throw ArgumentError(
      'No landlord read source for ${type.name}. Add a landlordPortals '
      'projection on the server before pulling it.',
    ),
  };

  static String _landlordPortalSection(OfflineEntityType type) =>
      switch (type) {
        OfflineEntityType.tenancy => 'tenancies',
        OfflineEntityType.payment => 'payments',
        OfflineEntityType.landlordReview => 'reviews',
        _ => throw ArgumentError(
          'No landlord portal section for ${type.name}.',
        ),
      };

  @override
  Future<List<RemoteRecord>> fetchPublicReviews(
    String landlordToken, {
    int limit = 20,
  }) async {
    final token = landlordToken.trim();
    if (token.isEmpty) return const <RemoteRecord>[];
    // Matches the deployed composite index exactly:
    // status ASC, landlordToken ASC, createdAt DESC. The rules also cap the
    // limit at 50, so a caller asking for more would be denied outright rather
    // than truncated.
    final snapshot = await _firestore
        .collection('publicReviews')
        .where('status', isEqualTo: 'published')
        .where('landlordToken', isEqualTo: token)
        .orderBy('createdAt', descending: true)
        .limit(limit.clamp(1, 50))
        .get();
    return snapshot.docs
        .map(
          (document) => RemoteRecord(
            entityType: OfflineEntityType.publicReview,
            id: document.id,
            data: toLocalShape(
              OfflineEntityType.publicReview,
              document.id,
              document.data(),
              publicOnly: true,
            ),
          ),
        )
        .toList(growable: false);
  }

  static String _landlordCollection(OfflineEntityType type) => switch (type) {
    OfflineEntityType.property => 'properties',
    OfflineEntityType.unit => 'units',
    OfflineEntityType.tenancy => 'tenantRecords',
    OfflineEntityType.listing => 'privateListings',
    OfflineEntityType.application => 'applications',
    OfflineEntityType.invoice => 'invoices',
    OfflineEntityType.payment => 'payments',
    OfflineEntityType.maintenanceRequest => 'maintenanceRequests',
    OfflineEntityType.document => 'documents',
    OfflineEntityType.notice => 'notices',
    OfflineEntityType.staffInvite => 'staffInvites',
    // Administrative scope only: `landlordReviews` names the reviewer and
    // `platformFeedback` names the submitting landlord, so Firestore Rules open
    // both to platform admins alone.
    OfflineEntityType.landlordReview => 'landlordReviews',
    OfflineEntityType.platformFeedback => 'platformFeedback',
    // Read in both scopes: filtered by `landlordId` for the owner, unfiltered
    // for the administrative queue. Firestore Rules open it to exactly those
    // two readers and to nobody else — not even to the owner's staff.
    OfflineEntityType.supportTicket => 'supportTickets',
    _ => throw ArgumentError('No landlord collection for ${type.name}.'),
  };

  static String _tenantSection(OfflineEntityType type) => switch (type) {
    OfflineEntityType.tenancy => 'leases',
    OfflineEntityType.invoice => 'invoices',
    OfflineEntityType.payment => 'payments',
    OfflineEntityType.maintenanceRequest => 'maintenance',
    OfflineEntityType.document => 'documents',
    OfflineEntityType.notice => 'notices',
    // The first tenant projection whose server shape and Dart mapper were
    // designed together rather than reconciled afterwards, and therefore the
    // first one this client can actually pull. See app_dependencies.dart for
    // why the types above it are still not read.
    OfflineEntityType.landlordReview => 'reviews',
    _ => throw ArgumentError('No tenant projection for ${type.name}.'),
  };

  static String _clientSection(OfflineEntityType type) => switch (type) {
    OfflineEntityType.application => 'applications',
    _ => throw ArgumentError('No client projection for ${type.name}.'),
  };

  /// Translates one server document into the shape the client's mapper reads.
  ///
  /// Public rather than private so the shape contract can be asserted directly
  /// — nothing type-checks across Dart and TypeScript, so a test against this
  /// function is the only thing that catches the server and the mapper drifting
  /// apart. See `test/features/listing_projection_test.dart`.
  static Map<String, Object?> toLocalShape(
    OfflineEntityType type,
    String id,
    Map<String, dynamic> source, {
    required bool publicOnly,
  }) {
    final result = <String, Object?>{
      for (final entry in source.entries) entry.key: _normalize(entry.value),
      'id': id,
    };
    if (type == OfflineEntityType.unit) {
      result['status'] = switch (result['occupancyStatus']) {
        'occupied' => 'occupied',
        'vacant' => 'vacant',
        'reserved' => 'reserved',
        'maintenance' => 'maintenance',
        'inactive' => 'inactive',
        _ => result['status'] ?? 'vacant',
      };
    }
    if (type == OfflineEntityType.property) {
      // Records created before the two-photo policy may still contain up to
      // five paths. Preserve their cover-first order while keeping the local
      // aggregate readable under the current invariant.
      result['imageUrls'] = propertyImageReferencesFromRemote(
        result,
      ).take(NyumbaMarket.maxPropertyPhotos).toList(growable: false);
      _flattenPin(
        result,
        field: 'location',
        latitudeKey: 'latitude',
        longitudeKey: 'longitude',
      );
    }
    if (type == OfflineEntityType.listing ||
        type == OfflineEntityType.publicListing) {
      result['status'] =
          result['publicationState'] ?? result['status'] ?? 'draft';
      if (result['status'] == 'unpublished') result['status'] = 'paused';
      result['imageUrls'] = propertyImageReferencesFromRemote(
        result,
      ).take(NyumbaMarket.maxListingPhotos).toList(growable: false);
      result['publicContactToken'] =
          result['landlordToken'] ?? result['publicContactToken'];
      _flattenPin(
        result,
        field: 'approximateLocation',
        latitudeKey: 'approximateLatitude',
        longitudeKey: 'approximateLongitude',
      );
      if (publicOnly) {
        final opaque = result['landlordToken']?.toString() ?? 'public';
        result['unitId'] = 'public_unit_$id';
        result['propertyId'] = 'public_property_$id';
        result['landlordId'] = opaque;
      }
    }
    return result;
  }

  /// Rewrites the server's nested map pin as the two flat scalars the client's
  /// aggregates carry.
  ///
  /// The server nests the pin ([field]); `Property` and `Listing` each hold two
  /// doubles. Without this translation the coordinate survived only on the
  /// device that authored it — every pull silently dropped it, so a map
  /// rendered empty for everyone else.
  ///
  /// Both key spellings are accepted on purpose: `{lat, lng}` is what the
  /// command handlers write today, and `{latitude, longitude}` is what
  /// [_normalize] produces from a Firestore `GeoPoint`, so migrating the field
  /// to a real GeoPoint later cannot quietly break this again.
  static void _flattenPin(
    Map<String, Object?> record, {
    required String field,
    required String latitudeKey,
    required String longitudeKey,
  }) {
    final pin = record[field];
    if (pin is! Map) return;
    final latitude = _coordinate(pin['lat'] ?? pin['latitude']);
    final longitude = _coordinate(pin['lng'] ?? pin['longitude']);
    // Both or neither: a lone axis cannot be placed on a map, and the
    // aggregates validate the two independently, so a half-written pair would
    // decode cleanly and then render nothing.
    if (latitude == null || longitude == null) return;
    record[latitudeKey] = latitude;
    record[longitudeKey] = longitude;
  }

  /// A coordinate axis, or null for anything that cannot be placed on a map.
  ///
  /// Lenient about the numeric type because JSON gives back an `int` for a
  /// whole-number coordinate, and strict about finiteness because a NaN would
  /// pass the aggregate's range check and then poison the map camera.
  static double? _coordinate(Object? value) => switch (value) {
    num() when value.isFinite => value.toDouble(),
    _ => null,
  };

  static Object? _normalize(Object? value) => switch (value) {
    Timestamp() => value.toDate().toUtc().toIso8601String(),
    GeoPoint() => <String, Object?>{
      'latitude': value.latitude,
      'longitude': value.longitude,
    },
    List() => value.map(_normalize).toList(growable: false),
    Map() => <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _normalize(entry.value),
    },
    _ => value,
  };
}

/// Whether the workspace is actually reading from the server right now.
///
/// [connecting] is the honest initial value: a subscription exists but no
/// snapshot has arrived, so nothing has been proven yet.
enum CloudLinkState { connecting, live, failed }

final class RemotePullCoordinator {
  RemotePullCoordinator({required this.database, required this.gateway});

  final OfflineDatabase database;
  final RemotePullGateway gateway;
  final List<StreamSubscription<List<RemoteRecord>>> _subscriptions = [];
  final List<_RemotePullRegistration> _registrations = [];
  // One state per watched collection, parallel to [_subscriptions]. The
  // workspace link is an aggregate of these: a single collection failing (a
  // missing projection, a rule that denies one type) must not report the whole
  // workspace offline while others are delivering data.
  final List<CloudLinkState> _subscriptionStates = [];
  final StreamController<CloudLinkState> _linkStates =
      StreamController<CloudLinkState>.broadcast();
  CloudLinkState _linkState = CloudLinkState.connecting;

  /// The most recent link state; [linkStates] emits every subsequent change.
  CloudLinkState get linkState => _linkState;

  Stream<CloudLinkState> get linkStates => _linkStates.stream;

  /// The honest workspace-wide link state.
  ///
  /// A delivered snapshot on any collection proves the server is reachable, so
  /// [live] wins outright. [failed] shows only when every collection has failed
  /// — one collection erroring while others are still opening is not the whole
  /// workspace going offline — and [connecting] holds until then.
  CloudLinkState _aggregate() {
    if (_subscriptionStates.contains(CloudLinkState.live)) {
      return CloudLinkState.live;
    }
    if (_subscriptionStates.isNotEmpty &&
        _subscriptionStates.every((state) => state == CloudLinkState.failed)) {
      return CloudLinkState.failed;
    }
    return CloudLinkState.connecting;
  }

  void _publish(int slot, CloudLinkState next) {
    _subscriptionStates[slot] = next;
    final aggregate = _aggregate();
    if (_linkState == aggregate || _linkStates.isClosed) return;
    _linkState = aggregate;
    _linkStates.add(aggregate);
  }

  void watch(
    OfflineEntityType type, {
    String? landlordId,
    String? tenantUid,
    String? clientUid,
    String? userUid,
    bool publicOnly = false,
    bool administrativeScope = false,
  }) {
    final registration = _RemotePullRegistration(
      type: type,
      landlordId: landlordId,
      tenantUid: tenantUid,
      clientUid: clientUid,
      userUid: userUid,
      publicOnly: publicOnly,
      administrativeScope: administrativeScope,
    );
    _registrations.add(registration);
    _subscribe(registration);
  }

  void _subscribe(
    _RemotePullRegistration registration, {
    Completer<void>? refreshReady,
  }) {
    final slot = _subscriptionStates.length;
    _subscriptionStates.add(CloudLinkState.connecting);
    final subscription = gateway
        .watchCollection(
          registration.type,
          landlordId: registration.landlordId,
          tenantUid: registration.tenantUid,
          clientUid: registration.clientUid,
          userUid: registration.userUid,
          publicOnly: registration.publicOnly,
          administrativeScope: registration.administrativeScope,
        )
        .listen(
          (records) async {
            // A delivered snapshot is the only proof the server is readable;
            // an empty list still proves it.
            if (records.isEmpty) {
              _publish(slot, CloudLinkState.live);
              if (refreshReady != null && !refreshReady.isCompleted) {
                refreshReady.complete();
              }
              return;
            }
            // One transaction for the whole snapshot. Merging record by record
            // woke the store's snapshot listeners once per document, so every
            // screen watching this collection rebuilt as many times as the
            // snapshot was long.
            late final List<RemoteMergeResult> results;
            try {
              results = await database.mergeRemoteEntities(<RemoteEntityMerge>[
                for (final record in records)
                  RemoteEntityMerge(
                    entityType: record.entityType,
                    entityId: record.id,
                    entity: record.data,
                  ),
              ]);
            } on Object catch (error, stackTrace) {
              // The snapshot proved connectivity even though the application
              // mirror could not accept it. A user-triggered refresh must still
              // surface the failed merge instead of completing over stale data.
              _publish(slot, CloudLinkState.live);
              developer.log(
                'Failed to merge a refreshed remote snapshot',
                name: 'remote_pull_gateway',
                error: error,
                stackTrace: stackTrace,
              );
              if (refreshReady != null && !refreshReady.isCompleted) {
                refreshReady.completeError(error, stackTrace);
              }
              return;
            }
            final failed = results
                .where((result) => result == RemoteMergeResult.failed)
                .length;
            _publish(slot, CloudLinkState.live);
            // A failed merge is recorded per record inside the database, but a
            // listener that keeps reporting `live` while quietly dropping every
            // update from one collection is its own failure mode; surface it
            // here too so it is visible from the pull side, not only a counter
            // buried in the merge transaction.
            if (failed > 0) {
              developer.log(
                '$failed of ${results.length} records failed to merge',
                name: 'remote_pull_gateway',
              );
            }
            if (refreshReady != null && !refreshReady.isCompleted) {
              if (failed > 0) {
                refreshReady.completeError(
                  StateError(
                    '$failed of ${results.length} refreshed records failed '
                    'to merge',
                  ),
                );
              } else {
                refreshReady.complete();
              }
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            // Listener errors leave the local source of truth intact. The SDK
            // retries transient streams; permission/configuration failures mark
            // only this collection failed, so the badge reports offline only
            // when no collection is live.
            _publish(slot, CloudLinkState.failed);
            if (_linkState == CloudLinkState.failed &&
                refreshReady != null &&
                !refreshReady.isCompleted) {
              refreshReady.completeError(error, stackTrace);
            }
          },
        );
    _subscriptions.add(subscription);
  }

  /// Re-establishes every authorized listener registered for this workspace.
  ///
  /// Firestore listeners normally reconnect by themselves. This is the
  /// deliberate user-triggered path used by pull-to-refresh: cancelling and
  /// reopening them requests a new scoped snapshot without widening the
  /// actor's read permissions or bypassing the local merge rules.
  Future<void> refresh() async {
    if (_registrations.isEmpty || _linkStates.isClosed) return;

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _subscriptionStates.clear();
    if (_linkState != CloudLinkState.connecting) {
      _linkState = CloudLinkState.connecting;
      _linkStates.add(CloudLinkState.connecting);
    }

    final refreshReady = Completer<void>();
    final settled = refreshReady.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    for (final registration in _registrations) {
      _subscribe(registration, refreshReady: refreshReady);
    }

    // A listener can remain in the SDK's connecting state while the device is
    // fully offline. Pull-to-refresh must finish rather than trapping the UI in
    // a permanent spinner; the cloud badge continues to show the honest state.
    await settled;
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _subscriptionStates.clear();
    _registrations.clear();
    await _linkStates.close();
  }
}

final class _RemotePullRegistration {
  const _RemotePullRegistration({
    required this.type,
    required this.landlordId,
    required this.tenantUid,
    required this.clientUid,
    required this.userUid,
    required this.publicOnly,
    required this.administrativeScope,
  });

  final OfflineEntityType type;
  final String? landlordId;
  final String? tenantUid;
  final String? clientUid;
  final String? userUid;
  final bool publicOnly;
  final bool administrativeScope;
}
