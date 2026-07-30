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
import 'package:nyumba_property_management/features/marketplace/presentation/listing_detail_screen.dart';
import 'package:nyumba_property_management/features/reviews/application/review_providers.dart';
import 'package:nyumba_property_management/features/reviews/domain/landlord_review.dart';

class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final UserSession? _session;

  @override
  UserSession? build() => _session;
}

void main() {
  final now = DateTime.utc(2026, 7, 28);
  final listing = Listing(
    id: 'listing-1',
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
    neighborhood: 'Ntinda Trading Centre',
    contactPhone: '+256700000000',
    createdAt: now,
    updatedAt: now,
    publishedAt: now,
  );

  Future<void> pump(
    WidgetTester tester, {
    required List<Listing> published,
    required List<Listing> ownListings,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      initialLocation: '/listing/${listing.id}',
      routes: [
        GoRoute(
          path: '/listing/:listingId',
          builder: (context, state) => ListingDetailScreen(
            listingId: state.pathParameters['listingId']!,
          ),
        ),
        GoRoute(
          path: '/explore',
          builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(
            () => _FixedSessionController(
              const UserSession(
                userId: 'landlord-uid',
                displayName: 'Sandra Nakato',
                email: 'sandra@acaciahomes.ug',
                role: AppRole.landlord,
                subscriptionStatus: LandlordSubscriptionStatus.active,
                subscriptionTier: 'starter',
              ),
            ),
          ),
          publicListingsProvider.overrideWith(
            (ref) => Stream.value(cloudOf(published)),
          ),
          landlordListingsProvider.overrideWith(
            (ref) => Stream.value(cloudOf(ownListings)),
          ),
          publicReviewsProvider.overrideWith(
            (ref, landlordToken) => Stream.value(const <LandlordReview>[]),
          ),
        ],
        child: MaterialApp.router(
          theme: NyumbaTheme.light,
          routerConfig: router,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            ...LugandaLocalizations.delegates,
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a listing in the public catalogue renders without the preview banner',
    (tester) async {
      await pump(tester, published: [listing], ownListings: [listing]);

      expect(find.text(listing.title), findsOneWidget);
      expect(find.textContaining('Preview — not live yet'), findsNothing);
    },
  );

  testWidgets('a listing absent from the public catalogue falls back to the '
      'landlord\'s own copy and shows the preview banner', (tester) async {
    await pump(tester, published: const [], ownListings: [listing]);

    expect(find.text(listing.title), findsOneWidget);
    expect(find.textContaining('Preview — not live yet'), findsOneWidget);
  });

  testWidgets('a listing in neither store still reads as not found', (
    tester,
  ) async {
    await pump(tester, published: const [], ownListings: const []);

    expect(find.text('This home is no longer available'), findsOneWidget);
    expect(find.textContaining('Preview — not live yet'), findsNothing);
  });
}
