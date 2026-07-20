import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
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
        options: const AuthenticationOptions(
          // Let the OS fall back to the device PIN/pattern: wet fingers and
          // failed sensors get a system-quality fallback for free.
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      return BiometricResult(
        passed ? BiometricOutcome.success : BiometricOutcome.dismissed,
      );
    } on PlatformException catch (error) {
      final outcome = switch (error.code) {
        auth_error.notAvailable ||
        auth_error.notEnrolled ||
        auth_error.passcodeNotSet => BiometricOutcome.unavailable,
        _ => BiometricOutcome.failure,
      };
      return BiometricResult(outcome, message: error.message);
    }
  }
}
