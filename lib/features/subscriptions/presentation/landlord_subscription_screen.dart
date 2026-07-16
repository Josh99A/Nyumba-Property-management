import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/config/market_config.dart';
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
          'Payment confirmed. Your landlord workspace is now available.',
          variant: NyumbaToastVariant.success,
        );
      } else {
        showNyumbaToast(
          'Payment has not been confirmed yet.',
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
      showNyumbaToast(
        '$planName plan selected. Your workspace opens once its payment is '
        'confirmed.',
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
                              alignment: Alignment.centerLeft,
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
                            label: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      active
                          ? 'Your subscription is active'
                          : 'Choose your plan',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      active
                          ? 'Your payment has been confirmed. You can now '
                                'enter your landlord workspace.'
                          : 'Your workspace opens as soon as Nyumba confirms '
                                'your subscription payment. Tenant and public '
                                'listing access stay free.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.nyumba.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _PaymentStatusCard(
                      status: status,
                      planName: _planName(tier, catalog),
                      accountEmail: session?.email ?? '',
                      isRefreshing: _isRefreshing,
                      onRefresh: _refresh,
                      onContinue: active
                          ? () => context.go('/dashboard')
                          : null,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Subscription tiers',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      active
                          ? 'Changing an active plan is handled with your '
                                'next payment — contact Nyumba support.'
                          : 'Pick the plan that fits your portfolio. You can '
                                'switch freely until your payment is '
                                'confirmed, and pricing is always confirmed '
                                'with you before you pay.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.nyumba.mutedInk,
                      ),
                    ),
                    if (catalog.isEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Plan capacity details could not be loaded right now, '
                        'so they are not shown — nothing is guessed on this '
                        'device.',
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
                                              presentation.fallbackName,
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

String? _planName(String? tier, Map<String, PublicPlanFacts> catalog) {
  if (tier == null || tier.isEmpty) return null;
  final fromCatalog = catalog[tier]?.displayName;
  if (fromCatalog != null) return fromCatalog;
  for (final presentation in _tiers) {
    if (presentation.tier == tier) return presentation.fallbackName;
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
                  active ? 'Payment confirmed' : _statusTitle(status),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  _statusMessage(status, planName),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!active) ...[
                  const SizedBox(height: 10),
                  Text(
                    _howToPay(accountEmail),
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
                        child: const Text('Enter workspace'),
                      ),
                    OutlinedButton.icon(
                      onPressed: isRefreshing ? null : onRefresh,
                      icon: isRefreshing
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Check payment status'),
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

String _statusTitle(LandlordSubscriptionStatus status) => switch (status) {
  LandlordSubscriptionStatus.pendingPayment => 'Awaiting payment confirmation',
  LandlordSubscriptionStatus.pastDue => 'Payment is past due',
  LandlordSubscriptionStatus.canceled => 'Subscription canceled',
  LandlordSubscriptionStatus.expired => 'Subscription expired',
  LandlordSubscriptionStatus.unavailable => 'Subscription status unavailable',
  _ => 'Subscription required',
};

String _statusMessage(LandlordSubscriptionStatus status, String? planName) {
  final plan = planName == null ? 'selected plan' : '$planName plan';
  return switch (status) {
    LandlordSubscriptionStatus.pendingPayment =>
      'Your $plan is reserved, and no payment has been confirmed yet.',
    LandlordSubscriptionStatus.pastDue =>
      'Your $plan payment is past due. Settle it to keep the workspace open.',
    LandlordSubscriptionStatus.canceled =>
      'A new paid subscription is required before entering the workspace.',
    LandlordSubscriptionStatus.expired =>
      'Renew your subscription before entering the workspace.',
    LandlordSubscriptionStatus.active =>
      'Payment for your $plan has been confirmed.',
    _ =>
      'Nyumba could not verify an active paid subscription for this account.',
  };
}

/// Manual activation guidance until electronic checkout ships. Payment rails
/// come from the market config; cash is excluded because subscriptions are
/// paid to Nyumba, not recorded by a landlord.
String _howToPay(String accountEmail) {
  final methods = NyumbaMarket.paymentMethods
      .where((method) => !method.startsWith('Cash'))
      .join(', ');
  final account = accountEmail.isEmpty
      ? 'your account email'
      : 'your account email ($accountEmail)';
  return 'In-app checkout is coming soon. To activate now, pay via $methods '
      'and share the transaction reference with Nyumba support, quoting '
      '$account. Your workspace opens automatically the moment the payment '
      'is confirmed — no need to stay on this page.';
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
    final name = facts?.displayName ?? presentation.fallbackName;
    final audience = facts?.tagline ?? presentation.audience;
    final capacity = facts == null
        ? null
        : facts!.capacityLabel ??
              'Up to ${facts!.unitLimit} rental spaces · '
                  '${facts!.activeListingLimit} active listings';
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
                    'Selected',
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
                    : const Text('Choose plan'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TierPresentation {
  const _TierPresentation(
    this.tier,
    this.fallbackName,
    this.audience,
    this.icon,
  );

  /// Catalog document ID; also what `subscription.selectPlan` records.
  final String tier;

  /// Shown only while the server catalog is unavailable.
  final String fallbackName;

  final String audience;
  final IconData icon;
}

/// Presentation order and iconography for the normative tier structure
/// (docs/architecture/subscription-tiers.md). Capacity numbers never live
/// here — they render only from the server-owned plan catalog.
const _tiers = [
  _TierPresentation(
    'starter',
    'Starter',
    'Individual landlords and small portfolios',
    Icons.home_work_outlined,
  ),
  _TierPresentation(
    'pro',
    'Pro',
    'Growing landlords and small teams',
    Icons.rocket_launch_outlined,
  ),
  _TierPresentation(
    'premium',
    'Premium',
    'Professional property managers',
    Icons.workspace_premium_outlined,
  ),
  _TierPresentation(
    'enterprise',
    'Enterprise',
    'Agencies, institutions, and large companies',
    Icons.domain_outlined,
  ),
];
