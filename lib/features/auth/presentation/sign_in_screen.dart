import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/motion.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/operational_actions.dart';
import '../application/session_controller.dart';
import '../domain/user_session.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'joshua@demo.nyumba.ug');
  final _passwordController = TextEditingController(text: 'password');
  bool _obscurePassword = true;
  bool _isSubmitting = false;

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
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _startDemo(AppRole role) {
    ref.read(sessionControllerProvider.notifier).startDemo(role);
  }

  @override
  Widget build(BuildContext context) {
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
                              if (!showBrand) ...[
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: NyumbaLogo(height: 48),
                                ),
                                const SizedBox(height: 46),
                              ],
                              Text(
                                'Welcome back',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineLarge,
                              ),
                              const SizedBox(height: 10),
                              Text(
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
                                    Text(
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
                                      decoration: const InputDecoration(
                                        hintText: 'you@example.com',
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
                                          child: Text(
                                            'Password',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelLarge,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => showNyumbaInfoDialog(
                                            context,
                                            title: 'Password reset',
                                            message:
                                                'Demo accounts do not use real passwords. '
                                                'For production accounts, Firebase must be '
                                                'configured before a reset email can be sent. '
                                                'No email has been sent from this demo.',
                                            icon: Icons.lock_reset_rounded,
                                          ),
                                          child: const Text('Forgot password?'),
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
                                        hintText: 'Enter your password',
                                        prefixIcon: const Icon(
                                          Icons.lock_outline_rounded,
                                        ),
                                        suffixIcon: IconButton(
                                          tooltip: _obscurePassword
                                              ? 'Show password'
                                              : 'Hide password',
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
                                      onPressed: _isSubmitting ? null : _submit,
                                      child: _isSubmitting
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('Sign in'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),
                              const _DividerLabel(
                                label: 'Explore the role demos',
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _DemoButton(
                                    label: 'Landlord',
                                    icon: Icons.home_work_outlined,
                                    onPressed: () =>
                                        _startDemo(AppRole.landlord),
                                  ),
                                  _DemoButton(
                                    label: 'Tenant',
                                    icon: Icons.person_outline_rounded,
                                    onPressed: () => _startDemo(AppRole.tenant),
                                  ),
                                  _DemoButton(
                                    label: 'Admin',
                                    icon: Icons.admin_panel_settings_outlined,
                                    onPressed: () => _startDemo(AppRole.admin),
                                  ),
                                ],
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
                                        child: Text(
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
                                  child: const Text('Browse available homes'),
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
      padding: const EdgeInsets.fromLTRB(56, 44, 56, 48),
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
              child: Text(
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
              child: Text(
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
              label: const Text('Browse available homes'),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.cloud_done_outlined, color: Color(0xFFBFD8C5)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
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

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 320) {
          return Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return Row(
          children: [
            const Expanded(child: Divider()),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        );
      },
    );
  }
}

class _DemoButton extends StatelessWidget {
  const _DemoButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
  }
}
