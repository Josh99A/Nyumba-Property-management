import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'localization_formats.dart';

/// Flutter does not currently ship Material/Cupertino bundles for `lg`.
/// These delegates keep standard controls available in Luganda instead of
/// silently dropping Material localizations for that locale.
abstract final class LugandaLocalizations {
  static const delegates = <LocalizationsDelegate<dynamic>>[
    _LugandaMaterialDelegate(),
    _LugandaWidgetsDelegate(),
    _LugandaCupertinoDelegate(),
  ];
}

final class _LugandaMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _LugandaMaterialDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lg';

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    await initializeNyumbaLocalizationFormats();
    return LugandaMaterialLocalizations();
  }

  @override
  bool shouldReload(_LugandaMaterialDelegate old) => false;
}

final class LugandaMaterialLocalizations extends MaterialLocalizationEn {
  LugandaMaterialLocalizations()
    : super(
        localeName: 'lg',
        fullYearFormat: DateFormat('y', 'lg'),
        compactDateFormat: DateFormat('yMd', 'lg'),
        shortDateFormat: DateFormat('yMMMd', 'lg'),
        mediumDateFormat: DateFormat('EEE, MMM d', 'lg'),
        longDateFormat: DateFormat('EEEE, MMMM d, y', 'lg'),
        yearMonthFormat: DateFormat('MMMM y', 'lg'),
        shortMonthDayFormat: DateFormat('MMM d', 'lg'),
        decimalFormat: NumberFormat('#,##0.###', 'en_UG'),
        twoDigitZeroPaddedFormat: NumberFormat('00', 'en_UG'),
      );

  @override
  String get cancelButtonLabel => 'Sazaamu';
  @override
  String get closeButtonLabel => 'Ggalawo';
  @override
  String get continueButtonLabel => 'Genda mu maaso';
  @override
  String get copyButtonLabel => 'Koppa';
  @override
  String get cutButtonLabel => 'Sala';
  @override
  String get deleteButtonTooltip => 'Gyawo';
  @override
  String get drawerLabel => 'Menyu y’okutambuliramu';
  @override
  String get firstPageTooltip => 'Omuko ogusooka';
  @override
  String get lastPageTooltip => 'Omuko ogusembayo';
  @override
  String get nextMonthTooltip => 'Omwezi oguddako';
  @override
  String get nextPageTooltip => 'Omuko oguddako';
  @override
  String get okButtonLabel => 'KALE';
  @override
  String get openAppDrawerTooltip => 'Ggulawo menyu';
  @override
  String get pasteButtonLabel => 'Teeka';
  @override
  String get previousMonthTooltip => 'Omwezi oguyise';
  @override
  String get previousPageTooltip => 'Omuko oguyise';
  @override
  String get refreshIndicatorSemanticLabel => 'Ddamu okupakua';
  @override
  String get rowsPerPageTitle => 'Ennyiriri ku muko:';
  @override
  String get saveButtonLabel => 'TEREKA';
  @override
  String get searchFieldLabel => 'Noonya';
  @override
  String get selectAllButtonLabel => 'Londa byonna';
  @override
  String get showMenuTooltip => 'Laga menyu';
  @override
  String get timePickerDialHelpText => 'LONDA ESSAAWA';
  @override
  String get timePickerInputHelpText => 'YINGIZA ESSAAWA';
  @override
  String get viewLicensesButtonLabel => 'Laba layisinsi';
}

final class _LugandaWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _LugandaWidgetsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lg';

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture<WidgetsLocalizations>(
        const DefaultWidgetsLocalizations(),
      );

  @override
  bool shouldReload(_LugandaWidgetsDelegate old) => false;
}

final class _LugandaCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _LugandaCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lg';

  @override
  Future<CupertinoLocalizations> load(Locale locale) async {
    await initializeNyumbaLocalizationFormats();
    return const LugandaCupertinoLocalizations();
  }

  @override
  bool shouldReload(_LugandaCupertinoDelegate old) => false;
}

final class LugandaCupertinoLocalizations
    extends DefaultCupertinoLocalizations {
  const LugandaCupertinoLocalizations();

  @override
  String datePickerMonth(int monthIndex) =>
      DateFormat('MMMM', 'lg').format(DateTime(2020, monthIndex));
  @override
  String datePickerStandaloneMonth(int monthIndex) =>
      datePickerMonth(monthIndex);
  @override
  String datePickerDayOfMonth(int dayIndex, [int? weekDay]) => weekDay == null
      ? '$dayIndex'
      : '${DateFormat('EEE', 'lg').format(DateTime(2020, 1, 6 + weekDay - 1))} $dayIndex';
  @override
  String datePickerMediumDate(DateTime date) =>
      DateFormat('EEE MMM d', 'lg').format(date);
  @override
  DatePickerDateOrder get datePickerDateOrder => DatePickerDateOrder.dmy;
  @override
  String get todayLabel => 'Leero';
  @override
  String get alertDialogLabel => 'Okulabula';
  @override
  String get cutButtonLabel => 'Sala';
  @override
  String get copyButtonLabel => 'Koppa';
  @override
  String get pasteButtonLabel => 'Teeka';
  @override
  String get clearButtonLabel => 'Gyawo';
  @override
  String get selectAllButtonLabel => 'Londa byonna';
  @override
  String get lookUpButtonLabel => 'Noonya';
  @override
  String get searchWebButtonLabel => 'Noonya ku mutimbagano';
  @override
  String get shareButtonLabel => 'Gabana…';
  @override
  String get searchTextFieldPlaceholderLabel => 'Noonya';
  @override
  String get modalBarrierDismissLabel => 'Ggalawo';
  @override
  String get menuDismissLabel => 'Ggalawo menyu';
  @override
  String get cancelButtonLabel => 'Sazaamu';
  @override
  String get backButtonLabel => 'Emabega';
  @override
  String get noSpellCheckReplacementsLabel => 'Tewali bikyusa bifuniddwa';
  @override
  String tabSemanticsLabel({required int tabIndex, required int tabCount}) =>
      'Tabu $tabIndex ku $tabCount';
  @override
  String timerPickerHourLabel(int hour) => 'ssaawa';
  @override
  List<String> get timerPickerHourLabels => const ['ssaawa'];
  @override
  String timerPickerMinuteLabel(int minute) => 'ddak.';
  @override
  List<String> get timerPickerMinuteLabels => const ['ddak.'];
  @override
  String timerPickerSecondLabel(int second) => 'sek.';
  @override
  List<String> get timerPickerSecondLabels => const ['sek.'];
}
