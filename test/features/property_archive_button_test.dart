import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/features/portfolio/presentation/property_archive_button.dart';

void main() {
  testWidgets('explains why a property with rental spaces cannot be archived', (
    tester,
  ) async {
    var archiveCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: NyumbaTheme.light,
        home: Scaffold(
          body: PropertyArchiveButton(
            propertyName: 'Garden Court',
            activeRentalSpaceCount: 3,
            onArchive: () async => archiveCalled = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('archive-property')));
    await tester.pumpAndSettle();

    expect(find.text('Archive rental spaces first'), findsOneWidget);
    expect(find.textContaining('3 active rental spaces'), findsOneWidget);
    expect(archiveCalled, isFalse);
  });

  testWidgets('confirms an empty property before invoking archive', (
    tester,
  ) async {
    var archiveCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: NyumbaTheme.light,
        home: Scaffold(
          body: PropertyArchiveButton(
            propertyName: 'Empty Court',
            activeRentalSpaceCount: 0,
            onArchive: () async => archiveCalled = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('archive-property')));
    await tester.pumpAndSettle();
    expect(find.text('Archive Empty Court?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Archive property'));
    await tester.pumpAndSettle();

    expect(archiveCalled, isTrue);
  });
}
