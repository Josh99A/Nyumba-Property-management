import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/features/admin/application/admin_directory_providers.dart';
import 'package:nyumba_property_management/features/admin/domain/platform_account.dart';
import 'package:nyumba_property_management/features/admin/presentation/admin_portfolio_screen.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';

class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final UserSession? _session;

  @override
  UserSession? build() => _session;
}

final _now = DateTime.utc(2026, 7, 20);

Property _property({required String id, required String name, bool archived = false}) =>
    Property(
      id: id,
      landlordId: 'landlord-uid',
      name: name,
      addressLine: 'Plot 12 Ntinda Road',
      city: 'Kampala',
      country: 'UG',
      createdAt: _now,
      updatedAt: _now,
      isArchived: archived,
      archivedAt: archived ? _now : null,
      syncMetadata: const SyncMetadata.synced(serverRevision: '3'),
    );

Unit _unit({
  required String id,
  required String propertyId,
  required String label,
  bool archived = false,
}) => Unit(
  id: id,
  propertyId: propertyId,
  landlordId: 'landlord-uid',
  label: label,
  type: UnitType.apartment,
  status: UnitStatus.vacant,
  monthlyRentMinor: 120000000,
  currency: 'UGX',
  createdAt: _now,
  updatedAt: _now,
  isArchived: archived,
  archivedAt: archived ? _now : null,
  syncMetadata: const SyncMetadata.synced(serverRevision: '2'),
);

void main() {
  testWidgets('groups a portfolio under the landlord who owns it', (
    tester,
  ) async {
    await _pump(
      tester,
      properties: [_property(id: 'property-1', name: 'Ntinda Rise')],
      units: [
        _unit(id: 'unit-1', propertyId: 'property-1', label: 'Apartment A1'),
      ],
    );

    expect(find.text('Sandra Nakato'), findsOneWidget);
    expect(find.text('Ntinda Rise'), findsOneWidget);
  });

  testWidgets('archived records stay hidden until they are asked for', (
    tester,
  ) async {
    await _pump(
      tester,
      properties: [
        _property(id: 'property-1', name: 'Ntinda Rise'),
        _property(id: 'property-2', name: 'Retired Court', archived: true),
      ],
    );

    expect(find.text('Retired Court'), findsNothing);

    await tester.tap(find.text('Show archived'));
    await tester.pumpAndSettle();

    expect(find.text('Retired Court'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
  });

  // An ordinary admin sees the archived record but has no way to destroy it,
  // matching the server gate on property.delete.
  testWidgets('an ordinary admin is not offered the permanent delete', (
    tester,
  ) async {
    await _pump(
      tester,
      properties: [
        _property(id: 'property-2', name: 'Retired Court', archived: true),
      ],
      role: AppRole.admin,
    );
    await tester.tap(find.text('Show archived'));
    await tester.pumpAndSettle();

    expect(find.text('Retired Court'), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever_outlined), findsNothing);
  });

  testWidgets('a super admin is offered the permanent delete', (tester) async {
    await _pump(
      tester,
      properties: [
        _property(id: 'property-2', name: 'Retired Court', archived: true),
      ],
      role: AppRole.superAdmin,
    );
    await tester.tap(find.text('Show archived'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_forever_outlined), findsOneWidget);
  });

  testWidgets('a property is only purgeable once its units are gone', (
    tester,
  ) async {
    await _pump(
      tester,
      properties: [
        _property(id: 'property-2', name: 'Retired Court', archived: true),
      ],
      // An archived unit still references the property, so the server would
      // reject the purge — the action must not be offered.
      units: [
        _unit(
          id: 'unit-1',
          propertyId: 'property-2',
          label: 'Apartment A1',
          archived: true,
        ),
      ],
      role: AppRole.superAdmin,
    );
    await tester.tap(find.text('Show archived'));
    await tester.pumpAndSettle();

    // The property's own row offers nothing while a unit still points at it.
    expect(find.byIcon(Icons.delete_forever_outlined), findsNothing);

    // Expanding it reveals the unit, which is purgeable on its own.
    await tester.ensureVisible(find.text('Retired Court'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retired Court'));
    await tester.pumpAndSettle();
    expect(find.text('Apartment A1'), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever_outlined), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  List<Property> properties = const <Property>[],
  List<Unit> units = const <Unit>[],
  List<Listing> listings = const <Listing>[],
  AppRole role = AppRole.superAdmin,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _FixedSessionController(
            UserSession(
              userId: 'admin-uid',
              displayName: 'Nyumba Admin',
              email: 'admin@nyumba.ug',
              role: role,
            ),
          ),
        ),
        adminPropertiesProvider.overrideWith((ref) => Stream.value(properties)),
        adminUnitsProvider.overrideWith((ref) => Stream.value(units)),
        landlordListingsProvider.overrideWith((ref) => Stream.value(listings)),
        platformAccountsProvider.overrideWith(
          (ref) => Stream.value(const <PlatformAccount>[
            PlatformAccount(
              uid: 'landlord-uid',
              displayName: 'Sandra Nakato',
              email: 'sandra@acaciahomes.ug',
              roleLabel: 'Landlord',
              status: PlatformAccountStatus.active,
              joinedLabel: '12 Mar 2026',
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: NyumbaTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          ...LugandaLocalizations.delegates,
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: AdminPortfolioScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
