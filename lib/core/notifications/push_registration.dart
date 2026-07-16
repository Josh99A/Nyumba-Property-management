import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../offline/client_platform.dart';
import '../offline/firebase_remote_sync_gateway.dart';

/// VAPID public key for web push, supplied at build time:
///
/// ```sh
/// flutter build web --release --dart-define=NYUMBA_VAPID_PUBLIC_KEY=<key>
/// ```
///
/// Generated once per Firebase project (Console → Project settings → Cloud
/// Messaging → Web Push certificates). Web push cannot be subscribed without
/// it, so an empty value skips registration on web rather than failing.
const _vapidPublicKey = String.fromEnvironment('NYUMBA_VAPID_PUBLIC_KEY');

/// Outcome of trying to register this device for push.
enum PushRegistration {
  /// A token was obtained and handed to the server.
  registered,

  /// The user declined, or previously declined. Not an error.
  permissionDenied,

  /// Push cannot work in this build or platform (no VAPID key on web, no
  /// APNs token yet on iOS). Not an error either.
  unavailable,

  /// Permission and token were fine but the server did not accept the token.
  /// The app is otherwise usable; the next launch retries.
  registrationFailed,
}

/// Requests notification permission and registers this device's FCM token.
///
/// Every failure path is non-fatal and returns rather than throws: push is a
/// courtesy channel layered over state that is already durable in Firestore and
/// the portal projections. A tenant who declines notifications, or whose token
/// registration fails, must still get a working app.
///
/// Safe to call on every launch. Registration is idempotent on the token, and
/// FCM returns the same token until it rotates.
Future<PushRegistration> registerForPush({
  required Future<FirebaseRemoteSyncGateway> Function() gateway,
  FirebaseMessaging? messaging,
}) async {
  if (kIsWeb && _vapidPublicKey.isEmpty) return PushRegistration.unavailable;
  final instance = messaging ?? FirebaseMessaging.instance;

  try {
    final settings = await instance.requestPermission();
    final status = settings.authorizationStatus;
    if (status != AuthorizationStatus.authorized &&
        status != AuthorizationStatus.provisional) {
      return PushRegistration.permissionDenied;
    }

    // On iOS the APNs token can lag the permission grant; without it getToken
    // throws rather than waiting. Skipping is correct — the next launch has it.
    if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
      final apnsToken = await instance.getAPNSToken();
      if (apnsToken == null) return PushRegistration.unavailable;
    }

    final token = await instance.getToken(
      vapidKey: kIsWeb ? _vapidPublicKey : null,
    );
    if (token == null || token.isEmpty) return PushRegistration.unavailable;

    await (await gateway()).sendCommand(
      type: 'profile.registerDevice',
      payload: <String, Object?>{
        'token': token,
        'platform': currentClientPlatform,
      },
    );
    return PushRegistration.registered;
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'Nyumba push registration',
      ),
    );
    return PushRegistration.registrationFailed;
  }
}
