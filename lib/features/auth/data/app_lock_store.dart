import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local persistence for the app-lock preference.
///
/// Only two booleans live here: whether the lock is on, and whether this
/// device has already been offered the feature once. No credential or token
/// is ever stored — the lock gates the UI, it does not authenticate.
abstract interface class AppLockStore {
  Future<bool> readEnabled();

  Future<void> writeEnabled(bool value);

  Future<bool> readOffered();

  Future<void> markOffered();
}

final class SecureAppLockStore implements AppLockStore {
  const SecureAppLockStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _enabledKey = 'nyumba.app-lock.enabled.v1';
  static const _offeredKey = 'nyumba.app-lock.offered.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<bool> readEnabled() async {
    try {
      return await _storage.read(key: _enabledKey) == 'true';
    } on Object {
      // An unreadable preference must not brick startup; the lock simply
      // stays off until the user re-enables it.
      return false;
    }
  }

  @override
  Future<void> writeEnabled(bool value) async {
    try {
      await _storage.write(key: _enabledKey, value: '$value');
    } on Object {
      // The in-memory state still applies for this run.
    }
  }

  @override
  Future<bool> readOffered() async {
    try {
      return await _storage.read(key: _offeredKey) == 'true';
    } on Object {
      return true; // When in doubt, don't nag.
    }
  }

  @override
  Future<void> markOffered() async {
    try {
      await _storage.write(key: _offeredKey, value: 'true');
    } on Object {
      // Worst case the offer shows once more on the next launch.
    }
  }
}
