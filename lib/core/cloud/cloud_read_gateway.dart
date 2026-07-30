import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/market_config.dart';
import 'cloud_command.dart';
import 'cloud_data.dart';

/// Which authorized projection a read comes from.
///
/// A scope is not a filter the client chooses for convenience — it names the
/// read Firestore Rules will actually allow for this actor. Anonymous visitors
/// have exactly one, and it is the world-readable catalogue.
sealed class CloudScope {
  const CloudScope();
}

/// Unauthenticated reads of world-readable projections. `publicListings` and
/// the plan catalogue, and nothing else, ever.
final class PublicScope extends CloudScope {
  const PublicScope();
}

/// The UID-keyed inbox every authenticated actor shares.
final class UserScope extends CloudScope {
  const UserScope(this.userUid);
  final String userUid;
}

/// A landlord workspace, read by its owner or by staff the membership doc
/// authorizes. [workspaceId] is the owner's uid in both cases.
final class LandlordScope extends CloudScope {
  const LandlordScope(this.workspaceId);
  final String workspaceId;
}

final class TenantScope extends CloudScope {
  const TenantScope(this.tenantUid);
  final String tenantUid;
}

final class ProspectScope extends CloudScope {
  const ProspectScope(this.clientUid);
  final String clientUid;
}

/// Platform-wide reads. Authorized by admin claims in Firestore Rules, not by
/// anything this client asserts.
final class AdministrativeScope extends CloudScope {
  const AdministrativeScope();
}

/// Reads canonical cloud collections and server-owned projections.
///
/// Returns [CloudData] rather than raw documents so that a caller cannot
/// accidentally treat "permission denied" or "not connected" as "no records" —
/// the distinction is carried in the type instead of being left to a `try`
/// block someone forgets to write.
abstract interface class CloudReadGateway {
  /// A live listener, for data whose changes matter while a screen is open.
  Stream<CloudData<List<Map<String, Object?>>>> watch(
    CommandAggregate aggregate,
    CloudScope scope,
  );

  /// A deliberate one-shot read, for data a listener would make expensive or
  /// pointless — long tails, rarely-changing catalogues, and anything fetched
  /// against a token only known once a particular screen opens.
  Future<CloudData<List<Map<String, Object?>>>> fetch(
    CommandAggregate aggregate,
    CloudScope scope, {
    int limit,
  });

  /// The published reviews written about one landlord.
  ///
  /// A fetch rather than a watch on purpose: the token to filter by is not
  /// known until a particular listing or profile is open, so a workspace-
  /// lifetime subscription would either watch the wrong reviews or leak a
  /// stream per listing visited.
  Future<CloudData<List<Map<String, Object?>>>> fetchPublicReviews(
    String landlordToken, {
    int limit,
  });
}

/// Translates a Firebase read failure into the honest user-facing distinction.
///
/// `permission-denied` is deliberately never folded into the connection case:
/// telling someone to check their internet when the server refused their
/// account sends them to fix the wrong thing.
CloudReadError cloudReadErrorFrom(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => CloudReadError.permissionDenied(
        detail: error.message,
      ),
      'unavailable' || 'deadline-exceeded' || 'cancelled' =>
        CloudReadError.connection(code: error.code, detail: error.message),
      'not-found' ||
      'failed-precondition' ||
      'invalid-argument' ||
      'resource-exhausted' => CloudReadError.serverRejection(
        code: error.code,
        detail: error.message,
      ),
      _ => CloudReadError.connection(code: error.code, detail: error.message),
    };
  }
  return const CloudReadError.connection(code: 'unknown');
}

/// A ceiling on one scoped read, not a page size.
///
/// Set well above the largest plan entitlement so it can never truncate a
/// legitimate workspace: a landlord silently missing properties is a far worse
/// failure than a slow read. A real workspace approaching this needs cursor
/// pagination, not a bigger constant.
const int maximumScopedDocuments = 2000;

final class FirestoreCloudReadGateway implements CloudReadGateway {
  FirestoreCloudReadGateway({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Stream<CloudData<List<Map<String, Object?>>>> watch(
    CommandAggregate aggregate,
    CloudScope scope,
  ) {
    final Query<Map<String, dynamic>> query;
    try {
      query = _queryFor(aggregate, scope);
    } on ArgumentError catch (error) {
      return Stream<CloudData<List<Map<String, Object?>>>>.value(
        CloudData<List<Map<String, Object?>>>.failure(
          CloudReadError.serverRejection(
            code: 'UNSUPPORTED_READ',
            detail: error.message?.toString(),
          ),
        ),
      );
    }

    // `includeMetadataChanges` is off and persistence is disabled app-wide, so
    // every snapshot here originates at the server. That is what lets a
    // delivered snapshot be treated as proof of freshness rather than as a
    // possible replay of the SDK's own local copy.
    return query
        .snapshots()
        .map((snapshot) {
          final records = _decode(aggregate, snapshot, scope);
          final now = DateTime.now().toUtc();
          return records.isEmpty
              ? CloudData<List<Map<String, Object?>>>.empty(
                  records,
                  retrievedAt: now,
                )
              : CloudData<List<Map<String, Object?>>>.live(
                  records,
                  retrievedAt: now,
                );
        })
        .handleError((Object error) {})
        .transform(_failureTransformer());
  }

  @override
  Future<CloudData<List<Map<String, Object?>>>> fetch(
    CommandAggregate aggregate,
    CloudScope scope, {
    int limit = maximumScopedDocuments,
  }) async {
    try {
      final snapshot = await _queryFor(
        aggregate,
        scope,
      ).limit(limit).get(const GetOptions(source: Source.server));
      final records = _decode(aggregate, snapshot, scope);
      final now = DateTime.now().toUtc();
      return records.isEmpty
          ? CloudData<List<Map<String, Object?>>>.empty(
              records,
              retrievedAt: now,
            )
          : CloudData<List<Map<String, Object?>>>.live(
              records,
              retrievedAt: now,
            );
    } on ArgumentError catch (error) {
      return CloudData<List<Map<String, Object?>>>.failure(
        CloudReadError.serverRejection(
          code: 'UNSUPPORTED_READ',
          detail: error.message?.toString(),
        ),
      );
    } on Object catch (error) {
      return CloudData<List<Map<String, Object?>>>.failure(
        cloudReadErrorFrom(error),
      );
    }
  }

  @override
  Future<CloudData<List<Map<String, Object?>>>> fetchPublicReviews(
    String landlordToken, {
    int limit = 20,
  }) async {
    final token = landlordToken.trim();
    if (token.isEmpty) {
      return CloudData<List<Map<String, Object?>>>.empty(
        const <Map<String, Object?>>[],
        retrievedAt: DateTime.now().toUtc(),
      );
    }
    try {
      // Matches the deployed composite index exactly:
      // status ASC, landlordToken ASC, createdAt DESC. Rules cap the limit at
      // 50, so asking for more is denied outright rather than truncated.
      final snapshot = await _firestore
          .collection('publicReviews')
          .where('status', isEqualTo: 'published')
          .where('landlordToken', isEqualTo: token)
          .orderBy('createdAt', descending: true)
          .limit(limit.clamp(1, 50))
          .get(const GetOptions(source: Source.server));
      final records = [
        for (final document in snapshot.docs)
          toClientShape(
            CommandAggregate.publicReview,
            document.id,
            document.data(),
            publicOnly: true,
          ),
      ];
      final now = DateTime.now().toUtc();
      return records.isEmpty
          ? CloudData<List<Map<String, Object?>>>.empty(
              records,
              retrievedAt: now,
            )
          : CloudData<List<Map<String, Object?>>>.live(
              records,
              retrievedAt: now,
            );
    } on Object catch (error) {
      return CloudData<List<Map<String, Object?>>>.failure(
        cloudReadErrorFrom(error),
      );
    }
  }

  List<Map<String, Object?>> _decode(
    CommandAggregate aggregate,
    QuerySnapshot<Map<String, dynamic>> snapshot,
    CloudScope scope,
  ) => [
    for (final document in snapshot.docs)
      toClientShape(
        aggregate,
        document.id,
        document.data(),
        publicOnly: scope is PublicScope,
      ),
  ];

  /// Rewrites listener errors as failure states instead of letting them tear
  /// the stream down. A stream that closes on a transient error leaves the
  /// screen with whatever it last saw and no way to know it went stale.
  StreamTransformer<
    CloudData<List<Map<String, Object?>>>,
    CloudData<List<Map<String, Object?>>>
  >
  _failureTransformer() =>
      StreamTransformer<
        CloudData<List<Map<String, Object?>>>,
        CloudData<List<Map<String, Object?>>>
      >.fromHandlers(
        handleError: (error, stackTrace, sink) => sink.add(
          CloudData<List<Map<String, Object?>>>.failure(
            cloudReadErrorFrom(error),
          ),
        ),
      );

  Query<Map<String, dynamic>> _queryFor(
    CommandAggregate aggregate,
    CloudScope scope,
  ) => switch (scope) {
    PublicScope() => _publicQuery(aggregate),
    UserScope(:final userUid) => _userQuery(aggregate, userUid),
    LandlordScope(:final workspaceId) => _landlordQuery(aggregate, workspaceId),
    TenantScope(:final tenantUid) =>
      _firestore
          .collection('tenantPortals')
          .doc(tenantUid)
          .collection(_tenantSection(aggregate))
          .limit(maximumScopedDocuments),
    ProspectScope(:final clientUid) =>
      _firestore
          .collection('clientPortals')
          .doc(clientUid)
          .collection(_clientSection(aggregate))
          .limit(maximumScopedDocuments),
    AdministrativeScope() =>
      _firestore.collection(_adminCollection(aggregate)).limit(200),
  };

  Query<Map<String, dynamic>> _publicQuery(CommandAggregate aggregate) =>
      switch (aggregate) {
        CommandAggregate.publicListing =>
          _firestore
              .collection('publicListings')
              .where('status', isEqualTo: 'published')
              // The list rule rechecks `expiresAt > request.time`. A cutoff
              // captured on the client can lag the server by the time the query
              // lands, so a small future safety window keeps an expired row
              // from ever surfacing.
              .where(
                'expiresAt',
                isGreaterThan: Timestamp.fromDate(
                  DateTime.now().toUtc().add(const Duration(minutes: 5)),
                ),
              )
              // Matches the deployed composite index exactly:
              // status ASC, expiresAt ASC, publishedAt DESC.
              .orderBy('expiresAt')
              .orderBy('publishedAt', descending: true)
              .limit(50),
        CommandAggregate.planCatalog =>
          _firestore
              .collection('planCatalog')
              .where('isPublic', isEqualTo: true)
              .limit(20),
        _ => throw ArgumentError(
          'Anonymous actors may read only the public catalogue and plans; '
          '${aggregate.name} is not public.',
        ),
      };

  Query<Map<String, dynamic>> _userQuery(
    CommandAggregate aggregate,
    String userUid,
  ) {
    if (aggregate != CommandAggregate.notification) {
      throw ArgumentError('Only notifications use the common user inbox.');
    }
    return _firestore
        .collection('notificationInboxes')
        .doc(userUid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(100);
  }

  Query<Map<String, dynamic>> _landlordQuery(
    CommandAggregate aggregate,
    String workspaceId,
  ) => switch (aggregate) {
    // Canonical shapes the client's mappers already accept.
    CommandAggregate.property ||
    CommandAggregate.unit ||
    CommandAggregate.listing ||
    CommandAggregate.staffInvite ||
    CommandAggregate.supportTicket =>
      _firestore
          .collection(_landlordCollection(aggregate))
          .where('landlordId', isEqualTo: workspaceId)
          .limit(maximumScopedDocuments),
    // Joined read models: no single canonical collection can rebuild these.
    CommandAggregate.tenancy ||
    CommandAggregate.payment ||
    CommandAggregate.maintenanceRequest ||
    CommandAggregate.notice ||
    CommandAggregate.document ||
    CommandAggregate.landlordReview =>
      _firestore
          .collection('landlordPortals')
          .doc(workspaceId)
          .collection(_landlordPortalSection(aggregate))
          .limit(maximumScopedDocuments),
    _ => throw ArgumentError('No landlord read source for ${aggregate.name}.'),
  };

  static String _landlordPortalSection(CommandAggregate type) => switch (type) {
    CommandAggregate.tenancy => 'tenancies',
    CommandAggregate.payment => 'payments',
    CommandAggregate.landlordReview => 'reviews',
    CommandAggregate.maintenanceRequest => 'maintenance',
    CommandAggregate.notice => 'notices',
    CommandAggregate.document => 'documents',
    _ => throw ArgumentError('No landlord portal section for ${type.name}.'),
  };

  static String _landlordCollection(CommandAggregate type) => switch (type) {
    CommandAggregate.property => 'properties',
    CommandAggregate.unit => 'units',
    CommandAggregate.listing => 'privateListings',
    CommandAggregate.staffInvite => 'staffInvites',
    CommandAggregate.supportTicket => 'supportTickets',
    _ => throw ArgumentError('No landlord collection for ${type.name}.'),
  };

  static String _adminCollection(CommandAggregate type) => switch (type) {
    CommandAggregate.property => 'properties',
    CommandAggregate.unit => 'units',
    CommandAggregate.listing => 'privateListings',
    CommandAggregate.landlordReview => 'landlordReviews',
    CommandAggregate.platformFeedback => 'platformFeedback',
    CommandAggregate.supportTicket => 'supportTickets',
    // Everything else needs an administrative read model before it can be read
    // unfiltered. Throwing here rather than defaulting to the canonical
    // collection is deliberate: an unlisted type would hand raw server JSON to
    // a mapper that rejects it, surfacing as a crash on a screen far from this
    // decision.
    _ => throw ArgumentError('No administrative read model for ${type.name}.'),
  };

  static String _tenantSection(CommandAggregate type) => switch (type) {
    CommandAggregate.tenancy => 'tenancies',
    CommandAggregate.invoice => 'invoices',
    CommandAggregate.payment => 'payments',
    CommandAggregate.maintenanceRequest => 'maintenance',
    CommandAggregate.document => 'documents',
    CommandAggregate.notice => 'notices',
    CommandAggregate.landlordReview => 'reviews',
    _ => throw ArgumentError('No tenant projection for ${type.name}.'),
  };

  static String _clientSection(CommandAggregate type) => switch (type) {
    CommandAggregate.application => 'applications',
    _ => throw ArgumentError('No prospect projection for ${type.name}.'),
  };

  /// Translates one server document into the shape the client's mapper reads.
  ///
  /// Public rather than private so the contract can be asserted directly:
  /// nothing type-checks across Dart and TypeScript, so a test against this
  /// function is the only thing standing between a server-side field rename
  /// and a mapper that throws on the next read.
  static Map<String, Object?> toClientShape(
    CommandAggregate type,
    String id,
    Map<String, dynamic> source, {
    required bool publicOnly,
  }) {
    final result = <String, Object?>{
      for (final entry in source.entries) entry.key: _normalize(entry.value),
      'id': id,
    };
    if (type == CommandAggregate.unit) {
      result['status'] = switch (result['occupancyStatus']) {
        'occupied' => 'occupied',
        'vacant' => 'vacant',
        'reserved' => 'reserved',
        'maintenance' => 'maintenance',
        'inactive' => 'inactive',
        _ => result['status'] ?? 'vacant',
      };
    }
    if (type == CommandAggregate.property) {
      result['imageUrls'] = imageReferencesFrom(
        result,
      ).take(NyumbaMarket.maxPropertyPhotos).toList(growable: false);
      _flattenPin(
        result,
        field: 'location',
        latitudeKey: 'latitude',
        longitudeKey: 'longitude',
      );
    }
    if (type == CommandAggregate.listing ||
        type == CommandAggregate.publicListing) {
      result['status'] =
          result['publicationState'] ?? result['status'] ?? 'draft';
      if (result['status'] == 'unpublished') result['status'] = 'paused';
      result['imageUrls'] = imageReferencesFrom(
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
        // A prospect has seen only a public advert, so they get opaque
        // placeholders rather than the real unit, property, and landlord ids.
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
  /// Both key spellings are accepted on purpose: `{lat, lng}` is what the
  /// command handlers write today, and `{latitude, longitude}` is what
  /// [_normalize] produces from a Firestore `GeoPoint`, so migrating the field
  /// to a real GeoPoint later cannot quietly break this.
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

/// The ordered storage references a record carries, under whichever field name
/// the writing build used.
List<String> imageReferencesFrom(Map<String, Object?> record) {
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
