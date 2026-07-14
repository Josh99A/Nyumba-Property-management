import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/motion.dart';
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
              FadeSlideIn(
                delay: NyumbaMotion.stagger(4),
                child: LayoutBuilder(
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
              ),
              const SizedBox(height: 18),
              FadeSlideIn(
                delay: NyumbaMotion.stagger(6),
                child: const _SyncStatusBar(),
              ),
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
    final cards = [
      KpiCard(
        label: 'Total units',
        value: snapshot.totalUnits,
        caption: 'All properties',
        icon: Icons.apartment_outlined,
        tone: context.nyumba.midnightNavy,
      ),
      KpiCard(
        label: 'Occupied',
        value: snapshot.occupiedUnits,
        caption: '${(snapshot.occupancyRate * 100).round()}% occupancy',
        icon: Icons.person_outline_rounded,
        tone: context.nyumba.sageDark,
      ),
      KpiCard(
        label: 'Rent collected',
        value: snapshot.rentCollectedMinor,
        format: (value) => formatUgx(value.round()),
        caption: 'This month',
        icon: Icons.account_balance_wallet_outlined,
        tone: context.nyumba.terracottaDark,
      ),
      KpiCard(
        label: 'Open requests',
        value: snapshot.openRequests,
        caption: 'Require attention',
        icon: Icons.build_outlined,
        tone: context.nyumba.danger,
      ),
    ];
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
            for (final (index, card) in cards.indexed)
              FadeSlideIn(
                delay: NyumbaMotion.stagger(index),
                child: SizedBox(width: width, height: 132, child: card),
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

/// Sync summary derived from the durable outbox so pending work is never
/// reported as synced.
class _SyncStatusBar extends ConsumerWidget {
  const _SyncStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];
    final failed = outbox
        .where((entry) => entry.state == OutboxState.permanentlyFailed)
        .length;
    final pending = outbox.length - failed;
    final settled = pending == 0 && failed == 0;
    final message = failed > 0
        ? '$failed change${failed == 1 ? '' : 's'} failed to sync'
        : pending > 0
        ? '$pending change${pending == 1 ? '' : 's'} waiting to sync'
        : 'All changes synced';

    return NyumbaSurface(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      backgroundColor: failed > 0
          ? context.nyumba.dangerTint
          : settled
          ? context.nyumba.sageTint
          : context.nyumba.goldTint,
      borderColor: failed > 0
          ? context.nyumba.dangerBorder
          : settled
          ? context.nyumba.sageBorder
          : context.nyumba.goldBorder,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failed > 0
                ? Icons.error_outline_rounded
                : settled
                ? Icons.check_circle_outline_rounded
                : Icons.cloud_upload_outlined,
            size: 19,
            color: failed > 0
                ? context.nyumba.danger
                : settled
                ? context.nyumba.sageDark
                : context.nyumba.terracottaDark,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message))),
            child: const Text('Sync status'),
          ),
        ],
      ),
    );
  }
}
