import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/marketplace/presentation/publish_actions.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';

/// Session stub that never touches Firebase.
class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final UserSession? _session;

  @override
  UserSession? build() => _session;
}

void main() {
  const landlord = UserSession(
    userId: 'landlord-1',
    displayName: 'Sandra Nakato',
    email: 'sandra@acaciahomes.ug',
    role: AppRole.landlord,
  );

  testWidgets('a vacant space with no advert is offered a new listing', (
    tester,
  ) async {
    await _pumpPrompt(tester, session: landlord, listings: const <Listing>[]);

    expect(find.text('Advertise this rental space?'), findsOneWidget);
    expect(find.text('Create listing'), findsOneWidget);
    expect(find.text('Publish now'), findsNothing);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Advertise this rental space?'), findsNothing);
  });

  testWidgets('a draft with photos is offered publication', (tester) async {
    await _pumpPrompt(
      tester,
      session: landlord,
      listings: [_listing(status: ListingStatus.draft, withPhoto: true)],
    );

    expect(find.text('Publish now'), findsOneWidget);
    expect(find.text('Create listing'), findsNothing);
  });

  testWidgets('a paused advert can go live again', (tester) async {
    await _pumpPrompt(
      tester,
      session: landlord,
      listings: [_listing(status: ListingStatus.paused, withPhoto: true)],
    );

    expect(find.text('Publish now'), findsOneWidget);
  });

  // A photoless advert cannot be published, so offering "Publish now" would
  // only hand the landlord a server refusal. The offer becomes the fix.
  testWidgets('a photoless draft is sent to add photos instead', (
    tester,
  ) async {
    await _pumpPrompt(
      tester,
      session: landlord,
      listings: [_listing(status: ListingStatus.draft, withPhoto: false)],
    );

    expect(find.text('Add photos'), findsOneWidget);
    expect(find.text('Publish now'), findsNothing);
  });

  testWidgets('an advert that is already live raises nothing', (tester) async {
    await _pumpPrompt(
      tester,
      session: landlord,
      listings: [_listing(status: ListingStatus.published, withPhoto: true)],
    );

    expect(find.text('Advertise this rental space?'), findsNothing);
  });

  // A closed advert cannot be republished, so the space is treated as though
  // it had none at all rather than being offered a publication that would fail.
  testWidgets('a closed advert is treated as no advert', (tester) async {
    await _pumpPrompt(
      tester,
      session: landlord,
      listings: [_listing(status: ListingStatus.closed, withPhoto: true)],
    );

    expect(find.text('Create listing'), findsOneWidget);
  });

  testWidgets('an account that cannot advertise is asked nothing', (
    tester,
  ) async {
    await _pumpPrompt(
      tester,
      session: const UserSession(
        userId: 'tenant-1',
        displayName: 'Brian Okello',
        email: 'brian@example.ug',
        role: AppRole.tenant,
      ),
      listings: const <Listing>[],
    );

    expect(find.text('Advertise this rental space?'), findsNothing);
  });
}

Unit _vacantUnit() => Unit(
  id: 'unit-1',
  propertyId: 'property-1',
  landlordId: 'landlord-1',
  label: '2B',
  type: UnitType.apartment,
  status: UnitStatus.vacant,
  monthlyRentMinor: 90000000,
  currency: 'UGX',
  createdAt: DateTime.utc(2026, 7, 29, 9),
  updatedAt: DateTime.utc(2026, 7, 29, 9),
);

Listing _listing({required ListingStatus status, required bool withPhoto}) =>
    Listing(
      id: 'listing-1',
      unitId: 'unit-1',
      propertyId: 'property-1',
      landlordId: 'landlord-1',
      title: 'Apartment 2B at Sunset Apartments',
      description: 'A well maintained home in a convenient Kampala location.',
      monthlyRentMinor: 90000000,
      currency: 'UGX',
      status: status,
      unitType: 'apartment',
      city: 'Kampala',
      neighborhood: 'Bukoto',
      imageUrls: withPhoto
          ? const <String>['https://example.test/photo.jpg']
          : const <String>[],
      createdAt: DateTime.utc(2026, 7, 29, 9),
      updatedAt: DateTime.utc(2026, 7, 29, 9),
      publishedAt: status == ListingStatus.published
          ? DateTime.utc(2026, 7, 29, 9)
          : null,
    );

Future<void> _pumpPrompt(
  WidgetTester tester, {
  required UserSession session,
  required List<Listing> listings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _FixedSessionController(session),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => promptToAdvertiseVacantSpace(
                context,
                ref,
                unit: _vacantUnit(),
                listings: listings,
              ),
              child: const Text('became vacant'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('became vacant'));
  await tester.pumpAndSettle();
}
