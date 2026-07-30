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
        theme: ThemeData(platform: TargetPlatform.android),
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

    await tester.fling(find.text('Short page'), const Offset(0, 300), 1000);
    await tester.pump();

    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(refreshCount, 1);

    completed.complete();
    await tester.pumpAndSettle();

    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  testWidgets('supports the pull gesture when the page is empty', (
    tester,
  ) async {
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: NyumbaRefreshIndicator(
            onRefresh: () async => refreshCount++,
            child: ListView(),
          ),
        ),
      ),
    );

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(refreshCount, 1);
  });
}
