import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/page_header.dart';
import '../../../core/presentation/responsive.dart';
import '../../../core/presentation/surface.dart';
import '../application/dashboard_snapshot.dart';
import 'widgets/dashboard_cards.dart';

class LandlordDashboardScreen extends ConsumerWidget {
  const LandlordDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        26,
        context.pageGutter,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Your portfolio at a glance',
                primaryAction: FilledButton.icon(
                  onPressed: () => context.go('/properties/new'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add property'),
                ),
              ),
              const SizedBox(height: 22),
              _KpiGrid(snapshot: snapshot),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final showActivityRail = constraints.maxWidth >= 1250;
                  final main = _DashboardMain(snapshot: snapshot);
                  if (!showActivityRail) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        main,
                        const SizedBox(height: 20),
                        ActivityCard(activity: snapshot.activity),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: main),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 270,
                        child: ActivityCard(activity: snapshot.activity),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              _SyncStatusBar(snapshot: snapshot),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 4 : 2;
        const spacing = 14.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: width,
              height: 132,
              child: KpiCard(
                label: 'Total units',
                value: '${snapshot.totalUnits}',
                caption: 'All properties',
                icon: Icons.apartment_outlined,
                tone: NyumbaColors.midnightNavy,
              ),
            ),
            SizedBox(
              width: width,
              height: 132,
              child: KpiCard(
                label: 'Occupied',
                value: '${snapshot.occupiedUnits}',
                caption: '${(snapshot.occupancyRate * 100).round()}% occupancy',
                icon: Icons.person_outline_rounded,
                tone: NyumbaColors.sageDark,
              ),
            ),
            SizedBox(
              width: width,
              height: 132,
              child: KpiCard(
                label: 'Rent collected',
                value: formatKes(snapshot.rentCollectedMinor),
                caption: 'This month',
                icon: Icons.account_balance_wallet_outlined,
                tone: NyumbaColors.terracottaDark,
              ),
            ),
            SizedBox(
              width: width,
              height: 132,
              child: KpiCard(
                label: 'Open requests',
                value: '${snapshot.openRequests}',
                caption: 'Require attention',
                icon: Icons.build_outlined,
                tone: NyumbaColors.danger,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardMain extends StatelessWidget {
  const _DashboardMain({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Column(
                children: [
                  SizedBox(
                    height: 346,
                    child: OccupancyCard(snapshot: snapshot),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 346,
                    child: RentCollectionCard(snapshot: snapshot),
                  ),
                ],
              );
            }
            return SizedBox(
              height: 330,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: OccupancyCard(snapshot: snapshot)),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 7,
                    child: RentCollectionCard(snapshot: snapshot),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final payments = RecentPaymentsCard(
              payments: snapshot.recentPayments,
              onViewAll: () => context.go('/finances'),
            );
            final maintenance = MaintenanceCard(
              items: snapshot.maintenance,
              onViewAll: () => context.go('/maintenance'),
            );
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [payments, const SizedBox(height: 20), maintenance],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: payments),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: maintenance),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SyncStatusBar extends StatelessWidget {
  const _SyncStatusBar({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final pending = snapshot.pendingChanges;
    return NyumbaSurface(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      backgroundColor: pending == 0
          ? NyumbaColors.sageTint
          : NyumbaColors.goldTint,
      borderColor: pending == 0
          ? const Color(0xFFCDE4D2)
          : const Color(0xFFF0D5A7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pending == 0
                ? Icons.check_circle_outline_rounded
                : Icons.cloud_upload_outlined,
            size: 19,
            color: pending == 0
                ? NyumbaColors.sageDark
                : NyumbaColors.terracottaDark,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              pending == 0
                  ? 'Synced just now'
                  : '$pending change${pending == 1 ? '' : 's'} waiting to sync',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Everything is up to date.')),
            ),
            child: const Text('Sync status'),
          ),
        ],
      ),
    );
  }
}
