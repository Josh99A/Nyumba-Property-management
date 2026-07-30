import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import '../support/cloud_fixtures.dart';
import 'package:go_router/go_router.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/presentation/remote_media_image.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/marketplace/application/marketplace_use_cases.dart';
import 'package:nyumba_property_management/features/marketplace/domain/application.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/landlord_listings_screen.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';

class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final UserSession? _session;

  @override
  UserSession? build() => _session;
}

/// Records the listing it was asked to save instead of reaching Firestore.
class _RecordingUpdateListing extends UpdateListing {
  _RecordingUpdateListing(super.ref);

  final calls = <Listing>[];

  @override
  Future<MutationResult> call(Listing listing) async {
    calls.add(listing);
    // A real save returns proof the server accepted it, not the edited object:
    // the authoritative copy arrives on the listener a moment later.
    return MutationResult(
      aggregateId: listing.id,
      outcome: CommandOutcome(committedAt: DateTime.utc(2026, 7, 29, 9)),
    );
  }
}

class _RecordingRemoveListing extends RemoveListing {
  _RecordingRemoveListing(super.ref);

  final calls = <String>[];

  @override
  Future<MutationResult> call(String listingId) async {
    calls.add(listingId);
    return MutationResult(
      aggregateId: listingId,
      outcome: CommandOutcome(committedAt: DateTime.utc(2026, 7, 29, 9)),
    );
  }
}

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

String _dataUri(Uint8List bytes) =>
    'data:image/png;base64,${base64Encode(bytes)}';

void main() {
  final now = DateTime.utc(2026, 7, 20);
  final listing = Listing(
    id: 'listing-1',
    unitId: 'unit-1',
    propertyId: 'property-1',
    landlordId: 'landlord-uid',
    title: 'Apartment A1 at Ntinda Rise',
    description: 'A well maintained one-bedroom apartment.',
    monthlyRentMinor: 120000000,
    currency: 'UGX',
    status: ListingStatus.draft,
    unitType: 'apartment',
    city: 'Kampala',
    district: 'Ntinda',
    neighborhood: 'Ntinda Trading Centre',
    minimumLeaseMonths: 12,
    petsPolicy: 'Ask the landlord',
    smokingPolicy: 'No smoking indoors',
    viewingInstructions: 'Request a viewing through Nyumba.',
    contactPhone: '+256700000000',
    imageUrls: [_dataUri(_pngBytes)],
    createdAt: now,
    updatedAt: now,
  );

  testWidgets(
    'edit listing pre-fills fields the create form always collected but '
    'edit used to withhold, and saves them back',
    (tester) async {
      late _RecordingUpdateListing recorder;
      await _pump(
        tester,
        listings: [listing],
        overrideUpdate: (ref) => recorder = _RecordingUpdateListing(ref),
      );

      await tester.tap(find.byTooltip('Listing actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit listing'));
      await tester.pumpAndSettle();

      // Fields the old dialog never exposed, now pre-filled from the record.
      expect(
        find.widgetWithText(TextFormField, '12'), // minimum lease months
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Ask the landlord'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Request a viewing through Nyumba.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, '+256700000000'),
        findsOneWidget,
      );
      // The saved photo renders as a removable chip.
      expect(find.text('Photo 1'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ask the landlord'),
        'No pets',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      final saved = recorder.calls.single;
      expect(saved.petsPolicy, 'No pets');
      // Fields the old dialog silently dropped now survive the round trip.
      expect(saved.minimumLeaseMonths, 12);
      expect(saved.smokingPolicy, 'No smoking indoors');
      expect(saved.viewingInstructions, 'Request a viewing through Nyumba.');
      expect(saved.contactPhone, '+256700000000');
      expect(saved.imageUrls, [_dataUri(_pngBytes)]);
    },
  );

  testWidgets('a published listing offers no edit action', (tester) async {
    await _pump(
      tester,
      listings: [
        listing.copyWith(
          status: ListingStatus.published,
          publishedAt: now,
          expiresAt: now.add(const Duration(days: 30)),
          // Publication requires server-hosted photos; a data URI would still
          // be a locally staged upload.
          imageUrls: const ['https://cdn.nyumba.example/listing-1/a.jpg'],
        ),
      ],
      overrideUpdate: (ref) => _RecordingUpdateListing(ref),
    );

    await tester.tap(find.byTooltip('Listing actions'));
    await tester.pumpAndSettle();

    expect(find.text('Edit listing'), findsNothing);
    expect(find.text('Remove listing'), findsNothing);
  });

  testWidgets('an off-market listing offers a confirmed permanent removal', (
    tester,
  ) async {
    late _RecordingRemoveListing recorder;
    await _pump(
      tester,
      listings: [listing.copyWith(status: ListingStatus.paused)],
      overrideUpdate: (ref) => _RecordingUpdateListing(ref),
      overrideRemove: (ref) => recorder = _RecordingRemoveListing(ref),
    );

    await tester.tap(find.byTooltip('Listing actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove listing'));
    await tester.pumpAndSettle();

    expect(find.text('Remove Apartment A1 at Ntinda Rise?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove listing'));
    await tester.pumpAndSettle();

    expect(recorder.calls, ['listing-1']);
  });

  testWidgets('a synced photo reopens as a real thumbnail, not a broken chip', (
    tester,
  ) async {
    // What a landlord's photo looks like after it has synced: the aggregate
    // holds the server's delivery path, not the `data:` URI they uploaded.
    // Treating "does not decode as a data URI" as "broken" showed a fully
    // working photo set as a row of broken-image chips, so the fix is pinned
    // on the storage-reference form specifically.
    await _pump(
      tester,
      listings: [
        listing.copyWith(
          imageUrls: const [
            'public/listings/listing-1/0-abcdef0123456789-full.webp',
          ],
        ),
      ],
      overrideUpdate: (ref) => _RecordingUpdateListing(ref),
    );

    await tester.tap(find.byTooltip('Listing actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit listing'));
    await tester.pumpAndSettle();

    expect(find.text('Photo 1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InputChip),
        matching: find.byType(RemoteMediaImage),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });

  testWidgets('publishing without a photo explains itself and offers the fix', (
    tester,
  ) async {
    await _pump(
      tester,
      listings: [listing.copyWith(imageUrls: const <String>[])],
      overrideUpdate: (ref) => _RecordingUpdateListing(ref),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Publish'));
    await tester.pumpAndSettle();

    // Not a raw validation exception in a snack bar.
    expect(find.text('Add a photo first'), findsOneWidget);
    expect(
      find.text(
        'Add at least one photo of this rental space before publishing it.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add photos'));
    await tester.pumpAndSettle();

    // Straight into the editor, on the field that is missing.
    expect(find.text('Listing photos (required)'), findsOneWidget);
  });

  testWidgets('the photo field leads the form and says it is required', (
    tester,
  ) async {
    await _pump(
      tester,
      listings: [listing.copyWith(imageUrls: const <String>[])],
      overrideUpdate: (ref) => _RecordingUpdateListing(ref),
    );

    await tester.tap(find.byTooltip('Listing actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit listing'));
    await tester.pumpAndSettle();

    expect(find.text('Listing photos (required)'), findsOneWidget);
    // The photo control must be reachable without scrolling past the rest of
    // the form: burying it is what let adverts go public with an empty tile.
    final photoField = tester.getTopLeft(
      find.widgetWithText(TextFormField, 'Request a viewing through Nyumba.'),
    );
    expect(
      tester.getTopLeft(find.text('Listing photos (required)')).dy,
      lessThan(photoField.dy),
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Listing> listings,
  required UpdateListing Function(Ref ref) overrideUpdate,
  RemoveListing Function(Ref ref)? overrideRemove,
}) async {
  // A narrow single-column width: the 3-column layout crowds the status
  // badge row into an unrelated, pre-existing overflow at this test's
  // default text scale, which is not what these tests are about.
  tester.view.physicalSize = const Size(600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final router = GoRouter(
    initialLocation: '/listings',
    routes: [
      GoRoute(
        path: '/listings',
        builder: (context, state) =>
            const Scaffold(body: LandlordListingsScreen()),
      ),
      GoRoute(
        path: '/listing/:listingId',
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
        landlordListingsProvider.overrideWith(
          (ref) => Stream.value(cloudOf(listings)),
        ),
        portfolioUnitsProvider.overrideWith(
          (ref) => Stream.value(cloudOf(const <Unit>[])),
        ),
        portfolioPropertiesProvider.overrideWith(
          (ref) => Stream.value(cloudOf(const <Property>[])),
        ),
        rentalApplicationsProvider.overrideWith(
          (ref) => Stream.value(const <RentalApplication>[]),
        ),
        outboxEntriesProvider.overrideWith((ref) => const Stream.empty()),
        updateListingProvider.overrideWith(overrideUpdate),
        if (overrideRemove != null)
          removeListingProvider.overrideWith(overrideRemove),
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
