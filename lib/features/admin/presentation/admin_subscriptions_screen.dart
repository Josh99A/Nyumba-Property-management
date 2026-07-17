import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../subscriptions/application/subscription_providers.dart';
import '../../subscriptions/domain/subscription_plan_draft.dart';
import '../application/admin_directory_providers.dart';
import '../domain/platform_account.dart';
import 'widgets/admin_components.dart';

(Color, IconData) _tierVisual(BuildContext context, String tier) =>
    switch (tier.toLowerCase()) {
      'starter' => (context.nyumba.sageDark, Icons.home_work_outlined),
      'pro' => (context.nyumba.midnightNavy, Icons.rocket_launch_outlined),
      'premium' => (
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
  @override
  Widget build(BuildContext context) {
    final source = ref.watch(adminDirectorySourceProvider);
    return switch (source) {
      AdminDirectorySource.live => _buildLive(context),
      AdminDirectorySource.demo => _buildDemo(context),
      AdminDirectorySource.unavailable => const AdminPage(
        showsDemoData: false,
        title: 'Subscriptions',
        description: 'Monitor landlord subscriptions and confirm payments.',
        children: [
          NyumbaSurface(
            child: AdminEmptyState(
              title: 'Subscription data is unavailable',
              message:
                  'Subscription records are server-owned and need a '
                  'configured Firebase project and an administrator session.',
              icon: Icons.cloud_off_outlined,
            ),
          ),
        ],
      ),
    };
  }

  // ---------------------------------------------------------------------
  // Live: real server-owned subscription documents and audited actions.
  // ---------------------------------------------------------------------

  Widget _buildLive(BuildContext context) {
    final accountsValue = ref.watch(platformAccountsProvider);
    final accounts = accountsValue.value ?? const <PlatformAccount>[];
    final withSubscription = accounts
        .where((a) => a.subscriptionStatus != PlatformSubscriptionStatus.none)
        .toList(growable: false);

    int countOf(Set<PlatformSubscriptionStatus> statuses) => withSubscription
        .where((a) => statuses.contains(a.subscriptionStatus))
        .length;

    final active = countOf(const {PlatformSubscriptionStatus.active});
    final awaiting = countOf(const {
      PlatformSubscriptionStatus.pendingPayment,
      PlatformSubscriptionStatus.trialing,
    });
    final pastDue = countOf(const {PlatformSubscriptionStatus.pastDue});
    final ended = countOf(const {
      PlatformSubscriptionStatus.canceled,
      PlatformSubscriptionStatus.expired,
    });

    final needsConfirmation = withSubscription
        .where(
          (a) => const {
            PlatformSubscriptionStatus.pendingPayment,
            PlatformSubscriptionStatus.trialing,
            PlatformSubscriptionStatus.pastDue,
          }.contains(a.subscriptionStatus),
        )
        .toList(growable: false);

    return AdminPage(
      showsDemoData: false,
      title: 'Subscriptions',
      description:
          'Live server-owned subscription records. Activation is an audited '
          'staff action against a payment reference.',
      children: [
        if (accountsValue.isLoading && accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (accountsValue.hasError && accounts.isEmpty)
          NyumbaSurface(
            child: AdminEmptyState(
              title: 'Could not load subscriptions',
              message:
                  'The server directory could not be read: '
                  '${accountsValue.error}.',
              icon: Icons.error_outline_rounded,
            ),
          )
        else ...[
          AdminMetricGrid(
            children: [
              AdminMetricCard(
                label: 'Active subscriptions',
                value: '$active',
                caption: 'Payment confirmed and workspace open',
                icon: Icons.workspace_premium_outlined,
                tone: context.nyumba.sageDark,
              ),
              AdminMetricCard(
                label: 'Awaiting payment',
                value: '$awaiting',
                caption: 'Confirm below once money is verified',
                icon: Icons.hourglass_bottom_rounded,
                tone: context.nyumba.terracottaDark,
              ),
              AdminMetricCard(
                label: 'Past due',
                value: '$pastDue',
                caption: 'Renewal payment outstanding',
                icon: Icons.warning_amber_rounded,
                tone: context.nyumba.danger,
              ),
              AdminMetricCard(
                label: 'Canceled or expired',
                value: '$ended',
                caption: 'Read access preserved, no new capacity',
                icon: Icons.cancel_outlined,
                tone: context.nyumba.midnightNavy,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _PendingPaymentsPanel(
            accounts: needsConfirmation,
            onConfirm: _confirmPayment,
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final mix = _LiveTierMix(accounts: withSubscription);
              const catalog = _ServerCatalogPanel();
              if (constraints.maxWidth < 960) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [mix, const SizedBox(height: 20), catalog],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: mix),
                  const SizedBox(width: 20),
                  const Expanded(flex: 6, child: catalog),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _SubscriptionActivityPanel(
            events: ref.watch(adminAuditEventsProvider),
          ),
        ],
        const SizedBox(height: 20),
        const _CommercialGuardrails(),
      ],
    );
  }

  Future<void> _confirmPayment(PlatformAccount account) async {
    final referenceController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Confirm payment for ${account.displayName}?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This activates the ${account.subscriptionTier ?? 'selected'} '
                'plan and opens the landlord workspace. Only confirm against '
                'money you have actually verified.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(
                  labelText: 'Payment reference (required)',
                  hintText: 'Provider transaction ID or manual reference',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (referenceController.text.trim().isEmpty) {
                showAdminMessage(
                  dialogContext,
                  'A payment reference is required for the audit trail.',
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Confirm payment'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ref
            .read(adminAccountCommandsProvider)
            .confirmSubscriptionPayment(
              account: account,
              reference: referenceController.text,
            );
        if (mounted) {
          showAdminMessage(
            context,
            'Subscription for ${account.displayName} activated.',
          );
        }
      } on Object catch (error) {
        if (mounted) {
          showAdminMessage(
            context,
            'The server rejected the confirmation: $error',
          );
        }
      }
    }
    referenceController.dispose();
  }

  // ---------------------------------------------------------------------
  // Demo: seeded local plan drafts, clearly labelled as such.
  // ---------------------------------------------------------------------

  Widget _buildDemo(BuildContext context) {
    final plansValue = ref.watch(subscriptionPlansProvider);
    final plans = plansValue.value ?? const <SubscriptionPlanDraft>[];
    final subscriberTotal = plans.fold<int>(
      0,
      (total, plan) => total + plan.subscribers,
    );
    final draftMrrMinor = plans.fold<int>(
      0,
      (total, plan) => total + plan.monthlyPriceMinor * plan.subscribers,
    );

    return AdminPage(
      title: 'Subscriptions',
      description: 'Configure local plan drafts for the demo workspace.',
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
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'Subscriptions apply to landlords and property managers '
                  'only; tenant and prospective-client access is always free. '
                  'Everything below is seeded demo working state — real '
                  'prices, entitlements, and subscriber counts are '
                  'server-owned.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AdminMetricGrid(
          children: [
            AdminMetricCard(
              label: 'Seeded subscribers',
              value: '$subscriberTotal',
              caption: 'Sum of the demo plan fixtures',
              icon: Icons.workspace_premium_outlined,
              tone: context.nyumba.midnightNavy,
            ),
            AdminMetricCard(
              label: 'Draft monthly revenue',
              value: formatAdminUgx(draftMrrMinor ~/ 100),
              caption: 'Draft prices × seeded subscribers',
              icon: Icons.account_balance_wallet_outlined,
              tone: context.nyumba.sageDark,
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
            StatusBadge(label: '${plans.length} tiers', tone: BadgeTone.info),
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
                        onEdit: () => _editPlan(plan),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 20),
        _DemoTierMix(plans: plans),
        const SizedBox(height: 20),
        const _CommercialGuardrails(),
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
          showAdminMessage(context, '${plan.tier} draft saved on this device.');
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

/// Subscriptions the staff can act on, with the audited confirm-payment flow.
class _PendingPaymentsPanel extends StatelessWidget {
  const _PendingPaymentsPanel({
    required this.accounts,
    required this.onConfirm,
  });

  final List<PlatformAccount> accounts;
  final ValueChanged<PlatformAccount> onConfirm;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      title: 'Awaiting payment confirmation',
      subtitle:
          'Activation requires a verified payment reference and is recorded '
          'in the audit log',
      child: accounts.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No subscriptions are waiting on a payment.'),
            )
          : Column(
              children: [
                for (var index = 0; index < accounts.length; index++) ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final account = accounts[index];
                      final identity = Row(
                        children: [
                          AdminAvatar(name: account.displayName),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account.displayName,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                Text(
                                  '${account.subscriptionTier ?? 'No tier selected'}'
                                  ' · ${account.subscriptionStatus.label}'
                                  '${account.email.isEmpty ? '' : ' · ${account.email}'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      final action = FilledButton.icon(
                        onPressed: () => onConfirm(account),
                        icon: const Icon(Icons.price_check_rounded, size: 18),
                        label: const Text('Confirm payment'),
                      );
                      if (constraints.maxWidth < 560) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            identity,
                            const SizedBox(height: 10),
                            action,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 16),
                          action,
                        ],
                      );
                    },
                  ),
                  if (index < accounts.length - 1) const Divider(height: 26),
                ],
              ],
            ),
    );
  }
}

class _LiveTierMix extends StatelessWidget {
  const _LiveTierMix({required this.accounts});

  final List<PlatformAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final activeByTier = <String, int>{};
    for (final account in accounts) {
      if (account.subscriptionStatus != PlatformSubscriptionStatus.active) {
        continue;
      }
      final tier = account.subscriptionTier ?? 'unknown';
      activeByTier[tier] = (activeByTier[tier] ?? 0) + 1;
    }
    final total = activeByTier.values.fold<int>(0, (a, b) => a + b);
    final tiers = activeByTier.keys.toList()..sort();
    return AdminPanel(
      title: 'Active subscriptions by tier',
      subtitle: 'Counted from the live subscription documents',
      child: total == 0
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No active subscriptions yet.'),
            )
          : Column(
              children: [
                for (var index = 0; index < tiers.length; index++) ...[
                  AdminProgressRow(
                    label: tiers[index],
                    value: activeByTier[tiers[index]]! / total,
                    trailing:
                        '${activeByTier[tiers[index]]} · '
                        '${(activeByTier[tiers[index]]! / total * 100).round()}%',
                    color: _tierVisual(context, tiers[index]).$1,
                  ),
                  if (index < tiers.length - 1) const SizedBox(height: 18),
                ],
              ],
            ),
    );
  }
}

/// The public server-owned plan catalog — the entitlements landlords actually
/// get. Prices are deliberately absent until commercial terms are final.
class _ServerCatalogPanel extends ConsumerWidget {
  const _ServerCatalogPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(publicPlanCatalogProvider);
    return AdminPanel(
      title: 'Server plan catalog',
      subtitle: 'planCatalog documents — server-owned, read-only here',
      child: switch (catalog) {
        AsyncValue(hasValue: true, :final value) when value!.isEmpty =>
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No public catalog entries are published yet. Entitlements '
              'fail closed until the catalog is seeded.',
            ),
          ),
        AsyncValue(hasValue: true, :final value) => Column(
          children: [
            for (final (index, plan) in value!.values.indexed) ...[
              Row(
                children: [
                  Icon(
                    _tierVisual(context, plan.tier).$2,
                    size: 20,
                    color: _tierVisual(context, plan.tier).$1,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.displayName,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          plan.capacityLabel ??
                              'Up to ${plan.unitLimit} rental spaces · '
                                  '${plan.activeListingLimit} active listings',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const StatusBadge(label: 'Public', tone: BadgeTone.info),
                ],
              ),
              if (index < value.length - 1) const Divider(height: 24),
            ],
          ],
        ),
        AsyncValue(:final error?) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Could not read the plan catalog: $error'),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}

/// Billing events from the server audit log, filtered to subscription
/// commands. Empty is the honest state until staff actions or webhooks occur.
class _SubscriptionActivityPanel extends StatelessWidget {
  const _SubscriptionActivityPanel({required this.events});

  final AsyncValue<List<AdminAuditEvent>> events;

  @override
  Widget build(BuildContext context) {
    final subscriptionEvents =
        events.value
            ?.where((event) => event.action.startsWith('subscription.'))
            .toList(growable: false) ??
        const <AdminAuditEvent>[];
    return AdminPanel(
      title: 'Recent subscription activity',
      subtitle: 'From the server audit log',
      child: events.isLoading && !events.hasValue
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : subscriptionEvents.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No subscription commands in the recent audit log.'),
            )
          : Column(
              children: [
                for (
                  var index = 0;
                  index < subscriptionEvents.length && index < 6;
                  index++
                ) ...[
                  Row(
                    children: [
                      Icon(
                        subscriptionEvents[index].outcome == 'rejected'
                            ? Icons.block_outlined
                            : Icons.price_check_rounded,
                        size: 18,
                        color: subscriptionEvents[index].outcome == 'rejected'
                            ? context.nyumba.danger
                            : context.nyumba.sageDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          subscriptionEvents[index].action,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      StatusBadge(
                        label: subscriptionEvents[index].outcome,
                        tone: subscriptionEvents[index].outcome == 'rejected'
                            ? BadgeTone.danger
                            : BadgeTone.success,
                      ),
                    ],
                  ),
                  if (index < subscriptionEvents.length - 1 && index < 5)
                    const Divider(height: 22),
                ],
              ],
            ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onEdit});

  final SubscriptionPlanDraft plan;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _tierVisual(context, plan.tier);
    final custom = plan.monthlyPriceMinor == 0;
    return NyumbaSurface(
      borderColor: plan.recommended
          ? context.nyumba.midnightNavy
          : context.nyumba.outline,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 290),
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
            const SizedBox(height: 12),
            Text(plan.tagline, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    custom
                        ? 'Custom'
                        : formatAdminUgx(plan.monthlyPriceMinor ~/ 100),
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(color: color),
                  ),
                ),
                if (!custom)
                  Padding(
                    padding: const EdgeInsets.only(left: 5, bottom: 3),
                    child: Text(
                      '/month (draft)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
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
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${plan.subscribers} seeded subscribers',
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

class _DemoTierMix extends StatelessWidget {
  const _DemoTierMix({required this.plans});

  final List<SubscriptionPlanDraft> plans;

  @override
  Widget build(BuildContext context) {
    final total = plans.fold<int>(0, (sum, item) => sum + item.subscribers);
    return AdminPanel(
      title: 'Seeded subscriber mix',
      subtitle: 'Share of the demo fixtures by tier',
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
