import 'package:flutter/material.dart';

import '../../core/presentation/motion.dart';
import '../theme/nyumba_colors.dart';
import 'nyumba_loading_indicator.dart';

/// Full-screen brand splash shown while the app settles on launch.
///
/// It reuses the app's own scaffold background so the hand-off to the first
/// real screen is a quiet cross-fade rather than a colour flip. The logo is
/// the real brand asset (guaranteeing an exact match) resting on an ivory
/// plate, and the loading dots give the wait a sense of progress instead of a
/// frozen logo.
class NyumbaSplashScreen extends StatelessWidget {
  const NyumbaSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.nyumba;

    return Material(
      color: palette.softIvory,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _LogoReveal(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 26,
                  ),
                  decoration: BoxDecoration(
                    // The brand asset carries its own ivory background, so the
                    // plate is ivory too: invisible on the light splash, and a
                    // clean framed logo on the dark one.
                    color: NyumbaColors.softIvory,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: NyumbaColors.midnightNavy.withValues(alpha: 0.10),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/branding/nyumba-stacked.png',
                    width: 236,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 52,
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 620),
                offset: Offset.zero,
                child: const Center(child: NyumbaLoadingIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades and gently scales its child in once, on first build. Collapses to a
/// static child under reduced motion.
class _LogoReveal extends StatelessWidget {
  const _LogoReveal({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (NyumbaMotion.reducedMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: NyumbaMotion.slow,
      curve: NyumbaMotion.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
      child: child,
    );
  }
}
