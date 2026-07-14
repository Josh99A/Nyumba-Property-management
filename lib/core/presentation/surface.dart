import 'package:flutter/material.dart';

import '../../app/theme/nyumba_colors.dart';
import 'motion.dart';

class NyumbaSurface extends StatefulWidget {
  const NyumbaSurface({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(20),
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 12,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  State<NyumbaSurface> createState() => _NyumbaSurfaceState();
}

class _NyumbaSurfaceState extends State<NyumbaSurface> {
  bool _hovered = false;
  bool _pressed = false;

  BoxDecoration _decoration({required bool lifted}) => BoxDecoration(
    color: widget.backgroundColor ?? context.nyumba.surface,
    borderRadius: BorderRadius.circular(widget.borderRadius),
    border: Border.all(
      color: lifted
          ? context.nyumba.navyBorder
          : widget.borderColor ?? context.nyumba.outline,
    ),
    boxShadow: [
      BoxShadow(
        color: lifted ? const Color(0x14123A6F) : const Color(0x08123A6F),
        blurRadius: lifted ? 22 : 16,
        offset: Offset(0, lifted ? 8 : 5),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return DecoratedBox(
        decoration: _decoration(lifted: false),
        child: Padding(padding: widget.padding, child: widget.child),
      );
    }

    final animate = !NyumbaMotion.reducedMotion(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: animate && _pressed ? .985 : 1,
        duration: NyumbaMotion.fast,
        curve: NyumbaMotion.easeOut,
        child: AnimatedContainer(
          duration: animate ? NyumbaMotion.medium : Duration.zero,
          curve: NyumbaMotion.easeOut,
          decoration: _decoration(lifted: _hovered && animate),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

class NyumbaSectionHeader extends StatelessWidget {
  const NyumbaSectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}
