import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/session_controller.dart';
import '../../features/profile/domain/user_settings.dart';
import '../bootstrap/app_dependencies.dart';

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceController, ThemePreference>(
      ThemePreferenceController.new,
    );

class ThemePreferenceController extends Notifier<ThemePreference> {
  String? _activeUserId;
  ThemePreference? _optimisticSelection;

  @override
  ThemePreference build() {
    final session = ref.watch(sessionControllerProvider);
    if (_activeUserId != session?.userId) {
      _activeUserId = session?.userId;
      _optimisticSelection = null;
    }
    if (session == null) return ThemePreference.system;
    final persisted = ref.watch(userSettingsProvider(session.userId));
    return _optimisticSelection ??
        persisted.value?.themePreference ??
        ThemePreference.system;
  }

  /// Applies a user choice immediately. Persistence is coordinated by the
  /// settings screen so visual feedback never waits for disk or validation.
  void select(ThemePreference preference) {
    _optimisticSelection = preference;
    state = preference;
  }

  /// Hydrates a persisted preference when the signed-in account changes or
  /// its local settings finish loading.
  void load(ThemePreference preference) {
    _optimisticSelection = null;
    state = preference;
  }
}
