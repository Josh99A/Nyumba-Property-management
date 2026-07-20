import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/auth/application/app_lock_controller.dart';
import 'package:nyumba_property_management/features/auth/data/app_lock_store.dart';
import 'package:nyumba_property_management/features/auth/domain/biometric_authenticator.dart';

final class _FakeStore implements AppLockStore {
  bool enabled = false;
  bool offered = false;

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
  bool supported = true;
  BiometricResult next = const BiometricResult(BiometricOutcome.success);
  int prompts = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<BiometricResult> authenticate(String reason) async {
    prompts += 1;
    return next;
  }
}

void main() {
  late _FakeStore store;
  late _FakeAuthenticator authenticator;
  late ProviderContainer container;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [
      appLockStoreProvider.overrideWithValue(store),
      biometricAuthenticatorProvider.overrideWithValue(authenticator),
    ],
  );

  setUp(() {
    store = _FakeStore();
    authenticator = _FakeAuthenticator();
    container = buildContainer();
    addTearDown(() => container.dispose());
  });

  /// Lets the controller's async preference restore land.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('cold start engages the lock when the preference is on', () async {
    store.enabled = true;
    final state1 = container.read(appLockControllerProvider);
    expect(state1.enabled, isFalse); // Restore has not landed yet.
    await settle();
    final state = container.read(appLockControllerProvider);
    expect(state.enabled, isTrue);
    expect(state.locked, isTrue);
  });

  test('cold start stays unlocked when the preference is off', () async {
    container.read(appLockControllerProvider);
    await settle();
    final state = container.read(appLockControllerProvider);
    expect(state.enabled, isFalse);
    expect(state.locked, isFalse);
  });

  test('a successful prompt lifts the lock', () async {
    store.enabled = true;
    container.read(appLockControllerProvider);
    await settle();
    final outcome = await container
        .read(appLockControllerProvider.notifier)
        .unlock('reason');
    expect(outcome, BiometricOutcome.success);
    expect(container.read(appLockControllerProvider).locked, isFalse);
  });

  test('a dismissed prompt keeps the lock engaged', () async {
    store.enabled = true;
    authenticator.next = const BiometricResult(BiometricOutcome.dismissed);
    container.read(appLockControllerProvider);
    await settle();
    await container.read(appLockControllerProvider.notifier).unlock('reason');
    final state = container.read(appLockControllerProvider);
    expect(state.locked, isTrue);
    expect(state.unlocking, isFalse);
  });

  test('biometrics gone from the device deactivates the lock', () async {
    store.enabled = true;
    authenticator.next = const BiometricResult(BiometricOutcome.unavailable);
    container.read(appLockControllerProvider);
    await settle();
    final outcome = await container
        .read(appLockControllerProvider.notifier)
        .unlock('reason');
    expect(outcome, BiometricOutcome.unavailable);
    final state = container.read(appLockControllerProvider);
    expect(state.enabled, isFalse);
    expect(state.locked, isFalse);
    expect(store.enabled, isFalse); // Persisted, so the next launch agrees.
  });

  test('re-locks after a background stay past the grace period', () async {
    store.enabled = true;
    container.read(appLockControllerProvider);
    await settle();
    final controller = container.read(appLockControllerProvider.notifier);
    await controller.unlock('reason');

    final leftAt = DateTime(2026, 7, 20, 12);
    controller.handleLifecycle(AppLifecycleState.hidden, at: leftAt);
    controller.handleLifecycle(
      AppLifecycleState.resumed,
      at: leftAt.add(AppLockController.relockAfter),
    );
    expect(container.read(appLockControllerProvider).locked, isTrue);
  });

  test('a brief background hop does not cost a fingerprint', () async {
    store.enabled = true;
    container.read(appLockControllerProvider);
    await settle();
    final controller = container.read(appLockControllerProvider.notifier);
    await controller.unlock('reason');

    final leftAt = DateTime(2026, 7, 20, 12);
    controller.handleLifecycle(AppLifecycleState.hidden, at: leftAt);
    // paused follows hidden on Android; it must not restart the clock.
    controller.handleLifecycle(
      AppLifecycleState.paused,
      at: leftAt.add(const Duration(seconds: 1)),
    );
    controller.handleLifecycle(
      AppLifecycleState.resumed,
      at: leftAt.add(const Duration(seconds: 30)),
    );
    expect(container.read(appLockControllerProvider).locked, isFalse);
  });

  test('enable succeeds only after the prompt passes', () async {
    container.read(appLockControllerProvider);
    await settle();
    final controller = container.read(appLockControllerProvider.notifier);

    authenticator.next = const BiometricResult(BiometricOutcome.dismissed);
    expect(await controller.enable('reason'), isFalse);
    expect(container.read(appLockControllerProvider).enabled, isFalse);
    expect(store.enabled, isFalse);

    authenticator.next = const BiometricResult(BiometricOutcome.success);
    expect(await controller.enable('reason'), isTrue);
    final state = container.read(appLockControllerProvider);
    expect(state.enabled, isTrue);
    expect(state.locked, isFalse); // Enabling must not lock the user out.
    expect(store.enabled, isTrue);
  });

  test('disable clears the preference and the lock', () async {
    store.enabled = true;
    container.read(appLockControllerProvider);
    await settle();
    await container.read(appLockControllerProvider.notifier).disable();
    final state = container.read(appLockControllerProvider);
    expect(state.enabled, isFalse);
    expect(state.locked, isFalse);
    expect(store.enabled, isFalse);
  });

  test('signing out stands the gate down', () async {
    store.enabled = true;
    container.read(appLockControllerProvider);
    await settle();
    container.read(appLockControllerProvider.notifier).handleSignedOut();
    final state = container.read(appLockControllerProvider);
    expect(state.locked, isFalse);
    expect(state.enabled, isTrue); // The device preference survives sign-out.
  });

  test('the enrollment offer shows once and only where it can work', () async {
    container.read(appLockControllerProvider);
    await settle();
    final controller = container.read(appLockControllerProvider.notifier);

    expect(await controller.shouldOffer(), isTrue);
    expect(await controller.shouldOffer(), isFalse); // Marked as shown.

    store.offered = false;
    authenticator.supported = false;
    expect(await controller.shouldOffer(), isFalse);
  });
}
