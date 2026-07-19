import 'package:flutter/material.dart';

import '../theme/nyumba_colors.dart';
import 'nyumba_loading_indicator.dart';

/// Full-screen brand splash shown while the app settles on launch.
///
/// It paints in its *settled* state — no entrance animation on the logo or the
/// dots — so it continues seamlessly from whatever preceded it (the HTML boot
/// splash on web, the OS launch window on mobile) with no re-animation flicker
/// at the hand-off. The only motion is the looping loading dots. It reuses the
/// app's own scaffold background so the eventual hand-off to the first screen
/// is a quiet cross-fade rather than a colour flip.
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
            const Positioned(
              left: 0,
              right: 0,
              bottom: 52,
              child: Center(child: NyumbaLoadingIndicator()),
            ),
          ],
        ),
      ),
    );
  }
}
