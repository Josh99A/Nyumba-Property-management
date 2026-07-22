import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/auth/domain/auth_failure.dart';
import 'package:nyumba_property_management/core/localization/app_language.dart';
import 'package:nyumba_property_management/core/offline/remote_sync_gateway.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';

FirebaseAuthException _authError(String code, {String? message}) =>
    FirebaseAuthException(code: code, message: message);

void main() {
  group('describeAuthFailure', () {
    test('never leaks a raw Firebase code to a signed-out user', () {
      // The regression this guards: forms rendered error.toString(), putting
      // '[firebase_auth/invalid-credential]' on screen, which names the fault
      // without telling the person what to do about it.
      for (final code in const [
        'invalid-credential',
        'wrong-password',
        'user-not-found',
        'invalid-email',
        'user-disabled',
        'email-already-in-use',
        'weak-password',
        'too-many-requests',
        'network-request-failed',
        'popup-blocked',
        'unauthorized-domain',
        'web-storage-unsupported',
      ]) {
        final described = describeAuthFailure(_authError(code));
        expect(described, isNot(contains('firebase_auth')));
        expect(described, isNot(contains(code)));
        expect(described, isNotEmpty);
      }
    });

    test('gives a wrong password and an unknown account the same answer', () {
      // Email-enumeration protection collapses these server-side; the wording
      // must not re-open the oracle by distinguishing them.
      final invalid = describeAuthFailure(_authError('invalid-credential'));
      expect(describeAuthFailure(_authError('wrong-password')), invalid);
      expect(describeAuthFailure(_authError('user-not-found')), invalid);
    });

    test('names the address that still needs verifying', () {
      final described = describeAuthFailure(
        const EmailNotVerifiedException('joshua@example.com'),
      );
      expect(described, contains('joshua@example.com'));
    });

    test('falls back to the server message for an unmapped code', () {
      expect(
        describeAuthFailure(
          _authError('some-new-code', message: 'Server said no.'),
        ),
        'Server said no.',
      );
    });

    test('still says something useful for an unmapped, message-less code', () {
      expect(describeAuthFailure(_authError('some-new-code')), isNotEmpty);
    });

    test('unwraps a StateError rather than printing "Bad state:"', () {
      expect(
        describeAuthFailure(StateError('Firebase is not configured.')),
        'Firebase is not configured.',
      );
    });

    test('has an answer for an error of no known type', () {
      expect(describeAuthFailure(Exception('boom')), isNotEmpty);
    });
  });

  group('isAuthCancellation', () {
    test('treats a dismissed provider popup as a choice, not a fault', () {
      // Showing an error toast here accuses the user of breaking something
      // they deliberately did.
      expect(isAuthCancellation(_authError('popup-closed-by-user')), isTrue);
      expect(isAuthCancellation(_authError('cancelled-popup-request')), isTrue);
      expect(isAuthCancellation(_authError('user-cancelled')), isTrue);
      expect(isAuthCancellation(_authError('web-context-canceled')), isTrue);
    });

    test('does not swallow a real failure', () {
      expect(isAuthCancellation(_authError('invalid-credential')), isFalse);
      expect(isAuthCancellation(_authError('popup-blocked')), isFalse);
      expect(isAuthCancellation(StateError('nope')), isFalse);
    });
  });

  test('session-owned command failures use the active language', () {
    const error = RemoteSyncException('SEAT_LIMIT_REACHED', retryable: false);
    final english = describeLocalizedSessionFailure(error, AppLanguage.english);
    final arabic = describeLocalizedSessionFailure(error, AppLanguage.arabic);
    expect(arabic, isNot(english));
    expect(arabic, isNotEmpty);
  });
}
