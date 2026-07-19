import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/google_g_logo.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/language_menu_button.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/operational_actions.dart';
import '../../../core/presentation/toast.dart';
import '../application/session_controller.dart';
import '../domain/auth_failure.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _isGoogleSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
      // The session itself lands on the auth-state listener, which greets the
      // user and redirects; nothing more to announce here.
    } on EmailNotVerifiedException catch (error) {
      if (!mounted) return;
      await _showVerificationSent(error.email);
    } on Object catch (error) {
      showNyumbaToast(
        describeAuthFailure(error),
        variant: NyumbaToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showVerificationSent(String email) => showNyumbaInfoDialog(
    context,
    title: 'Verify your email',
    message:
        'Your password is correct, but $email is not verified yet. We sent a '
        'fresh link — open it, then sign in again. Check your spam folder if '
        'it has not arrived.',
    icon: Icons.mark_email_read_outlined,
  );

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showNyumbaToast(
        'Enter your email address first.',
        variant: NyumbaToastVariant.info,
      );
      return;
    }
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .sendPasswordResetEmail(email);
      if (!mounted) return;
      await showNyumbaInfoDialog(
        context,
        title: 'Check your email',
        // Deliberately silent on whether the account exists: confirming it
        // would let anyone test addresses against Nyumba.
        message:
            'If $email has a Nyumba account, a password-reset link is on its '
            'way. Check your spam folder if it has not arrived.',
        icon: Icons.lock_reset_rounded,
      );
    } on Object catch (error) {
      showNyumbaToast(
        describeAuthFailure(error),
        variant: NyumbaToastVariant.error,
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleSubmitting = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signInWithGoogle();
    } on Object catch (error) {
      // Closing the Google window is a decision, not a fault.
      if (isAuthCancellation(error)) return;
      showNyumbaToast(
        describeAuthFailure(error),
        variant: NyumbaToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _isGoogleSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A credential is accepted well before the profile behind it resolves, so
    // the button keeps its spinner until the session actually lands rather
    // than going idle over a screen that is about to be replaced.
    final isResolving = ref.watch(sessionResolutionProvider).isResolving;
    final busy = _isSubmitting || isResolving;
    final googleBusy = _isGoogleSubmitting || isResolving;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showBrand =
                constraints.maxWidth >= 1100 && constraints.maxHeight >= 720;
            return Row(
              children: [
                if (showBrand)
                  Expanded(
                    flex: 11,
                    child: _BrandPanel(onExplore: () => context.go('/explore')),
                  ),
                Expanded(
                  flex: 9,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: showBrand
                            ? 56
                            : constraints.maxWidth < 600
                            ? 24
                            : 40,
                        vertical: showBrand ? 52 : 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: FadeSlideIn(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: LanguageMenuButton(),
                              ),
                              const SizedBox(height: 24),
                              if (!showBrand) ...[
                                const Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: NyumbaLogo(height: 48),
                                ),
                                const SizedBox(height: 46),
                              ],
                              Text.localized(
                                'Welcome back',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineLarge,
                              ),
                              const SizedBox(height: 10),
                              Text.localized(
                                'Sign in to manage your Nyumba workspace.',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: context.nyumba.mutedInk),
                              ),
                              const SizedBox(height: 32),
                              Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text.localized(
                                      'Email address',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.email,
                                      ],
                                      textInputAction: TextInputAction.next,
                                      decoration: InputDecoration(
                                        hintText: context.tr('you@example.com'),
                                        prefixIcon: Icon(
                                          Icons.mail_outline_rounded,
                                        ),
                                      ),
                                      validator: (value) {
                                        final email = value?.trim() ?? '';
                                        if (email.isEmpty ||
                                            !email.contains('@')) {
                                          return 'Enter a valid email address';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text.localized(
                                            'Password',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelLarge,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _resetPassword,
                                          child: const Text.localized(
                                            'Forgot password?',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      autofillHints: const [
                                        AutofillHints.password,
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) => _submit(),
                                      decoration: InputDecoration(
                                        hintText: context.tr(
                                          'Enter your password',
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.lock_outline_rounded,
                                        ),
                                        suffixIcon: IconButton(
                                          tooltip: context.tr(
                                            _obscurePassword
                                                ? 'Show password'
                                                : 'Hide password',
                                          ),
                                          onPressed: () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                        ),
                                      ),
                                      validator: (value) =>
                                          (value?.length ?? 0) < 6
                                          ? 'Password must have at least 6 characters'
                                          : null,
                                    ),
                                    const SizedBox(height: 24),
                                    FilledButton(
                                      onPressed: busy ? null : _submit,
                                      child: busy
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text.localized('Sign in'),
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: googleBusy
                                          ? null
                                          : _signInWithGoogle,
                                      icon: googleBusy
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const GoogleGLogo(),
                                      label: Text.localized(
                                        isResolving
                                            ? 'Opening your workspace…'
                                            : 'Continue with Google',
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    TextButton(
                                      onPressed: () => context.go('/sign-up'),
                                      child: const Text.localized(
                                        'New to Nyumba? Create a landlord account',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: context.nyumba.sageTint,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: context.nyumba.sageBorder,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.offline_bolt_outlined,
                                        color: context.nyumba.sageDark,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text.localized(
                                          'Your workspace stays available offline after your first secure sign-in.',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (!showBrand) ...[
                                const SizedBox(height: 20),
                                OutlinedButton(
                                  onPressed: () => context.go('/explore'),
                                  child: const Text.localized(
                                    'Browse available homes',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(56, 44, 56, 48),
      decoration: const BoxDecoration(color: NyumbaColors.midnightNavy),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: context.nyumba.softIvory,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const NyumbaLogo(height: 44),
          ),
          const Spacer(),
          FadeSlideIn(
            delay: NyumbaMotion.stagger(1),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Text.localized(
                'Every property, payment and request in one calm workspace.',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontSize: 46,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          FadeSlideIn(
            delay: NyumbaMotion.stagger(2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Text.localized(
                'Built to keep landlords and tenants moving—even when the connection does not.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFDCE7F4),
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 34),
          FadeSlideIn(
            delay: NyumbaMotion.stagger(3),
            child: OutlinedButton.icon(
              onPressed: onExplore,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF8FA9C8)),
              ),
              icon: const Icon(Icons.apartment_outlined),
              label: const Text.localized('Browse available homes'),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.cloud_done_outlined, color: Color(0xFFBFD8C5)),
              const SizedBox(width: 10),
              Expanded(
                child: Text.localized(
                  'Local-first • Secure sync • Multi-platform',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFDCE7F4),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
