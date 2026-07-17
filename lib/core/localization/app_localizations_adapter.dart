import 'app_language.dart';
import 'generated/app_localizations.dart';
import 'generated/app_localizations_ar.dart';
import 'generated/app_localizations_en.dart';
import 'generated/app_localizations_lg.dart';
import 'generated/app_localizations_sw.dart';

/// Resolves generated application copy outside a widget tree, including PDF
/// rendering and background/push presentation adapters.
AppLocalizations appLocalizationsFor(AppLanguage language) =>
    switch (language) {
      AppLanguage.english => AppLocalizationsEn(),
      AppLanguage.luganda => AppLocalizationsLg(),
      AppLanguage.kiswahili => AppLocalizationsSw(),
      AppLanguage.arabic => AppLocalizationsAr(),
    };
