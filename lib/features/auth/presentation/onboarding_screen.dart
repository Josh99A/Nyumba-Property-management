import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/config/market_config.dart';
import '../../../core/localization/app_localizations_adapter.dart';
import '../../../core/localization/command_failure_localizations.dart';
import '../../../core/presentation/async_action_button.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/language_menu_button.dart';
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
      if (!mounted) return;
      showNyumbaToast(
        _describeFailure(error),
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
      if (!mounted) return;
      showNyumbaToast(
        _describeFailure(error),
        variant: NyumbaToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _isCheckingInvites = false);
    }
  }

  String _describeFailure(Object error) => describeAuthFailure(
    error,
    commandFailureLocalizer: (failure) =>
        localizeCommandFailure(appLocalizationsOf(context), failure),
  );

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
                            alignment: AlignmentDirectional.centerStart,
                            child: NyumbaLogo(height: 44),
                          ),
                        ),
                        const LanguageMenuButton(compact: true),
                        const SizedBox(width: 8),
                        AsyncActionButton.text(
                          onPressed: () => ref
                              .read(sessionControllerProvider.notifier)
                              .signOut(),
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          child: const Text.localized('Sign out'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text.localized(
                      'Welcome, $firstName',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text.localized(
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
                                  child: Text.localized(
                                    'Set up a landlord workspace',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text.localized(
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
                              decoration: InputDecoration(
                                labelText: context.tr('Phone number'),
                                hintText: context.tr('+256 772 123 456'),
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
                              decoration: InputDecoration(
                                labelText: context.tr(
                                  'Business name (optional)',
                                ),
                                prefixIcon: Icon(Icons.storefront_outlined),
                              ),
                            ),
                            const SizedBox(height: 18),
                            AsyncActionButton.filled(
                              onPressed: _completeLandlordSetup,
                              busy: _isSubmitting,
                              child: const Text.localized(
                                'Continue to subscriptions',
                              ),
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
                                child: Text.localized(
                                  'Renting through Nyumba?',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text.localized(
                            'Tenants are added by their landlord — there is '
                            'nothing to register. If your landlord invited '
                            '${session?.email ?? 'your email'}, your portal '
                            'connects automatically.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          AsyncActionButton.outlined(
                            onPressed: _checkInvitations,
                            busy: _isCheckingInvites,
                            icon: const Icon(Icons.refresh_rounded, size: 19),
                            child: const Text.localized(
                              'Check for my invitation',
                            ),
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
