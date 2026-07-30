import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../config/market_config.dart';
import 'client_platform.dart';
import 'cloud_command.dart';

typedef CommandInvoker =
    Future<Map<String, Object?>> Function(Map<String, Object?> envelope);

typedef StagedImageUploader =
    Future<void> Function({
      required String path,
      required Uint8List bytes,
      required String contentType,
    });

/// Sends commands to the versioned callable router and reports what the server
/// said.
///
/// The envelope contract is unchanged from the previous architecture — same
/// `commandId` idempotency key, same `expectedVersion` concurrency guard, same
/// client fingerprint — because the backend's duplicate protection depends on
/// it. What changed is that a command now arrives here directly from the
/// action a user took, rather than being replayed from a durable queue.
final class FirebaseCommandGateway implements CloudCommandGateway {
  FirebaseCommandGateway({
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

  static Future<FirebaseCommandGateway> create({String? actorUid}) async {
    final installationId = await resolveInstallationId();
    final package = await PackageInfo.fromPlatform();
    final callable = FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable('executeCommand');
    final storage = FirebaseStorage.instance;
    return FirebaseCommandGateway(
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
  /// Secure storage can be genuinely unavailable — private browsing contexts,
  /// restricted device policies, a build whose plugin is not registered — and
  /// this identifier is not worth failing a whole session over. When it cannot
  /// be read or written, the run falls back to an ephemeral id and the backend
  /// simply sees a fresh installation.
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
      // Still identifies this run; it just will not survive to the next launch
      // while secure storage is unavailable.
    }
    return generated;
  }

  Map<String, Object?> buildEnvelope(CloudCommand command) => <String, Object?>{
    'commandId': command.commandId,
    'type': command.type,
    'schemaVersion': 1,
    'aggregateId': command.aggregateId,
    'expectedVersion': ?command.expectedVersion,
    'payload': command.payload,
    'client': <String, Object?>{
      'installationId': installationId,
      'appVersion': appVersion,
      'platform': platform,
    },
  };

  @override
  Future<CommandOutcome> send(CloudCommand command) async {
    final staged = await _stageImages(command);
    final response = await _invokeEnvelope(buildEnvelope(staged));
    final committedAt = DateTime.tryParse(
      response['serverUpdatedAt']?.toString() ?? '',
    );
    if (committedAt == null) {
      // Without a server commit time there is no proof of when — or whether —
      // this applied, so it is an ambiguous outcome rather than a success.
      throw const CommandException(
        kind: CommandFailureKind.uncertain,
        code: 'MISSING_SERVER_TIMESTAMP',
      );
    }
    return CommandOutcome(
      committedAt: committedAt.toUtc(),
      serverVersion: response['serverVersion']?.toString(),
      wasAlreadyApplied: response['wasAlreadyApplied'] == true,
    );
  }

  /// Uploads any inline image data to staging paths before the command is sent.
  ///
  /// Photos travel as data URIs while a user is composing, and the command
  /// router accepts only storage paths. This runs before dispatch so a failed
  /// upload fails the whole action visibly, rather than producing a command
  /// referencing objects that do not exist.
  ///
  /// The `imageUrls` key is always *replaced* rather than supplemented: every
  /// command payload schema on the server is strict, so leaving the composing
  /// field in place would get the whole command rejected for an unknown key.
  Future<CloudCommand> _stageImages(CloudCommand command) async {
    final isPhotoAggregate =
        command.aggregate == CommandAggregate.property ||
        command.aggregate == CommandAggregate.listing;
    final isPhotoWrite =
        isPhotoAggregate &&
        (command.operation == CommandOperation.create ||
            command.operation == CommandOperation.update);
    if (!isPhotoWrite || !command.payload.containsKey('imageUrls')) {
      return command;
    }

    final references = _stringList(command.payload['imageUrls']);
    final withoutComposingField = <String, Object?>{...command.payload}
      ..remove('imageUrls');

    // Already-stored references need no upload, but they still have to move
    // into the field the schema names.
    if (!references.any((reference) => reference.startsWith('data:image/'))) {
      return command.withPayload(<String, Object?>{
        ...withoutComposingField,
        'stagedImagePaths': references
            .where((reference) => reference.startsWith('uploads/'))
            .toList(growable: false),
      });
    }
    final isListing = command.aggregate == CommandAggregate.listing;
    final subject = isListing ? 'Listing' : 'Property';
    final filePrefix = isListing ? 'listing' : 'property';
    final limit = isListing
        ? NyumbaMarket.maxListingPhotos
        : NyumbaMarket.maxPropertyPhotos;
    final uid = actorUid?.trim();
    final uploader = uploadStagedImage;
    if (uid == null || uid.isEmpty || uploader == null) {
      throw CommandException(
        kind: CommandFailureKind.rejected,
        code: 'IMAGE_UPLOAD_UNAVAILABLE',
        details: <String, Object?>{'reason': '$subject image upload'},
      );
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
        throw const CommandException(
          kind: CommandFailureKind.rejected,
          code: 'IMAGE_MALFORMED',
        );
      }
      if (image.bytes.lengthInBytes > NyumbaMarket.maxImageSizeBytes) {
        throw const CommandException(
          kind: CommandFailureKind.rejected,
          code: 'IMAGE_TOO_LARGE',
        );
      }

      final path =
          'uploads/$uid/${command.commandId}/'
          '$filePrefix-$index.${image.extension}';
      try {
        await uploader(
          path: path,
          bytes: image.bytes,
          contentType: image.contentType,
        );
      } on Object catch (error) {
        // The upload never reached Storage, so the command was never sent —
        // a clean connection failure, not an ambiguous one.
        throw CommandException(
          kind: CommandFailureKind.connection,
          code: 'IMAGE_UPLOAD_FAILED',
          cause: error,
        );
      }
      stagedPaths.add(path);
    }

    return command.withPayload(<String, Object?>{
      ...withoutComposingField,
      'stagedImagePaths': stagedPaths,
    });
  }

  Future<Map<String, Object?>> _invokeEnvelope(
    Map<String, Object?> envelope,
  ) async {
    try {
      final response = await invoke(envelope);
      final status = response['status'];
      if (status == 'rejected') {
        final error = _optionalStringMap(response['error']);
        final code = error?['code']?.toString() ?? 'VALIDATION_FAILED';
        throw CommandException(
          kind: code == 'PERMISSION_DENIED'
              ? CommandFailureKind.permissionDenied
              : CommandFailureKind.rejected,
          code: code,
          details: _optionalStringMap(error?['details']),
        );
      }
      if (status != 'applied' && status != 'accepted') {
        throw const CommandException(
          kind: CommandFailureKind.uncertain,
          code: 'MALFORMED_COMMAND_RESPONSE',
        );
      }
      return response;
    } on CommandException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      final details = _optionalStringMap(error.details);
      final domainCode = details?['code']?.toString();
      final safeDetails = _optionalStringMap(details?['details']);

      // A reused idempotency key means the server already has this command.
      // That is the opposite of a retryable failure: the work is done.
      if ((error.code == 'invalid-argument' ||
              error.code == 'failed-precondition') &&
          domainCode == 'IDEMPOTENCY_KEY_REUSED') {
        throw CommandException(
          kind: CommandFailureKind.rejected,
          code: domainCode!,
          details: safeDetails,
          cause: error,
        );
      }

      throw CommandException(
        kind: switch (error.code) {
          'permission-denied' ||
          'unauthenticated' => CommandFailureKind.permissionDenied,
          // The request left this device and no answer came back. Whether the
          // server applied it is genuinely unknown.
          'unavailable' ||
          'deadline-exceeded' ||
          'cancelled' ||
          'internal' ||
          'aborted' => CommandFailureKind.uncertain,
          _ => CommandFailureKind.rejected,
        },
        code: domainCode ?? error.code,
        details: safeDetails,
        cause: error,
      );
    } on Object catch (error) {
      throw CommandException(
        kind: CommandFailureKind.uncertain,
        code: 'CALLABLE_FAILED',
        cause: error,
      );
    }
  }
}

Map<String, Object?> _stringMap(Object? value) {
  if (value is! Map) {
    throw const CommandException(
      kind: CommandFailureKind.uncertain,
      code: 'MALFORMED_COMMAND_RESPONSE',
    );
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
