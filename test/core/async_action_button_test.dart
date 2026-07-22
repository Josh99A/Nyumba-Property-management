import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/presentation/async_action_button.dart';

void main() {
  group('AsyncActionGuard', () {
    test('drops calls that arrive while a run is in flight', () async {
      final guard = AsyncActionGuard();
      final completer = Completer<int>();
      var runs = 0;

      final first = guard.run(() {
        runs++;
        return completer.future;
      });
      final second = await guard.run(() async {
        runs++;
        return 2;
      });

      expect(runs, 1);
      expect(second, isNull, reason: 'the dropped call reports no result');

      completer.complete(1);
      expect(await first, 1);
    });

    test('accepts the next call once the previous one settles', () async {
      final guard = AsyncActionGuard();
      await guard.run(() async {});
      expect(guard.isRunning, isFalse);
      expect(await guard.run(() async => 'again'), 'again');
    });

    test('releases the guard when the action throws', () async {
      final guard = AsyncActionGuard();
      await expectLater(
        guard.run(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(guard.isRunning, isFalse);
    });
  });

  group('AsyncActionButton', () {
    Future<void> pumpButton(
      WidgetTester tester, {
      required Future<void> Function()? onPressed,
      bool showBusyIndicator = true,
      bool busy = false,
      bool disableAnimations = false,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Scaffold(
              body: Center(
                child: AsyncActionButton.filled(
                  onPressed: onPressed,
                  busy: busy,
                  showBusyIndicator: showBusyIndicator,
                  child: const Text('Save payment'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a second tap during the action does not run it twice', (
      tester,
    ) async {
      final completer = Completer<void>();
      var runs = 0;
      await pumpButton(
        tester,
        onPressed: () {
          runs++;
          return completer.future;
        },
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();

      expect(runs, 1);

      completer.complete();
      await tester.pumpAndSettle();
      expect(runs, 1);
    });

    testWidgets('two taps in the same frame still run the action once', (
      tester,
    ) async {
      final completer = Completer<void>();
      var runs = 0;
      await pumpButton(
        tester,
        onPressed: () {
          runs++;
          return completer.future;
        },
      );

      // No pump between the taps: the disabled state has not painted yet, so
      // only the internal guard can stop the duplicate.
      await tester.tap(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();

      expect(runs, 1);
      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('shows a spinner and disables itself while running', (
      tester,
    ) async {
      final completer = Completer<void>();
      await pumpButton(tester, onPressed: () => completer.future);

      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save payment'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
          isFalse);

      completer.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isTrue,
      );
    });

    testWidgets('honours a busy flag owned by the caller', (tester) async {
      await pumpButton(tester, onPressed: () async {}, busy: true);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isFalse,
      );
    });

    testWidgets('guards without a spinner when the indicator is off', (
      tester,
    ) async {
      final completer = Completer<void>();
      var runs = 0;
      await pumpButton(
        tester,
        showBusyIndicator: false,
        onPressed: () {
          runs++;
          return completer.future;
        },
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();

      expect(runs, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('eases down while pressed and back on release', (tester) async {
      final completer = Completer<void>();
      await pumpButton(tester, onPressed: () => completer.future);

      double currentScale() => tester
          .widget<AnimatedScale>(find.byType(AnimatedScale))
          .scale;

      expect(currentScale(), 1);

      final gesture = await tester.press(find.byType(FilledButton));
      await tester.pump();
      expect(currentScale(), lessThan(1));

      await gesture.up();
      await tester.pump();
      expect(currentScale(), 1);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('skips the press animation under reduced motion', (
      tester,
    ) async {
      await pumpButton(
        tester,
        onPressed: () async {},
        disableAnimations: true,
      );
      expect(find.byType(AnimatedScale), findsNothing);
    });

    testWidgets('stays disabled when no callback is given', (tester) async {
      await pumpButton(tester, onPressed: null);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isFalse,
      );
    });
  });

  group('AsyncActionIconButton', () {
    testWidgets('drops the duplicate tap and swaps the icon for a spinner', (
      tester,
    ) async {
      final completer = Completer<void>();
      var runs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AsyncActionIconButton(
                onPressed: () {
                  runs++;
                  return completer.future;
                },
                icon: const Icon(Icons.print_outlined),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.tap(find.byType(IconButton), warnIfMissed: false);
      await tester.pump();

      expect(runs, 1);
      expect(find.byIcon(Icons.print_outlined), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.print_outlined), findsOneWidget);
    });
  });
}
