import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/toast.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/auth_failure.dart';
import '../../auth/domain/user_session.dart';

class LandlordSubscriptionScreen extends ConsumerStatefulWidget {
  const LandlordSubscriptionScreen({super.key});

  @override
  ConsumerState<LandlordSubscriptionScreen> createState() =>
      _LandlordSubscriptionScreenState();
}

class _LandlordSubscriptionScreenState
    extends ConsumerState<LandlordSubscriptionScreen> {
  bool _isRefreshing = false;

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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final status =
        session?.subscriptionStatus ?? LandlordSubscriptionStatus.unavailable;
    final active = status == LandlordSubscriptionStatus.active;
    final tier = session?.subscriptionTier;

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
                          : 'Subscription required to continue',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      active
                          ? 'Your payment has been confirmed by the server. '
                                'You can now enter your landlord workspace.'
                          : 'Landlord workspaces open only after Nyumba receives '
                                'server-confirmed payment. Tenant and public '
                                'listing access remain free.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.nyumba.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _PaymentStatusCard(
                      status: status,
                      tier: tier,
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
                      'Plan prices, billing intervals, and electronic checkout '
                      'are not configured yet. Nyumba will not simulate a '
                      'successful payment or unlock a workspace locally.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.nyumba.mutedInk,
                      ),
                    ),
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
                            for (final plan in _plans)
                              SizedBox(
                                width: width,
                                child: _PlanSummary(
                                  plan: plan,
                                  selected:
                                      tier?.toLowerCase() ==
                                      plan.name.toLowerCase(),
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

class _PaymentStatusCard extends StatelessWidget {
  const _PaymentStatusCard({
    required this.status,
    required this.tier,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onContinue,
  });

  final LandlordSubscriptionStatus status;
  final String? tier;
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
                  _statusMessage(status, tier),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (onContinue != null)
                      FilledButton(
                        onPressed: onContinue,
                        child: const Text('Enter workspace'),
                      )
                    else
                      FilledButton(
                        onPressed: null,
                        child: const Text('Checkout unavailable'),
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

String _statusMessage(LandlordSubscriptionStatus status, String? tier) {
  final plan = tier == null || tier.isEmpty ? 'selected plan' : '$tier plan';
  return switch (status) {
    LandlordSubscriptionStatus.pendingPayment =>
      'Your $plan is reserved, but no confirmed payment has been received.',
    LandlordSubscriptionStatus.pastDue =>
      'The server has marked your $plan payment as past due.',
    LandlordSubscriptionStatus.canceled =>
      'A new paid subscription is required before entering the workspace.',
    LandlordSubscriptionStatus.expired =>
      'Renew your subscription before entering the workspace.',
    LandlordSubscriptionStatus.active =>
      'The server confirmed payment for your $plan.',
    _ =>
      'Nyumba could not verify an active paid subscription for this account.',
  };
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan, required this.selected});

  final _Plan plan;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return NyumbaSurface(
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
                Icon(plan.icon, color: context.nyumba.midnightNavy),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    plan.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: context.nyumba.sageDark,
                    semanticLabel: 'Current plan',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(plan.audience, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(plan.capacity, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 18),
            Text(
              'Price awaiting server configuration',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.nyumba.terracottaDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Plan {
  const _Plan(this.name, this.audience, this.capacity, this.icon);

  final String name;
  final String audience;
  final String capacity;
  final IconData icon;
}

const _plans = [
  _Plan(
    'Starter',
    'Individual landlords and small portfolios',
    'Suggested limit: up to 10 units',
    Icons.home_work_outlined,
  ),
  _Plan(
    'Pro',
    'Growing landlords and small teams',
    'Suggested limit: up to 50 units',
    Icons.rocket_launch_outlined,
  ),
  _Plan(
    'Premium',
    'Professional property managers',
    'Suggested limit: up to 200 units',
    Icons.workspace_premium_outlined,
  ),
  _Plan(
    'Enterprise',
    'Agencies, institutions, and large companies',
    'Custom capacity and controls',
    Icons.domain_outlined,
  ),
];
