import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/presentation/toast.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/subscriptions/application/subscription_providers.dart';
import 'package:nyumba_property_management/features/subscriptions/presentation/landlord_subscription_screen.dart';

class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final UserSession? _session;

  @override
  UserSession? build() => _session;
}

/// Records the tier it was asked to reserve instead of reaching Firebase, so
/// the sheet's post-selection behaviour is testable without a live project.
class _RecordingSelectSubscriptionPlan extends SelectSubscriptionPlan {
  _RecordingSelectSubscriptionPlan(super.ref);

  final calls = <String>[];

  @override
  Future<void> call(String tier) async {
    calls.add(tier);
  }
}

void main() {
  // A freshly onboarded landlord already carries the `starter` tier (the
  // server default), so the first choosable card in tier order is `pro` —
  // matching what the earlier screenshot showed: Starter marked "Selected",
  // the rest offering "Choose plan".
  testWidgets(
    'choosing a plan asks how to pay, and cash tells the landlord to wait '
    'for approval and check their email',
    (tester) async {
      late _RecordingSelectSubscriptionPlan recorder;
      await _pump(
        tester,
        overrideSelectPlan: (ref) =>
            recorder = _RecordingSelectSubscriptionPlan(ref),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Choose plan').first);
      await tester.pumpAndSettle();

      expect(find.text('Pay for Pro'), findsOneWidget);
      expect(find.text('Mobile money'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);

      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();

      expect(recorder.calls, ['pro']);
      expect(
        find.textContaining('wait for approval'),
        findsOneWidget,
        reason: 'the toast must tell the landlord to wait for approval',
      );
      expect(
        find.textContaining('check your email'),
        findsOneWidget,
        reason: 'the toast must tell the landlord to check their email',
      );
    },
  );

  testWidgets(
    'choosing mobile money or card says electronic payment is coming soon, '
    'without a wait-for-approval promise it cannot keep',
    (tester) async {
      late _RecordingSelectSubscriptionPlan recorder;
      await _pump(
        tester,
        overrideSelectPlan: (ref) =>
            recorder = _RecordingSelectSubscriptionPlan(ref),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Choose plan').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile money'));
      await tester.pumpAndSettle();

      expect(recorder.calls, ['pro']);
      // The persistent status card already carries its own "coming soon"
      // line for in-app checkout in general, so match the toast specifically.
      expect(
        find.textContaining('automatic access once available'),
        findsOneWidget,
      );
      expect(find.textContaining('wait for approval'), findsNothing);
    },
  );

  testWidgets('dismissing the sheet without a choice reserves nothing', (
    tester,
  ) async {
    // A cancelled sheet never reaches selectSubscriptionPlanProvider, so
    // nothing here ever constructs the recorder — that omission is exactly
    // what this test is proving.
    var providerRead = false;
    await _pump(
      tester,
      overrideSelectPlan: (ref) {
        providerRead = true;
        return _RecordingSelectSubscriptionPlan(ref);
      },
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Choose plan').first);
    await tester.pumpAndSettle();
    expect(find.text('Cash'), findsOneWidget);
    // Tap the barrier above the sheet to dismiss it.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Cash'), findsNothing, reason: 'sheet should be closed');
    expect(providerRead, isFalse);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required SelectSubscriptionPlan Function(Ref ref) overrideSelectPlan,
}) async {
  // The default 800x600 test surface clips the plan grid; every tier's
  // "Choose plan" button must be reachable by tap().
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
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
              subscriptionStatus: LandlordSubscriptionStatus.pendingPayment,
              subscriptionTier: 'starter',
            ),
          ),
        ),
        selectSubscriptionPlanProvider.overrideWith(overrideSelectPlan),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: nyumbaMessengerKey,
        theme: NyumbaTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          ...LugandaLocalizations.delegates,
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const LandlordSubscriptionScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
