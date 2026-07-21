import 'package:flutter/material.dart' hide Text, Tooltip;
import 'package:intl/intl.dart';

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/status_badge.dart';
import '../../../core/presentation/surface.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/user_session.dart';
import '../../subscriptions/application/subscription_providers.dart';
import '../application/admin_directory_providers.dart';
import '../domain/platform_account.dart';
import 'widgets/admin_components.dart';

final _catalogUgx = NumberFormat.currency(
  locale: 'en_UG',
  symbol: 'UGX ',
  decimalDigits: 0,
);

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
      AdminDirectorySource.unavailable => const AdminPage(
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

    // Landlord-requested upgrades on active subscriptions join the queue:
    // they too are waiting on a verified payment before anything changes.
    final needsConfirmation = withSubscription
        .where(
          (a) =>
              const {
                PlatformSubscriptionStatus.pendingPayment,
                PlatformSubscriptionStatus.trialing,
                PlatformSubscriptionStatus.pastDue,
              }.contains(a.subscriptionStatus) ||
              a.hasPendingUpgrade,
        )
        .toList(growable: false);

    return AdminPage(
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
        title: Text.localized('Confirm payment for ${account.displayName}?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.localized(
                account.hasPendingUpgrade
                    ? 'This applies the requested cash upgrade from '
                          '${account.subscriptionTier} to '
                          '${account.subscriptionRequestedTier} — the account '
                          'keeps its current plan until you confirm. Only '
                          'confirm against cash you have actually received.'
                    : 'This activates the '
                          '${account.subscriptionTier ?? 'selected'} '
                          'plan, approves the account if it is still pending '
                          'review, and opens the landlord workspace. Only '
                          'confirm against money you have actually verified.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: referenceController,
                decoration: InputDecoration(
                  labelText: context.tr('Payment reference (required)'),
                  hintText: context.tr(
                    'Provider transaction ID or manual reference',
                  ),
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text.localized('Cancel'),
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
            child: const Text.localized('Confirm payment'),
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
              // Pin the upgrade target explicitly so a request the landlord
              // changes mid-dialog cannot silently redirect the confirmation.
              tier: account.subscriptionRequestedTier,
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
              child: Text.localized(
                'No subscriptions are waiting on a payment.',
              ),
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
                                Text.localized(
                                  account.displayName,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                Text.localized(
                                  account.hasPendingUpgrade
                                      ? '${account.subscriptionTier} → '
                                            '${account.subscriptionRequestedTier}'
                                            ' cash upgrade'
                                            '${account.email.isEmpty ? '' : ' · ${account.email}'}'
                                      : '${account.subscriptionTier ?? 'No tier selected'}'
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
                        label: const Text.localized('Confirm payment'),
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
              child: Text.localized('No active subscriptions yet.'),
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
/// get. Super admins edit prices, limits, and feature availability through
/// the audited `plan.update` command; everyone else reads.
class _ServerCatalogPanel extends ConsumerWidget {
  const _ServerCatalogPanel();

  String? _priceLabel(PublicPlanFacts plan) {
    final monthly = plan.monthlyPriceMinor;
    if (monthly == null) return null;
    final parts = ['${_catalogUgx.format(monthly / 100)}/mo'];
    final yearly = plan.yearlyPriceMinor;
    if (yearly != null) {
      final savings = plan.yearlySavingsPercent;
      parts.add(
        '${_catalogUgx.format(yearly / 100)}/yr'
        '${savings == null ? '' : ' (save $savings%)'}',
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(publicPlanCatalogProvider);
    final isSuperAdmin =
        ref.watch(sessionControllerProvider)?.role == AppRole.superAdmin;
    return AdminPanel(
      title: 'Server plan catalog',
      subtitle: isSuperAdmin
          ? 'planCatalog documents — edits run the audited plan.update command'
          : 'planCatalog documents — server-owned, read-only for this role',
      child: switch (catalog) {
        AsyncValue(hasValue: true, :final value) when value!.isEmpty =>
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text.localized(
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
                        Text.localized(
                          plan.displayName,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text.localized(
                          plan.capacityLabel ??
                              'Up to ${plan.unitLimit} rental spaces · '
                                  '${plan.activeListingLimit} active listings',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_priceLabel(plan) case final price?)
                          Text(
                            price,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: context.nyumba.sageDark),
                          ),
                        if (plan.features.any((f) => !f.implemented))
                          Text.localized(
                            '${plan.features.where((f) => !f.implemented).length} '
                            'listed benefits still on the roadmap',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: context.nyumba.mutedInk),
                          ),
                      ],
                    ),
                  ),
                  const StatusBadge(label: 'Public', tone: BadgeTone.info),
                  if (isSuperAdmin) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: context.tr('Edit plan'),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => _PlanEditDialog(plan: plan),
                      ),
                    ),
                  ],
                ],
              ),
              if (index < value.length - 1) const Divider(height: 24),
            ],
          ],
        ),
        AsyncValue(:final error?) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text.localized('Could not read the plan catalog: $error'),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}

/// Super-admin plan editing. Prices are entered in whole UGX; feature
/// switches control the `implemented` flag the plan cards grey out on. Saving
/// sends only what changed through `plan.update` — the catalog stream then
/// re-renders every screen from the server's answer.
class _PlanEditDialog extends ConsumerStatefulWidget {
  const _PlanEditDialog({required this.plan});

  final PublicPlanFacts plan;

  @override
  ConsumerState<_PlanEditDialog> createState() => _PlanEditDialogState();
}

class _PlanEditDialogState extends ConsumerState<_PlanEditDialog> {
  late final TextEditingController _monthly;
  late final TextEditingController _yearly;
  late final TextEditingController _unitLimit;
  late final TextEditingController _listingLimit;
  late final Map<String, bool> _implemented;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    String money(int? minor) => minor == null ? '' : '${minor ~/ 100}';
    _monthly = TextEditingController(text: money(plan.monthlyPriceMinor));
    _yearly = TextEditingController(text: money(plan.yearlyPriceMinor));
    _unitLimit = TextEditingController(text: '${plan.unitLimit}');
    _listingLimit = TextEditingController(text: '${plan.activeListingLimit}');
    _implemented = {
      for (final feature in plan.features) feature.id: feature.implemented,
    };
  }

  @override
  void dispose() {
    _monthly.dispose();
    _yearly.dispose();
    _unitLimit.dispose();
    _listingLimit.dispose();
    super.dispose();
  }

  int? _minorOrNull(TextEditingController controller) {
    final digits = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    final major = int.tryParse(digits);
    // Unparseable input (empty, or absurdly long) means "no change".
    return major == null ? null : major * 100;
  }

  Future<void> _save() async {
    final plan = widget.plan;
    final monthly = _minorOrNull(_monthly);
    final yearly = _minorOrNull(_yearly);
    final unitLimit = int.tryParse(_unitLimit.text.trim());
    final listingLimit = int.tryParse(_listingLimit.text.trim());
    final featuresChanged = plan.features.any(
      (feature) => _implemented[feature.id] != feature.implemented,
    );
    setState(() => _busy = true);
    try {
      await ref.read(updatePlanCatalogProvider)(
        current: plan,
        monthlyPriceMinor:
            monthly != null && monthly != plan.monthlyPriceMinor
            ? monthly
            : null,
        yearlyPriceMinor: yearly != null && yearly != plan.yearlyPriceMinor
            ? yearly
            : null,
        unitLimit: unitLimit != null && unitLimit != plan.unitLimit
            ? unitLimit
            : null,
        activeListingLimit:
            listingLimit != null && listingLimit != plan.activeListingLimit
            ? listingLimit
            : null,
        features: featuresChanged
            ? [
                for (final feature in plan.features)
                  PublicPlanFeature(
                    id: feature.id,
                    label: feature.label,
                    implemented: _implemented[feature.id] ?? false,
                  ),
              ]
            : null,
      );
      if (mounted) {
        Navigator.pop(context);
        showAdminMessage(context, 'The ${plan.displayName} plan was updated.');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showAdminMessage(context, 'The server rejected the edit: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return AlertDialog(
      title: Text.localized('Edit the ${plan.displayName} plan'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.localized(
                'Changes apply to every screen that renders this plan and to '
                'the limits the backend enforces. Prices are whole UGX per '
                'billing period.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _monthly,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('Monthly price (UGX)'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _yearly,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('Yearly price (UGX)'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _unitLimit,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('Rental space limit'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _listingLimit,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('Active listing limit'),
                      ),
                    ),
                  ),
                ],
              ),
              if (plan.features.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text.localized(
                  'Benefits — switch on when a feature ships',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                for (final feature in plan.features)
                  SwitchListTile.adaptive(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text.localized(
                      feature.label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    value: _implemented[feature.id] ?? false,
                    onChanged: _busy
                        ? null
                        : (value) =>
                              setState(() => _implemented[feature.id] = value),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text.localized('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text.localized('Save changes'),
        ),
      ],
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
              child: Text.localized(
                'No subscription commands in the recent audit log.',
              ),
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
                        child: Text.localized(
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
          child: Text.localized(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
