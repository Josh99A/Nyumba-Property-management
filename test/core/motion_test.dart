import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/presentation/motion.dart';

void main() {
  group('FadeSlideIn', () {
    testWidgets('child becomes fully visible after the entrance settles', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FadeSlideIn(
            delay: Duration(milliseconds: 120),
            child: Text('Entrance'),
          ),
        ),
      );

      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('Entrance'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 0);

      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();
      final settled = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('Entrance'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(settled.opacity.value, 1);
    });

    testWidgets('shows immediately when animations are disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: FadeSlideIn(
              delay: Duration(milliseconds: 400),
              child: Text('Reduced motion'),
            ),
          ),
        ),
      );

      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('Reduced motion'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
    });
  });

  group('AnimatedCount', () {
    testWidgets('settles on the exact formatted value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedCount(
            value: 84250000,
            format: (value) => 'UGX ${value.round()}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('UGX 84250000'), findsOneWidget);
    });

    testWidgets('renders the final value directly under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: AnimatedCount(value: 24, format: (value) => '$value units'),
          ),
        ),
      );
      expect(find.text('24 units'), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });
  });
}
