import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:nyumba_property_management/features/auth/data/local_auth_biometric_authenticator.dart';
import 'package:nyumba_property_management/features/auth/domain/biometric_authenticator.dart';

final class _FakeLocalAuthentication extends LocalAuthentication {
  bool authenticateResult = true;
  LocalAuthException? authenticateError;
  bool? persistedAcrossBackgrounding;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const <Object>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    persistedAcrossBackgrounding = persistAcrossBackgrounding;
    final error = authenticateError;
    if (error != null) throw error;
    return authenticateResult;
  }

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [
    BiometricType.fingerprint,
  ];
}

void main() {
  test(
    'authentication does not persist across Android focus changes',
    () async {
      final auth = _FakeLocalAuthentication();
      final adapter = LocalAuthBiometricAuthenticator(auth: auth);

      final result = await adapter.authenticate('Unlock Nyumba');

      expect(result.outcome, BiometricOutcome.success);
      expect(auth.persistedAcrossBackgrounding, isFalse);
    },
  );

  test('system cancellation is a dismissed prompt', () async {
    final auth = _FakeLocalAuthentication()
      ..authenticateError = const LocalAuthException(
        code: LocalAuthExceptionCode.systemCanceled,
      );

    final result = await LocalAuthBiometricAuthenticator(
      auth: auth,
    ).authenticate('Unlock Nyumba');

    expect(result.outcome, BiometricOutcome.dismissed);
  });

  test('missing credentials make app lock unavailable', () async {
    final auth = _FakeLocalAuthentication()
      ..authenticateError = const LocalAuthException(
        code: LocalAuthExceptionCode.noCredentialsSet,
      );

    final result = await LocalAuthBiometricAuthenticator(
      auth: auth,
    ).authenticate('Unlock Nyumba');

    expect(result.outcome, BiometricOutcome.unavailable);
  });

  test('device errors keep app lock enabled for a retry', () async {
    final auth = _FakeLocalAuthentication()
      ..authenticateError = const LocalAuthException(
        code: LocalAuthExceptionCode.deviceError,
        description: 'Sensor busy',
      );

    final result = await LocalAuthBiometricAuthenticator(
      auth: auth,
    ).authenticate('Unlock Nyumba');

    expect(result.outcome, BiometricOutcome.failure);
    expect(result.message, 'Sensor busy');
  });
}
