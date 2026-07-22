// FirebaseException (thrown by Firestore during the profile load) reaches this
// file through firebase_auth's re-export of firebase_core.
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/offline/command_failure.dart';
import '../../../core/offline/remote_sync_gateway.dart';

/// Sign-in succeeded but the address is unproven, so the session stays closed
/// and a fresh verification link goes out.
class EmailNotVerifiedException implements Exception {
  const EmailNotVerifiedException(this.email);

  final String email;

  @override
  String toString() => 'Verify $email before continuing.';
}

/// True when the person deliberately abandoned a provider popup.
///
/// Firebase reports a dismissed Google window as an exception, but a cancelled
/// sign-in is not a failure: showing an error for it accuses the user of
/// breaking something they chose to do.
bool isAuthCancellation(Object error) =>
    error is FirebaseAuthException &&
    const {
      'popup-closed-by-user',
      'cancelled-popup-request',
      'user-cancelled',
      'web-context-canceled',
    }.contains(error.code);

/// Actionable text for an auth or profile-load failure.
///
/// `error.toString()` puts raw codes such as `[firebase_auth/invalid-credential]`
/// in front of a signed-out user: it names the fault without telling them what
/// to do about it, and leaks internals to someone who is not yet trusted.
String describeAuthFailure(
  Object error, {
  CommandFailureLocalizer? commandFailureLocalizer,
}) {
  if (error is EmailNotVerifiedException) {
    return 'Verify ${error.email} before signing in.';
  }
  if (error is FirebaseAuthException) return _describeAuth(error);
  // Every backend mutation answers with a stable domain code; without this the
  // whole command surface collapsed into "Something went wrong".
  if (error is RemoteSyncException) {
    final failure = describeCommandFailure(error);
    return commandFailureLocalizer?.call(failure) ??
        'Something went wrong. Please try again.';
  }
  if (error is FirebaseException) return _describeBackend(error);
  if (error is StateError) return error.message;
  return 'Something went wrong. Please try again.';
}

String _describeAuth(FirebaseAuthException error) => switch (error.code) {
  // Email-enumeration protection collapses a wrong password and an unknown
  // account into invalid-credential. All three share one message so the reply
  // never confirms whether an address has an account.
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'That email and password do not match an account.',
  'invalid-email' => 'Enter a valid email address.',
  'user-disabled' => 'This account is disabled. Contact Nyumba support.',
  'email-already-in-use' =>
    'An account already uses that email. Sign in instead.',
  'weak-password' => 'Choose a stronger password of at least 8 characters.',
  'operation-not-allowed' => 'That sign-in method is turned off for Nyumba.',
  'too-many-requests' =>
    'Too many attempts. Wait a few minutes before trying again.',
  'network-request-failed' =>
    'No connection. Check your network and try again.',
  'requires-recent-login' => 'Sign in again to confirm this change.',
  'account-exists-with-different-credential' =>
    'That email already signs in another way. Use your password instead.',
  'popup-blocked' =>
    'Your browser blocked the Google window. Allow pop-ups and retry.',
  'unauthorized-domain' =>
    'This site is not authorised for sign-in. Contact Nyumba support.',
  'web-storage-unsupported' =>
    'Your browser is blocking sign-in storage. Turn off private browsing or '
        'allow cookies for this site.',
  _ => error.message ?? 'Sign-in failed. Please try again.',
};

String _describeBackend(FirebaseException error) => switch (error.code) {
  'permission-denied' => 'This account cannot open that workspace.',
  'unavailable' || 'network-request-failed' =>
    'Nyumba cannot reach the server. Check your connection and try again.',
  'deadline-exceeded' => 'The server took too long to respond. Try again.',
  _ => error.message ?? 'Something went wrong. Please try again.',
};
