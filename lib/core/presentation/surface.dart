import 'package:flutter/material.dart';

import '../../app/theme/nyumba_colors.dart';

class NyumbaSurface extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: backgroundColor ?? NyumbaColors.surface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor ?? NyumbaColors.outline),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08123A6F),
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    );

    if (onTap == null) {
      return DecoratedBox(
        decoration: decoration,
        child: Padding(padding: padding, child: child),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(padding: padding, decoration: decoration, child: child),
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
