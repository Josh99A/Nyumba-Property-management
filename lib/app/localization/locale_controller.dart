import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/sync_metadata.dart';
import '../../core/localization/app_language.dart';
import '../../core/localization/device_language_store.dart';
import '../../features/auth/application/session_controller.dart';
import '../../features/profile/application/profile_use_cases.dart';
import '../../features/profile/domain/user_settings.dart';
import '../bootstrap/app_dependencies.dart';

final deviceLanguageStoreProvider = Provider<DeviceLanguageStore>(
  (ref) => const SecureDeviceLanguageStore(),
);

final deviceLanguageProvider =
    AsyncNotifierProvider<DeviceLanguageController, AppLanguage?>(
      DeviceLanguageController.new,
    );

class DeviceLanguageController extends AsyncNotifier<AppLanguage?> {
  @override
  Future<AppLanguage?> build() => ref.read(deviceLanguageStoreProvider).read();

  Future<void> select(AppLanguage language) async {
    state = AsyncData(language);
    await ref.read(deviceLanguageStoreProvider).write(language);
  }
}

final localePreferenceProvider =
    NotifierProvider<LocalePreferenceController, AppLanguage>(
      LocalePreferenceController.new,
    );

class LocalePreferenceController extends Notifier<AppLanguage> {
  String? _activeUserId;
  AppLanguage? _optimisticSelection;

  @override
  AppLanguage build() {
    final session = ref.watch(sessionControllerProvider);
    if (_activeUserId != session?.userId) {
      _activeUserId = session?.userId;
      _optimisticSelection = null;
    }

    final deviceLanguage = ref.watch(deviceLanguageProvider).value;
    if (session == null) {
      return _optimisticSelection ?? deviceLanguage ?? AppLanguage.english;
    }

    final settings = ref.watch(userSettingsProvider(session.userId)).value;
    return _optimisticSelection ??
        settings?.language ??
        session.language ??
        deviceLanguage ??
        AppLanguage.english;
  }

  /// Persists the resolved app language to the authenticated profile when the
  /// server does not already know it.
  ///
  /// Server-rendered notifications (push and inbox) are localized to the
  /// `locale` stored on the user document. A language chosen while signed out
  /// only reaches the device store, so without this a user who picked, say,
  /// Kiswahili before signing in would read the app in Kiswahili but receive
  /// English notifications. Run once per session so the two agree.
  Future<void> reconcileServerLocale() async {
    final session = ref.read(sessionControllerProvider);
    // Demo and anonymous sessions have no server-side user document to localize
    // against, mirroring the push-registration policy.
    if (session == null || session.isDemo || session.isAnonymous) return;
    final effective = state;
    if (effective == session.language) return;
    // No correction needed when the server simply has no preference yet and the
    // app is on the default: an unset locale already renders notifications in
    // English, so there is nothing to bring into agreement.
    if (session.language == null && effective == AppLanguage.english) return;
    await select(effective);
  }

  /// Applies a locale immediately, stores a signed-out/device fallback, and
  /// atomically queues the authenticated profile preference when possible.
  Future<void> select(AppLanguage language) async {
    _optimisticSelection = language;
    state = language;
    await ref.read(deviceLanguageProvider.notifier).select(language);

    final session = ref.read(sessionControllerProvider);
    if (session == null) return;

    final current = await ref.read(loadUserSettingsProvider)(session.userId);
    final settings = current == null
        ? UserSettings(
            userId: session.userId,
            displayName: session.displayName,
            email: session.email,
            phone: session.phone,
            themePreference: ThemePreference.system,
            language: language,
            emailNotifications: true,
            pushNotifications: true,
            rentReminders: true,
            maintenanceUpdates: true,
            updatedAt: DateTime.now().toUtc(),
            syncMetadata: const SyncMetadata.pending(),
          )
        : current.copyWith(language: language);
    await ref.read(saveUserSettingsProvider)(settings);
  }
}
