import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/date_symbol_data_local.dart' as local_data;
import 'package:intl/date_symbols.dart';
import 'package:intl/date_time_patterns.dart';

/// Registers the Luganda calendar names missing from the `intl` CLDR bundle.
///
/// This runs before the first widget is built so existing `DateFormat` calls
/// automatically follow the active application locale, including Luganda.
Future<void>? _initialization;
bool _initialized = false;

Future<void> initializeNyumbaLocalizationFormats() async {
  if (_initialized) return;
  final inFlight = _initialization;
  if (inFlight != null) return inFlight;
  final initialization = _initializeNyumbaLocalizationFormats();
  _initialization = initialization;
  try {
    await initialization;
    _initialized = true;
  } finally {
    _initialization = null;
  }
}

Future<void> _initializeNyumbaLocalizationFormats() async {
  await local_data.initializeDateFormatting();

  final english = local_data.dateTimeSymbolMap()['en']!;
  final symbols = english.serializeToMap()
    ..['NAME'] = 'lg'
    ..['ERANAMES'] = const [
      'Nga Kristo tannazaalibwa',
      'Nga Kristo amaze okuzaalibwa',
    ]
    ..['MONTHS'] = _months
    ..['STANDALONEMONTHS'] = _months
    ..['SHORTMONTHS'] = _shortMonths
    ..['STANDALONESHORTMONTHS'] = _shortMonths
    ..['WEEKDAYS'] = _weekdays
    ..['STANDALONEWEEKDAYS'] = _weekdays
    ..['SHORTWEEKDAYS'] = _shortWeekdays
    ..['STANDALONESHORTWEEKDAYS'] = _shortWeekdays
    ..['NARROWWEEKDAYS'] = _narrowWeekdays
    ..['STANDALONENARROWWEEKDAYS'] = _narrowWeekdays
    ..['AMPMS'] = const ['AM', 'PM'];

  initializeDateFormattingCustom(
    locale: 'lg',
    symbols: DateSymbols.deserializeFromMap(symbols),
    patterns: Map<String, String>.from(dateTimePatternMap()['en']!),
  );
}

const _months = <String>[
  'Janwali',
  'Febwali',
  'Maaci',
  'Apuli',
  'Maayi',
  'Juuni',
  'Julaayi',
  'Agusito',
  'Ssebutemba',
  'Okitobba',
  'Novemba',
  'Desemba',
];

const _shortMonths = <String>[
  'Jan',
  'Feb',
  'Maa',
  'Apu',
  'Maa',
  'Juu',
  'Jul',
  'Agu',
  'Seb',
  'Oki',
  'Nov',
  'Des',
];

// DateSymbols uses Sunday-first weekday arrays.
const _weekdays = <String>[
  'Ssande',
  'Bbalaza',
  'Lwakubiri',
  'Lwakusatu',
  'Lwakuna',
  'Lwakutaano',
  'Lwamukaaga',
];

const _shortWeekdays = <String>[
  'San',
  'Bal',
  'Lw2',
  'Lw3',
  'Lw4',
  'Lw5',
  'Lw6',
];

const _narrowWeekdays = <String>['S', 'B', '2', '3', '4', '5', '6'];
