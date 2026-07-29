import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/config/maps_config.dart';
import 'package:nyumba_property_management/core/domain/coordinates.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/presentation/directions_button.dart';

Widget host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
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
  group('DirectionsButton', () {
    testWidgets('offers directions when a pin exists', (tester) async {
      await tester.pumpWidget(
        host(
          DirectionsButton(
            destination: Coordinates(latitude: 0.3476, longitude: 32.5825),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Get directions'), findsOneWidget);
    });

    // A disabled control invites a tap and then explains nothing. The screen
    // around it already states the address in words.
    testWidgets('renders nothing when no pin was placed', (tester) async {
      await tester.pumpWidget(host(const DirectionsButton(destination: null)));
      await tester.pumpAndSettle();

      expect(find.text('Get directions'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('lays out right-to-left in Arabic', (tester) async {
      await tester.pumpWidget(
        host(
          DirectionsButton(
            destination: Coordinates(latitude: 0.3476, longitude: 32.5825),
          ),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.byType(DirectionsButton))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the directions hand-off', () {
    test('carries the exact pin, not a coarsened one', () {
      // Staff are dispatched to a site. The ~110 m public rounding would put a
      // contractor at the wrong end of the road, so private surfaces must pass
      // the precise point through untouched.
      final exact = Coordinates(latitude: 0.3476219, longitude: 32.5825447);

      final url = NyumbaMaps.directionsTo(exact.latitude, exact.longitude);

      expect(url.queryParameters['destination'], '0.3476219,32.5825447');
      expect(url.host, 'www.google.com');
      expect(url.path, '/maps/dir/');
      // A universal Maps URL needs no API key and costs nothing per tap.
      expect(url.toString(), isNot(contains('key=')));
    });

    test('a coarsened pin is a different destination', () {
      final exact = Coordinates(latitude: 0.3476219, longitude: 32.5825447);

      expect(
        NyumbaMaps.directionsTo(exact.latitude, exact.longitude),
        isNot(
          NyumbaMaps.directionsTo(
            exact.coarsened().latitude,
            exact.coarsened().longitude,
          ),
        ),
      );
    });
  });
}
