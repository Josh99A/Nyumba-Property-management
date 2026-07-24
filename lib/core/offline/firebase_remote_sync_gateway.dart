import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../config/market_config.dart';
import 'client_platform.dart';
import 'offline_entity.dart';
import 'outbox_entry.dart';
import 'remote_sync_gateway.dart';

typedef CommandInvoker =
    Future<Map<String, Object?>> Function(Map<String, Object?> envelope);

typedef StagedImageUploader =
    Future<void> Function({
      required String path,
      required Uint8List bytes,
      required String contentType,
    });

final class FirebaseRemoteSyncGateway implements RemoteSyncGateway {
  FirebaseRemoteSyncGateway({
    required this.invoke,
    required this.installationId,
    required this.appVersion,
    required this.platform,
    this.actorUid,
    this.uploadStagedImage,
  });

  static const _installationKey = 'nyumba.installation-id.v1';
  final CommandInvoker invoke;
  final String installationId;
  final String appVersion;
  final String platform;
  final String? actorUid;
  final StagedImageUploader? uploadStagedImage;

  static Future<FirebaseRemoteSyncGateway> create({String? actorUid}) async {
    final installationId = await resolveInstallationId();
    final package = await PackageInfo.fromPlatform();
    final callable = FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable('executeCommand');
    final storage = FirebaseStorage.instance;
    return FirebaseRemoteSyncGateway(
      installationId: installationId,
      appVersion: package.version,
      platform: currentClientPlatform,
      actorUid: actorUid,
      uploadStagedImage:
          ({required path, required bytes, required contentType}) async {
            await storage
                .ref(path)
                .putData(bytes, SettableMetadata(contentType: contentType));
          },
      invoke: (envelope) async {
        final result = await callable.call<Object?>(envelope);
        return _stringMap(result.data);
      },
    );
  }

  /// A stable per-install identifier, persisted in secure storage.
  ///
  /// Secure storage can be genuinely unavailable — private/incognito web
  /// contexts, restricted device policies, or a build whose plugin is not yet
  /// registered — and this identifier is not worth failing the whole workspace
  /// over. When it can't be read or written, this run falls back to an
  /// ephemeral id: the backend simply sees a fresh installation until secure
  /// storage works again, which is a far better degradation than a dead app.
  ///
  /// [storage] is injectable so the degradation path can be tested; production
  /// callers use the default platform-backed store.
  @visibleForTesting
  static Future<String> resolveInstallationId({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) async {
    String? stored;
    try {
      stored = await storage.read(key: _installationKey);
    } on Object {
      stored = null;
    }
    if (stored != null && stored.isNotEmpty) return stored;

    final generated = const Uuid().v7().replaceAll('-', '_');
    try {
      await storage.write(key: _installationKey, value: generated);
    } on Object {
      // The generated id still identifies this run; it just won't persist to
      // the next launch while secure storage is unavailable.
    }
    return generated;
  }

  Map<String, Object?> buildEnvelope(RemoteMutation mutation) {
    final command = _commandFor(mutation);
    final expectedVersion = _expectedVersion(mutation, command.type);
    return <String, Object?>{
      'commandId': mutation.idempotencyKey,
      'type': command.type,
      'schemaVersion': 1,
      'aggregateId': mutation.entityId,
      'expectedVersion': ?expectedVersion,
      'payload': command.payload,
      'client': <String, Object?>{
        'installationId': installationId,
        'appVersion': appVersion,
        'platform': platform,
      },
    };
  }

  /// Sends a one-off command outside the outbox (auth-time flows such as
  /// landlord onboarding and tenant invite claims, which are online by
  /// nature). Returns the full command response; a rejected command throws.
  Future<Map<String, Object?>> sendCommand({
    required String type,
    String? aggregateId,
    int? expectedVersion,
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    final commandId = 'authcmd_${const Uuid().v7().replaceAll('-', '')}';
    return _invokeEnvelope(<String, Object?>{
      'commandId': commandId,
      'type': type,
      'schemaVersion': 1,
      'aggregateId': ?aggregateId,
      'expectedVersion': ?expectedVersion,
      'payload': payload,
      'client': <String, Object?>{
        'installationId': installationId,
        'appVersion': appVersion,
        'platform': platform,
      },
    });
  }

  @override
  Future<RemoteWriteResult> push(RemoteMutation mutation) async {
    final stagedMutation = await _stageImages(mutation);
    final response = await _invokeEnvelope(buildEnvelope(stagedMutation));
    final committedAt = DateTime.tryParse(
      response['serverUpdatedAt']?.toString() ?? '',
    );
    if (committedAt == null) {
      throw const RemoteSyncException('Missing serverUpdatedAt.');
    }
    return RemoteWriteResult(
      committedAt: committedAt.toUtc(),
      serverRevision: response['serverVersion']?.toString(),
      wasAlreadyApplied: response['wasAlreadyApplied'] == true,
    );
  }

  Future<RemoteMutation> _stageImages(RemoteMutation mutation) async {
    final isPhotoAggregate =
        mutation.entityType == OfflineEntityType.property ||
        mutation.entityType == OfflineEntityType.listing;
    final isPhotoWrite =
        isPhotoAggregate &&
        (mutation.operation == OutboxOperation.create ||
            mutation.operation == OutboxOperation.update);
    if (!isPhotoWrite) return mutation;

    final references = _stringList(mutation.payload['imageUrls']);
    if (!references.any((reference) => reference.startsWith('data:image/'))) {
      return mutation;
    }
    final isListing = mutation.entityType == OfflineEntityType.listing;
    final subject = isListing ? 'Listing' : 'Property';
    final filePrefix = isListing ? 'listing' : 'property';
    final limit = isListing ? NyumbaMarket.maxListingPhotos : 5;
    final uid = actorUid?.trim();
    final uploader = uploadStagedImage;
    if (uid == null || uid.isEmpty || uploader == null) {
      throw RemoteSyncException('$subject image upload is unavailable.');
    }

    final stagedPaths = <String>[];
    for (final (index, reference) in references.take(limit).indexed) {
      if (reference.startsWith('uploads/')) {
        stagedPaths.add(reference);
        continue;
      }
      if (!reference.startsWith('data:image/')) continue;

      final image = _decodeStagedImage(reference);
      if (image == null) {
        throw RemoteSyncException(
          '$subject image data is malformed.',
          retryable: false,
        );
      }
      if (image.bytes.lengthInBytes > NyumbaMarket.maxImageSizeBytes) {
        throw RemoteSyncException(
          '$subject image exceeds the upload limit.',
          retryable: false,
        );
      }

      final path =
          'uploads/$uid/${mutation.idempotencyKey}/'
          '$filePrefix-$index.${image.extension}';
      try {
        await uploader(
          path: path,
          bytes: image.bytes,
          contentType: image.contentType,
        );
      } on Object catch (error) {
        throw RemoteSyncException(
          '$subject image upload failed.',
          cause: error,
        );
      }
      stagedPaths.add(path);
    }

    return RemoteMutation(
      mutationId: mutation.mutationId,
      entityType: mutation.entityType,
      entityId: mutation.entityId,
      operation: mutation.operation,
      payload: <String, Object?>{
        ...mutation.payload,
        'stagedImagePaths': stagedPaths,
      },
      idempotencyKey: mutation.idempotencyKey,
      clientCreatedAt: mutation.clientCreatedAt,
    );
  }

  Future<Map<String, Object?>> _invokeEnvelope(
    Map<String, Object?> envelope,
  ) async {
    try {
      final response = await invoke(envelope);
      final status = response['status'];
      if (status == 'rejected') {
        final error = _optionalStringMap(response['error']);
        throw RemoteSyncException(
          error?['code']?.toString() ?? 'VALIDATION_FAILED',
          retryable: false,
          // The server's safe remediation data is what lets the UI name the
          // actual problem instead of showing a generic failure.
          details: _optionalStringMap(error?['details']),
        );
      }
      if (status != 'applied' && status != 'accepted') {
        throw const RemoteSyncException('Malformed command response.');
      }
      return response;
    } on RemoteSyncException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      final details = _optionalStringMap(error.details);
      final domainCode = details?['code']?.toString();
      final idempotencyReuse =
          (error.code == 'invalid-argument' ||
              error.code == 'failed-precondition') &&
          domainCode == 'IDEMPOTENCY_KEY_REUSED';
      throw RemoteSyncException(
        domainCode ?? error.code,
        retryable: !idempotencyReuse,
        cause: error,
        details: _optionalStringMap(details?['details']),
      );
    } on Object catch (error) {
      throw RemoteSyncException('Callable command failed.', cause: error);
    }
  }

  static int? _expectedVersion(RemoteMutation mutation, String commandType) {
    if (commandType == 'profile.update') return null;
    if (mutation.operation == OutboxOperation.create ||
        mutation.operation == OutboxOperation.apply) {
      return 0;
    }
    final raw = mutation.payload['_expectedVersion'];
    final version = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (version == null || version < 1) {
      throw RemoteSyncException(
        '$commandType requires a server version from a prior acknowledgement.',
        retryable: false,
      );
    }
    return version;
  }

  static _RemoteCommand _commandFor(RemoteMutation mutation) {
    final payload = mutation.payload;
    Map<String, Object?> pick(List<String> names) => <String, Object?>{
      for (final name in names)
        if (payload[name] != null) name: payload[name],
    };
    List<String> stagedPaths(int limit) => _stringList(
      payload['stagedImagePaths'] ?? payload['imageUrls'],
    ).where((path) => path.startsWith('uploads/')).take(limit).toList();
    final notificationPreferences = <String, Object?>{
      if (payload['emailNotifications'] != null)
        'email': payload['emailNotifications'],
      if (payload['pushNotifications'] != null)
        'push': payload['pushNotifications'],
      if (payload['rentReminders'] != null)
        'rentReminders': payload['rentReminders'],
      if (payload['maintenanceUpdates'] != null)
        'maintenanceUpdates': payload['maintenanceUpdates'],
    };

    _RemoteCommand noticePublicationCommand() {
      final audienceType = payload['audienceType'];
      final audience = switch (audienceType) {
        null || 'allActiveTenants' => 'all_active_tenants',
        'property' => 'property',
        'lease' => 'lease',
        _ => throw RemoteSyncException(
          'Unsupported notice audience type: $audienceType.',
          retryable: false,
        ),
      };
      final audienceId = payload['audienceId'];
      if (audience == 'all_active_tenants' && audienceId != null) {
        throw const RemoteSyncException(
          'All-tenant notices cannot include an audience ID.',
          retryable: false,
        );
      }
      if (audience != 'all_active_tenants' &&
          (audienceId is! String || audienceId.trim().isEmpty)) {
        throw const RemoteSyncException(
          'Scoped notices require an audience ID.',
          retryable: false,
        );
      }
      return _RemoteCommand('notice.publish', <String, Object?>{
        'title': payload['title'],
        'body': payload['body'],
        'audience': audience,
        'audienceId': ?audienceId,
      });
    }

    return switch ((mutation.entityType, mutation.operation)) {
      (OfflineEntityType.userProfile, OutboxOperation.update) => _RemoteCommand(
        'profile.update',
        <String, Object?>{
          ...pick(['displayName', 'phone']),
          ...pick(['locale']),
          if (notificationPreferences.isNotEmpty)
            'notifications': notificationPreferences,
        },
      ),
      (OfflineEntityType.property, OutboxOperation.create) => _RemoteCommand(
        'property.create',
        <String, Object?>{
          if (payload['landlordId'] != null)
            'targetLandlordId': payload['landlordId'],
          ...pick(['name', 'addressLine', 'city', 'district', 'description']),
          'stagedImagePaths': stagedPaths(5),
        },
      ),
      (OfflineEntityType.property, OutboxOperation.update) => _RemoteCommand(
        'property.update',
        <String, Object?>{
          ...pick(['name', 'addressLine', 'city', 'district', 'description']),
          if (stagedPaths(5).isNotEmpty) 'stagedImagePaths': stagedPaths(5),
        },
      ),
      (OfflineEntityType.property, OutboxOperation.delete) =>
        const _RemoteCommand('property.archive', <String, Object?>{}),
      (OfflineEntityType.unit, OutboxOperation.create) => _RemoteCommand(
        'unit.create',
        <String, Object?>{
          ...pick([
            'propertyId',
            'label',
            'type',
            'monthlyRentMinor',
            'bedrooms',
            'bathrooms',
            'amenities',
          ]),
          if (payload['status'] != null) 'occupancyStatus': payload['status'],
        },
      ),
      (OfflineEntityType.unit, OutboxOperation.update) => _RemoteCommand(
        'unit.update',
        <String, Object?>{
          ...pick([
            'label',
            'type',
            'monthlyRentMinor',
            'bedrooms',
            'bathrooms',
            'amenities',
          ]),
          if (payload['status'] != null) 'occupancyStatus': payload['status'],
        },
      ),
      (OfflineEntityType.unit, OutboxOperation.delete) => const _RemoteCommand(
        'unit.archive',
        <String, Object?>{},
      ),
      (OfflineEntityType.listing, OutboxOperation.create) => _RemoteCommand(
        'listing.saveDraft',
        <String, Object?>{
          ...pick([
            'unitId',
            'title',
            'description',
            'monthlyRentMinor',
            'unitType',
            'city',
            'neighborhood',
            'district',
            'bedrooms',
            'bathrooms',
            'amenities',
          ]),
          if (payload['approximateLatitude'] != null &&
              payload['approximateLongitude'] != null)
            'approximateLocation': <String, Object?>{
              'lat': payload['approximateLatitude'],
              'lng': payload['approximateLongitude'],
            },
          'stagedImagePaths': stagedPaths(NyumbaMarket.maxListingPhotos),
        },
      ),
      (OfflineEntityType.listing, OutboxOperation.update) => _RemoteCommand(
        'listing.saveDraft',
        <String, Object?>{
          ...pick([
            'unitId',
            'title',
            'description',
            'monthlyRentMinor',
            'unitType',
            'city',
            'neighborhood',
            'district',
            'bedrooms',
            'bathrooms',
            'amenities',
          ]),
          if (payload['approximateLatitude'] != null &&
              payload['approximateLongitude'] != null)
            'approximateLocation': <String, Object?>{
              'lat': payload['approximateLatitude'],
              'lng': payload['approximateLongitude'],
            },
          if (stagedPaths(NyumbaMarket.maxListingPhotos).isNotEmpty)
            'stagedImagePaths': stagedPaths(NyumbaMarket.maxListingPhotos),
        },
      ),
      (OfflineEntityType.listing, OutboxOperation.publish) =>
        const _RemoteCommand('listing.publish', <String, Object?>{}),
      (OfflineEntityType.listing, OutboxOperation.delete) =>
        const _RemoteCommand('listing.unpublish', <String, Object?>{}),
      (OfflineEntityType.application, OutboxOperation.apply) ||
      (OfflineEntityType.application, OutboxOperation.create) => _RemoteCommand(
        'application.submit',
        <String, Object?>{
          'listingId': payload['listingId'],
          'displayName': payload['applicantName'],
          'email': payload['applicantEmail'],
          'phone': payload['applicantPhone'],
          'message':
              payload['message'] ?? 'Application submitted through Nyumba.',
          'answers': <String, Object?>{
            if (payload['desiredMoveIn'] != null)
              'desiredMoveIn': payload['desiredMoveIn'],
          },
        },
      ),
      // The only application edit the client offers is withdrawal.
      (OfflineEntityType.application, OutboxOperation.update) =>
        const _RemoteCommand('application.withdraw', <String, Object?>{}),
      // One command for the whole tenancy: the server creates the tenant
      // record, activates the lease, and flips unit occupancy in a single
      // transaction. The client models all of that as one aggregate, so it can
      // only offer one idempotency key for it.
      (OfflineEntityType.tenancy, OutboxOperation.create) =>
        _RemoteCommand('tenancy.establish', <String, Object?>{
          'unitId': payload['unitId'],
          'displayName': payload['tenantName'],
          'email': payload['email'],
          'phone': payload['phone'],
          'startDate': payload['leaseStart'],
          'endDate': payload['leaseEnd'],
          'monthlyRentMinor': payload['monthlyRentMinor'],
          if (payload['balanceMinor'] != null)
            'openingBalanceMinor': payload['balanceMinor'],
        }),
      // A tenant reporting rent they paid and a landlord recording rent they
      // received are different acts with different authority: the tenant's is
      // a claim the landlord must confirm, so it routes to `payment.declare`.
      // Sending it to the landlord-only command would fail PERMISSION_DENIED
      // on every attempt.
      (OfflineEntityType.payment, OutboxOperation.create)
          when payload['declaredByTenant'] == true =>
        _RemoteCommand('payment.declare', <String, Object?>{
          'tenancyId': payload['tenancyId'],
          'amountMinor': payload['amountMinor'],
          'method': _snakeCase(payload['method']?.toString() ?? ''),
          'period': payload['period'],
          'reference': payload['reference'],
        }),
      (OfflineEntityType.payment, OutboxOperation.create) =>
        _RemoteCommand('payment.recordAgainstTenancy', <String, Object?>{
          'tenancyId': payload['tenancyId'],
          'amountMinor': payload['amountMinor'],
          'method': _snakeCase(payload['method']?.toString() ?? ''),
          'period': payload['period'],
        }),
      (OfflineEntityType.maintenanceRequest, OutboxOperation.create) =>
        _RemoteCommand('maintenance.create', <String, Object?>{
          ...pick(['unitId', 'title', 'description', 'category', 'priority']),
          if (payload['leaseId'] != null) 'leaseId': payload['leaseId'],
          'stagedAttachmentPaths': _stringList(
            payload['stagedAttachmentPaths'],
          ),
        }),
      (OfflineEntityType.maintenanceRequest, OutboxOperation.update) =>
        _RemoteCommand('maintenance.updateStatus', <String, Object?>{
          'status': _snakeCase(payload['status']?.toString() ?? ''),
          if (payload['statusNote'] != null) 'note': payload['statusNote'],
        }),
      (OfflineEntityType.notice, OutboxOperation.create) =>
        noticePublicationCommand(),
      (OfflineEntityType.notification, OutboxOperation.update) =>
        const _RemoteCommand('notification.markRead', <String, Object?>{}),
      _ => throw RemoteSyncException(
        'No production command mapping for '
        '${mutation.entityType.name}.${mutation.operation.name}.',
        retryable: false,
      ),
    };
  }
}

final class _RemoteCommand {
  const _RemoteCommand(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;
}

Map<String, Object?> _stringMap(Object? value) {
  if (value is! Map) {
    throw const RemoteSyncException('Callable result must be an object.');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

Map<String, Object?>? _optionalStringMap(Object? value) =>
    value is Map ? _stringMap(value) : null;

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

_StagedImage? _decodeStagedImage(String reference) {
  final match = RegExp(
    r'^data:(image\/(?:jpeg|png|webp));base64,(.+)$',
  ).firstMatch(reference);
  if (match == null) return null;
  try {
    final contentType = match.group(1)!;
    return _StagedImage(
      bytes: base64Decode(match.group(2)!),
      contentType: contentType,
      extension: switch (contentType) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => throw StateError('Unsupported image type.'),
      },
    );
  } on FormatException {
    return null;
  }
}

final class _StagedImage {
  const _StagedImage({
    required this.bytes,
    required this.contentType,
    required this.extension,
  });

  final Uint8List bytes;
  final String contentType;
  final String extension;
}

String _snakeCase(String value) => value.replaceAllMapped(
  RegExp(r'[A-Z]'),
  (match) => '_${match.group(0)!.toLowerCase()}',
);
