import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nyumba_property_management/app/bootstrap/app_dependencies.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/cloud/cloud_command.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/portfolio/application/portfolio_use_cases.dart';
import 'package:nyumba_property_management/features/portfolio/domain/property.dart';
import 'package:nyumba_property_management/features/portfolio/domain/unit.dart';
import 'package:nyumba_property_management/features/portfolio/presentation/properties_screen.dart';
import 'package:nyumba_property_management/features/portfolio/presentation/property_photo_picker.dart';
import 'package:nyumba_property_management/features/subscriptions/application/subscription_providers.dart';
import 'package:nyumba_property_management/features/subscriptions/domain/landlord_entitlement.dart';

import '../support/cloud_fixtures.dart';

class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final UserSession _session;

  @override
  UserSession? build() => _session;
}

class _RecordingCreateProperty extends CreateProperty {
  _RecordingCreateProperty(super.ref, {this.failure});

  final Object? failure;
  final calls = <CreatePropertyInput>[];

  @override
  Future<MutationResult> call(CreatePropertyInput input) async {
    calls.add(input);
    if (failure case final failure?) throw failure;
    return MutationResult(
      aggregateId: 'property-created',
      outcome: CommandOutcome(committedAt: DateTime.utc(2026, 7, 30, 15)),
    );
  }
}

final _photoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<ImagePickOutcome> _pickPhoto({required int remainingSlots}) async {
  return ImagePickOutcome(
    images: [
      PickedPropertyPhoto(
        name: 'property.png',
        mimeType: 'image/png',
        bytes: _photoBytes,
      ),
    ],
  );
}

void main() {
  testWidgets(
    'successful create closes with the mutation result and navigates by its id',
    (tester) async {
      late _RecordingCreateProperty create;
      final router = await _pumpCreateDialog(
        tester,
        overrideCreate: (ref) => create = _RecordingCreateProperty(ref),
      );

      await _completeRequiredFields(tester);
      await tester.tap(find.text('Save property'));
      await tester.pumpAndSettle();

      expect(create.calls, hasLength(1));
      expect(create.calls.single.imageUrls, hasLength(1));
      expect(
        router.routeInformationProvider.value.uri.path,
        '/properties/property-created',
      );
      expect(find.text('created-property-created'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed save can be cancelled only once without navigator lock',
    (tester) async {
      final router = await _pumpCreateDialog(
        tester,
        overrideCreate: (ref) => _RecordingCreateProperty(
          ref,
          failure: StateError('test rejection'),
        ),
      );

      await _completeRequiredFields(tester);
      await tester.tap(find.text('Save property'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nyumba could not save this property'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.tap(find.text('Cancel'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/properties');
      expect(find.text('Add property'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _completeRequiredFields(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Property name'),
    'Kisaasi Court',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Street address'),
    'Plot 8 Kisaasi Road',
  );
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  expect(find.text('Primary'), findsOneWidget);
}

Future<GoRouter> _pumpCreateDialog(
  WidgetTester tester, {
  required CreateProperty Function(Ref ref) overrideCreate,
}) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final router = GoRouter(
    initialLocation: '/properties',
    routes: [
      GoRoute(
        path: '/properties',
        builder: (context, state) => const Scaffold(
          body: PropertiesScreen(
            openCreateOnLoad: true,
            photoPicker: _pickPhoto,
          ),
        ),
      ),
      GoRoute(
        path: '/properties/:propertyId',
        builder: (context, state) => Scaffold(
          body: Text('created-${state.pathParameters['propertyId']}'),
        ),
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
              email: 'sandra@nyumba.test',
              role: AppRole.landlord,
              subscriptionStatus: LandlordSubscriptionStatus.active,
              subscriptionTier: 'starter',
            ),
          ),
        ),
        portfolioPropertiesProvider.overrideWith(
          (ref) => Stream.value(cloudOf(const <Property>[])),
        ),
        portfolioUnitsProvider.overrideWith(
          (ref) => Stream.value(cloudOf(const <Unit>[])),
        ),
        landlordEntitlementProvider.overrideWith(
          (ref) => Stream.value(const EntitlementNotApplicable()),
        ),
        createPropertyProvider.overrideWith(overrideCreate),
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
  expect(find.text('Save property'), findsOneWidget);
  return router;
}
