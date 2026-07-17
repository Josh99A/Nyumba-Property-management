import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_language.dart';

abstract interface class DeviceLanguageStore {
  Future<AppLanguage?> read();

  Future<void> write(AppLanguage language);
}

final class SecureDeviceLanguageStore implements DeviceLanguageStore {
  const SecureDeviceLanguageStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'nyumba.device-language.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<AppLanguage?> read() async {
    try {
      final code = await _storage.read(key: _key);
      if (code == null) return null;
      return AppLanguage.fromCode(code);
    } on Object {
      // A device preference must never prevent the offline workspace opening.
      // Authenticated preferences still live in the account-scoped Sembast
      // record and will take over after session resolution.
      return null;
    }
  }

  @override
  Future<void> write(AppLanguage language) async {
    try {
      await _storage.write(key: _key, value: language.code);
    } on Object {
      // The in-memory selection still applies for this run. Secure storage can
      // be unavailable in restricted/private browser contexts, so locale
      // choice is intentionally non-fatal.
    }
  }
}
