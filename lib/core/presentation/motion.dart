import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';

/// Shared motion vocabulary so every screen animates with the same calm,
/// unhurried character. All entrance helpers collapse to static widgets when
/// the platform requests reduced motion.
abstract final class NyumbaMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const entrance = Duration(milliseconds: 500);
  static const chart = Duration(milliseconds: 900);

  static const easeOut = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;

  /// Stagger step between sibling entrances.
  static const staggerStep = Duration(milliseconds: 60);

  static Duration stagger(int index, {int cap = 8}) =>
      staggerStep * index.clamp(0, cap);

  static bool reducedMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Fades and gently slides its child into place once, on first build.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    required this.child,
    super.key,
    this.delay = Duration.zero,
    this.duration = NyumbaMotion.entrance,
    this.offset = const Offset(0, .05),
    this.curve = NyumbaMotion.easeOut,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Fractional starting offset relative to the child's size.
  final Offset offset;
  final Curve curve;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (NyumbaMotion.reducedMotion(context)) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
      return;
    }
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(parent: _controller, curve: widget.curve);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.offset,
          end: Offset.zero,
        ).animate(animation),
        child: widget.child,
      ),
    );
  }
}

/// Counts a numeric value up from zero on first build, keeping the final
/// text identical to `format(value)`.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    required this.value,
    required this.format,
    super.key,
    this.duration = NyumbaMotion.chart,
    this.curve = NyumbaMotion.easeOut,
    this.style,
  });

  final num value;
  final String Function(num value) format;
  final Duration duration;
  final Curve curve;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (NyumbaMotion.reducedMotion(context)) {
      return Text(format(value), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: curve,
      builder: (context, animated, _) => Text(
        animated == value.toDouble() ? format(value) : format(animated),
        style: style,
      ),
    );
  }
}
