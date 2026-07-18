import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/config/market_config.dart';
import '../../../core/localization/app_localizations_adapter.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/toast.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/auth_failure.dart';
import '../../auth/domain/user_session.dart';
import '../application/subscription_providers.dart';

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
      showNyumbaToast(
        describeAuthFailure(error),
        variant: NyumbaToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _choosePlan(String tier, String planName) async {
    setState(() => _selectingTier = tier);
    try {
      await ref.read(selectSubscriptionPlanProvider)(tier);
      if (!mounted) return;
      showNyumbaToast(
        appLocalizationsOf(context).subscriptionPlanSelected(planName),
        variant: NyumbaToastVariant.success,
      );
    } on Object catch (error) {
      showNyumbaToast(
        describeAuthFailure(error),
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
                          TextButton.icon(
                            onPressed: () => ref
                                .read(sessionControllerProvider.notifier)
                                .signOut(),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: Text(copy.signOut),
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
                      planName: _planName(copy, tier, catalog),
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
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final presentation in _tiers)
                              SizedBox(
                                width: width,
                                child: _PlanCard(
                                  presentation: presentation,
                                  facts: catalog[presentation.tier],
                                  selected: tier == presentation.tier,
                                  busy: _selectingTier == presentation.tier,
                                  onChoose:
                                      active ||
                                          _selectingTier != null ||
                                          tier == presentation.tier
                                      ? null
                                      : () => _choosePlan(
                                          presentation.tier,
                                          catalog[presentation.tier]
                                                  ?.displayName ??
                                              _fallbackPlanName(
                                                copy,
                                                presentation.tier,
                                              ),
                                        ),
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
    required this.planName,
    required this.accountEmail,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onContinue,
  });

  final LandlordSubscriptionStatus status;
  final String? planName;
  final String accountEmail;
  final bool isRefreshing;
  final VoidCallback onRefresh;
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
                if (!active) ...[
                  const SizedBox(height: 10),
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
                    OutlinedButton.icon(
                      onPressed: isRefreshing ? null : onRefresh,
                      icon: isRefreshing
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(copy.subscriptionCheckPaymentStatus),
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
    required this.selected,
    required this.busy,
    required this.onChoose,
  });

  final _TierPresentation presentation;
  final PublicPlanFacts? facts;
  final bool selected;
  final bool busy;
  final VoidCallback? onChoose;

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
    return NyumbaSurface(
      onTap: onChoose,
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
            if (capacity != null) ...[
              const SizedBox(height: 12),
              Text(capacity, style: Theme.of(context).textTheme.labelLarge),
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
                    copy.selected,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.nyumba.sageDark,
                    ),
                  ),
                ],
              )
            else
              OutlinedButton(
                onPressed: onChoose,
                child: busy
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(copy.choosePlan),
              ),
          ],
        ),
      ),
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
const _tiers = [
  _TierPresentation('starter', Icons.home_work_outlined),
  _TierPresentation('pro', Icons.rocket_launch_outlined),
  _TierPresentation('premium', Icons.workspace_premium_outlined),
  _TierPresentation('enterprise', Icons.domain_outlined),
];
