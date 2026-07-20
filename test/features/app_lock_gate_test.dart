import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/features/auth/application/app_lock_controller.dart';
import 'package:nyumba_property_management/features/auth/application/session_controller.dart';
import 'package:nyumba_property_management/features/auth/data/app_lock_store.dart';
import 'package:nyumba_property_management/features/auth/domain/biometric_authenticator.dart';
import 'package:nyumba_property_management/features/auth/domain/user_session.dart';
import 'package:nyumba_property_management/features/auth/presentation/app_lock_gate.dart';

final class _FakeStore implements AppLockStore {
  bool enabled = false;
  bool offered = true;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool value) async => enabled = value;

  @override
  Future<bool> readOffered() async => offered;

  @override
  Future<void> markOffered() async => offered = true;
}

final class _FakeAuthenticator implements BiometricAuthenticator {
  BiometricResult next = const BiometricResult(BiometricOutcome.dismissed);

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<BiometricResult> authenticate(String reason) async => next;
}

/// Firebase.apps is empty under test, so the real controller would build to
/// null and never resolve a session; this stands a signed-in landlord up.
final class _FakeSessionController extends SessionController {
  @override
  UserSession? build() => const UserSession(
    userId: 'landlord-1',
    displayName: 'Test Landlord',
    email: 'landlord@example.com',
    role: AppRole.landlord,
  );
}

void main() {
  testWidgets('a locked workspace is hidden from semantics and focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final store = _FakeStore()..enabled = true;
    final workspaceButton = FocusNode(debugLabel: 'workspace-action');
    addTearDown(workspaceButton.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockStoreProvider.overrideWithValue(store),
          biometricAuthenticatorProvider.overrideWithValue(
            _FakeAuthenticator(),
          ),
          sessionControllerProvider.overrideWith(_FakeSessionController.new),
        ],
        child: MaterialApp(
          theme: NyumbaTheme.light,
          home: AppLockGate(
            child: Scaffold(
              body: TextButton(
                focusNode: workspaceButton,
                onPressed: () {},
                child: const Text('Workspace action'),
              ),
            ),
          ),
        ),
      ),
    );
    // Let the stored preference restore (locks) and the auto-prompt resolve
    // (dismissed, so the cover stays up).
    await tester.pump();
    await tester.pump();

    expect(find.text('Nyumba is locked'), findsOneWidget);
    // The workspace widget is still built underneath, but a screen reader
    // must not be able to read it through the cover.
    expect(find.text('Workspace action'), findsOneWidget);
    expect(find.semantics.byLabel('Workspace action'), findsNothing);
    expect(find.semantics.byLabel('Unlock'), findsOne);

    // Keyboard traversal must not reach behind the cover either.
    workspaceButton.requestFocus();
    await tester.pump();
    expect(workspaceButton.hasFocus, isFalse);
    for (var presses = 0; presses < 5; presses++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(workspaceButton.hasFocus, isFalse);
    }

    semantics.dispose();
  });

  testWidgets('an unlocked workspace keeps its semantics and focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final workspaceButton = FocusNode(debugLabel: 'workspace-action');
    addTearDown(workspaceButton.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockStoreProvider.overrideWithValue(_FakeStore()),
          biometricAuthenticatorProvider.overrideWithValue(
            _FakeAuthenticator(),
          ),
          sessionControllerProvider.overrideWith(_FakeSessionController.new),
        ],
        child: MaterialApp(
          theme: NyumbaTheme.light,
          home: AppLockGate(
            child: Scaffold(
              body: TextButton(
                focusNode: workspaceButton,
                onPressed: () {},
                child: const Text('Workspace action'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nyumba is locked'), findsNothing);
    expect(find.semantics.byLabel('Workspace action'), findsOne);

    workspaceButton.requestFocus();
    await tester.pump();
    expect(workspaceButton.hasFocus, isTrue);

    semantics.dispose();
  });
}
