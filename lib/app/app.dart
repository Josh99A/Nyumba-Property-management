import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import '../core/presentation/toast.dart';
import '../features/auth/application/session_controller.dart';
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
    // Sign-in resolution finishes on the auth-state listener, after the form
    // that started it has been redirected away. Watching from the root is what
    // gives those outcomes somewhere to surface.
    ref.listen<SessionResolution>(sessionResolutionProvider, (_, next) {
      final error = next.error;
      if (error != null) {
        showNyumbaToast(error, variant: NyumbaToastVariant.error);
        return;
      }
      final welcome = next.welcome;
      if (welcome != null) {
        showNyumbaToast(
          'Welcome back, $welcome.',
          variant: NyumbaToastVariant.success,
        );
      }
    });
    return MaterialApp.router(
      title: 'Nyumba Property Management',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'nyumba',
      scaffoldMessengerKey: nyumbaMessengerKey,
      theme: NyumbaTheme.light,
      darkTheme: NyumbaTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
