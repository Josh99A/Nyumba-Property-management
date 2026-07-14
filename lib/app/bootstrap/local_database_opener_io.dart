import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nyumba_property_management/core/offline/aes_gcm_json_codec.dart';
import 'package:nyumba_property_management/core/offline/offline_database.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

const _storage = FlutterSecureStorage();

Future<OfflineDatabase> openScopedOfflineDatabase(String scope) async {
  final directory = await getApplicationSupportDirectory();
  final encrypt = Platform.isAndroid || Platform.isIOS;
  final codec = encrypt ? await _codecForScope(scope) : null;
  return OfflineDatabase.open(
    factory: databaseFactoryIo,
    path: path.join(directory.path, 'nyumba_$scope.db'),
    codec: codec,
  );
}

Future<SembastCodec> _codecForScope(String scope) async {
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
  return SembastCodec(
    signature: 'nyumba-aes-256-gcm-v1',
    codec: AesGcmJsonCodec(key),
  );
}
