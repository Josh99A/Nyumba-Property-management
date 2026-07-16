import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/user_session.dart';
import '../../portfolio/domain/property.dart';
import '../../portfolio/domain/unit.dart';
import 'widgets/admin_components.dart';

class AdminOverviewScreen extends ConsumerStatefulWidget {
  const AdminOverviewScreen({super.key});

  @override
  ConsumerState<AdminOverviewScreen> createState() =>
      _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends ConsumerState<AdminOverviewScreen> {
  /// Counts the administrative scope actually pulled from the server.
  ///
  /// Landlord and unit totals are real: an admin session mirrors every property
  /// and unit. Revenue and subscription totals need a server-side aggregation
  /// job that does not exist yet, so they are reported as unavailable rather
  /// than invented — a wrong number here is worse than no number.
  _AdminOverviewMetrics get _metrics {
    final properties =
        ref.watch(portfolioPropertiesProvider).value ?? const <Property>[];
    final units = ref.watch(portfolioUnitsProvider).value ?? const <Unit>[];
    return _AdminOverviewMetrics(
      landlords: properties.map((p) => p.landlordId).toSet().length,
      units: units.length,
      monthlyRevenue: null,
      activeSubscriptions: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    return AdminPage(
      // Nothing on this page is seeded any more: it shows real counts or says
      // plainly that a figure is unavailable.
      showsDemoData: false,
      title: 'Platform overview',
      description: 'Monitor adoption, approvals, and service health.',
      primaryAction: FilledButton.icon(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Refresh data'),
      ),
      children: [
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'Landlords with a portfolio',
              value: '${metrics.landlords}',
              caption: 'Owners of at least one property',
              icon: Icons.real_estate_agent_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Managed rental spaces',
              value: '${metrics.units}',
              caption: 'Across every landlord',
              icon: Icons.apartment_rounded,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'Subscription revenue',
              value: metrics.monthlyRevenue == null
                  ? '—'
                  : formatAdminUgx(metrics.monthlyRevenue!),
              caption: 'Needs server reporting',
              icon: Icons.payments_outlined,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Active subscriptions',
              value: metrics.activeSubscriptions == null
                  ? '—'
                  : '${metrics.activeSubscriptions}',
              caption: 'Needs server reporting',
              icon: Icons.workspace_premium_outlined,
              tone: context.nyumba.sageDark,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Consumer(
          builder: (context, ref, _) {
            final role = ref.watch(sessionControllerProvider)?.role;
            return _AccessOperationsPanel(role: role ?? AppRole.admin);
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            const insights = _PlatformInsights();
            const health = _SystemHealth();
            if (constraints.maxWidth < 980) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [insights, const SizedBox(height: 20), health],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(flex: 7, child: insights),
                const SizedBox(width: 20),
                const Expanded(flex: 4, child: health),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            const approvals = _ApprovalPanel();
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
                const Expanded(flex: 7, child: approvals),
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
    // The mirror refreshes itself from the server listeners; this only
    // acknowledges the tap.
    showAdminMessage(context, 'Platform data refreshed from the local cache.');
  }
}

class _AccessOperationsPanel extends StatelessWidget {
  const _AccessOperationsPanel({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = role == AppRole.superAdmin;
    return AdminPanel(
      title: 'Your access & operations',
      subtitle: 'Visible CRUD permissions for every platform resource',
      trailing: StatusBadge(
        label: isSuperAdmin ? 'Full site operations' : 'Almost all operations',
        tone: BadgeTone.success,
        icon: Icons.verified_user_outlined,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSuperAdmin
                    ? 'You can manage business data, platform configuration, '
                          'and privileged accounts. Audit history remains read-only.'
                    : 'You can operate across users, portfolios, billing, '
                          'maintenance, listings, and reports. Privileged '
                          'administrator accounts remain protected.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  StatusBadge(label: 'Create', tone: BadgeTone.success),
                  StatusBadge(label: 'Read', tone: BadgeTone.success),
                  StatusBadge(label: 'Update', tone: BadgeTone.success),
                  StatusBadge(label: 'Archive', tone: BadgeTone.success),
                ],
              ),
            ],
          );
          final action = FilledButton.icon(
            onPressed: () => context.go('/admin/access'),
            icon: const Icon(Icons.policy_outlined),
            label: const Text('View all operations'),
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, const SizedBox(height: 18), action],
            );
          }
          return Row(
            children: [
              Expanded(child: summary),
              const SizedBox(width: 24),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _PlatformInsights extends StatelessWidget {
  const _PlatformInsights();

  @override
  Widget build(BuildContext context) {
    return const AdminPanel(
      title: 'Platform growth',
      subtitle: 'New rental spaces and subscription revenue',
      child: AdminEmptyState(
        title: 'Reporting is not available yet',
        message:
            'Growth and revenue must be aggregated across every landlord by a '
            'server-side reporting job. Until that job exists there is no '
            'trustworthy number to draw here.',
        icon: Icons.query_stats_outlined,
      ),
    );
  }
}

class _SystemHealth extends StatelessWidget {
  const _SystemHealth();

  @override
  Widget build(BuildContext context) {
    return const AdminPanel(
      title: 'System health',
      subtitle: 'Service status',
      child: AdminEmptyState(
        title: 'Health checks are not wired up',
        message:
            'Service status has to come from real probes. Reporting everything '
            'as healthy without checking would hide an outage.',
        icon: Icons.monitor_heart_outlined,
      ),
    );
  }
}

class _ApprovalPanel extends StatelessWidget {
  const _ApprovalPanel();

  @override
  Widget build(BuildContext context) {
    return const AdminPanel(
      title: 'Landlord approvals',
      subtitle: 'Applications awaiting a decision',
      child: AdminEmptyState(
        title: 'Approvals are not available in the app yet',
        message:
            'Landlord accounts are server-owned and are not mirrored to this '
            'client, so the queue cannot be shown. Approve with '
            'scripts/approve-landlord.mjs until this is wired up.',
        icon: Icons.verified_user_outlined,
      ),
    );
  }
}

class _AdminActivityPanel extends StatelessWidget {
  const _AdminActivityPanel();

  @override
  Widget build(BuildContext context) {
    return const AdminPanel(
      title: 'Platform activity',
      subtitle: 'Recent security and billing events',
      child: AdminEmptyState(
        title: 'Activity feed is not available yet',
        message:
            'Platform events come from the server audit log, which this client '
            'does not mirror yet.',
        icon: Icons.history_toggle_off_outlined,
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
  });

  final int landlords;
  final int units;

  /// Null until a server-side reporting job exists. Platform-wide money must
  /// never be totalled on a client from a partial mirror.
  final int? monthlyRevenue;
  final int? activeSubscriptions;
}
