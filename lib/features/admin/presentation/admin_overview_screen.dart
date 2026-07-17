import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/user_session.dart';
import '../../portfolio/domain/property.dart';
import '../../portfolio/domain/unit.dart';
import '../application/admin_directory_providers.dart';
import '../domain/platform_account.dart';
import 'widgets/admin_components.dart';

class AdminOverviewScreen extends ConsumerWidget {
  const AdminOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(adminDirectorySourceProvider);
    final accountsValue = ref.watch(platformAccountsProvider);
    final accounts = accountsValue.value ?? const <PlatformAccount>[];
    final properties =
        ref.watch(portfolioPropertiesProvider).value ?? const <Property>[];
    final units = ref.watch(portfolioUnitsProvider).value ?? const <Unit>[];

    final live = source == AdminDirectorySource.live;
    final activeSubscriptions = accounts
        .where((a) => a.subscriptionStatus == PlatformSubscriptionStatus.active)
        .length;
    final pendingApprovals = accounts
        .where((a) => a.status == PlatformAccountStatus.pendingApproval)
        .toList(growable: false);

    return AdminPage(
      // Nothing on this page is seeded any more: it shows real counts or says
      // plainly that a figure is unavailable.
      showsDemoData: false,
      title: 'Platform overview',
      description: 'Monitor adoption, approvals, and service health.',
      children: [
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'Landlords with a portfolio',
              value: '${properties.map((p) => p.landlordId).toSet().length}',
              caption: 'Owners of at least one property',
              icon: Icons.real_estate_agent_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Managed rental spaces',
              value: '${units.length}',
              caption: 'Across every landlord',
              icon: Icons.apartment_rounded,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'Active subscriptions',
              value: live ? '$activeSubscriptions' : '—',
              caption: live
                  ? 'Payment-confirmed landlord workspaces'
                  : 'Needs a live admin session',
              icon: Icons.workspace_premium_outlined,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Pending approvals',
              value: live ? '${pendingApprovals.length}' : '—',
              caption: live
                  ? 'Landlord applications awaiting review'
                  : 'Needs a live admin session',
              icon: Icons.pending_actions_outlined,
              tone: context.nyumba.danger,
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
            final approvals = _ApprovalPanel(
              live: live,
              accountsValue: accountsValue,
              pending: pendingApprovals,
            );
            final activity = _AdminActivityPanel(live: live);
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
                Expanded(flex: 4, child: activity),
              ],
            );
          },
        ),
      ],
    );
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
              Text.localized(
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
            label: const Text.localized('View all operations'),
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

/// The real landlord approval queue, actioned through the audited
/// `landlord.approve` command from the Users screen.
class _ApprovalPanel extends StatelessWidget {
  const _ApprovalPanel({
    required this.live,
    required this.accountsValue,
    required this.pending,
  });

  final bool live;
  final AsyncValue<List<PlatformAccount>> accountsValue;
  final List<PlatformAccount> pending;

  @override
  Widget build(BuildContext context) {
    if (!live) {
      return const AdminPanel(
        title: 'Landlord approvals',
        subtitle: 'Applications awaiting a decision',
        child: AdminEmptyState(
          title: 'Approvals need a live admin session',
          message:
              'The approval queue reads server-owned landlord accounts, which '
              'a demo workspace does not hold.',
          icon: Icons.verified_user_outlined,
        ),
      );
    }
    return AdminPanel(
      title: 'Landlord approvals',
      subtitle: 'Applications awaiting a decision',
      trailing: TextButton.icon(
        onPressed: () => context.go('/admin/users'),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text.localized('Review in Users'),
      ),
      child: switch ((accountsValue, pending)) {
        (AsyncValue(isLoading: true, hasValue: false), _) => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        (AsyncValue(:final error?), _) when !accountsValue.hasValue => Padding(
          padding: const EdgeInsets.all(12),
          child: Text.localized('Could not load the approval queue: $error'),
        ),
        (_, []) => const Padding(
          padding: EdgeInsets.all(12),
          child: Text.localized(
            'No landlord applications are waiting right now.',
          ),
        ),
        _ => Column(
          children: [
            for (var index = 0; index < pending.length && index < 6; index++)
              Column(
                children: [
                  Row(
                    children: [
                      AdminAvatar(name: pending[index].displayName),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.localized(
                              pending[index].businessName == null
                                  ? pending[index].displayName
                                  : '${pending[index].displayName} · '
                                        '${pending[index].businessName}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text.localized(
                              '${pending[index].email.isEmpty ? 'No email' : pending[index].email}'
                              ' · joined ${pending[index].joinedLabel}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const StatusBadge(
                        label: 'Pending',
                        tone: BadgeTone.warning,
                      ),
                    ],
                  ),
                  if (index < pending.length - 1 && index < 5)
                    const Divider(height: 24),
                ],
              ),
          ],
        ),
      },
    );
  }
}

/// Live view of the server-owned audit log.
class _AdminActivityPanel extends ConsumerWidget {
  const _AdminActivityPanel({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!live) {
      return const AdminPanel(
        title: 'Platform activity',
        subtitle: 'Recent security and billing events',
        child: AdminEmptyState(
          title: 'Activity feed needs a live admin session',
          message:
              'Platform events come from the server audit log, which a demo '
              'workspace cannot read.',
          icon: Icons.history_toggle_off_outlined,
        ),
      );
    }
    final events = ref.watch(adminAuditEventsProvider);
    return AdminPanel(
      title: 'Platform activity',
      subtitle: 'Server audit log, newest first',
      child: switch (events) {
        AsyncValue(hasValue: true, :final value) when value!.isEmpty =>
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text.localized('No audited commands recorded yet.'),
          ),
        AsyncValue(hasValue: true, :final value) => Column(
          children: [
            for (var index = 0; index < value!.length && index < 6; index++)
              Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        value[index].outcome == 'rejected'
                            ? Icons.block_outlined
                            : Icons.verified_outlined,
                        size: 18,
                        color: value[index].outcome == 'rejected'
                            ? context.nyumba.danger
                            : context.nyumba.sageDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.localized(
                              value[index].action,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text.localized(
                              DateFormat(
                                'd MMM, HH:mm',
                              ).format(value[index].at.toLocal()),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (index < value.length - 1 && index < 5)
                    const Divider(height: 20),
                ],
              ),
          ],
        ),
        AsyncValue(:final error?) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text.localized('Could not read the audit log: $error'),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}
