import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/offline/offline_entity.dart';
import 'package:nyumba_property_management/core/offline/outbox_entry.dart';
import 'package:nyumba_property_management/core/presentation/status_badge.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
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

/// Records the re-queue instead of touching the outbox.
class _RecordingRetry extends RetryMutation {
  _RecordingRetry(super.ref);

  final calls = <String>[];

  @override
  Future<bool> call(String mutationId) async {
    calls.add(mutationId);
    return true;
  }
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
    // What a refused publication looks like locally: the advert reads as
    // published on this device and is not public anywhere.
    status: ListingStatus.published,
    unitType: 'apartment',
    city: 'Kampala',
    neighborhood: 'Ntinda Trading Centre',
    contactPhone: '+256700000000',
    imageUrls: const ['public/listings/listing-1/0-abcdef0123456789-full.webp'],
    createdAt: now,
    updatedAt: now,
    publishedAt: now,
    syncMetadata: const SyncMetadata.pending(),
  );

  OutboxEntry entry({
    required OutboxState state,
    int attemptCount = 0,
    String? lastError,
    String? errorReason,
  }) => OutboxEntry(
    id: 'mutation-1',
    entityType: OfflineEntityType.listing,
    entityId: listing.id,
    operation: OutboxOperation.publish,
    payload: const <String, Object?>{},
    createdAt: now,
    state: state,
    attemptCount: attemptCount,
    lastError: lastError,
    errorReason: errorReason,
  );

  testWidgets('a refused advert says so, gives the reason, and can be retried', (
    tester,
  ) async {
    late _RecordingRetry retry;
    await _pump(
      tester,
      listings: [listing],
      outbox: [
        entry(
          state: OutboxState.permanentlyFailed,
          attemptCount: 6,
          lastError: 'VALIDATION_FAILED',
          errorReason: 'listingMissingPhotos',
        ),
      ],
      overrideRetry: (ref) => retry = _RecordingRetry(ref),
    );

    // Never "Publishing" — the wait already ended, with a no.
    expect(find.text('Publishing'), findsNothing);
    expect(find.text('Not published'), findsOneWidget);
    // The whole point: what is wrong and how to fix it, never the raw
    // "VALIDATION_FAILED" the server actually sent.
    expect(find.textContaining('VALIDATION_FAILED'), findsNothing);
    expect(
      find.text(
        'This advert has no photo of the rental space. Add at least one '
        'photo, then publish it again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'One advert did not go through. Open the card marked in red to see '
        'why and try again.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(retry.calls, ['mutation-1']);
  });

  testWidgets('a refused advert can still be edited', (tester) async {
    await _pump(
      tester,
      listings: [listing],
      outbox: [
        entry(state: OutboxState.permanentlyFailed, attemptCount: 6),
      ],
      overrideRetry: _RecordingRetry.new,
    );

    // A locally-published advert normally hides Edit. One the server refused
    // has to stay editable or there is no way to fix what it objected to.
    await tester.tap(find.byTooltip('Listing actions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit listing'), findsOneWidget);
  });

  testWidgets('the ordinary wait is quiet and claims nothing', (tester) async {
    await _pump(
      tester,
      listings: [listing],
      outbox: [entry(state: OutboxState.pending)],
      overrideRetry: _RecordingRetry.new,
    );

    expect(find.text('Going live…'), findsOneWidget);
    // Scoped to the badge: "Published" is also a filter chip.
    expect(find.widgetWithText(StatusBadge, 'Published'), findsNothing);
    expect(find.textContaining('did not go through'), findsNothing);
    // No retry offered for work that is still on its way.
    expect(find.text('Try again'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Listing> listings,
  required List<OutboxEntry> outbox,
  required RetryMutation Function(Ref ref) overrideRetry,
}) async {
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
        landlordListingsProvider.overrideWith((ref) => Stream.value(listings)),
        portfolioUnitsProvider.overrideWith(
          (ref) => Stream.value(const <Unit>[]),
        ),
        portfolioPropertiesProvider.overrideWith(
          (ref) => Stream.value(const <Property>[]),
        ),
        rentalApplicationsProvider.overrideWith(
          (ref) => Stream.value(const <RentalApplication>[]),
        ),
        outboxEntriesProvider.overrideWith((ref) => Stream.value(outbox)),
        retryMutationProvider.overrideWith(overrideRetry),
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
