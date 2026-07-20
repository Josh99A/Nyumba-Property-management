import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/toast.dart';
import '../application/app_lock_controller.dart';
import '../application/session_controller.dart';
import '../domain/user_session.dart';
import 'app_lock_screen.dart';

/// Paints [AppLockScreen] over the entire app while the biometric lock is
/// engaged, and feeds app-lifecycle changes to the lock controller.
///
/// Sits inside the `MaterialApp.builder`, above the router's Navigator, so no
/// navigation — deep link, back gesture, restoration — can surface workspace
/// content while locked. Anonymous browsing of public listings is never
/// gated: the lock protects a signed-in workspace, not the marketplace.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLockControllerProvider.notifier).handleLifecycle(state);
  }

  Future<void> _maybeOffer() async {
    final controller = ref.read(appLockControllerProvider.notifier);
    if (!await controller.shouldOffer()) return;
    if (!mounted) return;
    final copy = context.l10n;
    showNyumbaToast(
      'Protect your workspace with fingerprint unlock.',
      action: SnackBarAction(
        label: copy.text('Enable'),
        onPressed: () async {
          final enabled = await controller.enable(
            copy.text('Confirm your fingerprint to turn on app lock.'),
          );
          showNyumbaToast(
            enabled
                ? 'App lock is on. Nyumba will ask for your fingerprint when you return.'
                : 'Fingerprint unlock was not turned on.',
            variant: enabled
                ? NyumbaToastVariant.success
                : NyumbaToastVariant.info,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UserSession?>(sessionControllerProvider, (previous, next) {
      if (next == null) {
        // The sign-in that follows is itself proof of identity; a lock kept
        // engaged here would cover the sign-in form.
        ref.read(appLockControllerProvider.notifier).handleSignedOut();
        return;
      }
      if (!next.isAnonymous && previous?.userId != next.userId) {
        _maybeOffer();
      }
    });

    final lock = ref.watch(appLockControllerProvider);
    final session = ref.watch(sessionControllerProvider);
    final covered =
        lock.enabled && lock.locked && session != null && !session.isAnonymous;

    return Stack(
      children: [
        // The overlay stops pointers, but screen readers and keyboard Tab
        // traversal walk the widget tree, not the paint order — the covered
        // workspace must leave the semantics tree and focus scope too.
        ExcludeSemantics(
          excluding: covered,
          child: ExcludeFocus(excluding: covered, child: widget.child),
        ),
        if (covered) const Positioned.fill(child: AppLockScreen()),
      ],
    );
  }
}
