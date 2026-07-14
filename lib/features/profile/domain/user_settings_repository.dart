import 'user_settings.dart';

abstract interface class UserSettingsRepository {
  Future<UserSettings?> getByUserId(String userId);
  Stream<UserSettings?> watchByUserId(String userId);
  Future<UserSettings> save(UserSettings settings);
}
