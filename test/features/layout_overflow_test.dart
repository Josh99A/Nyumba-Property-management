/// Guards the shared cards against overflowing their box.
///
/// Every case renders on a phone, a tablet and a desktop, at text scales up to
/// 2.0, because that combination is what actually produces the yellow-and-black
/// overflow stripes: a narrow column plus a label long enough to wrap. A
/// `RenderFlex overflowed` error fails the surrounding test, so pumping each
/// widget is the assertion.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/app/theme/nyumba_colors.dart';
import 'package:nyumba_property_management/app/theme/nyumba_theme.dart';
import 'package:nyumba_property_management/core/presentation/metric_grid.dart';
import 'package:nyumba_property_management/features/admin/presentation/widgets/admin_components.dart';
import 'package:nyumba_property_management/features/dashboard/application/dashboard_snapshot.dart';
import 'package:nyumba_property_management/features/dashboard/presentation/widgets/dashboard_cards.dart';
import 'package:nyumba_property_management/features/finance/presentation/finance_screen.dart';
import 'package:nyumba_property_management/features/tenant_portal/presentation/widgets/tenant_components.dart';

final _now = DateTime(2026, 7, 15, 10);

final _snapshot = DashboardSnapshot(
  totalUnits: 24,
  occupiedUnits: 20,
  rentCollectedMinor: 2250000000,
  rentOutstandingMinor: 315000000,
  openRequests: 6,
  collectionTrend: const [.08, .24, .33, .47, .60, .66, .74, .78, .83, .84],
  outstandingTrend: const [
    .08,
    .09,
    .10,
    .11,
    .105,
    .112,
    .115,
    .116,
    .117,
    .1175,
  ],
  recentPayments: [
    RecentPayment(
      id: 'pay-1',
      tenant: 'Brian Okello',
      unit: 'B4',
      property: 'Sunset Apartments',
      amountMinor: 120000000,
      date: _now,
      state: PaymentState.paid,
    ),
  ],
  maintenance: [
    MaintenanceSummary(
      id: 'm-1',
      title: 'Leaking tap in kitchen',
      unit: 'A2',
      property: 'Greenview Court',
      reportedBy: 'Alice Namutebi',
      reportedAt: _now,
      priority: MaintenancePriority.urgent,
    ),
  ],
  activity: [
    ActivitySummary(
      icon: Icons.check_rounded,
      title: 'Rent received from Brian Okello',
      detail: 'Apartment B4 · Sunset Apartments',
      at: _now,
      tone: const Color(0xFF367248),
    ),
  ],
  lastSyncedAt: _now,
);

Future<void> _pump(
  WidgetTester tester,
  Widget Function(BuildContext) build,
  double scale,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: NyumbaTheme.light,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Builder(builder: build),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final cases = <String, Widget Function(BuildContext)>{
    'OccupancyCard': (_) => OccupancyCard(snapshot: _snapshot),
    'RentCollectionCard': (_) => RentCollectionCard(snapshot: _snapshot),
    'RecentPaymentsCard': (_) => RecentPaymentsCard(
      payments: _snapshot.recentPayments,
      onViewAll: () {},
    ),
    'MaintenanceCard': (_) =>
        MaintenanceCard(items: _snapshot.maintenance, onViewAll: () {}),
    'ActivityCard': (_) => ActivityCard(activity: _snapshot.activity),
    'FinanceSummary': (_) => const FinanceSummary(payments: [], tenancies: []),
    'AdminMetricGrid': (context) => AdminMetricGrid(
      children: [
        AdminMetricCard(
          label: 'Rent payment volume',
          value: 'UGX 22,500,000',
          caption: 'Across recorded tenant payments',
          trend: '+11.8%',
          icon: Icons.payments_outlined,
          tone: context.nyumba.sageDark,
        ),
        AdminMetricCard(
          label: 'New managed rental spaces',
          value: '18',
          caption: 'Added in the selected period',
          trend: '+6.2%',
          icon: Icons.apartment_outlined,
          tone: context.nyumba.midnightNavy,
        ),
      ],
    ),
    'TenantBalanceHero': (_) => TenantBalanceHero(
      amount: 120000000,
      dueLabel: 'Invoice NYB-INV-2608 • due 5 Aug 2026',
      onPay: () async {},
    ),
    'TenantQuickAction': (context) => TenantQuickAction(
      label: 'Report a problem',
      caption: 'Works while offline',
      icon: Icons.home_repair_service_outlined,
      color: context.nyumba.terracottaDark,
      onTap: () {},
    ),
    'TenantMetricCard': (context) => TenantMetricGrid(
      children: [
        TenantMetricCard(
          label: 'Next payment due',
          value: 'UGX 1,200,000',
          caption: 'Due in 21 days',
          icon: Icons.event_outlined,
          color: context.nyumba.midnightNavy,
        ),
        TenantMetricCard(
          label: 'Maintenance requests',
          value: '2',
          caption: 'One awaiting a landlord reply',
          icon: Icons.build_outlined,
          color: context.nyumba.terracottaDark,
        ),
      ],
    ),
    'TenantTimelineStep': (_) => const TenantTimelineStep(
      title: 'Request submitted while offline',
      detail: 'Queued on your device and waiting to sync',
      complete: true,
    ),
    'TenantInfoRow': (_) => const TenantInfoRow(
      icon: Icons.person_outline_rounded,
      label: 'Property manager',
      value: 'Nyumbani Gardens Management Company',
    ),
  };

  const sizes = {
    'phone': Size(393, 852),
    'tablet': Size(768, 1024),
    'desktop': Size(1280, 900),
  };

  for (final entry in cases.entries) {
    for (final size in sizes.entries) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        testWidgets('${entry.key} @ ${size.key} x$scale', (tester) async {
          await _pump(tester, entry.value, scale, size.value);
        });
      }
    }
  }

  testWidgets('finance summary still reads correctly once wrapped', (
    tester,
  ) async {
    await _pump(
      tester,
      (_) => const FinanceSummary(payments: [], tenancies: []),
      1,
      const Size(393, 852),
    );

    // The card that overflowed: its label and caption both wrap to two lines.
    expect(find.text('A month or more behind'), findsOneWidget);
    expect(find.text('0 tenants require follow-up'), findsOneWidget);
  });

  testWidgets('a metric row grows to fit its tallest card', (tester) async {
    await _pump(
      tester,
      (_) => MetricGrid(
        minRowHeight: 100,
        columnsForWidth: (_) => 2,
        children: [
          const SizedBox(key: ValueKey('short'), height: 20),
          Container(
            key: const ValueKey('tall'),
            height: 180,
            color: const Color(0xFF000000),
          ),
        ],
      ),
      1,
      const Size(393, 852),
    );

    expect(tester.getSize(find.byKey(const ValueKey('tall'))).height, 180);
    expect(
      tester.getSize(find.byKey(const ValueKey('short'))).height,
      tester.getSize(find.byKey(const ValueKey('tall'))).height,
    );
  });
}
