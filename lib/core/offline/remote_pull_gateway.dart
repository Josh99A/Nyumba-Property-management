import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'offline_database.dart';
import 'offline_entity.dart';

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

abstract interface class RemotePullGateway {
  Stream<List<RemoteRecord>> watchCollection(
    OfflineEntityType entityType, {
    String? landlordId,
    String? tenantUid,
    String? clientUid,
    bool publicOnly = false,
    bool administrativeScope = false,
  });
}

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
    bool publicOnly = false,
    bool administrativeScope = false,
  }) {
    Query<Map<String, dynamic>> query;
    if (publicOnly) {
      if (entityType != OfflineEntityType.listing) {
        throw ArgumentError('Only listings have a public read model.');
      }
      query = _firestore
          .collection('publicListings')
          .where('status', isEqualTo: 'published')
          .where('expiresAt', isGreaterThan: Timestamp.now())
          .limit(50);
    } else if (administrativeScope) {
      query = _firestore.collection(_landlordCollection(entityType)).limit(200);
    } else if (landlordId != null) {
      query = _firestore
          .collection(_landlordCollection(entityType))
          .where('landlordId', isEqualTo: landlordId);
    } else if (tenantUid != null) {
      query = _firestore
          .collection('tenantPortals')
          .doc(tenantUid)
          .collection(_tenantSection(entityType));
    } else if (clientUid != null) {
      query = _firestore
          .collection('clientPortals')
          .doc(clientUid)
          .collection(_clientSection(entityType));
    } else {
      throw ArgumentError(
        'A landlord, tenant, client, administrative, or public scope is required.',
      );
    }

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map(
            (document) => RemoteRecord(
              entityType: entityType,
              id: document.id,
              data: _toLocalShape(
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
    _ => throw ArgumentError('No landlord collection for ${type.name}.'),
  };

  static String _tenantSection(OfflineEntityType type) => switch (type) {
    OfflineEntityType.tenancy => 'leases',
    OfflineEntityType.invoice => 'invoices',
    OfflineEntityType.payment => 'payments',
    OfflineEntityType.maintenanceRequest => 'maintenance',
    OfflineEntityType.document => 'documents',
    OfflineEntityType.notice => 'notices',
    _ => throw ArgumentError('No tenant projection for ${type.name}.'),
  };

  static String _clientSection(OfflineEntityType type) => switch (type) {
    OfflineEntityType.application => 'applications',
    _ => throw ArgumentError('No client projection for ${type.name}.'),
  };

  static Map<String, Object?> _toLocalShape(
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
        _ => result['status'] ?? 'vacant',
      };
    }
    if (type == OfflineEntityType.listing) {
      result['status'] =
          result['publicationState'] ?? result['status'] ?? 'draft';
      if (result['status'] == 'unpublished') result['status'] = 'paused';
      result['imageUrls'] = result['imagePaths'] ?? result['imageUrls'] ?? [];
      result['publicContactToken'] =
          result['landlordToken'] ?? result['publicContactToken'];
      if (publicOnly) {
        final opaque = result['landlordToken']?.toString() ?? 'public';
        result['unitId'] = 'public_unit_$id';
        result['propertyId'] = 'public_property_$id';
        result['landlordId'] = opaque;
      }
    }
    return result;
  }

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

final class RemotePullCoordinator {
  RemotePullCoordinator({required this.database, required this.gateway});

  final OfflineDatabase database;
  final RemotePullGateway gateway;
  final List<StreamSubscription<List<RemoteRecord>>> _subscriptions = [];

  void watch(
    OfflineEntityType type, {
    String? landlordId,
    String? tenantUid,
    String? clientUid,
    bool publicOnly = false,
    bool administrativeScope = false,
  }) {
    final subscription = gateway
        .watchCollection(
          type,
          landlordId: landlordId,
          tenantUid: tenantUid,
          clientUid: clientUid,
          publicOnly: publicOnly,
          administrativeScope: administrativeScope,
        )
        .listen(
          (records) async {
            for (final record in records) {
              await database.mergeRemoteEntity(
                entityType: record.entityType,
                entityId: record.id,
                entity: record.data,
              );
            }
          },
          onError: (_) {
            // Listener errors leave the local source of truth intact. The SDK
            // retries transient streams; permission/configuration failures are
            // surfaced by the existing local stale/sync status.
          },
        );
    _subscriptions.add(subscription);
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
