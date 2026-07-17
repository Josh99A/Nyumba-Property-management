import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'router.dart';
import '../core/localization/luganda_localizations.dart';
import '../core/localization/generated/app_localizations.dart';
import '../core/localization/app_localizations_adapter.dart';
import '../core/localization/nyumba_localizations.dart';
import '../core/presentation/toast.dart';
import '../features/auth/application/session_controller.dart';
import '../features/profile/domain/user_settings.dart';
import 'theme/theme_mode_controller.dart';
import 'theme/nyumba_theme.dart';
import 'localization/locale_controller.dart';

class NyumbaApp extends ConsumerWidget {
  const NyumbaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final language = ref.watch(localePreferenceProvider);
    Intl.defaultLocale = language.intlLocale;
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
    // When a new session arrives, make sure the server knows the language the
    // app is already showing so its notifications are localized to match.
    ref.listen(sessionControllerProvider, (previous, next) {
      if (next != null && previous?.userId != next.userId) {
        ref
            .read(localeReconciliationProvider.notifier)
            .reconcileCurrentSession();
      }
    });
    ref.listen<LocaleReconciliationState>(localeReconciliationProvider, (
      previous,
      next,
    ) {
      if (next.status != LocaleReconciliationStatus.rejected ||
          previous?.status == LocaleReconciliationStatus.rejected) {
        return;
      }
      final copy = appLocalizationsFor(language);
      showNyumbaToast(
        copy.languageSaveFailed,
        variant: NyumbaToastVariant.error,
        action: SnackBarAction(
          label: copy.retry,
          onPressed: () =>
              ref.read(localeReconciliationProvider.notifier).retry(),
        ),
      );
    });
    return MaterialApp.router(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)?.appTitle ??
          'Nyumba Property Management',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'nyumba',
      scaffoldMessengerKey: nyumbaMessengerKey,
      theme: NyumbaTheme.light,
      darkTheme: NyumbaTheme.dark,
      themeMode: themeMode,
      locale: Locale(language.code),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        NyumbaLocalizations.delegate,
        ...LugandaLocalizations.delegates,
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
