import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_dependencies.dart';
import '../../../app/theme/nyumba_colors.dart';
import '../../../core/offline/aggregate_sync_status.dart';
import '../../../core/offline/offline_entity.dart';
import '../../../core/offline/outbox_entry.dart';
import '../../../core/presentation/operational_actions.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/sync_state_badge.dart';
import '../../subscriptions/application/subscription_providers.dart';
import '../../subscriptions/domain/subscription_plan_draft.dart';
import 'widgets/admin_components.dart';

(Color, IconData) _tierVisual(BuildContext context, String tier) =>
    switch (tier) {
      'Starter' => (context.nyumba.sageDark, Icons.home_work_outlined),
      'Pro' => (context.nyumba.midnightNavy, Icons.rocket_launch_outlined),
      'Premium' => (
        context.nyumba.terracottaDark,
        Icons.workspace_premium_outlined,
      ),
      _ => (context.nyumba.navyDark, Icons.domain_outlined),
    };

class AdminSubscriptionsScreen extends ConsumerStatefulWidget {
  const AdminSubscriptionsScreen({super.key});

  @override
  ConsumerState<AdminSubscriptionsScreen> createState() =>
      _AdminSubscriptionsScreenState();
}

class _AdminSubscriptionsScreenState
    extends ConsumerState<AdminSubscriptionsScreen> {
  String _billingView = 'Monthly';

  @override
  Widget build(BuildContext context) {
    final plansValue = ref.watch(subscriptionPlansProvider);
    final outbox =
        ref.watch(outboxEntriesProvider).value ?? const <OutboxEntry>[];
    final plans = plansValue.value ?? const <SubscriptionPlanDraft>[];
    final subscriberTotal = plans.fold<int>(
      0,
      (total, plan) => total + plan.subscribers,
    );
    return AdminPage(
      title: 'Subscriptions',
      description:
          'Configure plan drafts and monitor recurring platform revenue.',
      secondaryAction: _BillingViewSelector(
        value: _billingView,
        onChanged: (value) => setState(() => _billingView = value),
      ),
      primaryAction: FilledButton.icon(
        onPressed: () => showNyumbaInfoDialog(
          context,
          title: 'Billing settings',
          message:
              'Plan drafts can be edited on this screen. Provider credentials, '
              'prices, tax calculation, and billing intervals remain '
              'server-owned and are not configured in this demo.',
          icon: Icons.settings_outlined,
        ),
        icon: const Icon(Icons.settings_outlined),
        label: const Text('Billing settings'),
      ),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: context.nyumba.goldTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.nyumba.goldBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.edit_note_rounded,
                color: context.nyumba.terracottaDark,
              ),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Subscriptions apply to landlords and property managers only; '
                  'tenant and prospective-client access is always free. Prices '
                  'and limits below are working drafts — edits are local to '
                  'this demo until final commercial terms are approved.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'Active subscriptions',
              value: '$subscriberTotal',
              caption: '89.6% of verified landlords',
              trend: '+7.9%',
              icon: Icons.workspace_premium_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Monthly recurring revenue',
              value: 'UGX 295M',
              caption: 'Draft plan rates applied',
              trend: '+12.7%',
              icon: Icons.account_balance_wallet_outlined,
              tone: context.nyumba.sageDark,
            ),
            AdminMetricCard(
              label: 'Trial conversions',
              value: '68.4%',
              caption: 'Last 30 days',
              trend: '+3.2%',
              icon: Icons.trending_up_rounded,
              tone: context.nyumba.terracottaDark,
            ),
            AdminMetricCard(
              label: 'Payment attention',
              value: '14',
              caption: '8 retrying • 6 past due',
              icon: Icons.warning_amber_rounded,
              tone: context.nyumba.danger,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Draft plan configuration',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const StatusBadge(label: '4 tiers', tone: BadgeTone.info),
          ],
        ),
        const SizedBox(height: 12),
        if (plansValue.isLoading && plans.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (plansValue.hasError && plans.isEmpty)
          NyumbaSurface(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load plan drafts: ${plansValue.error}'),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1180
                  ? 4
                  : constraints.maxWidth >= 650
                  ? 2
                  : 1;
              const spacing = 14.0;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final plan in plans)
                    SizedBox(
                      width: width,
                      child: _PlanCard(
                        plan: plan,
                        annual: _billingView == 'Annual',
                        syncStatus: resolveAggregateSyncStatus(
                          entityType: OfflineEntityType.subscriptionPlan,
                          entityId: plan.id,
                          outbox: outbox,
                          syncMetadata: plan.syncMetadata,
                        ),
                        onEdit: () => _editPlan(plan),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final mix = _RevenueMix(plans: plans);
            const health = _SubscriptionHealth();
            if (constraints.maxWidth < 960) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [mix, const SizedBox(height: 20), health],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: mix),
                const SizedBox(width: 20),
                const Expanded(flex: 5, child: health),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const _CommercialGuardrails(),
        const SizedBox(height: 20),
        const _RecentSubscriptionActivity(),
      ],
    );
  }

  Future<void> _editPlan(SubscriptionPlanDraft plan) async {
    final unitController = TextEditingController(text: '${plan.unitLimit}');
    final priceController = TextEditingController(
      text: '${plan.monthlyPriceMinor ~/ 100}',
    );
    var enabled = plan.enabled;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${plan.tier} draft'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: unitController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Manageable rental-space limit',
                    prefixIcon: Icon(Icons.apartment_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Illustrative monthly price (UGX)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Plan available'),
                  subtitle: const Text(
                    'Shown as selectable during subscription',
                  ),
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final limit = int.tryParse(unitController.text.trim());
                final price = int.tryParse(
                  priceController.text.replaceAll(',', '').trim(),
                );
                if (limit == null || limit < 1 || price == null || price < 0) {
                  showAdminMessage(
                    dialogContext,
                    'Enter a valid rental-space limit and monthly price.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save draft'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      try {
        await ref.read(updatePlanDraftProvider)(
          UpdatePlanDraftInput(
            planId: plan.id,
            unitLimit: int.parse(unitController.text.trim()),
            monthlyPriceMinor:
                int.parse(priceController.text.replaceAll(',', '').trim()) *
                100,
            enabled: enabled,
          ),
        );
        if (mounted) {
          showAdminMessage(
            context,
            '${plan.tier} draft saved locally and queued to sync.',
          );
        }
      } on Object catch (error) {
        if (mounted) {
          showAdminMessage(context, 'Could not save the draft: $error');
        }
      }
    }
    unitController.dispose();
    priceController.dispose();
  }
}

class _BillingViewSelector extends StatelessWidget {
  const _BillingViewSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.nyumba.surface,
        border: Border.all(color: context.nyumba.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in const ['Monthly', 'Annual'])
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: ChoiceChip(
                label: Text(item),
                selected: value == item,
                showCheckmark: false,
                onSelected: (_) => onChanged(item),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.annual,
    required this.syncStatus,
    required this.onEdit,
  });

  final SubscriptionPlanDraft plan;
  final bool annual;
  final AggregateSyncStatus syncStatus;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _tierVisual(context, plan.tier);
    final custom = plan.monthlyPriceMinor == 0;
    final monthlyWhole = plan.monthlyPriceMinor ~/ 100;
    final amount = annual ? (monthlyWhole * 10.2).round() : monthlyWhole;
    return NyumbaSurface(
      borderColor: plan.recommended
          ? context.nyumba.midnightNavy
          : context.nyumba.outline,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 310),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    plan.tier,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (plan.recommended)
                  const StatusBadge(label: 'Popular', tone: BadgeTone.info),
              ],
            ),
            const SizedBox(height: 17),
            const SizedBox(height: 5),
            Text(plan.tagline, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    custom ? 'Custom' : formatAdminUgx(amount),
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(color: color),
                  ),
                ),
                if (!custom)
                  Padding(
                    padding: const EdgeInsets.only(left: 5, bottom: 3),
                    child: Text(
                      annual ? '/year' : '/month',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            if (annual && !custom) ...[
              const SizedBox(height: 4),
              Text(
                'Illustrative 15% annual saving',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.nyumba.sageDark),
              ),
            ],
            const SizedBox(height: 18),
            _PlanFeature(
              icon: Icons.apartment_outlined,
              text: plan.tier == 'Enterprise'
                  ? 'Custom rental-space limit, ${plan.unitLimit}+'
                  : 'Up to ${plan.unitLimit} managed rental spaces',
            ),
            _PlanFeature(
              icon: Icons.manage_accounts_outlined,
              text: plan.staffLabel,
            ),
            _PlanFeature(
              icon: Icons.campaign_outlined,
              text: plan.listingsLabel,
            ),
            _PlanFeature(icon: Icons.support_agent_rounded, text: plan.support),
            const Spacer(),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${plan.subscribers} subscribers',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                SyncStateBadge(status: syncStatus),
                const SizedBox(width: 6),
                StatusBadge(
                  label: plan.enabled ? 'Available' : 'Hidden',
                  tone: plan.enabled ? BadgeTone.success : BadgeTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: 13),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit draft'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanFeature extends StatelessWidget {
  const _PlanFeature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.nyumba.mutedInk),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _RevenueMix extends StatelessWidget {
  const _RevenueMix({required this.plans});

  final List<SubscriptionPlanDraft> plans;

  @override
  Widget build(BuildContext context) {
    final total = plans.fold<int>(0, (sum, item) => sum + item.subscribers);
    return AdminPanel(
      title: 'Subscriber mix',
      subtitle: 'Share of active subscriptions by tier',
      child: total == 0
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No subscription data yet.'),
            )
          : Column(
              children: [
                for (var index = 0; index < plans.length; index++) ...[
                  AdminProgressRow(
                    label: plans[index].tier,
                    value: plans[index].subscribers / total,
                    trailing:
                        '${plans[index].subscribers} • ${(plans[index].subscribers / total * 100).round()}%',
                    color: _tierVisual(context, plans[index].tier).$1,
                  ),
                  if (index < plans.length - 1) const SizedBox(height: 18),
                ],
              ],
            ),
    );
  }
}

class _SubscriptionHealth extends StatelessWidget {
  const _SubscriptionHealth();

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Subscription health',
      subtitle: 'Renewals and trials requiring attention',
      child: Column(
        children: [
          _HealthLine(
            label: 'Renewing in 7 days',
            value: '83',
            icon: Icons.autorenew_rounded,
            color: context.nyumba.midnightNavy,
          ),
          Divider(height: 25),
          _HealthLine(
            label: 'Trials ending this week',
            value: '26',
            icon: Icons.hourglass_bottom_rounded,
            color: context.nyumba.terracottaDark,
          ),
          Divider(height: 25),
          _HealthLine(
            label: 'Payment retries queued',
            value: '8',
            icon: Icons.sync_problem_outlined,
            color: context.nyumba.danger,
          ),
          Divider(height: 25),
          _HealthLine(
            label: 'Cancelled this month',
            value: '11',
            icon: Icons.cancel_outlined,
            color: context.nyumba.mutedInk,
          ),
        ],
      ),
    );
  }
}

class _HealthLine extends StatelessWidget {
  const _HealthLine({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Commercial rules that hold across every tier; see
/// docs/architecture/subscription-tiers.md.
class _CommercialGuardrails extends StatelessWidget {
  const _CommercialGuardrails();

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Commercial guardrails',
      subtitle: 'These rules apply to every tier and cannot be paywalled',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GuardrailLine(
            icon: Icons.lock_open_rounded,
            text:
                'Security, tenant access, data export, offline reliability, '
                'and server-side audit logging are never paywalled. Higher '
                'tiers may add longer audit retention and advanced search.',
          ),
          Divider(height: 25),
          const _GuardrailLine(
            icon: Icons.cloud_done_outlined,
            text:
                'Rental-space limits and entitlements live in versioned server-owned '
                'configuration — never hard-coded in the app. Unknown or '
                'missing plans grant no entitlement.',
          ),
          Divider(height: 25),
          const _GuardrailLine(
            icon: Icons.trending_down_rounded,
            text:
                'Downgrades never delete rental spaces or block tenants: a grace '
                'period applies, read access is preserved, and only creating '
                'rental spaces or publishing new listings is held until the account '
                'is back within its limit.',
          ),
        ],
      ),
    );
  }
}

class _GuardrailLine extends StatelessWidget {
  const _GuardrailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _RecentSubscriptionActivity extends StatelessWidget {
  const _RecentSubscriptionActivity();

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Recent subscription activity',
      subtitle: 'Latest upgrades, renewals, and payment events',
      trailing: TextButton.icon(
        onPressed: () => showNyumbaInfoDialog(
          context,
          title: 'Subscription ledger',
          message:
              'Acacia Homes Ltd — upgraded to Premium — 12 min ago\n'
              'Kololo Property Co. — renewal recorded — 1 h ago\n'
              'Lakeview Estates — payment awaiting confirmation — 3 h ago',
          icon: Icons.receipt_long_outlined,
        ),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text('View ledger'),
      ),
      child: const Column(
        children: [
          _SubscriptionEvent(
            business: 'Acacia Homes Ltd',
            event: 'Upgraded Pro to Premium',
            amount: 'UGX 700,000',
            time: '12 min ago',
            tone: BadgeTone.success,
          ),
          Divider(height: 25),
          _SubscriptionEvent(
            business: 'Kololo Property Co.',
            event: 'Premium renewed',
            amount: 'UGX 700,000',
            time: '48 min ago',
            tone: BadgeTone.info,
          ),
          Divider(height: 25),
          _SubscriptionEvent(
            business: 'Coastline Lettings',
            event: 'Renewal payment retrying',
            amount: 'UGX 80,000',
            time: '2 hr ago',
            tone: BadgeTone.warning,
          ),
        ],
      ),
    );
  }
}

class _SubscriptionEvent extends StatelessWidget {
  const _SubscriptionEvent({
    required this.business,
    required this.event,
    required this.amount,
    required this.time,
    required this.tone,
  });

  final String business;
  final String event;
  final String amount;
  final String time;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AdminAvatar(name: business),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(business, style: Theme.of(context).textTheme.labelLarge),
              Text(event, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(amount, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 3),
            StatusBadge(label: time, tone: tone),
          ],
        ),
      ],
    );
  }
}
