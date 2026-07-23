import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/router.dart';
import 'package:nyumba_property_management/app/splash/splash_gate.dart';
import 'package:nyumba_property_management/features/auth/application/app_lock_controller.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/data/app_lock_store.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/auth/presentation/app_lock_gate.dart';
import 'package:nyumba_property_management/features/auth/presentation/app_lock_screen.dart';

class _StubSessionController extends SessionController {
  _StubSessionController(this.session);
  final UserSession? session;
  @override
  UserSession? build() => session;
}

class _EnabledLockStore implements AppLockStore {
  @override
  Future<bool> readEnabled() async => true;
  @override
  Future<void> writeEnabled(bool enabled) async {}
  @override
  Future<bool> readOffered() async => true;
  @override
  Future<void> markOffered() async {}
}

const _landlord = UserSession(
  userId: 'landlord-1',
  displayName: 'Landlord',
  email: 'landlord@nyumba.test',
  role: AppRole.landlord,
  subscriptionStatus: LandlordSubscriptionStatus.active,
  subscriptionTier: 'starter',
);

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = tester.binding.clock.now().add(duration);
  while (tester.binding.clock.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the lock engages across a zero-sized resume', (tester) async {
    // ExcludeSemantics is half of what the lock toggles, and a widget test
    // builds no semantics tree unless asked — so without this the toggle is
    // only doing half its work here, unlike on a device.
    final semantics = tester.ensureSemantics();
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 2408);

    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _StubSessionController(_landlord),
        ),
        appLockStoreProvider.overrideWithValue(_EnabledLockStore()),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => SplashGate(
            child: AppLockGate(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
    router.go('/properties');
    await _pumpFor(tester, const Duration(seconds: 4));

    // The lock is on but already passed for this session, which is where a
    // landlord actually works from.
    container.read(appLockControllerProvider.notifier).handleSignedOut();
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(container.read(appLockControllerProvider).locked, isFalse);

    // The Add-property dialog, open with a focused field and the keyboard up,
    // which is the state the photo picker interrupts.
    final navigatorContext = router.routerDelegate.navigatorKey.currentContext!;
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);
    unawaited(
      showDialog<void>(
        context: navigatorContext,
        builder: (dialogContext) =>
            AlertDialog(content: TextField(focusNode: fieldFocus)),
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    fieldFocus.requestFocus();
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(fieldFocus.hasFocus, isTrue, reason: 'field holds focus');

    final lock = container.read(appLockControllerProvider.notifier);
    // The picker Activity takes over: Flutter is hidden, then resumed more
    // than the grace period later, and the viewport collapses to 0x0 in
    // between exactly as the device logs show.
    final hiddenAt = DateTime.now();
    lock.handleLifecycle(AppLifecycleState.hidden, at: hiddenAt);
    await tester.pump();

    tester.view.physicalSize = Size.zero;
    await tester.pump();
    await tester.pump();

    tester.view.physicalSize = const Size(1080, 2408);
    lock.handleLifecycle(
      AppLifecycleState.resumed,
      at: hiddenAt.add(const Duration(minutes: 5)),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    expect(container.read(appLockControllerProvider).locked, isTrue);
    expect(find.byType(ExcludeFocus), findsNothing);
    expect(
      find.ancestor(
        of: find.byType(AppLockScreen),
        matching: find.byType(BlockSemantics),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
