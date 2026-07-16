import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/operational_actions.dart';
import '../../../core/presentation/toast.dart';
import '../application/session_controller.dart';
import '../domain/auth_failure.dart';

/// Self-registration is for landlords: tenants are invited by their landlord
/// and prospective tenants browse without an account. After email
/// verification, the first sign-in lands on the onboarding screen, which runs
/// the server-authoritative landlord.onboard command.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _isGoogleSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .register(
            displayName: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
          );
      if (!mounted) return;
      await showNyumbaInfoDialog(
        context,
        title: 'Verify your email',
        message:
            'We sent a verification link to ${_emailController.text.trim()}. '
            'Open it, then sign in to finish setting up your workspace. '
            'Check your spam folder if it has not arrived in a few minutes.',
        icon: Icons.mark_email_read_outlined,
      );
      if (mounted) context.go('/sign-in');
      showNyumbaToast(
        'Account created. Verify your email to continue.',
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

  Future<void> _signUpWithGoogle() async {
    setState(() => _isGoogleSubmitting = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signInWithGoogle();
      // Google emails arrive verified; the router forwards the new session to
      // onboarding automatically.
    } on Object catch (error) {
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
    // Google hands back a credential long before the new account's profile
    // resolves, so the button stays busy until the session lands.
    final isResolving = ref.watch(sessionResolutionProvider).isResolving;
    final googleBusy = _isGoogleSubmitting || isResolving;
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: FadeSlideIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: NyumbaLogo(height: 44),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      'Create your landlord account',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Manage properties, tenants, and payments in one calm '
                      'workspace. Tenants are invited by their landlord and '
                      'do not need to register.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.nyumba.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) =>
                                (value?.trim().length ?? 0) < 2
                                ? 'Enter your name'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty || !email.contains('@')) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => (value?.length ?? 0) < 8
                                ? 'Use at least 8 characters'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              labelText: 'Confirm password',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                            validator: (value) =>
                                value != _passwordController.text
                                ? 'Passwords do not match'
                                : null,
                          ),
                          const SizedBox(height: 22),
                          FilledButton(
                            onPressed: _isSubmitting ? null : _submit,
                            child: _isSubmitting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Create account'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: googleBusy ? null : _signUpWithGoogle,
                            icon: googleBusy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.g_mobiledata_rounded,
                                    size: 26,
                                  ),
                            label: Text(
                              isResolving
                                  ? 'Setting up your account…'
                                  : 'Sign up with Google',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () => context.go('/sign-in'),
                      child: const Text('Already have an account? Sign in'),
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
