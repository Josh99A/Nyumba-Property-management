import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';

// TODO(release): replace through environment-specific build configuration
// after the web app is registered in Firebase App Check. Never commit a real
// production site key to the environment-neutral firebase/ directory.
const _webRecaptchaV3SiteKey = 'TBD_RECAPTCHA_V3_SITE_KEY';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeFirebase();
  // The offline workspace opens lazily per session scope inside
  // appDependenciesProvider; open/seed failures surface through the
  // provider's error state on whichever screen needs the data.
  runApp(const ProviderScope(child: NyumbaApp()));
}

/// Firebase availability must never block the offline-first workspace: a
/// failed initialization leaves sync pending rather than preventing launch.
Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    try {
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaV3Provider(_webRecaptchaV3SiteKey),
        providerAndroid: const AndroidPlayIntegrityProvider(),
        providerApple: const AppleAppAttestProvider(),
      );
    } on Object catch (error, stackTrace) {
      // App Check setup must not prevent access to the local offline source of
      // truth. Callable sync remains pending until platform registration is
      // corrected and activation succeeds.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Nyumba Firebase App Check bootstrap',
        ),
      );
    }
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'Nyumba Firebase bootstrap',
      ),
    );
  }
}
