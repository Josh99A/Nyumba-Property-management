import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nyumba_property_management/core/offline/aes_gcm_json_codec.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

const _storage = FlutterSecureStorage();
const _backgroundCompactionThresholdBytes = 5 * 1024 * 1024;

Future<OfflineDatabase> openScopedOfflineDatabase(String scope) async {
  final directory = await getApplicationSupportDirectory();
  final databasePath = path.join(directory.path, 'nyumba_$scope.db');
  final encrypt = Platform.isAndroid || Platform.isIOS;
  final key = encrypt ? await _keyForScope(scope) : null;
  if (key != null) {
    await compactLargeDatabaseInBackground(databasePath, key);
  }
  return OfflineDatabase.openRecovering(
    factory: databaseFactoryIo,
    path: databasePath,
    codec: key == null ? null : _codecForKey(key, offload: true),
  );
}

Future<Uint8List> _keyForScope(String scope) async {
  final storageKey = 'nyumba.workspace-key.v1.$scope';
  var encoded = await _storage.read(key: storageKey);
  if (encoded == null) {
    final bytes = Uint8List(32);
    final random = Random.secure();
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = random.nextInt(256);
    }
    encoded = base64UrlEncode(bytes);
    await _storage.write(key: storageKey, value: encoded);
  }
  final key = Uint8List.fromList(base64Url.decode(encoded));
  if (key.length != 32) {
    throw StateError('The protected workspace key has an invalid length.');
  }
  return key;
}

SembastCodec _codecForKey(Uint8List key, {bool offload = false}) =>
    SembastCodec(
      signature: 'nyumba-aes-256-gcm-v1',
      codec: offload ? IsolateAesGcmJsonCodec(key) : AesGcmJsonCodec(key),
    );

/// Compacts a large encrypted Sembast log without occupying Flutter's UI
/// isolate. Offline photos can make a single transaction several megabytes,
/// and importing obsolete transaction lines on the UI isolate makes Android
/// treat the lock screen as unresponsive.
///
/// Sembast writes compaction output to its recovery file and swaps it into
/// place only after the write completes. A process death therefore leaves the
/// original database or a recoverable completed replacement, never a partially
/// rewritten source of truth.
Future<void> compactLargeDatabaseInBackground(
  String databasePath,
  Uint8List key, {
  int thresholdBytes = _backgroundCompactionThresholdBytes,
}) async {
  final file = File(databasePath);
  if (!await file.exists() || await file.length() < thresholdBytes) return;

  final transferableKey = Uint8List.fromList(key);
  await Isolate.run(() async {
    final Database database;
    try {
      database = await databaseFactoryIo.openDatabase(
        databasePath,
        codec: _codecForKey(transferableKey),
      );
    } on Object catch (error) {
      // Leave unreadable-mirror handling to OfflineDatabase.openRecovering.
      // Compaction must never prevent its established delete-and-rebuild path.
      if (OfflineDatabase.isUnreadableMirror(error)) return;
      rethrow;
    }
    try {
      await database.compact();
    } finally {
      await database.close();
    }
  });
}
