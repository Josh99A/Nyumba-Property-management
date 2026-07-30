import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/cloud_fixtures.dart';
import 'package:go_router/go_router.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public/listing_query.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public/listing_result_card.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public_listings_screen.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/public_search_screen.dart';

final _publishedAt = DateTime.utc(2026, 7, 20);

class _VisitorSessionController extends SessionController {
  @override
  UserSession? build() => null;
}

void main() {
  group('landing page', () {
    testWidgets('features a bounded sample and routes browsing to /search', (
      tester,
    ) async {
      final copy = await AppLocalizations.delegate.load(const Locale('en'));
      await _setViewport(tester, const Size(1280, 2400));
      final harness = _harness(
        listings: [
          for (var index = 0; index < 12; index++)
            _publishedListing(
              id: 'listing_public_$index',
              title: 'Listed home number $index',
            ),
        ],
      );
      await tester.pumpWidget(harness.app);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The landing page is a sample, not the catalogue: it must never try to
      // render every home.
      final featured = find.byType(ListingResultCard).evaluate().length;
      expect(featured, lessThan(12));
      expect(featured, greaterThan(0));

      await tester.tap(find.widgetWithText(OutlinedButton, copy.viewAllHomes));
      await tester.pumpAndSettle();

      expect(find.byType(PublicSearchScreen), findsOneWidget);
      expect(harness.router.state.uri.path, '/search');
    });

    testWidgets('a hero location shortcut opens the search with that query', (
      tester,
    ) async {
      await _setViewport(tester, const Size(1280, 2400));
      final harness = _harness(
        listings: [
          _publishedListing(),
          _publishedListing(
            id: 'listing_public_2',
            title: 'Bugolobi townhouse',
            neighborhood: 'Bugolobi',
          ),
        ],
      );
      await tester.pumpWidget(harness.app);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // The shortcuts come from the catalogue, so tapping one can never land
      // on an empty result.
      await tester.tap(find.widgetWithText(InkWell, 'Ntinda').first);
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/search');
      expect(harness.router.state.uri.queryParameters['q'], 'Ntinda');
      expect(find.text('Modern two-bedroom home'), findsOneWidget);
      expect(find.text('Bugolobi townhouse'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in Luganda, which intl has no number symbols for', (
      tester,
    ) async {
      await _setViewport(tester, const Size(1280, 2400));
      await tester.pumpWidget(
        _harness(
          locale: const Locale('lg'),
          listings: [_publishedListing(availableFrom: _publishedAt)],
        ).app,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Rent formatting used to be handed the catalogue locale directly, and
      // NumberFormat throws on a locale CLDR does not carry rather than
      // falling back — every card on the page became a red error box.
      expect(tester.takeException(), isNull);
      expect(find.byType(ListingResultCard), findsWidgets);
      expect(find.textContaining('UGX 1,500,000'), findsWidgets);
      // Dates still follow the Luganda names registered at startup.
      expect(find.textContaining('20 Jul'), findsWidgets);
    });

    testWidgets('no longer advertises offline browsing', (tester) async {
      final copy = await AppLocalizations.delegate.load(const Locale('en'));
      await _setViewport(tester, const Size(1280, 2400));
      await tester.pumpWidget(_harness().app);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text(copy.trustWorksOffline), findsNothing);
      expect(find.text(copy.benefitBrowseOffline), findsNothing);
      expect(find.text(copy.trustRealTenantReviews), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('search screen', () {
    testWidgets('restores the filters a shared link carried', (tester) async {
      await _setViewport(tester, const Size(1280, 2400));
      final harness = _harness(
        initialLocation: '/search?q=ntinda&beds=threePlus',
        listings: [_publishedListing()],
      );
      await tester.pumpWidget(harness.app);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // The seeded home has two bedrooms, so the linked filter excludes it —
      // proving the URL, not the default, decided what is on screen.
      expect(find.widgetWithText(InputChip, '3+ bedrooms'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'ntinda'), findsOneWidget);
      expect(find.text('Modern two-bedroom home'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('writes a changed filter back into the URL', (tester) async {
      await _setViewport(tester, const Size(1280, 2400));
      final harness = _harness(
        initialLocation: '/search',
        listings: [_publishedListing()],
      );
      await tester.pumpWidget(harness.app);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.queryParameters, isEmpty);

      await tester.tap(find.text('Any bedrooms').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3+ bedrooms').last);
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.queryParameters['beds'], 'threePlus');
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays overflow-free on a narrow Arabic screen', (
      tester,
    ) async {
      final arabicCopy = await AppLocalizations.delegate.load(
        const Locale('ar'),
      );
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _harness(initialLocation: '/search', locale: const Locale('ar')).app,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(find.byType(PublicSearchScreen))),
        TextDirection.rtl,
      );
      expect(find.text(arabicCopy.searchHomesTitle), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Modern two-bedroom home'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Modern two-bedroom home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing defers filtering but never the field itself', (
      tester,
    ) async {
      await _setViewport(tester, const Size(1280, 2400));
      await tester.pumpWidget(_harness(initialLocation: '/search').app);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Modern two-bedroom home'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'not-a-real-place');
      await tester.pump();

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

    testWidgets('clears a search that matched nothing', (tester) async {
      final copy = await AppLocalizations.delegate.load(const Locale('en'));
      await _setViewport(tester, const Size(1280, 2400));
      await tester.pumpWidget(
        _harness(initialLocation: '/search?q=not-a-real-place').app,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text(copy.noHomesMatch), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, copy.clearFilters));
      await tester.pumpAndSettle();

      expect(find.text('Modern two-bedroom home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('results below the fold are not built until scrolled to', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _harness(
          initialLocation: '/search',
          listings: [
            for (var index = 0; index < 30; index++)
              _publishedListing(
                id: 'listing_public_$index',
                title: 'Listed home number $index',
              ),
          ],
        ).app,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // The whole grid used to be laid out on first paint, which started every
      // card's photo download at once. Only a fraction may exist now.
      expect(
        find.byType(ListingResultCard).evaluate().length,
        lessThan(30),
        reason: 'the grid must not build all thirty cards up front',
      );

      await tester.scrollUntilVisible(
        find.text('Listed home number 29'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Listed home number 29'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the mobile filter sheet applies and a chip removes it', (
      tester,
    ) async {
      final copy = await AppLocalizations.delegate.load(const Locale('en'));
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_harness(initialLocation: '/search').app);
      await tester.pump(const Duration(milliseconds: 100));
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

      expect(find.text(copy.noHomesMatch), findsOneWidget);
      expect(find.widgetWithText(InputChip, '3+ bedrooms'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, '3+ bedrooms'),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNothing);
      expect(find.text('Modern two-bedroom home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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

/// The two public screens plus the routing between them, which is now part of
/// what these tests are checking.
({Widget app, GoRouter router}) _harness({
  String initialLocation = '/explore',
  List<Listing>? listings,
  Locale locale = const Locale('en'),
}) {
  final catalogue = listings ?? <Listing>[_publishedListing()];
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/explore',
        builder: (context, state) => const PublicListingsScreen(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => PublicSearchScreen(
          initialQuery: ListingQuery.fromQueryParameters(
            state.uri.queryParameters,
          ),
        ),
      ),
      GoRoute(
        path: '/listing/:listingId',
        builder: (context, state) =>
            Scaffold(body: Text(state.pathParameters['listingId'] ?? '')),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const Scaffold(body: Text('sign in')),
      ),
    ],
  );
  final app = ProviderScope(
    overrides: [
      sessionControllerProvider.overrideWith(_VisitorSessionController.new),
      publicListingsProvider.overrideWith(
        (ref) => Stream.value(cloudOf(catalogue)),
      ),
      cloudStatusProvider.overrideWith((ref) => Stream.value(CloudStatus.live)),
    ],
    child: MaterialApp.router(
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
      routerConfig: router,
    ),
  );
  return (app: app, router: router);
}

Listing _publishedListing({
  String id = 'listing_public_1',
  String title = 'Modern two-bedroom home',
  String neighborhood = 'Ntinda',
  DateTime? availableFrom,
}) => Listing(
  availableFrom: availableFrom,
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
);
