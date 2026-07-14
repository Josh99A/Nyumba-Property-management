import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import '../features/profile/domain/user_settings.dart';
import 'theme/theme_mode_controller.dart';
import 'theme/nyumba_theme.dart';

class NyumbaApp extends ConsumerWidget {
  const NyumbaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final preference = ref.watch(themePreferenceProvider);
    final themeMode = switch (preference) {
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
