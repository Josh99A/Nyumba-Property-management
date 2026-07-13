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
        NyumbaColors.midnightNavy,
        NyumbaColors.navyTint,
        const Color(0xFFC9D9EB),
      ),
      BadgeTone.success => (
        NyumbaColors.sageDark,
        NyumbaColors.sageTint,
        const Color(0xFFCDE4D2),
      ),
      BadgeTone.warning => (
        NyumbaColors.terracottaDark,
        NyumbaColors.goldTint,
        const Color(0xFFF0D5A7),
      ),
      BadgeTone.danger => (
        NyumbaColors.danger,
        NyumbaColors.dangerTint,
        const Color(0xFFF2C2B7),
      ),
      BadgeTone.neutral => (
        NyumbaColors.mutedInk,
        const Color(0xFFF4F5F7),
        NyumbaColors.outline,
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
