import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// intl exports its own TextDirection class, which shadows the framework enum
// this file needs for the direction-aware chevron below.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/config/market_config.dart';
import '../../../core/localization/app_localizations_adapter.dart';
import '../../../core/localization/command_failure_localizations.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/localization/nyumba_localizations.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/offline/remote_sync_gateway.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/toast.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/auth_failure.dart';
import '../../auth/domain/user_session.dart';
import '../application/subscription_providers.dart';

final _ugx = NumberFormat.currency(
  locale: 'en_UG',
  symbol: 'UGX ',
  decimalDigits: 0,
);

final _renewalDate = DateFormat('d MMMM yyyy');

/// Pre-payment gate for landlord accounts. Lets the landlord pick the plan
/// they intend to pay for and shows live payment status; the workspace itself
/// unlocks only when the server-owned subscription turns `active`, which the
/// session controller watches and the router enforces.
class LandlordSubscriptionScreen extends ConsumerStatefulWidget {
  const LandlordSubscriptionScreen({super.key});

  @override
  ConsumerState<LandlordSubscriptionScreen> createState() =>
      _LandlordSubscriptionScreenState();
}

class _LandlordSubscriptionScreenState
    extends ConsumerState<LandlordSubscriptionScreen> {
  bool _isRefreshing = false;
  String? _selectingTier;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      await ref.read(sessionControllerProvider.notifier).refreshSession();
      if (!mounted) return;
      final session = ref.read(sessionControllerProvider);
      if (session?.hasConfirmedSubscription == true) {
        context.go('/dashboard');
        showNyumbaToast(
          appLocalizationsOf(context).subscriptionPaymentConfirmedWorkspace,
          variant: NyumbaToastVariant.success,
        );
      } else {
        showNyumbaToast(
          appLocalizationsOf(context).subscriptionPaymentNotConfirmed,
          variant: NyumbaToastVariant.info,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      showNyumbaToast(
        _describeFailure(context, error),
        variant: NyumbaToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  /// Records intent to pay for [tier] via `subscription.selectPlan`. The
  /// command itself carries no billing channel — only `requestUpgrade` (paid
  /// plan changes) does — so [channel] only shapes which toast plays: cash
  /// tells the landlord what to do next and that they'll hear back by email;
  /// electronic methods aren't wired up yet and say so.
  Future<void> _choosePlan(
    String tier,
    String planName,
    UpgradeBillingChannel channel,
  ) async {
    setState(() => _selectingTier = tier);
    final copy = appLocalizationsOf(context);
    try {
      await ref.read(selectSubscriptionPlanProvider)(tier);
      if (!mounted) return;
      showNyumbaToast(
        channel == UpgradeBillingChannel.cash
            ? copy.subscriptionPlanReservedCashToast(planName)
            : copy.subscriptionInitialElectronicComingSoon,
        variant: channel == UpgradeBillingChannel.cash
            ? NyumbaToastVariant.success
            : NyumbaToastVariant.info,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showNyumbaToast(
        _describeFailure(context, error),
        variant: NyumbaToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _selectingTier = null);
    }
  }

  /// Asks how the landlord intends to pay for [tier] before reserving it —
  /// the pre-payment counterpart to [_chooseUpgradeMethod]. Only cash does
  /// anything today; mobile money and card are offered so the option is
  /// visible, but activate nobody until an aggregator is wired up.
  Future<void> _chooseInitialPaymentMethod(String tier, String planName) async {
    final copy = appLocalizationsOf(context);
    final channel = await _pickBillingChannel(
      title: copy.subscriptionChooseInitialPaymentMethodTitle(planName),
      subtitle: copy.subscriptionChooseInitialPaymentMethodSubtitle,
    );
    if (channel == null || !mounted) return;
    await _choosePlan(tier, planName, channel);
  }

  /// Asks how the landlord will pay, then requests the upgrade on that
  /// channel. Cash goes to admin verification; mobile money and card are the
  /// electronic auto-upgrade path (fail-closed until an aggregator is live).
  Future<void> _chooseUpgradeMethod(String tier, String planName) async {
    final copy = appLocalizationsOf(context);
    final channel = await _pickBillingChannel(
      title: copy.subscriptionChoosePaymentMethodTitle(planName),
      subtitle: copy.subscriptionChoosePaymentMethodSubtitle,
    );
    if (channel == null || !mounted) return;
    await _requestUpgrade(tier, planName, channel);
  }

  /// The billing-channel bottom sheet shared by the pre-payment and upgrade
  /// flows — only its heading text differs between them.
  Future<UpgradeBillingChannel?> _pickBillingChannel({
    required String title,
    required String subtitle,
  }) {
    final copy = appLocalizationsOf(context);
    return showModalBottomSheet<UpgradeBillingChannel>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
              child: Text(
                title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                subtitle,
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: sheetContext.nyumba.mutedInk,
                ),
              ),
            ),
            _UpgradeMethodTile(
              icon: Icons.smartphone_rounded,
              title: copy.subscriptionPayMobileMoney,
              subtitle: copy.subscriptionPayMobileMoneySub,
              onTap: () => Navigator.pop(
                sheetContext,
                UpgradeBillingChannel.mobileMoney,
              ),
            ),
            _UpgradeMethodTile(
              icon: Icons.credit_card_rounded,
              title: copy.subscriptionPayCard,
              subtitle: copy.subscriptionPayCardSub,
              onTap: () =>
                  Navigator.pop(sheetContext, UpgradeBillingChannel.card),
            ),
            _UpgradeMethodTile(
              icon: Icons.payments_outlined,
              title: copy.subscriptionPayCash,
              subtitle: copy.subscriptionPayCashSub,
              onTap: () =>
                  Navigator.pop(sheetContext, UpgradeBillingChannel.cash),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Requests a paid plan change on the chosen billing channel. Entitlements
  /// never change here — the toast says exactly what happens next.
  Future<void> _requestUpgrade(
    String tier,
    String planName,
    UpgradeBillingChannel channel,
  ) async {
    setState(() => _selectingTier = tier);
    final copy = appLocalizationsOf(context);
    try {
      await ref.read(requestPlanUpgradeProvider)(tier, channel);
      if (!mounted) return;
      showNyumbaToast(
        channel == UpgradeBillingChannel.cash
            ? copy.subscriptionUpgradeCashRequested(planName)
            : copy.subscriptionUpgradeRequestedToast(planName),
        variant: NyumbaToastVariant.success,
      );
    } on RemoteSyncException catch (error) {
      if (!mounted) return;
      // Electronic checkout has no aggregator wired yet, so the server fails
      // it closed. Say so plainly and point at the cash path that works today.
      showNyumbaToast(
        error.message == 'PAYMENT_PROVIDER_UNAVAILABLE'
            ? copy.subscriptionElectronicComingSoon
            : _describeFailure(context, error),
        variant: NyumbaToastVariant.error,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showNyumbaToast(
        _describeFailure(context, error),
        variant: NyumbaToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _selectingTier = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final session = ref.watch(sessionControllerProvider);
    final status =
        session?.subscriptionStatus ?? LandlordSubscriptionStatus.unavailable;
    final active = status == LandlordSubscriptionStatus.active;
    final tier = session?.subscriptionTier?.toLowerCase();
    final requestedTier = session?.subscriptionRequestedTier?.toLowerCase();
    final currentTierIndex = _tiers.indexWhere(
      (presentation) => presentation.tier == tier,
    );
    final catalog = ref
        .watch(publicPlanCatalogProvider)
        .maybeWhen(
          data: (plans) => plans,
          orElse: () => const <String, PublicPlanFacts>{},
        );

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: FadeSlideIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: NyumbaLogo(
                                compact: constraints.maxWidth < 480,
                                height: 44,
                              ),
                            ),
                          ),
                          AsyncActionButton.text(
                            onPressed: () => ref
                                .read(sessionControllerProvider.notifier)
                                .signOut(),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            child: Text(copy.signOut),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      active
                          ? copy.subscriptionActiveTitle
                          : copy.subscriptionChoosePlanTitle,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      active
                          ? copy.subscriptionActiveDescription
                          : copy.subscriptionGateDescription,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.nyumba.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _PaymentStatusCard(
                      status: status,
                      renewal: ref
                          .watch(subscriptionRenewalProvider)
                          .maybeWhen(
                            data: (state) => state,
                            orElse: () => const SubscriptionRenewalState(),
                          ),
                      planName: _planName(copy, tier, catalog),
                      requestedPlanName: active && requestedTier != null
                          ? _planName(copy, requestedTier, catalog)
                          : null,
                      accountEmail: session?.email ?? '',
                      isRefreshing: _isRefreshing,
                      onRefresh: _refresh,
                      onContinue: active
                          ? () => context.go('/dashboard')
                          : null,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      copy.subscriptionTiers,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      active
                          ? copy.subscriptionChangeActivePlanDescription
                          : copy.subscriptionChoosePlanDescription,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.nyumba.mutedInk,
                      ),
                    ),
                    if (catalog.isEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        copy.subscriptionPlanCapacityUnavailable,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.nyumba.terracottaDark,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 900
                            ? 4
                            : constraints.maxWidth >= 560
                            ? 2
                            : 1;
                        const gap = 12.0;
                        final width =
                            (constraints.maxWidth - gap * (columns - 1)) /
                            columns;
                        // Unpaid: any tier can be selected. Active: higher
                        // tiers become self-service upgrade requests; the
                        // current and lower tiers stay read-only (downgrades
                        // go through support, per the downgrade-safety rules).
                        Future<void> Function()? actionFor(
                          int index,
                          _TierPresentation presentation,
                        ) {
                          if (_selectingTier != null ||
                              tier == presentation.tier) {
                            return null;
                          }
                          final planName =
                              catalog[presentation.tier]?.displayName ??
                              _fallbackPlanName(copy, presentation.tier);
                          if (!active) {
                            return () => _chooseInitialPaymentMethod(
                              presentation.tier,
                              planName,
                            );
                          }
                          if (index > currentTierIndex &&
                              currentTierIndex != -1 &&
                              requestedTier != presentation.tier) {
                            return () => _chooseUpgradeMethod(
                              presentation.tier,
                              planName,
                            );
                          }
                          return null;
                        }

                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final (index, presentation) in _tiers.indexed)
                              SizedBox(
                                width: width,
                                child: _PlanCard(
                                  presentation: presentation,
                                  facts: catalog[presentation.tier],
                                  includesPlanName:
                                      switch (catalog[presentation.tier]
                                          ?.includesTier) {
                                        null => null,
                                        final includes =>
                                          catalog[includes]?.displayName ??
                                              _fallbackPlanName(copy, includes),
                                      },
                                  selected: tier == presentation.tier,
                                  selectedLabel: active
                                      ? copy.subscriptionCurrentPlan
                                      : copy.selected,
                                  upgradeRequested:
                                      active &&
                                      requestedTier == presentation.tier,
                                  actionLabel: active
                                      ? copy.subscriptionUpgrade
                                      : copy.choosePlan,
                                  busy: _selectingTier == presentation.tier,
                                  onChoose: actionFor(index, presentation),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _planName(
  AppLocalizations copy,
  String? tier,
  Map<String, PublicPlanFacts> catalog,
) {
  if (tier == null || tier.isEmpty) return null;
  final fromCatalog = catalog[tier]?.displayName;
  if (fromCatalog != null) return fromCatalog;
  for (final presentation in _tiers) {
    if (presentation.tier == tier) {
      return _fallbackPlanName(copy, presentation.tier);
    }
  }
  return tier;
}

class _PaymentStatusCard extends StatelessWidget {
  const _PaymentStatusCard({
    required this.status,
    required this.renewal,
    required this.planName,
    required this.requestedPlanName,
    required this.accountEmail,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onContinue,
  });

  final LandlordSubscriptionStatus status;

  /// Renewal deadline and, once overdue, the grace window.
  final SubscriptionRenewalState renewal;

  final String? planName;

  /// Plan an active landlord asked to upgrade to; non-null only while an
  /// upgrade awaits payment confirmation.
  final String? requestedPlanName;

  final String accountEmail;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final active = status == LandlordSubscriptionStatus.active;
    return NyumbaSurface(
      borderColor: active
          ? context.nyumba.sageBorder
          : context.nyumba.goldBorder,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: active ? context.nyumba.sageTint : context.nyumba.goldTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              active ? Icons.verified_outlined : Icons.hourglass_top_rounded,
              color: active
                  ? context.nyumba.sageDark
                  : context.nyumba.terracottaDark,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active
                      ? copy.subscriptionPaymentConfirmed
                      : _statusTitle(copy, status),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  _statusMessage(copy, status, planName),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // An overdue-but-active subscription is the grace window: the
                // workspace still works, so the deadline is a warning rather
                // than a lockout notice.
                if (active && renewal.isOverdue) ...[
                  const SizedBox(height: 10),
                  Text(
                    copy.subscriptionOverdueTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: context.nyumba.danger,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    switch (renewal.daysUntilLock) {
                      final days? when days > 0 =>
                        copy.subscriptionOverdueLocksIn(
                          days,
                          _renewalDate.format(renewal.graceEndsAt!.toLocal()),
                        ),
                      _ => copy.subscriptionOverdueLocksToday,
                    },
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.nyumba.terracottaDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _howToPay(copy, accountEmail),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.nyumba.mutedInk,
                    ),
                  ),
                ] else if (active && renewal.renewalDueAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    copy.subscriptionRenewsOn(
                      _renewalDate.format(renewal.renewalDueAt!.toLocal()),
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.nyumba.mutedInk,
                    ),
                  ),
                ],
                if (!active) ...[
                  const SizedBox(height: 10),
                  Text(
                    _howToPay(copy, accountEmail),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.nyumba.mutedInk,
                    ),
                  ),
                ] else if (requestedPlanName != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    copy.subscriptionUpgradeRequestedMessage(
                      requestedPlanName!,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.nyumba.terracottaDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _howToPay(copy, accountEmail),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.nyumba.mutedInk,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (onContinue != null)
                      FilledButton(
                        onPressed: onContinue,
                        child: Text(copy.subscriptionEnterWorkspace),
                      ),
                    AsyncActionButton.outlined(
                      onPressed: onRefresh,
                      busy: isRefreshing,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      child: Text(copy.subscriptionCheckPaymentStatus),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _statusTitle(AppLocalizations copy, LandlordSubscriptionStatus status) =>
    switch (status) {
      LandlordSubscriptionStatus.pendingPayment =>
        copy.subscriptionAwaitingPaymentConfirmation,
      LandlordSubscriptionStatus.pastDue => copy.subscriptionPaymentPastDue,
      LandlordSubscriptionStatus.canceled => copy.subscriptionCanceled,
      LandlordSubscriptionStatus.expired => copy.subscriptionExpired,
      LandlordSubscriptionStatus.unavailable =>
        copy.subscriptionStatusUnavailable,
      _ => copy.subscriptionRequired,
    };

String _statusMessage(
  AppLocalizations copy,
  LandlordSubscriptionStatus status,
  String? planName,
) {
  final plan = planName ?? copy.subscriptionSelectedPlanName;
  return switch (status) {
    LandlordSubscriptionStatus.pendingPayment =>
      copy.subscriptionPendingMessage(plan),
    LandlordSubscriptionStatus.pastDue => copy.subscriptionPastDueMessage(plan),
    LandlordSubscriptionStatus.canceled => copy.subscriptionCanceledMessage,
    LandlordSubscriptionStatus.expired => copy.subscriptionExpiredMessage,
    LandlordSubscriptionStatus.active => copy.subscriptionActiveMessage(plan),
    _ => copy.subscriptionUnverifiedMessage,
  };
}

/// Manual activation guidance until electronic checkout ships. Payment rails
/// come from the market config; cash is excluded because subscriptions are
/// paid to Nyumba, not recorded by a landlord.
String _howToPay(AppLocalizations copy, String accountEmail) {
  final methods = NyumbaMarket.paymentMethods
      .where((method) => !method.startsWith('Cash'))
      .join(', ');
  return accountEmail.isEmpty
      ? copy.subscriptionHowToPay(methods)
      : copy.subscriptionHowToPayWithEmail(methods, accountEmail);
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.presentation,
    required this.facts,
    required this.includesPlanName,
    required this.selected,
    required this.selectedLabel,
    required this.upgradeRequested,
    required this.actionLabel,
    required this.busy,
    required this.onChoose,
  });

  final _TierPresentation presentation;
  final PublicPlanFacts? facts;

  /// Display name of the tier whose benefits this plan inherits.
  final String? includesPlanName;

  final bool selected;

  /// "Selected" pre-payment, "Current plan" once active.
  final String selectedLabel;

  /// This tier is the landlord's pending upgrade request.
  final bool upgradeRequested;

  /// "Choose plan" pre-payment, "Upgrade" once active.
  final String actionLabel;

  final bool busy;
  final Future<void> Function()? onChoose;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final name =
        facts?.displayName ?? _fallbackPlanName(copy, presentation.tier);
    final audience =
        facts?.tagline ?? _fallbackPlanAudience(copy, presentation.tier);
    final capacity = facts == null
        ? null
        : facts!.capacityLabel ??
              copy.subscriptionPlanCapacity(
                facts!.unitLimit,
                facts!.activeListingLimit,
              );
    final monthly = facts?.monthlyPriceMinor;
    final yearly = facts?.yearlyPriceMinor;
    final savings = facts?.yearlySavingsPercent;
    final features = facts?.features ?? const <PublicPlanFeature>[];
    return NyumbaSurface(
      onTap: onChoose == null ? null : () => onChoose!(),
      borderColor: selected
          ? context.nyumba.midnightNavy
          : context.nyumba.outline,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 178),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(presentation.icon, color: context.nyumba.midnightNavy),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(audience, style: Theme.of(context).textTheme.bodySmall),
            if (monthly != null) ...[
              const SizedBox(height: 12),
              Text(
                copy.subscriptionMonthlyPrice(_ugx.format(monthly / 100)),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (yearly != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    savings == null
                        ? copy.subscriptionYearlyPrice(
                            _ugx.format(yearly / 100),
                          )
                        : '${copy.subscriptionYearlyPrice(_ugx.format(yearly / 100))}'
                              ' · ${copy.subscriptionYearlySavings(savings)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.nyumba.sageDark,
                    ),
                  ),
                ),
            ],
            if (capacity != null) ...[
              const SizedBox(height: 12),
              Text(capacity, style: Theme.of(context).textTheme.labelLarge),
            ],
            if (features.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (includesPlanName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    copy.subscriptionEverythingInPlus(includesPlanName!),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.nyumba.mutedInk,
                    ),
                  ),
                ),
              for (final feature in features)
                _PlanFeatureLine(feature: feature),
            ],
            const SizedBox(height: 14),
            if (selected)
              Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 19,
                    color: context.nyumba.sageDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    selectedLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.nyumba.sageDark,
                    ),
                  ),
                ],
              )
            else if (upgradeRequested)
              Row(
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 19,
                    color: context.nyumba.terracottaDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    copy.subscriptionUpgradeRequestedBadge,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.nyumba.terracottaDark,
                    ),
                  ),
                ],
              )
            else
              AsyncActionButton.outlined(
                onPressed: onChoose,
                // The screen raises `busy` once the real request starts; the
                // billing-channel sheet in between is not work to report on.
                busy: busy,
                showBusyIndicator: false,
                child: Text(actionLabel),
              ),
          ],
        ),
      ),
    );
  }
}

/// One benefit line. Unimplemented benefits stay visible but greyed out with
/// a "coming soon" marker — sold on the roadmap, never mistaken for shipped.
class _PlanFeatureLine extends StatelessWidget {
  const _PlanFeatureLine({required this.feature});

  final PublicPlanFeature feature;

  @override
  Widget build(BuildContext context) {
    final copy = appLocalizationsOf(context);
    final muted = context.nyumba.mutedInk.withValues(alpha: 0.55);
    final implemented = feature.implemented;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              implemented ? Icons.check_rounded : Icons.schedule_rounded,
              size: 15,
              color: implemented ? context.nyumba.sageDark : muted,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              implemented
                  ? context.tr(feature.label)
                  : '${context.tr(feature.label)}'
                        ' · ${copy.subscriptionComingSoon}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: implemented ? null : muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One selectable payment method in the upgrade chooser sheet.
class _UpgradeMethodTile extends StatelessWidget {
  const _UpgradeMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.nyumba.navyTint,
        child: Icon(icon, color: context.nyumba.midnightNavy, size: 22),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      // The affordance points the way the reader moves forward, which is
      // leftwards in Arabic; a fixed right chevron points back out of the flow.
      trailing: Icon(
        Directionality.of(context) == TextDirection.rtl
            ? Icons.chevron_left_rounded
            : Icons.chevron_right_rounded,
      ),
      onTap: onTap,
    );
  }
}

class _TierPresentation {
  const _TierPresentation(this.tier, this.icon);

  /// Catalog document ID; also what `subscription.selectPlan` records.
  final String tier;

  final IconData icon;
}

String _fallbackPlanName(AppLocalizations copy, String tier) => switch (tier) {
  'starter' => copy.subscriptionStarterPlan,
  'pro' => copy.subscriptionProPlan,
  'premium' => copy.subscriptionPremiumPlan,
  _ => copy.subscriptionEnterprisePlan,
};

String _fallbackPlanAudience(AppLocalizations copy, String tier) =>
    switch (tier) {
      'starter' => copy.subscriptionStarterAudience,
      'pro' => copy.subscriptionProAudience,
      'premium' => copy.subscriptionPremiumAudience,
      _ => copy.subscriptionEnterpriseAudience,
    };

/// Presentation order and iconography for the normative tier structure
/// (docs/architecture/subscription-tiers.md). Capacity numbers never live
/// here — they render only from the server-owned plan catalog.
String _describeFailure(BuildContext context, Object error) =>
    describeAuthFailure(
      error,
      commandFailureLocalizer: (failure) =>
          localizeCommandFailure(appLocalizationsOf(context), failure),
    );

const _tiers = [
  _TierPresentation('starter', Icons.home_work_outlined),
  _TierPresentation('pro', Icons.rocket_launch_outlined),
  _TierPresentation('premium', Icons.workspace_premium_outlined),
  _TierPresentation('enterprise', Icons.domain_outlined),
];
