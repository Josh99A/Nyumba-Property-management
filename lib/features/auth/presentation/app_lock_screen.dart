import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/nyumba_colors.dart';
import '../../../core/presentation/nyumba_logo.dart';
import '../../../core/presentation/toast.dart';
import '../application/app_lock_controller.dart';
import '../application/session_controller.dart';
import '../domain/biometric_authenticator.dart';

/// Full-screen cover shown while the app lock is engaged.
///
/// Deliberately a plain overlay rather than a route: routes can be reached
/// around (deep links, back navigation, state restoration), while a widget
/// painted above the whole Navigator cannot.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  String? _message;

  @override
  void initState() {
    super.initState();
    // The screen only exists while locked, so mounting it is the moment to
    // raise the OS prompt — no extra tap needed on the happy path.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    final copy = context.l10n;
    final outcome = await ref
        .read(appLockControllerProvider.notifier)
        .unlock(copy.text('Unlock Nyumba'));
    if (!mounted) return;
    switch (outcome) {
      case BiometricOutcome.success || BiometricOutcome.dismissed:
        setState(() => _message = null);
      case BiometricOutcome.unavailable:
        showNyumbaToast(
          'Fingerprint is no longer set up on this device, so app lock was turned off.',
        );
      case BiometricOutcome.failure:
        setState(
          () => _message =
              'We could not confirm your fingerprint. Try again in a moment.',
        );
    }
  }

  Future<void> _signOut() =>
      ref.read(sessionControllerProvider.notifier).signOut();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlocking = ref.watch(
      appLockControllerProvider.select((lock) => lock.unlocking),
    );
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NyumbaLogo(height: 52),
                const SizedBox(height: 48),
                Icon(
                  Icons.fingerprint_rounded,
                  size: 64,
                  color: context.nyumba.mutedInk,
                ),
                const SizedBox(height: 18),
                Text.localized(
                  'Nyumba is locked',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text.localized(
                  'Unlock with your fingerprint to continue.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.nyumba.mutedInk,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Text.localized(
                    _message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.nyumba.danger,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: unlocking ? null : _unlock,
                  icon: unlocking
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint_rounded),
                  label: Text.localized(unlocking ? 'Unlocking…' : 'Unlock'),
                ),
                const SizedBox(height: 10),
                // Escape hatch for a permanently failing sensor: back to the
                // sign-in screen, where the password still works.
                TextButton(
                  onPressed: _signOut,
                  child: const Text.localized('Sign out instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
