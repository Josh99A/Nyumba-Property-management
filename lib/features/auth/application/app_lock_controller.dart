import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_lock_store.dart';
import '../data/local_auth_biometric_authenticator.dart';
import '../domain/biometric_authenticator.dart';

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => LocalAuthBiometricAuthenticator(),
);

final appLockStoreProvider = Provider<AppLockStore>(
  (ref) => const SecureAppLockStore(),
);

/// Whether this device can offer biometric unlock. Settings uses it to decide
/// if the toggle appears at all; unsupported devices never see the feature.
final biometricSupportProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricAuthenticatorProvider).isSupported(),
);

final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

@immutable
class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.unlocking = false,
  });

  final bool enabled;
  final bool locked;

  /// True while an OS prompt is on screen, so a second tap cannot stack a
  /// second prompt on top of the first.
  final bool unlocking;

  AppLockState copyWith({bool? enabled, bool? locked, bool? unlocking}) =>
      AppLockState(
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
        unlocking: unlocking ?? this.unlocking,
      );
}

/// UI gate over an already-persisted Firebase session.
///
/// Biometrics cannot sign anyone in — there is no server-side fingerprint
/// credential — so this deliberately stores no secret and touches no token.
/// It only decides whether the workspace is visible: locked on cold start and
/// after the app spends longer than [relockAfter] in the background.
class AppLockController extends Notifier<AppLockState> {
  /// Backgrounding shorter than this does not re-prompt: momentarily checking
  /// another app should not cost a fingerprint on every return.
  static const relockAfter = Duration(minutes: 2);

  DateTime? _hiddenAt;

  @override
  AppLockState build() {
    // The preference read is async; until it lands the lock reports disabled.
    // The launch splash covers that window, so an enabled lock is engaged
    // before the workspace is ever visible.
    Future<void>.microtask(_restore);
    return const AppLockState();
  }

  Future<void> _restore() async {
    final enabled = await ref.read(appLockStoreProvider).readEnabled();
    if (enabled) state = state.copyWith(enabled: true, locked: true);
  }

  /// Turns the lock on after one successful biometric pass, proving the
  /// prompt works on this device before the app starts relying on it.
  Future<bool> enable(String reason) async {
    final result = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(reason);
    if (result.outcome != BiometricOutcome.success) return false;
    await ref.read(appLockStoreProvider).writeEnabled(true);
    state = state.copyWith(enabled: true, locked: false);
    return true;
  }

  Future<void> disable() async {
    await ref.read(appLockStoreProvider).writeEnabled(false);
    _hiddenAt = null;
    state = const AppLockState();
  }

  /// Runs the OS prompt and lifts the lock on success. Returns the outcome so
  /// the lock screen can phrase what happened; on [BiometricOutcome.unavailable]
  /// the lock deactivates entirely — removing an enrolled biometric already
  /// required the device PIN, so this is the owner reconfiguring their device,
  /// and a lock that can never be passed would just trap them.
  Future<BiometricOutcome> unlock(String reason) async {
    if (state.unlocking) return BiometricOutcome.dismissed;
    if (!state.locked) return BiometricOutcome.success;
    state = state.copyWith(unlocking: true);
    final result = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(reason);
    switch (result.outcome) {
      case BiometricOutcome.success:
        state = state.copyWith(locked: false, unlocking: false);
      case BiometricOutcome.unavailable:
        await ref.read(appLockStoreProvider).writeEnabled(false);
        _hiddenAt = null;
        state = const AppLockState();
      case BiometricOutcome.dismissed || BiometricOutcome.failure:
        state = state.copyWith(unlocking: false);
    }
    return result.outcome;
  }

  /// Fed by the app-level lifecycle observer. [at] exists for tests.
  void handleLifecycle(AppLifecycleState lifecycle, {DateTime? at}) {
    if (!state.enabled) return;
    final now = at ?? DateTime.now();
    switch (lifecycle) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        // Keep the earliest timestamp: paused follows hidden and must not
        // restart the grace period.
        _hiddenAt ??= now;
      case AppLifecycleState.resumed:
        final hiddenAt = _hiddenAt;
        _hiddenAt = null;
        if (state.locked || hiddenAt == null) return;
        if (now.difference(hiddenAt) >= relockAfter) {
          state = state.copyWith(locked: true);
        }
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        // inactive fires for transient interruptions (notification shade,
        // permission dialogs, the biometric prompt itself); reacting to it
        // would re-lock the app while the user is trying to unlock it.
        break;
    }
  }

  /// Signing out removes everything the lock protects, and the sign-in that
  /// follows is itself proof of identity, so the gate stands down until the
  /// next cold start or background timeout.
  void handleSignedOut() {
    _hiddenAt = null;
    if (state.locked) state = state.copyWith(locked: false, unlocking: false);
  }

  /// One-time enrollment nudge after sign-in: true only the first time a
  /// capable device lands a session with the lock off. Marks the offer as
  /// shown so it never nags again.
  Future<bool> shouldOffer() async {
    if (state.enabled) return false;
    final store = ref.read(appLockStoreProvider);
    if (await store.readOffered()) return false;
    if (!await ref.read(biometricAuthenticatorProvider).isSupported()) {
      return false;
    }
    await store.markOffered();
    return true;
  }
}
