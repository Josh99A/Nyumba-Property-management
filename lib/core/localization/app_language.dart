enum AppLanguage {
  english(code: 'en', nativeName: 'English'),
  luganda(code: 'lg', nativeName: 'Luganda'),
  kiswahili(code: 'sw', nativeName: 'Kiswahili'),
  arabic(code: 'ar', nativeName: '\u0627\u0644\u0639\u0631\u0628\u064a\u0629');

  const AppLanguage({required this.code, required this.nativeName});

  final String code;
  final String nativeName;

  /// Locale used by `intl`. Luganda calendar data is registered at startup.
  String get intlLocale => switch (this) {
    AppLanguage.english => 'en_UG',
    AppLanguage.luganda => 'lg',
    AppLanguage.kiswahili => 'sw',
    AppLanguage.arabic => 'ar',
  };

  /// Locale used by `intl` for numbers and money.
  ///
  /// CLDR carries no number symbols for Luganda, and `NumberFormat` throws on
  /// a locale it does not know rather than falling back, so a Luganda screen
  /// that formats rent would crash. Ugandan English groups and separates
  /// digits identically, so Luganda borrows it. Dates are unaffected: Luganda
  /// calendar names are registered with `intl` at startup.
  String get intlNumberLocale =>
      this == AppLanguage.luganda ? AppLanguage.english.intlLocale : intlLocale;

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (language) => language.code == code,
    orElse: () => AppLanguage.english,
  );

  /// Resolves an `intl` locale name — `lg`, `en`, `lg_UG` — back to the
  /// language it was loaded for, so formatting can follow the active catalogue.
  static AppLanguage fromLocaleName(String localeName) =>
      fromCode(localeName.split(RegExp('[_-]')).first);
}
