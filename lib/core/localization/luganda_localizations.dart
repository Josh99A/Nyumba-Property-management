import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

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
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(LugandaMaterialLocalizations());

  @override
  bool shouldReload(_LugandaMaterialDelegate old) => false;
}

final class LugandaMaterialLocalizations extends MaterialLocalizationEn {
  LugandaMaterialLocalizations()
    : super(
        localeName: 'lg',
        fullYearFormat: DateFormat('y', 'en'),
        compactDateFormat: DateFormat('yMd', 'en'),
        shortDateFormat: DateFormat('yMMMd', 'en'),
        mediumDateFormat: DateFormat('EEE, MMM d', 'en'),
        longDateFormat: DateFormat('EEEE, MMMM d, y', 'en'),
        yearMonthFormat: DateFormat('MMMM y', 'en'),
        shortMonthDayFormat: DateFormat('MMM d', 'en'),
        decimalFormat: NumberFormat('#,##0.###', 'en'),
        twoDigitZeroPaddedFormat: NumberFormat('00', 'en'),
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
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(
        const DefaultCupertinoLocalizations(),
      );

  @override
  bool shouldReload(_LugandaCupertinoDelegate old) => false;
}
