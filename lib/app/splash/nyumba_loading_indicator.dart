import 'package:flutter/material.dart';

import '../../core/presentation/motion.dart';
import '../theme/nyumba_colors.dart';

/// A calm, brand-tinted loading affordance: three dots that rise and brighten
/// in a continuous wave. The dot colors echo the checklist bullets in the
/// Nyumba mark (sage, navy, gold), so it reads as part of the same family
/// rather than a generic spinner.
///
/// Collapses to three static dots when the platform requests reduced motion,
/// so it never becomes a source of vestibular discomfort.
class NyumbaLoadingIndicator extends StatefulWidget {
  const NyumbaLoadingIndicator({
    super.key,
    this.size = 9,
    this.gap = 7,
    this.color,
  });

  /// Diameter of each dot at its resting size.
  final double size;

  /// Space between dots.
  final double gap;

  /// When set, every dot uses this single color. When null, the three dots
  /// cycle through the brand palette (sage, navy, gold).
  final Color? color;

  @override
  State<NyumbaLoadingIndicator> createState() => _NyumbaLoadingIndicatorState();
}

class _NyumbaLoadingIndicatorState extends State<NyumbaLoadingIndicator>
    with SingleTickerProviderStateMixin {
  static const _dotCount = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    // A static row of dots still signals "working" without any motion.
    if (!NyumbaMotion.reducedMotion(context)) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> get _palette {
    final color = widget.color;
    if (color != null) return List.filled(_dotCount, color);
    return const [
      NyumbaColors.sageGreen,
      NyumbaColors.midnightNavy,
      NyumbaColors.terracottaGold,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final reduced = NyumbaMotion.reducedMotion(context);
    return SizedBox(
      height: widget.size * 1.8,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _dotCount; i++) ...[
                if (i > 0) SizedBox(width: widget.gap),
                _Dot(
                  color: palette[i],
                  size: widget.size,
                  // Each dot trails the previous by a third of the cycle,
                  // producing a smooth left-to-right wave.
                  value: reduced
                      ? 0.5
                      : _phased(_controller.value, i / _dotCount),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Shifts [t] by [offset] and wraps into 0..1.
  double _phased(double t, double offset) => (t + offset) % 1.0;
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size, required this.value});

  final Color color;
  final double size;

  /// Position within this dot's own cycle, 0..1.
  final double value;

  @override
  Widget build(BuildContext context) {
    // A single smooth swell: eased up to the midpoint, eased back down.
    final swell = Curves.easeInOut.transform(
      value < 0.5 ? value * 2 : (1 - value) * 2,
    );
    final scale = 0.62 + 0.38 * swell;
    final opacity = 0.4 + 0.6 * swell;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
