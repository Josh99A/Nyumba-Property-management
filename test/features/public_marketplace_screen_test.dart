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

Widget _testApp({required Locale locale}) => ProviderScope(
  overrides: [
    sessionControllerProvider.overrideWith(_VisitorSessionController.new),
    publicListingsProvider.overrideWith(
      (ref) => Stream.value(<Listing>[_publishedListing()]),
    ),
    cloudStatusProvider.overrideWith((ref) => Stream.value(CloudStatus.live)),
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

Listing _publishedListing() => Listing(
  id: 'listing_public_1',
  unitId: 'unit_1',
  propertyId: 'property_1',
  landlordId: 'landlord_1',
  title: 'Modern two-bedroom home',
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
  neighborhood: 'Ntinda',
  publicContactToken: 'public-contact-1',
  createdAt: _publishedAt.subtract(const Duration(days: 2)),
  updatedAt: _publishedAt,
  publishedAt: _publishedAt,
  expiresAt: _publishedAt.add(const Duration(days: 30)),
  syncMetadata: SyncMetadata.synced(lastSyncedAt: _publishedAt),
);
