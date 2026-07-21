import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/features/auth/application/app_lock_controller.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/data/app_lock_store.dart';
import 'package:nyumba_property_management/features/auth/domain/biometric_authenticator.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/profile/application/profile_use_cases.dart';
import 'package:nyumba_property_management/features/profile/domain/user_settings.dart';
import 'package:nyumba_property_management/features/profile/presentation/profile_settings_screen.dart';

/// The security card is hidden wherever biometrics are unsupported, which
/// includes every headless and web target — so its visibility is only ever
/// provable here, with support forced on.
void main() {
  late _FakeStore store;
  late _FakeAuthenticator authenticator;

  setUp(() {
    store = _FakeStore();
    authenticator = _FakeAuthenticator();
  });

  Widget harness({bool supported = true}) => ProviderScope(
    overrides: [
      appLockStoreProvider.overrideWithValue(store),
      biometricAuthenticatorProvider.overrideWithValue(authenticator),
      biometricSupportProvider.overrideWith((ref) => supported),
      sessionControllerProvider.overrideWith(_FixedSession.new),
      loadUserSettingsProvider.overrideWithValue(const _NoStoredSettings()),
    ],
    child: MaterialApp(
      theme: NyumbaTheme.light,
      home: const Scaffold(body: ProfileSettingsScreen()),
    ),
  );

  testWidgets('an unprotected device leads with an explicit enable button', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final button = find.widgetWithText(
      FilledButton,
      'Turn on fingerprint unlock',
    );
    expect(button, findsOneWidget);
    expect(find.text('Fingerprint unlock'), findsOneWidget);

    // The card must lead the preference column: the appearance controls it
    // used to hide behind start further down the page.
    final lockY = tester.getTopLeft(find.text('Fingerprint unlock')).dy;
    final appearanceY = tester.getTopLeft(find.text('Appearance')).dy;
    expect(lockY, lessThan(appearanceY));

    // A filled button carries the page's primary emphasis; the notification
    // switches below it deliberately do not.
    expect(
      tester.widget<FilledButton>(button).enabled,
      isTrue,
      reason: 'the enable action must be actionable, not a disabled hint',
    );
  });

  testWidgets('enabling swaps the card to its protected state', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Turn on fingerprint unlock'));
    await tester.pumpAndSettle();

    expect(authenticator.prompts, 1);
    expect(store.enabled, isTrue);
    expect(find.text('Turn on fingerprint unlock'), findsNothing);
    expect(find.text('Turn off fingerprint unlock'), findsOneWidget);
    expect(
      find.text('On. Your fingerprint is required when Nyumba reopens.'),
      findsOneWidget,
    );
  });

  testWidgets('a refused prompt leaves the enable button offered', (
    tester,
  ) async {
    authenticator.next = const BiometricResult(BiometricOutcome.dismissed);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Turn on fingerprint unlock'));
    await tester.pumpAndSettle();

    expect(store.enabled, isFalse);
    expect(find.text('Turn on fingerprint unlock'), findsOneWidget);
    expect(find.text('Fingerprint unlock was not turned on.'), findsOneWidget);
  });

  testWidgets('a device without biometrics is offered nothing', (tester) async {
    await tester.pumpWidget(harness(supported: false));
    await tester.pumpAndSettle();

    expect(find.text('Fingerprint unlock'), findsNothing);
    expect(find.text('Turn on fingerprint unlock'), findsNothing);
    // The rest of the screen is unaffected.
    expect(find.text('Appearance'), findsOneWidget);
  });
}

final class _FakeStore implements AppLockStore {
  bool enabled = false;
  bool offered = true;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool value) async => enabled = value;

  @override
  Future<bool> readOffered() async => offered;

  @override
  Future<void> markOffered() async => offered = true;
}

final class _FakeAuthenticator implements BiometricAuthenticator {
  BiometricResult next = const BiometricResult(BiometricOutcome.success);
  int prompts = 0;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<BiometricResult> authenticate(String reason) async {
    prompts += 1;
    return next;
  }
}

class _FixedSession extends SessionController {
  @override
  UserSession? build() => const UserSession(
    userId: 'landlord-1',
    displayName: 'Namuli Landlord',
    email: 'landlord@nyumba.test',
    role: AppRole.landlord,
  );
}

class _NoStoredSettings implements LoadUserSettings {
  const _NoStoredSettings();

  @override
  Future<UserSettings?> call(String userId) async => null;
}
