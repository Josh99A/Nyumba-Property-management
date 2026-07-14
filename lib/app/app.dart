import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import '../features/auth/application/session_controller.dart';
import '../features/profile/domain/user_settings.dart';
import 'bootstrap/app_dependencies.dart';
import 'theme/nyumba_theme.dart';

class NyumbaApp extends ConsumerWidget {
  const NyumbaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final session = ref.watch(sessionControllerProvider);
    final savedSettings = session == null
        ? const AsyncValue<UserSettings?>.data(null)
        : ref.watch(userSettingsProvider(session.userId));
    final themeMode = switch (savedSettings.value?.themePreference) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp.router(
      title: 'Nyumba Property Management',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'nyumba',
      theme: NyumbaTheme.light,
      darkTheme: NyumbaTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
