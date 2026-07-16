import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/config/market_config.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/surface.dart';
import '../../../core/presentation/toast.dart';
import '../application/session_controller.dart';
import '../domain/auth_failure.dart';

/// First verified sign-in for an account without a role. Landlords finish
/// setup here (server command, pending admin approval); invited tenants are
/// linked automatically by email, with a manual re-check offered.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(
    text: NyumbaMarket.phoneCountryCode,
  );
  final _businessController = TextEditingController();
  bool _isSubmitting = false;
  bool _isCheckingInvites = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _businessController.dispose();
    super.dispose();
  }

  Future<void> _completeLandlordSetup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .completeLandlordOnboarding(
            phone: _phoneController.text.trim(),
            businessName: _businessController.text,
          );
      if (mounted) context.go('/subscription');
      showNyumbaToast(
        'Landlord details saved. Choose a subscription and wait for confirmed '
        'payment to open your workspace.',
        variant: NyumbaToastVariant.success,
      );
    } on Object catch (error) {
      showNyumbaToast(
        describeAuthFailure(error),
        variant: NyumbaToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _checkInvitations() async {
    setState(() => _isCheckingInvites = true);
    try {
      final linked = await ref
          .read(sessionControllerProvider.notifier)
          .claimTenantInvites();
      if (!mounted) return;
      if (linked > 0) {
        context.go('/tenant');
        showNyumbaToast(
          linked == 1
              ? 'Tenancy linked. Your portal is open.'
              : '$linked tenancies linked. Your portal is open.',
          variant: NyumbaToastVariant.success,
        );
      } else {
        final email =
            ref.read(sessionControllerProvider)?.email ?? 'this email';
        showNyumbaToast(
          'No invitation found for $email. Ask your landlord to add you with '
          'this exact email address.',
          variant: NyumbaToastVariant.info,
        );
      }
    } on Object catch (error) {
      showNyumbaToast(
        describeAuthFailure(error),
        variant: NyumbaToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _isCheckingInvites = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final firstName = session?.firstName ?? 'there';
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: FadeSlideIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: NyumbaLogo(height: 44),
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
                    const SizedBox(height: 32),
                    Text(
                      'Welcome, $firstName',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Choose how you will use Nyumba to finish setting up.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.nyumba.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 26),
                    NyumbaSurface(
                      padding: const EdgeInsets.all(22),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.home_work_outlined,
                                  color: context.nyumba.midnightNavy,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Set up a landlord workspace',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'After setup, choose a subscription. The landlord '
                              'workspace stays locked until payment is '
                              'confirmed by the server.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Phone number',
                                hintText: '+256 772 123 456',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                              validator: (value) =>
                                  !NyumbaMarket.isValidPhone(
                                    value?.trim() ?? '',
                                  )
                                  ? 'Enter a valid Ugandan phone number (+256…)'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _businessController,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _completeLandlordSetup(),
                              decoration: const InputDecoration(
                                labelText: 'Business name (optional)',
                                prefixIcon: Icon(Icons.storefront_outlined),
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : _completeLandlordSetup,
                              child: _isSubmitting
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Continue to subscriptions'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    NyumbaSurface(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                color: context.nyumba.sageDark,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Renting through Nyumba?',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tenants are added by their landlord — there is '
                            'nothing to register. If your landlord invited '
                            '${session?.email ?? 'your email'}, your portal '
                            'connects automatically.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _isCheckingInvites
                                ? null
                                : _checkInvitations,
                            icon: _isCheckingInvites
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 19),
                            label: const Text('Check for my invitation'),
                          ),
                        ],
                      ),
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
