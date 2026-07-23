import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';

import '../domain/biometric_authenticator.dart';

/// [BiometricAuthenticator] backed by the `local_auth` plugin.
final class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() async {
    // local_auth has no web implementation; the web build gets WebAuthn or
    // nothing, so the feature simply does not surface there.
    if (kIsWeb) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<BiometricResult> authenticate(String reason) async {
    try {
      final passed = await _auth.authenticate(
        localizedReason: reason,
        // Let the OS fall back to the device PIN/pattern: wet fingers and
        // failed sensors get a system-quality fallback for free. App lock can
        // be retried from its own screen, so do not persist the native prompt
        // across Activity focus changes.
        biometricOnly: false,
        persistAcrossBackgrounding: false,
      );
      return BiometricResult(
        passed ? BiometricOutcome.success : BiometricOutcome.dismissed,
      );
    } on LocalAuthException catch (error) {
      final outcome = switch (error.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware =>
          BiometricOutcome.unavailable,
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled => BiometricOutcome.dismissed,
        _ => BiometricOutcome.failure,
      };
      return BiometricResult(outcome, message: error.description);
    } on Object catch (error) {
      // MissingPluginException and friends are not PlatformExceptions; an
      // uncaught throw here would leave callers' in-flight flags stuck.
      return BiometricResult(BiometricOutcome.failure, message: '$error');
    }
  }
}
