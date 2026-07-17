import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/notifications/application/notification_providers.dart';
import 'package:nyumba_property_management/features/notifications/domain/app_notification.dart';
import 'package:nyumba_property_management/features/notifications/presentation/notification_center_sheet.dart';

void main() {
  testWidgets('notification bell opens an empty inbox without phone overflow', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appNotificationsProvider.overrideWith(
            (ref) => Stream.value(const <AppNotification>[]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [NotificationBell()])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.text('New account updates will appear here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
