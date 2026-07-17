import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class NyumbaLocalizations {
  NyumbaLocalizations._({
    required this.locale,
    required Map<String, String> englishByKey,
    required Map<String, String> localizedByKey,
  }) : _byKey = {
         for (final entry in englishByKey.entries)
           entry.key: localizedByKey[entry.key] ?? entry.value,
       },
       _bySource = {
         for (final entry in englishByKey.entries)
           entry.value: localizedByKey[entry.key] ?? entry.value,
       },
       _templates = _buildTemplates(englishByKey, localizedByKey);

  final Locale locale;
  final Map<String, String> _byKey;
  final Map<String, String> _bySource;
  final List<_TemplateTranslation> _templates;

  static const LocalizationsDelegate<NyumbaLocalizations> delegate =
      _NyumbaLocalizationsDelegate();

  static final NyumbaLocalizations _englishFallback = NyumbaLocalizations._(
    locale: const Locale('en'),
    englishByKey: const {},
    localizedByKey: const {},
  );

  /// Falls back to unchanged English source copy for isolated widgets that
  /// are intentionally rendered without the app-level localization delegate.
  static NyumbaLocalizations of(BuildContext context) =>
      maybeOf(context) ?? _englishFallback;

  static NyumbaLocalizations? maybeOf(BuildContext context) =>
      Localizations.of<NyumbaLocalizations>(context, NyumbaLocalizations);

  String key(String key) => _byKey[key] ?? key;

  /// Translates existing English source copy while the application migrates
  /// to generated typed getters. Exact source messages are preferred; ARB
  /// placeholder templates cover interpolated values without translating the
  /// user-supplied value itself.
  String text(String source) {
    final exact = _bySource[source];
    if (exact != null) return exact;
    for (final template in _templates) {
      final translated = template.apply(source);
      if (translated != null) return translated;
    }
    return source;
  }

  static List<_TemplateTranslation> _buildTemplates(
    Map<String, String> english,
    Map<String, String> localized,
  ) => [
    for (final entry in english.entries)
      if (entry.value.contains('{'))
        _TemplateTranslation(
          source: entry.value,
          target: localized[entry.key] ?? entry.value,
        ),
  ];
}

extension NyumbaLocalizationContext on BuildContext {
  NyumbaLocalizations get l10n => NyumbaLocalizations.of(this);

  String tr(String source) => l10n.text(source);
}

final class _NyumbaLocalizationsDelegate
    extends LocalizationsDelegate<NyumbaLocalizations> {
  const _NyumbaLocalizationsDelegate();

  static const _supported = {'en', 'lg', 'sw', 'ar'};

  @override
  bool isSupported(Locale locale) => _supported.contains(locale.languageCode);

  @override
  Future<NyumbaLocalizations> load(Locale locale) async {
    final code = isSupported(locale) ? locale.languageCode : 'en';
    final english = await _loadArb('en');
    final localized = code == 'en' ? english : await _loadArb(code);
    return NyumbaLocalizations._(
      locale: Locale(code),
      englishByKey: english,
      localizedByKey: localized,
    );
  }

  Future<Map<String, String>> _loadArb(String code) async {
    final source = await rootBundle.loadString('assets/l10n/app_$code.arb');
    final json = jsonDecode(source) as Map<String, dynamic>;
    return {
      for (final entry in json.entries)
        if (!entry.key.startsWith('@') && entry.value is String)
          entry.key: entry.value as String,
    };
  }

  @override
  bool shouldReload(_NyumbaLocalizationsDelegate old) => false;
}

final class _TemplateTranslation {
  _TemplateTranslation({required String source, required this.target}) {
    final matches = _placeholder.allMatches(source).toList();
    final pattern = StringBuffer('^');
    var cursor = 0;
    for (final match in matches) {
      pattern.write(RegExp.escape(source.substring(cursor, match.start)));
      pattern.write('(.+?)');
      _names.add(match.group(1)!);
      cursor = match.end;
    }
    pattern.write(RegExp.escape(source.substring(cursor)));
    pattern.write(r'$');
    _sourcePattern = RegExp(pattern.toString(), dotAll: true);
  }

  static final _placeholder = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}');

  final String target;
  final List<String> _names = [];
  late final RegExp _sourcePattern;

  String? apply(String input) {
    final match = _sourcePattern.firstMatch(input);
    if (match == null) return null;
    final values = <String, String>{
      for (var index = 0; index < _names.length; index++)
        _names[index]: match.group(index + 1) ?? '',
    };
    return target.replaceAllMapped(
      _placeholder,
      (placeholder) => values[placeholder.group(1)] ?? placeholder.group(0)!,
    );
  }
}
