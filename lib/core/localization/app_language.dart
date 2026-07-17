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

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (language) => language.code == code,
    orElse: () => AppLanguage.english,
  );
}
