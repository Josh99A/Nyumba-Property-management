import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/app/localization/locale_controller.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/localization/app_language.dart';
import 'package:nyumba_property_management/core/localization/device_language_store.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/profile/application/profile_use_cases.dart';
import 'package:nyumba_property_management/features/profile/domain/user_settings.dart';

/// Server-rendered notifications are localized to the `locale` on the user
/// document, so the resolved app language must reach the account. These tests
/// pin the sign-in reconciliation that closes the gap for a language chosen
/// while signed out.
void main() {
  UserSettings settingsFor(String userId, {AppLanguage? language}) =>
      UserSettings(
        userId: userId,
        displayName: 'Namuli Landlord',
        email: 'landlord@nyumba.test',
        phone: '+256772000100',
        themePreference: ThemePreference.system,
        language: language,
        emailNotifications: true,
        pushNotifications: false,
        rentReminders: true,
        maintenanceUpdates: true,
        updatedAt: DateTime.utc(2026, 1, 1),
        syncMetadata: const SyncMetadata.synced(),
      );

  ProviderContainer harness({
    required UserSession? session,
    required AppLanguage device,
    UserSettings? existing,
    required List<UserSettings> saved,
    SaveUserSettings? save,
  }) {
    return ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(() => _FixedSession(session)),
        deviceLanguageStoreProvider.overrideWithValue(
          _FixedDeviceLanguageStore(device),
        ),
        userSettingsProvider.overrideWith(
          (ref, id) => Stream<UserSettings?>.value(existing),
        ),
        loadUserSettingsProvider.overrideWithValue(
          _FixedLoad((id) async => existing),
        ),
        saveUserSettingsProvider.overrideWithValue(
          save ?? _CapturingSave(saved.add),
        ),
      ],
    );
  }

  const landlord = UserSession(
    userId: 'landlord-1',
    displayName: 'Namuli Landlord',
    email: 'landlord@nyumba.test',
    role: AppRole.landlord,
  );

  test(
    'persists a signed-out language pick the server never learned',
    () async {
      final saved = <UserSettings>[];
      final container = harness(
        session: landlord,
        device: AppLanguage.kiswahili,
        existing: settingsFor('landlord-1'),
        saved: saved,
      );
      addTearDown(container.dispose);
      // Prime the async device language before resolving the effective locale.
      await container.read(deviceLanguageProvider.future);

      expect(container.read(localePreferenceProvider), AppLanguage.kiswahili);
      await container
          .read(localePreferenceProvider.notifier)
          .reconcileServerLocale();

      expect(saved, hasLength(1));
      expect(saved.single.language, AppLanguage.kiswahili);
      // Existing account preferences must survive the locale write.
      expect(saved.single.pushNotifications, isFalse);
    },
  );

  test('is a no-op when the account already knows the language', () async {
    final saved = <UserSettings>[];
    final container = harness(
      session: const UserSession(
        userId: 'landlord-1',
        displayName: 'Namuli Landlord',
        email: 'landlord@nyumba.test',
        role: AppRole.landlord,
        language: AppLanguage.kiswahili,
      ),
      device: AppLanguage.kiswahili,
      existing: settingsFor('landlord-1', language: AppLanguage.kiswahili),
      saved: saved,
    );
    addTearDown(container.dispose);
    await container.read(deviceLanguageProvider.future);

    await container
        .read(localePreferenceProvider.notifier)
        .reconcileServerLocale();

    expect(saved, isEmpty);
  });

  test(
    'does not write English when the server simply has no preference',
    () async {
      final saved = <UserSettings>[];
      final container = harness(
        session: landlord,
        device: AppLanguage.english,
        existing: settingsFor('landlord-1'),
        saved: saved,
      );
      addTearDown(container.dispose);
      await container.read(deviceLanguageProvider.future);

      await container
          .read(localePreferenceProvider.notifier)
          .reconcileServerLocale();

      expect(saved, isEmpty);
    },
  );

  test('skips anonymous sessions with no server document', () async {
    final saved = <UserSettings>[];
    final container = harness(
      session: const UserSession(
        userId: 'anon-1',
        displayName: 'Prospective tenant',
        email: '',
        role: AppRole.client,
        isAnonymous: true,
      ),
      device: AppLanguage.kiswahili,
      saved: saved,
    );
    addTearDown(container.dispose);
    await container.read(deviceLanguageProvider.future);

    await container
        .read(localePreferenceProvider.notifier)
        .reconcileServerLocale();

    expect(saved, isEmpty);
  });

  test('anonymous selection stays device-only', () async {
    const session = UserSession(
      userId: 'anon-1',
      displayName: 'Prospective tenant',
      email: '',
      role: AppRole.client,
      isAnonymous: true,
    );
    final saved = <UserSettings>[];
    final container = harness(
      session: session,
      device: AppLanguage.english,
      saved: saved,
    );
    addTearDown(container.dispose);
    await container.read(deviceLanguageProvider.future);

    await container
        .read(localePreferenceProvider.notifier)
        .select(AppLanguage.luganda);

    expect(container.read(localePreferenceProvider), AppLanguage.luganda);
    expect(saved, isEmpty);
  });

  test('rejected reconciliation remains retryable for the same user', () async {
    final saved = <UserSettings>[];
    final save = _FailOnceSave(saved.add);
    final container = harness(
      session: landlord,
      device: AppLanguage.kiswahili,
      existing: settingsFor('landlord-1'),
      saved: saved,
      save: save,
    );
    addTearDown(container.dispose);
    await container.read(deviceLanguageProvider.future);

    container
        .read(localeReconciliationProvider.notifier)
        .reconcileCurrentSession();
    await _settleReconciliation(container);
    expect(
      container.read(localeReconciliationProvider).status,
      LocaleReconciliationStatus.rejected,
    );

    container.read(localeReconciliationProvider.notifier).retry();
    await _settleReconciliation(container);
    expect(
      container.read(localeReconciliationProvider).status,
      LocaleReconciliationStatus.confirmed,
    );
    expect(saved, hasLength(1));
  });
}

Future<void> _settleReconciliation(ProviderContainer container) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (container.read(localeReconciliationProvider).status !=
        LocaleReconciliationStatus.pending) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _FixedSession extends SessionController {
  _FixedSession(this._session);

  final UserSession? _session;

  @override
  UserSession? build() => _session;
}

class _FixedDeviceLanguageStore implements DeviceLanguageStore {
  _FixedDeviceLanguageStore(this._language);

  AppLanguage _language;

  @override
  Future<AppLanguage?> read() async => _language;

  @override
  Future<void> write(AppLanguage language) async => _language = language;
}

class _FixedLoad implements LoadUserSettings {
  const _FixedLoad(this._load);

  final Future<UserSettings?> Function(String userId) _load;

  @override
  Future<UserSettings?> call(String userId) => _load(userId);
}

class _CapturingSave implements SaveUserSettings {
  const _CapturingSave(this._capture);

  final void Function(UserSettings) _capture;

  @override
  Future<UserSettings> call(UserSettings settings) async {
    _capture(settings);
    return settings;
  }
}

class _FailOnceSave implements SaveUserSettings {
  _FailOnceSave(this._capture);

  final void Function(UserSettings) _capture;
  bool _failed = false;

  @override
  Future<UserSettings> call(UserSettings settings) async {
    if (!_failed) {
      _failed = true;
      throw StateError('temporary failure');
    }
    _capture(settings);
    return settings;
  }
}
