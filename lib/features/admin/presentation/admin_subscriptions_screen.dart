import 'package:flutter/material.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import 'widgets/admin_components.dart';

class AdminSubscriptionsScreen extends StatefulWidget {
  const AdminSubscriptionsScreen({super.key});

  @override
  State<AdminSubscriptionsScreen> createState() =>
      _AdminSubscriptionsScreenState();
}

class _AdminSubscriptionsScreenState extends State<AdminSubscriptionsScreen> {
  final List<_SubscriptionPlan> _plans = [..._seedPlans];
  String _billingView = 'Monthly';

  int get _subscriberTotal =>
      _plans.fold(0, (total, plan) => total + plan.subscribers);

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Subscriptions',
      description:
          'Configure plan drafts and monitor recurring platform revenue.',
      secondaryAction: _BillingViewSelector(
        value: _billingView,
        onChanged: (value) => setState(() => _billingView = value),
      ),
      primaryAction: FilledButton.icon(
        onPressed: _showBillingSettings,
        icon: const Icon(Icons.settings_outlined),
        label: const Text('Billing settings'),
      ),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: NyumbaColors.goldTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF0D5A7)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.edit_note_rounded, color: NyumbaColors.terracottaDark),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Plan prices and unit limits below are working drafts. '
                  'Edits are local to this demo until final commercial terms '
                  'are approved.',
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
              value: '$_subscriberTotal',
              caption: '89.6% of verified landlords',
              trend: '+7.9%',
              icon: Icons.workspace_premium_outlined,
              tone: NyumbaColors.midnightNavy,
            ),
            const AdminMetricCard(
              label: 'Monthly recurring revenue',
              value: 'KES 472,000',
              caption: 'Draft plan rates applied',
              trend: '+12.7%',
              icon: Icons.account_balance_wallet_outlined,
              tone: NyumbaColors.sageDark,
            ),
            const AdminMetricCard(
              label: 'Trial conversions',
              value: '68.4%',
              caption: 'Last 30 days',
              trend: '+3.2%',
              icon: Icons.trending_up_rounded,
              tone: NyumbaColors.terracottaDark,
            ),
            const AdminMetricCard(
              label: 'Payment attention',
              value: '14',
              caption: '8 retrying • 6 past due',
              icon: Icons.warning_amber_rounded,
              tone: NyumbaColors.danger,
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
                for (final plan in _plans)
                  SizedBox(
                    width: width,
                    child: _PlanCard(
                      plan: plan,
                      annual: _billingView == 'Annual',
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
            final mix = _RevenueMix(plans: _plans);
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
        const _RecentSubscriptionActivity(),
      ],
    );
  }

  Future<void> _editPlan(_SubscriptionPlan plan) async {
    final unitController = TextEditingController(text: '${plan.unitLimit}');
    final priceController = TextEditingController(text: '${plan.monthlyPrice}');
    var advertising = plan.advertising;
    var enabled = plan.enabled;
    final updated = await showDialog<_SubscriptionPlan>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${plan.name} draft'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: unitController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Manageable unit limit',
                    prefixIcon: Icon(Icons.apartment_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Illustrative monthly price (KES)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Public listing advertising'),
                  subtitle: const Text(
                    'Allow subscribed landlords to advertise',
                  ),
                  value: advertising,
                  onChanged: (value) =>
                      setDialogState(() => advertising = value),
                ),
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
                final price = int.tryParse(priceController.text.trim());
                if (limit == null || limit < 1 || price == null || price < 0) {
                  showAdminMessage(
                    dialogContext,
                    'Enter a valid unit limit and monthly price.',
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  plan.copyWith(
                    unitLimit: limit,
                    monthlyPrice: price,
                    advertising: advertising,
                    enabled: enabled,
                  ),
                );
              },
              child: const Text('Save draft'),
            ),
          ],
        ),
      ),
    );
    unitController.dispose();
    priceController.dispose();
    if (updated == null || !mounted) return;
    final index = _plans.indexOf(plan);
    if (index < 0) return;
    setState(() => _plans[index] = updated);
    showAdminMessage(context, '${plan.name} draft updated locally.');
  }

  Future<void> _showBillingSettings() {
    var retryFailedPayments = true;
    var trialReminders = true;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Billing settings'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: retryFailedPayments,
                  title: const Text('Automatic payment retries'),
                  subtitle: const Text('Retry failed renewals over seven days'),
                  onChanged: (value) =>
                      setDialogState(() => retryFailedPayments = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: trialReminders,
                  title: const Text('Trial expiry reminders'),
                  subtitle: const Text(
                    'Notify landlords three days before expiry',
                  ),
                  onChanged: (value) =>
                      setDialogState(() => trialReminders = value),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text('Billing receipt prefix'),
                  subtitle: Text('NYB-SUB-2026'),
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
                Navigator.pop(dialogContext);
                showAdminMessage(context, 'Billing preferences saved locally.');
              },
              child: const Text('Save settings'),
            ),
          ],
        ),
      ),
    );
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
        color: NyumbaColors.surface,
        border: Border.all(color: NyumbaColors.outline),
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
    required this.onEdit,
  });

  final _SubscriptionPlan plan;
  final bool annual;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final amount = annual
        ? (plan.monthlyPrice * 10.2).round()
        : plan.monthlyPrice;
    return NyumbaSurface(
      borderColor: plan.recommended
          ? NyumbaColors.midnightNavy
          : NyumbaColors.outline,
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
                    color: plan.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(plan.icon, color: plan.color),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    plan.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (plan.recommended)
                  const StatusBadge(label: 'Popular', tone: BadgeTone.info),
              ],
            ),
            const SizedBox(height: 17),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    plan.name == 'Enterprise'
                        ? 'Custom'
                        : formatAdminKes(amount),
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(color: plan.color),
                  ),
                ),
                if (plan.name != 'Enterprise')
                  Padding(
                    padding: const EdgeInsets.only(left: 5, bottom: 3),
                    child: Text(
                      annual ? '/year' : '/month',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            if (annual && plan.name != 'Enterprise') ...[
              const SizedBox(height: 4),
              Text(
                'Illustrative 15% annual saving',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: NyumbaColors.sageDark),
              ),
            ],
            const SizedBox(height: 18),
            _PlanFeature(
              icon: Icons.apartment_outlined,
              text: 'Up to ${plan.unitLimit} managed units',
            ),
            _PlanFeature(
              icon: plan.advertising
                  ? Icons.campaign_outlined
                  : Icons.hide_source_outlined,
              text: plan.advertising
                  ? 'Public listing advertising'
                  : 'Advertising not included',
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
          Icon(icon, size: 18, color: NyumbaColors.mutedInk),
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

  final List<_SubscriptionPlan> plans;

  @override
  Widget build(BuildContext context) {
    final total = plans.fold<int>(0, (sum, item) => sum + item.subscribers);
    return AdminPanel(
      title: 'Subscriber mix',
      subtitle: 'Share of active subscriptions by tier',
      child: Column(
        children: [
          for (var index = 0; index < plans.length; index++) ...[
            AdminProgressRow(
              label: plans[index].name,
              value: plans[index].subscribers / total,
              trailing:
                  '${plans[index].subscribers} • ${(plans[index].subscribers / total * 100).round()}%',
              color: plans[index].color,
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
    return const AdminPanel(
      title: 'Subscription health',
      subtitle: 'Renewals and trials requiring attention',
      child: Column(
        children: [
          _HealthLine(
            label: 'Renewing in 7 days',
            value: '83',
            icon: Icons.autorenew_rounded,
            color: NyumbaColors.midnightNavy,
          ),
          Divider(height: 25),
          _HealthLine(
            label: 'Trials ending this week',
            value: '26',
            icon: Icons.hourglass_bottom_rounded,
            color: NyumbaColors.terracottaDark,
          ),
          Divider(height: 25),
          _HealthLine(
            label: 'Payment retries queued',
            value: '8',
            icon: Icons.sync_problem_outlined,
            color: NyumbaColors.danger,
          ),
          Divider(height: 25),
          _HealthLine(
            label: 'Cancelled this month',
            value: '11',
            icon: Icons.cancel_outlined,
            color: NyumbaColors.mutedInk,
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

class _RecentSubscriptionActivity extends StatelessWidget {
  const _RecentSubscriptionActivity();

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Recent subscription activity',
      subtitle: 'Latest upgrades, renewals, and payment events',
      trailing: TextButton.icon(
        onPressed: () =>
            showAdminMessage(context, 'Subscription activity export prepared.'),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text('View ledger'),
      ),
      child: const Column(
        children: [
          _SubscriptionEvent(
            business: 'Acacia Homes Ltd',
            event: 'Upgraded Pro to Premium',
            amount: 'KES 7,500',
            time: '12 min ago',
            tone: BadgeTone.success,
          ),
          Divider(height: 25),
          _SubscriptionEvent(
            business: 'Kilimani Property Co.',
            event: 'Premium renewed',
            amount: 'KES 7,500',
            time: '48 min ago',
            tone: BadgeTone.info,
          ),
          Divider(height: 25),
          _SubscriptionEvent(
            business: 'Coastline Lettings',
            event: 'Renewal payment retrying',
            amount: 'KES 2,500',
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

class _SubscriptionPlan {
  const _SubscriptionPlan({
    required this.name,
    required this.monthlyPrice,
    required this.unitLimit,
    required this.subscribers,
    required this.advertising,
    required this.support,
    required this.color,
    required this.icon,
    this.recommended = false,
    this.enabled = true,
  });

  final String name;
  final int monthlyPrice;
  final int unitLimit;
  final int subscribers;
  final bool advertising;
  final String support;
  final Color color;
  final IconData icon;
  final bool recommended;
  final bool enabled;

  _SubscriptionPlan copyWith({
    int? monthlyPrice,
    int? unitLimit,
    bool? advertising,
    bool? enabled,
  }) {
    return _SubscriptionPlan(
      name: name,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      unitLimit: unitLimit ?? this.unitLimit,
      subscribers: subscribers,
      advertising: advertising ?? this.advertising,
      support: support,
      color: color,
      icon: icon,
      recommended: recommended,
      enabled: enabled ?? this.enabled,
    );
  }
}

const _seedPlans = [
  _SubscriptionPlan(
    name: 'Starter',
    monthlyPrice: 1200,
    unitLimit: 10,
    subscribers: 412,
    advertising: false,
    support: 'Standard email support',
    color: NyumbaColors.sageDark,
    icon: Icons.home_work_outlined,
  ),
  _SubscriptionPlan(
    name: 'Pro',
    monthlyPrice: 2500,
    unitLimit: 40,
    subscribers: 476,
    advertising: true,
    support: 'Priority email support',
    color: NyumbaColors.midnightNavy,
    icon: Icons.rocket_launch_outlined,
    recommended: true,
  ),
  _SubscriptionPlan(
    name: 'Premium',
    monthlyPrice: 7500,
    unitLimit: 150,
    subscribers: 204,
    advertising: true,
    support: 'Priority phone support',
    color: NyumbaColors.terracottaDark,
    icon: Icons.workspace_premium_outlined,
  ),
  _SubscriptionPlan(
    name: 'Enterprise',
    monthlyPrice: 0,
    unitLimit: 1000,
    subscribers: 44,
    advertising: true,
    support: 'Dedicated success manager',
    color: NyumbaColors.navyDark,
    icon: Icons.domain_outlined,
  ),
];
