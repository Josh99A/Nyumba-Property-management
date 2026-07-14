import 'package:flutter/material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import 'widgets/admin_components.dart';

class AdminOverviewScreen extends StatefulWidget {
  const AdminOverviewScreen({super.key});

  @override
  State<AdminOverviewScreen> createState() => _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends State<AdminOverviewScreen> {
  String _period = 'This month';
  DateTime _lastRefreshed = DateTime(2026, 7, 13, 9, 42);
  final List<_LandlordApproval> _approvals = [..._seedApprovals];

  _AdminOverviewMetrics get _metrics => switch (_period) {
    'Today' => const _AdminOverviewMetrics(
      landlords: 1268,
      units: 18420,
      monthlyRevenue: 394000,
      activeSubscriptions: 1136,
      landlordTrend: '+4 today',
      unitTrend: '+18 today',
      revenueTrend: '+1.4%',
      subscriptionTrend: '+3 today',
    ),
    'This quarter' => const _AdminOverviewMetrics(
      landlords: 1268,
      units: 18420,
      monthlyRevenue: 1462000,
      activeSubscriptions: 1136,
      landlordTrend: '+14.2%',
      unitTrend: '+11.8%',
      revenueTrend: '+18.6%',
      subscriptionTrend: '+12.4%',
    ),
    _ => const _AdminOverviewMetrics(
      landlords: 1268,
      units: 18420,
      monthlyRevenue: 472000,
      activeSubscriptions: 1136,
      landlordTrend: '+8.4%',
      unitTrend: '+6.2%',
      revenueTrend: '+12.7%',
      subscriptionTrend: '+7.9%',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    return AdminPage(
      title: 'Platform overview',
      description: 'Monitor adoption, revenue, approvals, and service health.',
      secondaryAction: _PeriodSelector(
        value: _period,
        onChanged: (value) => setState(() => _period = value),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Refresh data'),
      ),
      children: [
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'Verified landlords',
              value: '${metrics.landlords}',
              caption: 'Across 31 districts',
              trend: metrics.landlordTrend,
              icon: Icons.real_estate_agent_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Managed units',
              value: '${metrics.units}',
              caption: '89.6% currently occupied',
              trend: metrics.unitTrend,
              icon: Icons.apartment_rounded,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'Subscription revenue',
              value: formatAdminUgx(metrics.monthlyRevenue),
              caption: _period == 'This quarter'
                  ? 'Quarter to date'
                  : 'Period total',
              trend: metrics.revenueTrend,
              icon: Icons.payments_outlined,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Active subscriptions',
              value: '${metrics.activeSubscriptions}',
              caption: '89.6% of verified landlords',
              trend: metrics.subscriptionTrend,
              icon: Icons.workspace_premium_outlined,
              tone: context.nyumba.sageDark,
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final insights = _PlatformInsights(period: _period);
            final health = _SystemHealth(lastRefreshed: _lastRefreshed);
            if (constraints.maxWidth < 980) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [insights, const SizedBox(height: 20), health],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: insights),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: health),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final approvals = _ApprovalPanel(
              approvals: _approvals,
              onApprove: _approve,
              onReview: _review,
            );
            const activity = _AdminActivityPanel();
            if (constraints.maxWidth < 980) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [approvals, const SizedBox(height: 20), activity],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: approvals),
                const SizedBox(width: 20),
                const Expanded(flex: 4, child: activity),
              ],
            );
          },
        ),
      ],
    );
  }

  void _refresh() {
    setState(() => _lastRefreshed = DateTime.now());
    showAdminMessage(context, 'Platform data refreshed from the local cache.');
  }

  Future<void> _approve(_LandlordApproval approval) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve landlord?'),
        content: Text(
          '${approval.name} will be able to activate a subscription and '
          'advertise available units.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.verified_rounded),
            label: const Text('Approve'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _approvals.remove(approval));
    showAdminMessage(context, '${approval.name} has been approved.');
  }

  Future<void> _review(_LandlordApproval approval) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Landlord verification'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AdminAvatar(name: approval.name, radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          approval.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          approval.email,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ReviewFact(label: 'Business', value: approval.business),
              _ReviewFact(label: 'District', value: approval.district),
              _ReviewFact(label: 'Submitted', value: approval.submitted),
              const SizedBox(height: 12),
              const StatusBadge(
                label: 'Identity checked',
                tone: BadgeTone.success,
                icon: Icons.check_rounded,
              ),
              const SizedBox(height: 8),
              const StatusBadge(
                label: 'Ownership documents ready',
                tone: BadgeTone.info,
                icon: Icons.description_outlined,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _approve(approval);
            },
            child: const Text('Approve landlord'),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Change reporting period',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'Today', child: Text('Today')),
        PopupMenuItem(value: 'This month', child: Text('This month')),
        PopupMenuItem(value: 'This quarter', child: Text('This quarter')),
      ],
      child: IgnorePointer(
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(value),
        ),
      ),
    );
  }
}

class _PlatformInsights extends StatelessWidget {
  const _PlatformInsights({required this.period});

  final String period;

  @override
  Widget build(BuildContext context) {
    final List<double> values = switch (period) {
      'Today' => const [18.0, 22, 28, 26, 36, 43, 47],
      'This quarter' => const [282.0, 318, 347, 366, 405, 441, 472],
      _ => const [72.0, 91, 83, 108, 119, 132, 147],
    };
    return AdminPanel(
      title: 'Platform growth',
      subtitle: 'New managed units and subscription revenue',
      trailing: const StatusBadge(
        label: 'Healthy growth',
        tone: BadgeTone.success,
        icon: Icons.trending_up_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 22,
            runSpacing: 10,
            children: [
              _Legend(color: context.nyumba.midnightNavy, label: 'New units'),
              _Legend(
                color: context.nyumba.terracottaGold,
                label: 'Revenue index',
              ),
            ],
          ),
          const SizedBox(height: 16),
          AdminBarChart(
            values: values,
            secondaryValues: values
                .map((value) => (value * .72).toDouble())
                .toList(),
            labels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
            height: 205,
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SystemHealth extends StatelessWidget {
  const _SystemHealth({required this.lastRefreshed});

  final DateTime lastRefreshed;

  @override
  Widget build(BuildContext context) {
    final minute = lastRefreshed.minute.toString().padLeft(2, '0');
    final timestamp = '${lastRefreshed.hour}:$minute';
    return AdminPanel(
      title: 'System health',
      subtitle: 'Last checked today at $timestamp',
      child: const Column(
        children: [
          _HealthRow(
            icon: Icons.cloud_done_outlined,
            title: 'Firebase services',
            detail: '99.99% availability',
            status: 'Operational',
            tone: BadgeTone.success,
          ),
          Divider(height: 25),
          _HealthRow(
            icon: Icons.sync_rounded,
            title: 'Offline sync queue',
            detail: '37 changes in progress',
            status: 'Normal',
            tone: BadgeTone.info,
          ),
          Divider(height: 25),
          _HealthRow(
            icon: Icons.notifications_active_outlined,
            title: 'Notifications',
            detail: '2 delayed deliveries',
            status: 'Watching',
            tone: BadgeTone.warning,
          ),
          Divider(height: 25),
          _HealthRow(
            icon: Icons.security_outlined,
            title: 'Authentication',
            detail: 'No elevated risk',
            status: 'Secure',
            tone: BadgeTone.success,
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.status,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String status;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.nyumba.navyTint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: context.nyumba.midnightNavy),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        StatusBadge(label: status, tone: tone),
      ],
    );
  }
}

class _ApprovalPanel extends StatelessWidget {
  const _ApprovalPanel({
    required this.approvals,
    required this.onApprove,
    required this.onReview,
  });

  final List<_LandlordApproval> approvals;
  final ValueChanged<_LandlordApproval> onApprove;
  final ValueChanged<_LandlordApproval> onReview;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Landlord approvals',
      subtitle: '${approvals.length} applications require a decision',
      trailing: StatusBadge(
        label: '${approvals.length} pending',
        tone: approvals.isEmpty ? BadgeTone.success : BadgeTone.warning,
      ),
      child: approvals.isEmpty
          ? const AdminEmptyState(
              title: 'Approval queue is clear',
              message: 'New landlord applications will appear here.',
              icon: Icons.verified_user_outlined,
            )
          : Column(
              children: [
                for (var index = 0; index < approvals.length; index++) ...[
                  _ApprovalRow(
                    approval: approvals[index],
                    onApprove: () => onApprove(approvals[index]),
                    onReview: () => onReview(approvals[index]),
                  ),
                  if (index < approvals.length - 1) const Divider(height: 25),
                ],
              ],
            ),
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({
    required this.approval,
    required this.onApprove,
    required this.onReview,
  });

  final _LandlordApproval approval;
  final VoidCallback onApprove;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final details = Row(
          children: [
            AdminAvatar(name: approval.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    approval.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${approval.business} • ${approval.district}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Submitted ${approval.submitted}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: onReview, child: const Text('Review')),
            FilledButton(onPressed: onApprove, child: const Text('Approve')),
          ],
        );
        if (constraints.maxWidth < 590) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              details,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: details),
            const SizedBox(width: 14),
            actions,
          ],
        );
      },
    );
  }
}

class _AdminActivityPanel extends StatelessWidget {
  const _AdminActivityPanel();

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Platform activity',
      subtitle: 'Recent security and billing events',
      child: Column(
        children: [
          _ActivityRow(
            icon: Icons.person_add_alt_1_outlined,
            color: context.nyumba.midnightNavy,
            title: '18 new users registered',
            detail: 'Landlords 6 • Tenants 12',
            time: '38 min ago',
          ),
          Divider(height: 25),
          _ActivityRow(
            icon: Icons.workspace_premium_outlined,
            color: context.nyumba.terracottaDark,
            title: '7 subscriptions upgraded',
            detail: 'Pro to Premium was most common',
            time: '2 hr ago',
          ),
          Divider(height: 25),
          _ActivityRow(
            icon: Icons.admin_panel_settings_outlined,
            color: context.nyumba.sageDark,
            title: 'Access review completed',
            detail: 'No anomalous admin sessions found',
            time: '4 hr ago',
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.time,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .11),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                time,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.nyumba.mutedInk,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewFact extends StatelessWidget {
  const _ReviewFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.labelLarge),
          ),
        ],
      ),
    );
  }
}

class _AdminOverviewMetrics {
  const _AdminOverviewMetrics({
    required this.landlords,
    required this.units,
    required this.monthlyRevenue,
    required this.activeSubscriptions,
    required this.landlordTrend,
    required this.unitTrend,
    required this.revenueTrend,
    required this.subscriptionTrend,
  });

  final int landlords;
  final int units;
  final int monthlyRevenue;
  final int activeSubscriptions;
  final String landlordTrend;
  final String unitTrend;
  final String revenueTrend;
  final String subscriptionTrend;
}

class _LandlordApproval {
  const _LandlordApproval({
    required this.name,
    required this.email,
    required this.business,
    required this.district,
    required this.submitted,
  });

  final String name;
  final String email;
  final String business;
  final String district;
  final String submitted;
}

const _seedApprovals = [
  _LandlordApproval(
    name: 'Grace Auma',
    email: 'grace@karurihomes.ug',
    business: 'Karuri Homes',
    district: 'Wakiso',
    submitted: 'today at 08:14',
  ),
  _LandlordApproval(
    name: 'David Opio',
    email: 'david@lakeviewlettings.ug',
    business: 'Lakeview Lettings',
    district: 'Gulu',
    submitted: 'yesterday at 16:40',
  ),
  _LandlordApproval(
    name: 'Amina Noor',
    email: 'amina@tuliahomes.ug',
    business: 'Tulia Homes',
    district: 'Mbarara',
    submitted: '11 Jul at 10:22',
  ),
];
