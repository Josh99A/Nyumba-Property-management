import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/config/maps_config.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/listing_location_section.dart';

Listing listingWith({double? latitude, double? longitude}) {
  final now = DateTime.utc(2026, 7, 28);
  return Listing(
    id: 'listing_abcd1234',
    unitId: 'unit-1',
    propertyId: 'property-1',
    landlordId: 'landlord-uid',
    title: 'Apartment A1 at Ntinda Rise',
    description: 'A well maintained one-bedroom apartment.',
    monthlyRentMinor: 120000000,
    currency: 'UGX',
    status: ListingStatus.published,
    unitType: 'apartment',
    city: 'Kampala',
    neighborhood: 'Ntinda',
    approximateLatitude: latitude,
    approximateLongitude: longitude,
    contactPhone: '+256700000000',
    createdAt: now,
    updatedAt: now,
    publishedAt: now,
  );
}

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
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('ListingLocationSection', () {
    testWidgets('renders the area, the caveat, and directions', (tester) async {
      await tester.pumpWidget(
        host(
          ListingLocationSection(
            listing: listingWith(latitude: 0.357, longitude: 32.612),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Where you will live'), findsOneWidget);
      expect(find.text('Get directions'), findsOneWidget);
      // The visitor is told plainly that this is not the doorstep.
      expect(
        find.textContaining('Approximate location in Ntinda'),
        findsOneWidget,
      );
      expect(find.textContaining('shares the exact address'), findsOneWidget);
    });

    // An empty grey box would read as a broken page. The location line the
    // advert already carries is a better fallback than a hole.
    testWidgets('renders nothing at all when no pin was placed', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ListingLocationSection(listing: listingWith())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Where you will live'), findsNothing);
      expect(find.text('Get directions'), findsNothing);
    });

    testWidgets('a half-written pair is treated as no pin', (tester) async {
      await tester.pumpWidget(
        host(ListingLocationSection(listing: listingWith(latitude: 0.357))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Where you will live'), findsNothing);
    });

    testWidgets('lays out right-to-left in Arabic', (tester) async {
      await tester.pumpWidget(
        host(
          ListingLocationSection(
            listing: listingWith(latitude: 0.357, longitude: 32.612),
          ),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.byType(ListingLocationSection))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the map image is served from Nyumba, never from Google', () {
    test('the URL is a first-party path carrying no key', () {
      final url = NyumbaMaps.listingMapUrl('listing_abcd1234');

      expect(url, 'https://nyumba.online/listing/listing_abcd1234/map');
      // The Static Maps key lives in Secret Manager. A key in an image URL is
      // a key handed to every visitor.
      expect(url, isNot(contains('key')));
      expect(url, isNot(contains('googleapis')));
    });

    // Kept in sync with listingMapPath in
    // firebase/functions/src/http/static-map.ts, and covered by the
    // /listing/{id}/map route on the publicSeo function.
    test('the path matches the route the backend serves', () {
      expect(
        Uri.parse(NyumbaMaps.listingMapUrl('listing_abcd1234')).path,
        '/listing/listing_abcd1234/map',
      );
    });
  });

  group('location copy is translated in every language', () {
    for (final code in const ['lg', 'sw', 'ar']) {
      test('$code carries the location copy', () async {
        final catalogue = await NyumbaLocalizations.delegate.load(Locale(code));

        for (final source in const [
          'Where you will live',
          'Get directions',
          'The map will appear when you are back online.',
        ]) {
          final translated = catalogue.text(source);
          expect(translated, isNot(source), reason: '$code: $source');
          expect(translated, isNotEmpty, reason: '$code: $source');
        }
      });
    }
  });
}
