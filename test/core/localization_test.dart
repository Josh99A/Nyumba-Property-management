import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:nyumba_property_management/app/localization/locale_controller.dart';
import 'package:nyumba_property_management/core/documents/nyumba_document_service.dart';
import 'package:nyumba_property_management/core/localization/app_language.dart';
import 'package:nyumba_property_management/core/localization/command_failure_localizations.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/localization_formats.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:nyumba_property_management/core/offline/command_failure.dart';
import 'package:nyumba_property_management/core/offline/remote_sync_gateway.dart';
import 'package:nyumba_property_management/core/presentation/language_menu_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all four catalogs have the same complete, clean key set', () async {
    final catalogs = <String, Map<String, dynamic>>{};
    for (final language in AppLanguage.values) {
      final source = await rootBundle.loadString(
        'assets/l10n/app_${language.code}.arb',
      );
      final catalog = jsonDecode(source) as Map<String, dynamic>;
      catalogs[language.code] = catalog;

      final messages = catalog.entries.where(
        (entry) => !entry.key.startsWith('@'),
      );
      expect(messages, isNotEmpty, reason: language.code);
      for (final message in messages) {
        expect(message.value, isA<String>(), reason: message.key);
        expect(
          (message.value as String).trim(),
          isNotEmpty,
          reason: '${language.code}:${message.key}',
        );
        expect(
          message.value,
          isNot(matches(RegExp(r'Ã|Â|â|Ø|Ù|�'))),
          reason: '${language.code}:${message.key}',
        );
      }
    }

    final expected = _messageKeys(catalogs['en']!);
    for (final language in AppLanguage.values.skip(1)) {
      final localized = catalogs[language.code]!;
      expect(_messageKeys(localized), expected);
      for (final key in expected) {
        final englishMessage = catalogs['en']![key] as String;
        final localizedMessage = localized[key] as String;
        expect(
          _icuPlaceholders(localizedMessage),
          _icuPlaceholders(englishMessage),
          reason: '${language.code}:$key placeholders',
        );
        expect(
          _placeholderMetadata(localized, key),
          _placeholderMetadata(catalogs['en']!, key),
          reason: '${language.code}:@$key.placeholders',
        );
      }
    }
    expect(expected.length, greaterThan(590));
  });

  test('command failures do not silently fall back to English', () async {
    final errors = <RemoteSyncException>[
      for (final code in const [
        'UNAUTHENTICATED',
        'APP_CHECK_REQUIRED',
        'PERMISSION_DENIED',
        'ACCOUNT_NOT_APPROVED',
        'ACCOUNT_SUSPENDED',
        'SUBSCRIPTION_INACTIVE',
        'ENTITLEMENT_MISSING',
        'UNIT_LIMIT_REACHED',
        'SEAT_LIMIT_REACHED',
        'CUSTOM_ROLES_UNAVAILABLE',
        'PAYMENT_PROVIDER_UNAVAILABLE',
        'PAYMENT_PENDING',
        'NOT_FOUND',
        'ALREADY_EXISTS',
        'VERSION_CONFLICT',
        'IDEMPOTENCY_KEY_REUSED',
        'RATE_LIMITED',
        'REQUIRES_ONLINE',
        'INTERNAL_RETRYABLE',
        'unavailable',
        'deadline-exceeded',
        'unknownFailure',
      ])
        RemoteSyncException(code),
      for (final reason in const [
        'subscriptionAlreadyActive',
        'subscriptionNotActive',
        'tierUnchanged',
        'accountSuspended',
        'landlordAccountMissing',
        'accountApprovalStatusInvalid',
        'invalidApprovalTransition',
        'alreadyArchived',
        'notArchived',
        'roleUnchanged',
        'amountExceedsBalance',
        'leaseNotActive',
        'noFieldsToUpdate',
        'yearlyPriceExceedsMonthlyTimesTwelve',
        'unknownCommandType',
        'envelopeInvalid',
        'unknownValidationReason',
      ])
        RemoteSyncException('VALIDATION_FAILED', details: {'reason': reason}),
      const RemoteSyncException('VALIDATION_FAILED'),
      const RemoteSyncException(
        'VALIDATION_FAILED',
        details: {
          'fields': ['amount', 'tier'],
        },
      ),
    ];
    final failures = errors.map(describeCommandFailure).toList();
    final english = await AppLocalizations.delegate.load(
      const material.Locale('en'),
    );

    expect(failures.map((failure) => failure.code).toSet(), hasLength(41));
    for (final language in AppLanguage.values.skip(1)) {
      final localized = await AppLocalizations.delegate.load(
        material.Locale(language.code),
      );
      for (final failure in failures) {
        final source = localizeCommandFailure(english, failure);
        final translation = localizeCommandFailure(localized, failure);
        expect(translation, isNot(source), reason: '${language.code}: $source');
        if (source.contains('amount, tier')) {
          expect(translation, contains('amount, tier'));
        }
      }
    }
  });

  test(
    'dynamic values are inserted without translating user content',
    () async {
      final luganda = await NyumbaLocalizations.delegate.load(
        const material.Locale('lg'),
      );
      final arabic = await NyumbaLocalizations.delegate.load(
        const material.Locale('ar'),
      );

      expect(luganda.text('Welcome back, Amina.'), 'Tukwanirizza nate, Amina.');
      expect(arabic.text('Edit Kisaasi Heights'), 'تعديل Kisaasi Heights');
    },
  );

  test('Luganda calendar names are available to intl', () async {
    await initializeNyumbaLocalizationFormats();
    expect(DateFormat('MMMM', 'lg').format(DateTime(2026, 9)), 'Ssebutemba');
    expect(DateFormat('EEEE', 'lg').format(DateTime(2026, 7, 13)), 'Bbalaza');
  });

  testWidgets('Arabic uses RTL and Luganda provides Material controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      material.MaterialApp(
        locale: const material.Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: _delegates,
        home: const material.SizedBox(key: material.ValueKey('locale-anchor')),
      ),
    );
    await tester.pumpAndSettle();

    final arabicContext = tester.element(
      find.byKey(const material.ValueKey('locale-anchor')),
    );
    expect(
      material.Directionality.of(arabicContext),
      material.TextDirection.rtl,
    );

    await tester.pumpWidget(
      material.MaterialApp(
        locale: const material.Locale('lg'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: _delegates,
        home: const material.SizedBox(key: material.ValueKey('locale-anchor')),
      ),
    );
    await tester.pumpAndSettle();

    final lugandaContext = tester.element(
      find.byKey(const material.ValueKey('locale-anchor')),
    );
    expect(
      material.MaterialLocalizations.of(lugandaContext).okButtonLabel,
      'KALE',
    );
    final cupertinoCopy = cupertino.CupertinoLocalizations.of(lugandaContext);
    expect(cupertinoCopy.copyButtonLabel, 'Koppa');
    expect(cupertinoCopy.datePickerMonth(9), 'Ssebutemba');
  });

  testWidgets('Arabic PDF embeds Unicode fonts and generates successfully', (
    tester,
  ) async {
    final bytes = await const PdfDocumentService().generate(
      PrintableDocumentData(
        title: 'Receipt',
        number: 'RCT-2026-0184',
        recipient: 'آمنة ناموسوكي',
        property: 'Nyumba Heights',
        unit: 'A-12',
        amountMinor: 125000000,
        date: DateTime.utc(2026, 7, 17),
        status: 'Paid',
        language: AppLanguage.arabic,
      ),
    );

    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(10000));

    if (const bool.fromEnvironment('NYUMBA_WRITE_PDF_FIXTURE')) {
      final directory = Directory('tmp/pdfs')..createSync(recursive: true);
      File(
        '${directory.path}/nyumba-arabic-receipt.pdf',
      ).writeAsBytesSync(bytes);
    }
  });

  testWidgets('language selector has no overflow in narrow and wide Arabic', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = material.Size(width, 700);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localePreferenceProvider.overrideWith(_ArabicLocaleController.new),
          ],
          child: material.MaterialApp(
            locale: const material.Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: _delegates,
            home: const material.Scaffold(
              body: material.Align(
                alignment: material.Alignment.topCenter,
                child: material.SizedBox(
                  width: 280,
                  child: LanguageMenuButton(expanded: true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width=$width');
      expect(find.byType(LanguageMenuButton), findsOneWidget);
      expect(find.byIcon(material.Icons.translate_rounded), findsOneWidget);
    }

    await pumpAt(320);
    await pumpAt(1200);
  });
}

Set<String> _messageKeys(Map<String, dynamic> catalog) =>
    catalog.keys.where((key) => !key.startsWith('@')).toSet();

Set<String> _icuPlaceholders(String message) => RegExp(
  r'\{([A-Za-z][A-Za-z0-9_]*)\s*(?:,|\})',
).allMatches(message).map((match) => match.group(1)!).toSet();

Map<String, dynamic> _placeholderMetadata(
  Map<String, dynamic> catalog,
  String key,
) {
  final metadata = catalog['@$key'];
  if (metadata is! Map) return const {};
  final placeholders = metadata['placeholders'];
  if (placeholders is! Map) return const {};
  return <String, dynamic>{
    for (final entry in placeholders.entries) entry.key.toString(): entry.value,
  };
}

const _delegates = <material.LocalizationsDelegate<dynamic>>[
  ...LugandaLocalizations.delegates,
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

final class _ArabicLocaleController extends LocalePreferenceController {
  @override
  AppLanguage build() => AppLanguage.arabic;

  @override
  Future<void> select(AppLanguage language) async {
    state = language;
  }
}
