import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/domain/sync_metadata.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/features/notifications/application/notification_providers.dart';
import 'package:nyumba_property_management/features/notifications/domain/app_notification.dart';
import 'package:nyumba_property_management/features/notifications/presentation/notification_center_sheet.dart';

void main() {
  const expectations = <String, ({String title, String empty, String item})>{
    'lg': (
      title: 'Obubaka',
      empty: 'Tewali bubaka bunaatuuka',
      item: 'Obubaka obupya',
    ),
    'sw': (title: 'Arifa', empty: 'Bado hakuna arifa', item: 'Arifa mpya'),
    'ar': (
      title: 'الإشعارات',
      empty: 'لا توجد إشعارات بعد',
      item: 'إشعار جديد',
    ),
  };

  for (final entry in expectations.entries) {
    testWidgets('notification center uses ${entry.key} app copy', (
      tester,
    ) async {
      await _pump(
        tester,
        locale: Locale(entry.key),
        notifications: const [],
        width: 360,
      );

      expect(tester.takeException(), isNull);
      final bell = tester.widget<IconButton>(find.byType(IconButton));
      expect(bell.tooltip, entry.value.title);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text(entry.value.title), findsOneWidget);
      expect(find.text(entry.value.empty), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('localized server title remains data and Arabic is RTL', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in [320.0, 1200.0]) {
      await _pump(
        tester,
        locale: const Locale('ar'),
        width: width,
        notifications: [_notification(title: expectations['ar']!.item)],
      );
      final bellContext = tester.element(find.byType(NotificationBell));
      expect(Directionality.of(bellContext), TextDirection.rtl);

      await tester.tap(find.byTooltip('إشعار واحد غير مقروء'));
      await tester.pumpAndSettle();
      expect(find.text(expectations['ar']!.item), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width=$width');
      await tester.tap(find.byTooltip('إغلاق الإشعارات'));
      await tester.pumpAndSettle();
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Locale locale,
  required List<AppNotification> notifications,
  required double width,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 760);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appNotificationsProvider.overrideWith(
          (ref) => Stream.value(notifications),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          ...LugandaLocalizations.delegates,
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: Align(child: NotificationBell())),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

AppNotification _notification({required String title}) => AppNotification(
  id: 'notification-1',
  kind: AppNotificationKind.system,
  title: title,
  body: 'تفاصيل الحساب',
  route: '/settings',
  createdAt: DateTime.utc(2026, 7, 17, 8),
  updatedAt: DateTime.utc(2026, 7, 17, 8),
  isRead: false,
  syncMetadata: const SyncMetadata.synced(),
);
