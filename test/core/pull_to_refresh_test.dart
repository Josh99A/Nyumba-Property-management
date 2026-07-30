import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/presentation/pull_to_refresh.dart';

void main() {
  testWidgets('supports refresh when the page is shorter than the viewport', (
    tester,
  ) async {
    final completed = Completer<void>();
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NyumbaRefreshIndicator(
            onRefresh: () {
              refreshCount++;
              return completed.future;
            },
            child: ListView(
              children: const [SizedBox(height: 80, child: Text('Short page'))],
            ),
          ),
        ),
      ),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.physics, isA<AlwaysScrollableScrollPhysics>());

    final indicator = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    unawaited(indicator.show());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(refreshCount, 1);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);

    completed.complete();
    await tester.pumpAndSettle();

    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });
}
