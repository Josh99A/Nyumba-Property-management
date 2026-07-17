import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/config/market_config.dart';
import '../../../../core/presentation/motion.dart';
import '../../../../core/presentation/responsive.dart';
import '../../../../core/presentation/status_badge.dart';
import '../../../../core/presentation/surface.dart';
import '../../application/dashboard_snapshot.dart';
import 'dashboard_charts.dart';

final _ugx = NumberFormat.currency(
  locale: NyumbaMarket.currencyLocale,
  symbol: NyumbaMarket.currencySymbol,
  decimalDigits: 0,
);

String formatUgx(int amountMinor) => _ugx.format(amountMinor / 100);

String relativeTime(DateTime at) {
  final difference = DateTime.now().difference(at);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.tone,
    super.key,
    this.format = _defaultFormat,
  });

  final String label;
  final num value;
  final String Function(num value) format;
  final String caption;
  final IconData icon;
  final Color tone;

  static String _defaultFormat(num value) => value.round().toString();

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: .11),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tone, size: 23),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: AnimatedCount(
                        value: value,
                        format: format,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class OccupancyCard extends StatelessWidget {
  const OccupancyCard({required this.snapshot, super.key});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NyumbaSectionHeader(
            title: 'Occupancy',
            trailing: Icon(Icons.more_vert_rounded, size: 20),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 410;
              // The ring is a graphic, not text, so it keeps its size while the
              // card grows around it.
              final chart = OccupancyRing(
                rate: snapshot.occupancyRate,
                size: vertical ? 150 : 170,
              );
              final legend = _OccupancyLegend(snapshot: snapshot);
              if (vertical) {
                return Column(
                  children: [
                    Center(child: chart),
                    const SizedBox(height: 10),
                    legend,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 3, child: Center(child: chart)),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: legend),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Occupancy rate across all properties',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _OccupancyLegend extends StatelessWidget {
  const _OccupancyLegend({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 22,
      runSpacing: 12,
      direction: Axis.vertical,
      children: [
        _LegendItem(
          color: context.nyumba.sageGreen,
          label: 'Occupied',
          value: '${snapshot.occupiedUnits} rental spaces',
          valueColor: context.nyumba.sageDark,
        ),
        _LegendItem(
          color: context.nyumba.divider,
          label: 'Vacant',
          value:
              '${snapshot.totalUnits - snapshot.occupiedUnits} rental spaces',
          valueColor: context.nyumba.mutedInk,
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final Color color;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class RentCollectionCard extends StatelessWidget {
  const RentCollectionCard({required this.snapshot, super.key});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NyumbaSectionHeader(
            title: 'Rent collection',
            subtitle: 'This month',
            trailing: Icon(Icons.more_vert_rounded, size: 20),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _AmountSummary(
                label: 'Collected',
                amount: formatUgx(snapshot.rentCollectedMinor),
                color: context.nyumba.sageDark,
              ),
              _AmountSummary(
                label: 'Outstanding',
                amount: formatUgx(snapshot.rentOutstandingMinor),
                color: context.nyumba.terracottaDark,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 18,
            runSpacing: 6,
            children: [
              _LineLegend(color: context.nyumba.sageDark, label: 'Collected'),
              _LineLegend(
                color: context.nyumba.terracottaGold,
                label: 'Outstanding',
                dashed: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 150,
            child: RentTrendChart(
              collected: snapshot.collectionTrend,
              outstanding: snapshot.outstandingTrend,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountSummary extends StatelessWidget {
  const _AmountSummary({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
        ),
        const SizedBox(height: 3),
        Text(
          amount,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LineLegend extends StatelessWidget {
  const _LineLegend({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          child: Row(
            children: dashed
                ? [
                    Expanded(child: Container(height: 2, color: color)),
                    const SizedBox(width: 3),
                    Expanded(child: Container(height: 2, color: color)),
                  ]
                : [Expanded(child: Container(height: 2, color: color))],
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class RecentPaymentsCard extends StatelessWidget {
  const RecentPaymentsCard({
    required this.payments,
    required this.onViewAll,
    super.key,
  });

  final List<RecentPayment> payments;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 12, 12),
            child: NyumbaSectionHeader(
              title: 'Recent payments',
              trailing: TextButton(
                onPressed: onViewAll,
                child: const Text('View all'),
              ),
            ),
          ),
          const Divider(),
          if (context.isCompact)
            for (final payment in payments) _PaymentListRow(payment: payment)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 720),
                child: DataTable(
                  headingRowHeight: 42,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 60,
                  horizontalMargin: 20,
                  columnSpacing: 30,
                  columns: const [
                    DataColumn(label: Text('Tenant')),
                    DataColumn(label: Text('Rental space')),
                    DataColumn(label: Text('Property')),
                    DataColumn(label: Text('Amount')),
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: payments
                      .map(
                        (payment) => DataRow(
                          cells: [
                            DataCell(Text(payment.tenant)),
                            DataCell(Text(payment.unit)),
                            DataCell(Text(payment.property)),
                            DataCell(Text(formatUgx(payment.amountMinor))),
                            DataCell(
                              Text(DateFormat('d MMM y').format(payment.date)),
                            ),
                            DataCell(_PaymentBadge(state: payment.state)),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 10, 10),
              child: TextButton.icon(
                onPressed: onViewAll,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('View all payments'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentListRow extends StatelessWidget {
  const _PaymentListRow({required this.payment});

  final RecentPayment payment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.nyumba.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.nyumba.sageTint,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 19,
              color: context.nyumba.sageDark,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.tenant,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${payment.unit} · ${payment.property}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatUgx(payment.amountMinor),
                  style: Theme.of(context).textTheme.labelLarge,
                  textAlign: TextAlign.end,
                ),
                const SizedBox(height: 3),
                Text(
                  DateFormat('d MMM').format(payment.date),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.state});

  final PaymentState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      PaymentState.paid => const StatusBadge(
        label: 'Paid',
        tone: BadgeTone.success,
      ),
      PaymentState.pending => const StatusBadge(
        label: 'Pending',
        tone: BadgeTone.warning,
      ),
      PaymentState.overdue => const StatusBadge(
        label: 'Overdue',
        tone: BadgeTone.danger,
      ),
    };
  }
}

class MaintenanceCard extends StatelessWidget {
  const MaintenanceCard({
    required this.items,
    required this.onViewAll,
    super.key,
  });

  final List<MaintenanceSummary> items;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 12, 6),
            child: NyumbaSectionHeader(
              title: 'Maintenance',
              trailing: TextButton(
                onPressed: onViewAll,
                child: const Text('View all'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 2, 20, 12),
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const StatusBadge(label: 'Urgent (3)', tone: BadgeTone.info),
                Text(
                  'Open (3)',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: context.nyumba.midnightNavy,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          for (final item in items) _MaintenanceRow(item: item),
        ],
      ),
    );
  }
}

class _MaintenanceRow extends StatelessWidget {
  const _MaintenanceRow({required this.item});

  final MaintenanceSummary item;

  @override
  Widget build(BuildContext context) {
    final urgent = item.priority == MaintenancePriority.urgent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.nyumba.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: urgent ? context.nyumba.danger : context.nyumba.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${item.unit} · ${item.property}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Reported ${relativeTime(item.reportedAt)} by ${item.reportedBy}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: StatusBadge(
              label: urgent ? 'Urgent' : 'High',
              tone: urgent ? BadgeTone.danger : BadgeTone.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({required this.activity, super.key});

  final List<ActivitySummary> activity;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(18, 18, 18, 12),
            child: NyumbaSectionHeader(title: 'Recent activity'),
          ),
          for (final item in activity)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.nyumba.divider),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: item.tone.withValues(alpha: .1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(item.icon, color: item.tone, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.detail,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            relativeTime(item.at),
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Activity history'),
                  content: SizedBox(
                    width: 480,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: activity.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final item = activity[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(item.icon, color: item.tone),
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.detail}\n${relativeTime(item.at)}',
                          ),
                        );
                      },
                    ),
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 17),
              label: const Text('View all activity'),
            ),
          ),
        ],
      ),
    );
  }
}
