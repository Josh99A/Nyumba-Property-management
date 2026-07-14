import 'package:flutter/material.dart';

class NyumbaLogo extends StatelessWidget {
  const NyumbaLogo({super.key, this.compact = false, this.height});

  final bool compact;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final resolvedHeight = height ?? (compact ? 42 : 56);
    // The logo asset carries its own ivory background, so it is clipped into
    // a soft badge that stays legible on dark surfaces.
    return Semantics(
      image: true,
      label: 'Nyumba Property Management',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(resolvedHeight * .18),
        child: Image.asset(
          compact
              ? 'assets/branding/nyumba-app-icon.png'
              : 'assets/branding/nyumba-horizontal.png',
          height: resolvedHeight,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => SizedBox(
            height: resolvedHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.home_work_outlined, size: resolvedHeight * .72),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Text('Nyumba', style: Theme.of(context).textTheme.titleLarge),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
