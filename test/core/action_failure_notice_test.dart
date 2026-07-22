import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/presentation/action_failure.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: NyumbaTheme.light, home: Scaffold(body: child));

void main() {
  testWidgets('a failure leads with the plain sentence, not the exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ActionFailureNotice(
          failure: ActionFailure(
            message: 'Photos must contain at most 5 images.',
            details: 'DomainValidationException: imageUrls: at most 5 images',
          ),
        ),
      ),
    );

    expect(find.text('Photos must contain at most 5 images.'), findsOneWidget);
    // The raw error is one tap away, never in the reader's face.
    expect(find.textContaining('DomainValidationException'), findsNothing);

    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DomainValidationException'), findsOneWidget);
  });

  testWidgets('a failure with nothing technical to add offers no toggle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ActionFailureNotice(
          failure: ActionFailure(message: 'Add at least one photo.'),
        ),
      ),
    );

    expect(find.text('Add at least one photo.'), findsOneWidget);
    expect(find.text('Technical details'), findsNothing);
  });

  testWidgets('every rejected photo is listed, not just the first', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const PickProblemsNotice(
          problems: ['"deed.pdf" is not an image.', '"huge.png" is too large.'],
        ),
      ),
    );

    expect(find.text('"deed.pdf" is not an image.'), findsOneWidget);
    expect(find.text('"huge.png" is too large.'), findsOneWidget);
  });

  testWidgets('nothing rejected means nothing on screen', (tester) async {
    await tester.pumpWidget(_host(const PickProblemsNotice(problems: [])));

    expect(find.byType(Icon), findsNothing);
  });
}
