import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../domain/user_settings.dart';

/// Application-layer entry points for profile settings.
final loadUserSettingsProvider = Provider<LoadUserSettings>(
  LoadUserSettings.new,
);
final saveUserSettingsProvider = Provider<SaveUserSettings>(
  SaveUserSettings.new,
);

class LoadUserSettings {
  const LoadUserSettings(this._ref);

  final Ref _ref;

  Future<UserSettings?> call(String userId) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.userSettings.getByUserId(userId);
  }
}

class SaveUserSettings {
  const SaveUserSettings(this._ref);

  final Ref _ref;

  Future<UserSettings> call(UserSettings settings) async {
    final deps = await _ref.read(appDependenciesProvider.future);
    return deps.userSettings.save(settings);
  }
}
