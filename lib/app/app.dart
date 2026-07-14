import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/nyumba_theme.dart';

class NyumbaApp extends ConsumerWidget {
  const NyumbaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Nyumba Property Management',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'nyumba',
      theme: NyumbaTheme.light,
      darkTheme: NyumbaTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
