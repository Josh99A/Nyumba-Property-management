import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/auth/application/app_lock_controller.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/data/app_lock_store.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/auth/presentation/app_lock_gate.dart';

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

/// The lock screen animates a spinner, so this tree never settles.
Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(ProviderContainer container, FocusNode workspaceFocus) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AppLockGate(
          child: Scaffold(body: TextField(focusNode: workspaceFocus)),
        ),
      ),
    );

ProviderContainer _container() => ProviderContainer(
  overrides: [
    sessionControllerProvider.overrideWith(
      () => _StubSessionController(_landlord),
    ),
    appLockStoreProvider.overrideWithValue(_EnabledLockStore()),
  ],
);

/// The cover hides the workspace from sight and, through BlockSemantics, from
/// assistive technology. Focus is neither of those. A hardware keyboard — a
/// Bluetooth board, or DeX on the Samsung hardware this ships to — types into
/// whatever holds focus no matter what is painted over it, so the lock has to
/// take focus away as well as cover the pixels.
void main() {
  testWidgets('an engaged lock takes focus off the workspace behind it', (
    tester,
  ) async {
    final workspaceFocus = FocusNode(debugLabel: 'workspace-field');
    addTearDown(workspaceFocus.dispose);
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, workspaceFocus));
    await _pump(tester);

    // A landlord mid-form with the field focused, which is where the biometric
    // prompt interrupts them.
    final lock = container.read(appLockControllerProvider.notifier);
    lock.handleSignedOut();
    await _pump(tester);
    workspaceFocus.requestFocus();
    await _pump(tester);
    expect(workspaceFocus.hasFocus, isTrue, reason: 'precondition');

    lock.handleLifecycle(AppLifecycleState.hidden, at: DateTime(2026));
    lock.handleLifecycle(
      AppLifecycleState.resumed,
      at: DateTime(2026).add(const Duration(minutes: 5)),
    );
    await _pump(tester);

    expect(container.read(appLockControllerProvider).locked, isTrue);
    expect(
      workspaceFocus.hasFocus,
      isFalse,
      reason: 'keystrokes must not reach a field the lock is covering',
    );
  });

  testWidgets('tab traversal cannot walk into the covered workspace', (
    tester,
  ) async {
    final workspaceFocus = FocusNode(debugLabel: 'workspace-field');
    addTearDown(workspaceFocus.dispose);
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, workspaceFocus));
    await _pump(tester);
    expect(container.read(appLockControllerProvider).locked, isTrue);

    for (var press = 1; press <= 25; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        workspaceFocus.hasFocus,
        isFalse,
        reason: 'tab reached the covered workspace after $press presses',
      );
    }
  });
}
