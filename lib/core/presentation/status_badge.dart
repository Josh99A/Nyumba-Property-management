import 'package:flutter/material.dart';

import '../../app/theme/nyumba_colors.dart';

enum BadgeTone { neutral, info, success, warning, danger }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    super.key,
    this.tone = BadgeTone.neutral,
    this.icon,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, border) = switch (tone) {
      BadgeTone.info => (
        context.nyumba.midnightNavy,
        context.nyumba.navyTint,
        context.nyumba.navyBorder,
      ),
      BadgeTone.success => (
        context.nyumba.sageDark,
        context.nyumba.sageTint,
        context.nyumba.sageBorder,
      ),
      BadgeTone.warning => (
        context.nyumba.terracottaDark,
        context.nyumba.goldTint,
        context.nyumba.goldBorder,
      ),
      BadgeTone.danger => (
        context.nyumba.danger,
        context.nyumba.dangerTint,
        context.nyumba.dangerBorder,
      ),
      BadgeTone.neutral => (
        context.nyumba.mutedInk,
        context.nyumba.neutralTint,
        context.nyumba.outline,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
