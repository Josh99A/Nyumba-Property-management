import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/router.dart';
import 'package:nyumba_property_management/app/splash/splash_gate.dart';
import 'package:nyumba_property_management/core/presentation/async_action_button.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/auth/presentation/app_lock_gate.dart';

class _StubSessionController extends SessionController {
  _StubSessionController(this.session);
  final UserSession? session;
  @override
  UserSession? build() => session;
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

/// Every other router test pumps `MaterialApp.router` bare. The real app wraps
/// the router in `SplashGate > AppLockGate`, and that chain — including the
/// splash handing off mid-session above the whole Navigator — was untested,
/// so nothing caught what it did to routes or focus.
void main() {
  testWidgets('a popped dialog settles before navigation and the next dialog', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _StubSessionController(_landlord),
        ),
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
    expect(tester.takeException(), isNull, reason: 'reaching /properties');

    // Stand in for the Add-property dialog: a modal with a focused text field,
    // dismissed from inside its own button, with a route change chasing it in
    // the same continuation — exactly what _createProperty does on success.
    final navigatorContext = router.routerDelegate.navigatorKey.currentContext!;
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);

    ModalRoute<bool>? dialogRoute;
    final pending = showDialog<bool>(
      context: navigatorContext,
      builder: (dialogContext) {
        dialogRoute ??= ModalRoute.of<bool>(dialogContext);
        return AlertDialog(
          content: TextField(focusNode: fieldFocus, autofocus: true),
          actions: [
            AsyncActionButton.text(
              onPressed: () async => Navigator.pop(dialogContext, true),
              child: const Text('Save property'),
            ),
          ],
        );
      },
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(fieldFocus.hasFocus, isTrue, reason: 'field took focus');

    await tester.tap(find.text('Save property'));
    await pending;
    expect(dialogRoute, isNotNull);
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await dialogRoute!.completed;
    expect(find.text('Save property'), findsNothing);

    router.go('/finances');
    await tester.pump();
    final nextDialog = showDialog<void>(
      context: router.routerDelegate.navigatorKey.currentContext!,
      builder: (dialogContext) => AlertDialog(
        content: const TextField(autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close next dialog'),
          ),
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(find.text('Close next dialog'), findsOneWidget);
    await tester.tap(find.text('Close next dialog'));
    await nextDialog;
    await _pumpFor(tester, const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull, reason: 'after pop + go');
  });
}
