import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public/listing_result_card.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public_listings_screen.dart';

final _publishedAt = DateTime.utc(2026, 7, 20);

class _VisitorSessionController extends SessionController {
  @override
  UserSession? build() => null;
}

void main() {
  testWidgets('marketplace shows published homes and clears a search', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1280, 900));
    await tester.pumpWidget(_testApp(locale: const Locale('en')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Active listings'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'not-a-real-place');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Search').first);
    await tester.pumpAndSettle();

    expect(find.text('No homes match those filters'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear filters'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Modern two-bedroom home'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Modern two-bedroom home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marketplace stays overflow-free on a narrow Arabic screen', (
    tester,
  ) async {
    final arabicCopy = await AppLocalizations.delegate.load(const Locale('ar'));
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp(locale: const Locale('ar')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(Scaffold))),
      TextDirection.rtl,
    );
    await tester.scrollUntilVisible(
      find.text('Modern two-bedroom home'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Modern two-bedroom home'), findsOneWidget);
    expect(find.text(arabicCopy.availableHomes), findsOneWidget);
    expect(find.text(arabicCopy.listingAvailableNow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned filter bar applies and removes a filter on a phone', (
    tester,
  ) async {
    final copy = await AppLocalizations.delegate.load(const Locale('en'));
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp(locale: const Locale('en')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byIcon(Icons.tune_rounded),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Any bedrooms').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3+ bedrooms').last);
    await tester.pumpAndSettle();

    // The sheet previews the result before the visitor commits to it.
    expect(find.text(copy.showHomesCount(0)), findsOneWidget);
    await tester.tap(find.text(copy.showHomesCount(0)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(copy.noHomesMatch),
      -260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(copy.noHomesMatch), findsOneWidget);

    // The chip sits above the results, and far enough down the page to be
    // behind the pinned bar unless the list is nudged past it.
    await tester.scrollUntilVisible(
      find.byType(InputChip),
      -160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 180));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, '3+ bedrooms'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InputChip, '3+ bedrooms'),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Modern two-bedroom home'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Modern two-bedroom home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hero location shortcut searches that neighbourhood', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1280, 2400));
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('en'),
        listings: [
          _publishedListing(),
          _publishedListing(
            id: 'listing_public_2',
            title: 'Bugolobi townhouse',
            neighborhood: 'Bugolobi',
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Bugolobi townhouse'), findsOneWidget);

    // The shortcuts come from the catalogue, so tapping one can never land on
    // an empty result.
    await tester.tap(find.widgetWithText(InkWell, 'Ntinda').first);
    await tester.pumpAndSettle();

    expect(find.text('Modern two-bedroom home'), findsOneWidget);
    expect(find.text('Bugolobi townhouse'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Ntinda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing defers filtering but never the field itself', (
    tester,
  ) async {
    // Tall enough that the hero, the results header, and the first card are all
    // on screen at once, so the card appearing and disappearing is observable
    // without scrolling away from the search field.
    await _setViewport(tester, const Size(1280, 2400));
    await tester.pumpWidget(_testApp(locale: const Locale('en')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Modern two-bedroom home'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'not-a-real-place');
    await tester.pump();

    // The text is on screen at once; the results have not been re-filtered yet.
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'not-a-real-place',
    );
    expect(
      find.text('Modern two-bedroom home'),
      findsOneWidget,
      reason: 'filtering must not run on the first keystroke',
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Modern two-bedroom home'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a filter chip still applies immediately, without waiting', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1280, 2400));
    await tester.pumpWidget(_testApp(locale: const Locale('en')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // A dropdown selection is a finished decision, so it must not be debounced
    // the way a half-typed word is.
    await tester.tap(find.text('Any bedrooms').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3+ bedrooms').last);
    await tester.pump();

    expect(find.text('Modern two-bedroom home'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('results below the fold are not built until scrolled to', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('en'),
        listings: [
          for (var index = 0; index < 30; index++)
            _publishedListing(
              id: 'listing_public_$index',
              title: 'Listed home number $index',
            ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // The whole grid used to be laid out on first paint, which started every
    // card's photo download at once. Only a fraction may exist now.
    final built = find.byType(ListingResultCard).evaluate().length;
    expect(
      built,
      lessThan(30),
      reason: 'the grid must not build all thirty cards up front',
    );

    await tester.scrollUntilVisible(
      find.text('Listed home number 29'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Settles the entry animations of the rows that scrolling just built.
    await tester.pumpAndSettle();

    expect(find.text('Listed home number 29'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _testApp({required Locale locale, List<Listing>? listings}) =>
    ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(_VisitorSessionController.new),
        publicListingsProvider.overrideWith(
          (ref) => Stream.value(listings ?? <Listing>[_publishedListing()]),
        ),
        cloudStatusProvider.overrideWith(
          (ref) => Stream.value(CloudStatus.live),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        theme: NyumbaTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          ...LugandaLocalizations.delegates,
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const PublicListingsScreen(),
      ),
    );

Listing _publishedListing({
  String id = 'listing_public_1',
  String title = 'Modern two-bedroom home',
  String neighborhood = 'Ntinda',
}) => Listing(
  id: id,
  unitId: 'unit_1',
  propertyId: 'property_1',
  landlordId: 'landlord_1',
  title: title,
  description:
      'A bright, well-kept home near shops, schools, and public transport.',
  monthlyRentMinor: 150000000,
  currency: 'UGX',
  status: ListingStatus.published,
  bedrooms: 2,
  bathrooms: 1,
  unitType: 'Apartment',
  furnished: true,
  city: 'Kampala',
  district: 'Kampala',
  neighborhood: neighborhood,
  publicContactToken: 'public-contact-1',
  createdAt: _publishedAt.subtract(const Duration(days: 2)),
  updatedAt: _publishedAt,
  publishedAt: _publishedAt,
  expiresAt: _publishedAt.add(const Duration(days: 30)),
  syncMetadata: SyncMetadata.synced(lastSyncedAt: _publishedAt),
);
