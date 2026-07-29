import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/config/maps_config.dart';
import 'package:nyumba_property_management/core/domain/coordinates.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:nyumba_property_management/core/presentation/location_picker.dart';

Widget _host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: NyumbaTheme.light,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    ...LugandaLocalizations.delegates,
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  final kampala = Coordinates(latitude: 0.3476, longitude: 32.5825);

  group('LocationPickerField', () {
    testWidgets('offers to set a location when none is placed', (tester) async {
      await tester.pumpWidget(
        _host(LocationPickerField(value: null, onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Set location on map'), findsOneWidget);
      // Nothing to take back yet, so the destructive action stays absent
      // rather than sitting there disabled.
      expect(find.text('Remove location'), findsNothing);
    });

    testWidgets('shows the placed pin and offers to change it', (tester) async {
      await tester.pumpWidget(
        _host(LocationPickerField(value: kampala, onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Change location'), findsOneWidget);
      expect(find.text('Remove location'), findsOneWidget);
      // Coordinates are data, never pushed through the translation catalogue.
      expect(find.text('0.3476, 32.5825'), findsOneWidget);
    });

    testWidgets('removing reports null to the form', (tester) async {
      Coordinates? received = kampala;
      var calls = 0;
      await tester.pumpWidget(
        _host(
          LocationPickerField(
            value: kampala,
            onChanged: (value) {
              received = value;
              calls++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove location'));
      await tester.pump();

      expect(calls, 1);
      expect(received, isNull);
    });

    testWidgets('lays out right-to-left in Arabic', (tester) async {
      await tester.pumpWidget(
        _host(
          LocationPickerField(value: kampala, onChanged: (_) {}),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.byType(LocationPickerField))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the picker degrades honestly without an API key', () {
    // The test binding runs with no --dart-define, so this is the unconfigured
    // path by construction. It is also the path every build takes until the
    // keys are provisioned, which is what makes the feature safe to merge
    // first.
    test('an unkeyed build reports itself unconfigured', () {
      expect(NyumbaMaps.isConfigured, isFalse);
    });

    testWidgets('explains itself instead of showing a dead grey map', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(LocationPickerField(value: null, onChanged: (_) {})),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set location on map'));
      await tester.pumpAndSettle();

      expect(
        find.text('The map is not available in this build'),
        findsOneWidget,
      );
      // Still actionable: geolocator needs no Maps key, so a landlord standing
      // at the property can capture it anyway.
      expect(find.text('Use my current location'), findsOneWidget);
    });

    testWidgets('cannot confirm a pin nobody chose', (tester) async {
      await tester.pumpWidget(
        _host(LocationPickerField(value: null, onChanged: (_) {})),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set location on map'));
      await tester.pumpAndSettle();

      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm location'),
      );

      // With no map to read a centre from, confirming would invent a location
      // the landlord never placed.
      expect(confirm.onPressed, isNull);
    });
  });

  // Localization is asserted against the catalogue rather than a rendered
  // frame, matching test/core/localization_test.dart: the bridge resolves its
  // ARB through the delegate, so loading it directly tests the same lookup the
  // widget performs without standing a whole app up to do it.
  group('map copy is translated in every language', () {
    for (final code in const ['lg', 'sw', 'ar']) {
      test('$code carries the picker copy', () async {
        final catalogue = await NyumbaLocalizations.delegate.load(Locale(code));

        for (final source in const [
          'Set location on map',
          'Change location',
          'Remove location',
          'Confirm location',
          'Use my current location',
          'The map is not available in this build',
        ]) {
          final translated = catalogue.text(source);
          expect(translated, isNot(source), reason: '$code: $source');
          expect(translated, isNotEmpty, reason: '$code: $source');
        }
      });
    }
  });

  group('directions hand-off', () {
    test('builds a universal Google Maps directions URL', () {
      final url = NyumbaMaps.directionsTo(0.3476, 32.5825);

      expect(url.host, 'www.google.com');
      expect(url.path, '/maps/dir/');
      expect(url.queryParameters['api'], '1');
      expect(url.queryParameters['destination'], '0.3476,32.5825');
    });
  });
}
