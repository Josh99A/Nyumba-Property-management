import 'dart:async';

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

enum LocaleReconciliationStatus { idle, pending, confirmed, rejected }

final class LocaleReconciliationState {
  const LocaleReconciliationState({
    this.status = LocaleReconciliationStatus.idle,
    this.userId,
    this.error,
  });

  final LocaleReconciliationStatus status;
  final String? userId;
  final Object? error;
}

final localeReconciliationProvider =
    NotifierProvider<LocaleReconciliationController, LocaleReconciliationState>(
      LocaleReconciliationController.new,
    );

/// Owns the observable outcome of reconciling the device locale to the
/// server profile. A rejected attempt stays retryable for the same session;
/// callers do not need to wait for another auth-state transition.
class LocaleReconciliationController
    extends Notifier<LocaleReconciliationState> {
  int _generation = 0;

  @override
  LocaleReconciliationState build() => const LocaleReconciliationState();

  void reconcileCurrentSession() {
    final session = ref.read(sessionControllerProvider);
    final generation = ++_generation;
    if (session == null || session.isDemo || session.isAnonymous) {
      state = LocaleReconciliationState(
        status: LocaleReconciliationStatus.confirmed,
        userId: session?.userId,
      );
      return;
    }
    final userId = session.userId;
    state = LocaleReconciliationState(
      status: LocaleReconciliationStatus.pending,
      userId: userId,
    );
    unawaited(_run(userId, generation));
  }

  void retry() {
    if (state.status != LocaleReconciliationStatus.rejected) return;
    final session = ref.read(sessionControllerProvider);
    if (session == null || session.userId != state.userId) return;
    reconcileCurrentSession();
  }

  Future<void> _run(String userId, int generation) async {
    try {
      await ref.read(localePreferenceProvider.notifier).reconcileServerLocale();
      if (generation != _generation) return;
      final session = ref.read(sessionControllerProvider);
      if (session?.userId != userId) return;
      state = LocaleReconciliationState(
        status: LocaleReconciliationStatus.confirmed,
        userId: userId,
      );
    } on Object catch (error) {
      if (generation != _generation) return;
      final session = ref.read(sessionControllerProvider);
      if (session?.userId != userId) return;
      state = LocaleReconciliationState(
        status: LocaleReconciliationStatus.rejected,
        userId: userId,
        error: error,
      );
    }
  }
}

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
    if (session == null || session.isDemo || session.isAnonymous) return;

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
