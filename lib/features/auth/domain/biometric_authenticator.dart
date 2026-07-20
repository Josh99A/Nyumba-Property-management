/// Outcome of one OS biometric prompt.
enum BiometricOutcome {
  /// The user passed the biometric (or device-credential fallback) check.
  success,

  /// The user dismissed or failed the prompt; nothing is wrong with the
  /// device, so the caller may simply offer to try again.
  dismissed,

  /// The device can no longer verify its owner (biometrics unenrolled, no
  /// passcode set, sensor gone). The app lock cannot keep its promise and
  /// should deactivate rather than trap the user.
  unavailable,

  /// A transient platform failure (for example: locked out after too many
  /// attempts). The lock stays engaged; [BiometricResult.message] explains.
  failure,
}

class BiometricResult {
  const BiometricResult(this.outcome, {this.message});

  final BiometricOutcome outcome;
  final String? message;
}

/// Port for the platform biometric prompt, so the app-lock logic can be
/// exercised in tests without a device.
abstract interface class BiometricAuthenticator {
  /// Whether this device can offer biometric unlock at all: a supported
  /// platform with at least one enrolled biometric.
  Future<bool> isSupported();

  /// Shows the OS prompt. [reason] is the already-localized sentence the OS
  /// displays to explain why the app is asking.
  Future<BiometricResult> authenticate(String reason);
}
