import 'dart:convert';
import 'dart:typed_data';

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
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/marketplace/domain/listing.dart';
import 'package:nyumba_property_management/features/portfolio/application/portfolio_use_cases.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:nyumba_property_management/features/portfolio/presentation/property_detail_screen.dart';

class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final UserSession? _session;

  @override
  UserSession? build() => _session;
}

/// Records the property it was asked to save instead of reaching Firestore.
class _RecordingUpdateProperty extends UpdateProperty {
  _RecordingUpdateProperty(super.ref);

  final calls = <Property>[];

  @override
  Future<Property> call(Property property) async {
    calls.add(property);
    return property;
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
  final property = Property(
    id: 'property-1',
    landlordId: 'landlord-uid',
    name: 'Ntinda Rise',
    addressLine: 'Plot 12 Ntinda Road',
    city: 'Kampala',
    country: 'Uganda',
    description: 'A quiet block near the shops.',
    imageUrls: [_dataUri(_pngBytes), _dataUri(_pngBytes)],
    createdAt: now,
    updatedAt: now,
    syncMetadata: const SyncMetadata.synced(serverRevision: '3'),
  );

  testWidgets(
    'edit property pre-fills every saved field, including photos, and '
    'saves the full set back',
    (tester) async {
      late _RecordingUpdateProperty recorder;
      await _pump(
        tester,
        properties: [property],
        overrideUpdate: (ref) => recorder = _RecordingUpdateProperty(ref),
      );

      await tester.tap(find.byKey(const ValueKey('edit-property')));
      await tester.pumpAndSettle();

      // Every text field arrives pre-filled with what the record already has.
      expect(find.widgetWithText(TextFormField, 'Ntinda Rise'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Plot 12 Ntinda Road'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, 'Kampala'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'A quiet block near the shops.'),
        findsOneWidget,
      );
      // Both saved photos render as removable chips — the point of this change.
      expect(find.text('Photo 1'), findsOneWidget);
      expect(find.text('Photo 2'), findsOneWidget);

      // Remove one photo and change the name.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Photo 2'),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ntinda Rise'),
        'Ntinda Rise Apartments',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      final saved = recorder.calls.single;
      expect(saved.name, 'Ntinda Rise Apartments');
      // Untouched fields survive the round trip unchanged.
      expect(saved.addressLine, 'Plot 12 Ntinda Road');
      expect(saved.city, 'Kampala');
      expect(saved.description, 'A quiet block near the shops.');
      // One photo was removed; the surviving one keeps its data.
      expect(saved.imageUrls, [_dataUri(_pngBytes)]);
    },
  );

  testWidgets(
    'removing every photo blocks the save instead of erasing them all',
    (tester) async {
      // A blocked save must never even reach the command, so the provider is
      // never read — proving that is the point of this test.
      var providerRead = false;
      await _pump(
        tester,
        properties: [property],
        overrideUpdate: (ref) {
          providerRead = true;
          return _RecordingUpdateProperty(ref);
        },
      );

      await tester.tap(find.byKey(const ValueKey('edit-property')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Photo 1'),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Photo 2'),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(providerRead, isFalse);
      expect(
        find.text('Keep at least one photo of the property.'),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Property> properties,
  required UpdateProperty Function(Ref ref) overrideUpdate,
}) async {
  tester.view.physicalSize = const Size(1280, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final router = GoRouter(
    initialLocation: '/properties/${properties.first.id}',
    routes: [
      GoRoute(
        path: '/properties/:propertyId',
        builder: (context, state) => Scaffold(
          body: PropertyDetailScreen(
            propertyId: state.pathParameters['propertyId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/properties',
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
        portfolioPropertiesProvider.overrideWith(
          (ref) => Stream.value(properties),
        ),
        portfolioUnitsProvider.overrideWith(
          (ref) => Stream.value(const <Unit>[]),
        ),
        landlordListingsProvider.overrideWith(
          (ref) => Stream.value(const <Listing>[]),
        ),
        updatePropertyProvider.overrideWith(overrideUpdate),
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
