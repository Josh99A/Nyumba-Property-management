import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';

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
