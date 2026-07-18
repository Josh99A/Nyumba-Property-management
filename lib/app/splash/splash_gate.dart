import 'package:flutter/material.dart';

import '../../core/presentation/motion.dart';
import 'nyumba_splash_screen.dart';

/// Shows [NyumbaSplashScreen] over the app exactly once at launch, then fades
/// it away to reveal whatever the router has already built underneath.
///
/// The splash overlaps real startup work rather than adding a hard delay: the
/// app builds behind it the whole time. The hold is just long enough to let
/// the mark finish drawing before the cross-fade, and shrinks to a brief
/// moment under reduced motion.
class SplashGate extends StatefulWidget {
  const SplashGate({required this.child, super.key});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  static const _fadeDuration = Duration(milliseconds: 480);

  bool _fading = false;
  bool _done = false;
  bool _reduced = false;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    _reduced = NyumbaMotion.reducedMotion(context);
    // Let the mark's draw-in play out before dismissing; reduced motion gets a
    // token brand moment and an instant hand-off.
    final hold = _reduced
        ? const Duration(milliseconds: 350)
        : const Duration(milliseconds: 1650);
    Future<void>.delayed(hold, () {
      if (mounted) setState(() => _fading = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _fading,
            child: AnimatedOpacity(
              opacity: _fading ? 0 : 1,
              duration: _reduced ? Duration.zero : _fadeDuration,
              curve: NyumbaMotion.easeOut,
              onEnd: () {
                if (_fading && mounted) setState(() => _done = true);
              },
              child: const NyumbaSplashScreen(),
            ),
          ),
        ),
      ],
    );
  }
}
