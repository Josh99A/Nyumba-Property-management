import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers which of an account's profiles was last active on this device,
/// so a landlord who switched to their tenant portal reopens there after a
/// cold start. Stores only a profile key (e.g. `landlord`, `staff:<uid>`) —
/// never a credential — keyed per account so shared devices don't bleed a
/// choice across sign-ins.
final class SecureActiveProfileStore {
  const SecureActiveProfileStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _keyFor(String userId) => 'nyumba.active-profile.v1.$userId';

  Future<String?> read(String userId) async {
    try {
      return await _storage.read(key: _keyFor(userId));
    } on Object {
      // A device preference must never block session resolution; the resolver
      // falls back to the highest-priority profile.
      return null;
    }
  }

  Future<void> write(String userId, String profileKey) async {
    try {
      await _storage.write(key: _keyFor(userId), value: profileKey);
    } on Object {
      // The in-memory choice still applies for this run. Secure storage can be
      // unavailable in restricted/private browser contexts; losing the sticky
      // choice is intentionally non-fatal.
    }
  }
}
