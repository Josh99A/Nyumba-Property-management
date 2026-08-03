import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/localization/localization_formats.dart';
import 'firebase_options.dart';

/// reCAPTCHA v3 site key for web App Check, supplied at build time:
///
/// ```sh
/// flutter build web --release --dart-define=NYUMBA_RECAPTCHA_V3_SITE_KEY=<key>
/// ```
///
/// Empty by default, which disables activation. A site key is not a secret (it
/// ships in the page), but it *is* environment-specific: staging and production
/// register different keys, so hard-coding one here would silently point a
/// production build at the wrong project's App Check. Each deploy workflow
/// carries the key for the project it deploys to — the development key lives in
/// `.github/workflows/ci-cd.yml`. See `docs/architecture/README.md` for the
/// registration steps.
const _webRecaptchaV3SiteKey = String.fromEnvironment(
  'NYUMBA_RECAPTCHA_V3_SITE_KEY',
);

/// A registered App Check debug token for non-release builds, supplied at build
/// time:
///
/// ```sh
/// flutter run --profile --dart-define=NYUMBA_APP_CHECK_DEBUG_TOKEN=<uuid>
/// ```
///
/// Empty by default, in which case the debug provider mints a fresh token and
/// prints it once per install — fine for a single developer, but it has to be
/// pasted into the console every reinstall. Registering one token and passing it
/// here keeps every development device attested across reinstalls. A debug token
/// *is* a secret: anyone holding it can produce valid App Check tokens for the
/// project, so it belongs in a local `--dart-define`, never in a committed file
/// or a CI workflow that publishes artefacts.
const _appCheckDebugToken = String.fromEnvironment(
  'NYUMBA_APP_CHECK_DEBUG_TOKEN',
);

/// [_appCheckDebugToken], or null when the define was left empty — which is
/// what tells the debug provider to mint and log a token of its own.
const String? _configuredDebugToken = _appCheckDebugToken == ''
    ? null
    : _appCheckDebugToken;

/// A ceiling on how long App Check activation may hold up the first frame.
///
/// Activation is normally near-instant, but it can reach the network, and the
/// whole point of the offline-first workspace is that a stalled Firebase call
/// never gates the UI. Exceeding this is reported like any other activation
/// failure and the app carries on unattested.
const _appCheckActivationBudget = Duration(seconds: 5);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNyumbaLocalizationFormats();
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
    var options = DefaultFirebaseOptions.currentPlatform;
    if (kIsWeb) {
      options = options.copyWith(
        authDomain: _webAuthDomain(options.authDomain),
      );
    }
    await Firebase.initializeApp(options: options);
    // Push registration deliberately does not happen here: it names a user, and
    // no one is signed in yet. SessionController registers once a verified
    // session resolves.
    //
    // Web activation needs a site key for this environment. Android and iOS
    // need no required build input, so they activate whenever the platform is
    // registered; the backend keeps enforcement off until every platform is.
    if (kIsWeb && _webRecaptchaV3SiteKey.isEmpty) return;
    try {
      await FirebaseAppCheck.instance
          .activate(
            providerWeb: kIsWeb
                ? ReCaptchaV3Provider(_webRecaptchaV3SiteKey)
                : null,
            // Play Integrity and App Attest attest the *distribution*, not just
            // the binary: they only return a valid verdict for an install that
            // came from Play or the App Store. A debug or profile build running
            // on a developer's device can never satisfy either, so it answered
            // every token request with an attestation failure and was then
            // throttled — 54 token warnings in a single profile session — while
            // anything the backend enforces (a Firestore listener, a callable)
            // was rejected outright for want of a token. Non-release builds
            // therefore use the debug provider, whose token is registered by
            // hand in the console; Play-distributed release builds keep real
            // attestation, which is the only place it means anything.
            providerAndroid: kReleaseMode
                ? const AndroidPlayIntegrityProvider()
                : const AndroidDebugProvider(debugToken: _configuredDebugToken),
            providerApple: kReleaseMode
                ? const AppleAppAttestProvider()
                : const AppleDebugProvider(debugToken: _configuredDebugToken),
          )
          .timeout(_appCheckActivationBudget);
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

/// Serves the Google/OAuth handler from the origin the app is already running
/// on, instead of the generated `<project>.firebaseapp.com`.
///
/// Browsers that partition storage give a cross-origin handler a different
/// storage bucket than the app, so the handler cannot read the state the app
/// wrote and sign-in fails with "missing initial state". Firebase Hosting
/// serves the helper at `/__/auth` on every site in the project, so the app's
/// own origin is always a valid same-origin handler. A dev server has no such
/// helper, so local hosts keep the generated domain.
String? _webAuthDomain(String? generated) {
  const localHosts = {'localhost', '127.0.0.1', '0.0.0.0'};
  final host = Uri.base.host;
  if (host.isEmpty || localHosts.contains(host)) return generated;
  return host;
}
