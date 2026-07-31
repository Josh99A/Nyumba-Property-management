import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/cloud/cloud_data.dart';
import 'package:nyumba_property_management/core/localization/generated/app_localizations.dart';
import 'package:nyumba_property_management/core/localization/luganda_localizations.dart';
import 'package:nyumba_property_management/core/presentation/cloud_data_view.dart';
import 'package:nyumba_property_management/core/presentation/status_message.dart';

Widget host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: NyumbaTheme.light,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    ...LugandaLocalizations.delegates,
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

Widget viewOf(
  CloudData<List<String>> data, {
  Future<void> Function()? onRetry,
}) => CloudDataView<List<String>>(
  data: data,
  onRetry: onRetry,
  builder: (context, value, isValidated) =>
      Column(children: [for (final item in value) Text(item)]),
);

void main() {
  final readAt = DateTime.now().toUtc();

  group('initial loading', () {
    testWidgets('shows a spinner with an announced label', (tester) async {
      await tester.pumpWidget(
        host(viewOf(const CloudData<List<String>>.initialLoading())),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading'), findsOneWidget);
    });
  });

  group('confirmed empty', () {
    testWidgets('is not rendered as a failure', (tester) async {
      await tester.pumpWidget(
        host(
          viewOf(CloudData<List<String>>.empty(const [], retrievedAt: readAt)),
        ),
      );
      await tester.pumpAndSettle();

      // The distinction this whole type exists to preserve: an empty server
      // answer is a result, not an error and not a loading state.
      expect(find.byType(NyumbaStatusMessage), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Last updated'), findsOneWidget);
    });
  });

  group('live data', () {
    testWidgets('renders content with a freshness stamp', (tester) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.live(const ['Kololo'], retrievedAt: readAt),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kololo'), findsOneWidget);
      expect(find.byType(NyumbaStatusMessage), findsNothing);
      expect(find.textContaining('Last updated'), findsOneWidget);
    });

    testWidgets('warns when the server also returned unreadable records', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.live(
              const ['Kololo'],
              retrievedAt: readAt,
              discardedRecordCount: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kololo'), findsOneWidget);
      expect(find.text('Some records could not be shown'), findsOneWidget);
      expect(find.textContaining('2 records'), findsOneWidget);
      expect(find.byType(NyumbaStatusMessage), findsOneWidget);
    });
  });

  group('cached awaiting validation', () {
    testWidgets('shows data immediately and says it is being checked', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.cached(const [
              'Kololo',
            ], retrievedAt: readAt),
          ),
        ),
      );
      await tester.pump();

      // Data is visible on the first frame — that is the point of the cache.
      expect(find.text('Kololo'), findsOneWidget);
      // And it is honest that nothing has been proven yet.
      expect(find.text('Checking for updates…'), findsOneWidget);
    });
  });

  group('refresh failure over cached data', () {
    testWidgets('keeps the data, warns, and offers retry', (tester) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.stale(
              const ['Kololo'],
              retrievedAt: readAt,
              error: const CloudReadError.connection(),
            ),
            onRetry: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Visible data is not discarded because a refresh failed…
      expect(find.text('Kololo'), findsOneWidget);
      // …but it is never presented as current.
      expect(find.text('This may be out of date'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('never shows stale data without the warning', (tester) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.stale(
              const ['Kololo'],
              retrievedAt: readAt,
              error: const CloudReadError.connection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NyumbaStatusMessage), findsOneWidget);
    });
  });

  group('failures with nothing to show', () {
    testWidgets('a connection failure offers retry', (tester) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.failure(const CloudReadError.connection()),
            onRetry: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No connection to Nyumba'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets(
      'a permission denial is not a network message and has no retry',
      (tester) async {
        await tester.pumpWidget(
          host(
            viewOf(
              CloudData<List<String>>.failure(
                const CloudReadError.permissionDenied(),
              ),
              // Even when a caller offers one, retrying a refusal cannot help.
              onRetry: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('You do not have access to this'), findsOneWidget);
        expect(find.text('No connection to Nyumba'), findsNothing);
        expect(find.text('Try again'), findsNothing);
      },
    );

    testWidgets('a server rejection is distinct from both', (tester) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.failure(
              const CloudReadError.serverRejection(code: 'invalid-argument'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nyumba could not load this'), findsOneWidget);
    });
  });

  group('reconnecting', () {
    testWidgets('retains visible data rather than blanking the screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.reconnecting(
              value: const ['Kololo'],
              retrievedAt: readAt,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Kololo'), findsOneWidget);
      expect(find.text('Reconnecting…'), findsOneWidget);
    });
  });

  group('localization and direction', () {
    testWidgets('lays out right-to-left in Arabic', (tester) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.stale(
              const ['Kololo'],
              retrievedAt: readAt,
              error: const CloudReadError.connection(),
            ),
            onRetry: () async {},
          ),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.text('Kololo'))),
        TextDirection.rtl,
      );
      expect(find.text('قد تكون هذه البيانات قديمة'), findsOneWidget);
    });

    testWidgets('renders Kiswahili copy', (tester) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.failure(const CloudReadError.connection()),
          ),
          locale: const Locale('sw'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hakuna muunganisho na Nyumba'), findsOneWidget);
    });

    testWidgets('partial-data warning follows Arabic RTL direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          viewOf(
            CloudData<List<String>>.live(
              const ['Kololo'],
              retrievedAt: readAt,
              discardedRecordCount: 1,
            ),
          ),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.text('تعذّر عرض بعض السجلات'))),
        TextDirection.rtl,
      );
    });
  });
}
