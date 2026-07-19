import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';

import '../../app/theme/nyumba_colors.dart';

/// A theme-aware, code-native brand lockup.
///
/// The previous raster logo included a fixed ivory canvas, which looked like a
/// pale rectangle on dark surfaces. This mark keeps the approved brand colors
/// while allowing its typography and contrast to follow the active theme.
class NyumbaLogo extends StatelessWidget {
  const NyumbaLogo({super.key, this.compact = false, this.height});

  final bool compact;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final resolvedHeight = height ?? (compact ? 42 : 56);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navy = isDark
        ? context.nyumba.midnightNavy
        : NyumbaColors.midnightNavy;
    final sage = isDark ? context.nyumba.sageDark : NyumbaColors.sageGreen;
    final gold = isDark
        ? context.nyumba.terracottaGold
        : NyumbaColors.terracottaGold;

    return Semantics(
      image: true,
      label: context.tr('Nyumba Property Management'),
      child: SizedBox(
        height: resolvedHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: Size.square(resolvedHeight),
              painter: _NyumbaMarkPainter(navy: navy, sage: sage, gold: gold),
            ),
            if (!compact) ...[
              SizedBox(width: resolvedHeight * .16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.localized(
                    'Nyumba',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: navy,
                      fontSize: resolvedHeight * .47,
                      fontWeight: FontWeight.w800,
                      height: .95,
                      letterSpacing: -0.6,
                    ),
                  ),
                  SizedBox(height: resolvedHeight * .08),
                  Text.localized(
                    'PROPERTY MANAGEMENT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: sage,
                      fontSize: resolvedHeight * .13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: resolvedHeight * .025,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NyumbaMarkPainter extends CustomPainter {
  const _NyumbaMarkPainter({
    required this.navy,
    required this.sage,
    required this.gold,
  });

  final Color navy;
  final Color sage;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    // A simple house: navy roof, sage walls, gold door. Fewer shapes than the
    // previous "document under a roof" mark, so it still reads as a home at
    // app-bar sizes instead of dissolving into clutter.
    final stroke = size.width * .09;
    final roofPaint = Paint()
      ..color = navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final wallPaint = Paint()
      ..color = sage
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * .82
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Walls with a rounded floor line, drawn first so the roof overhangs them.
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .22, size.height * .46)
        ..lineTo(size.width * .22, size.height * .8)
        ..quadraticBezierTo(
          size.width * .22,
          size.height * .9,
          size.width * .32,
          size.height * .9,
        )
        ..lineTo(size.width * .68, size.height * .9)
        ..quadraticBezierTo(
          size.width * .78,
          size.height * .9,
          size.width * .78,
          size.height * .8,
        )
        ..lineTo(size.width * .78, size.height * .46),
      wallPaint,
    );

    // Roof with a slight overhang past the walls.
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .1, size.height * .46)
        ..lineTo(size.width * .5, size.height * .12)
        ..lineTo(size.width * .9, size.height * .46),
      roofPaint,
    );

    // Gold door, the single warm accent.
    final doorWidth = size.width * .18;
    final doorHeight = size.height * .3;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(
          size.width * .5 - doorWidth / 2,
          size.height * .9 - doorHeight + stroke * .41,
          doorWidth,
          doorHeight,
        ),
        topLeft: Radius.circular(doorWidth * .5),
        topRight: Radius.circular(doorWidth * .5),
      ),
      Paint()..color = gold,
    );
  }

  @override
  bool shouldRepaint(covariant _NyumbaMarkPainter oldDelegate) =>
      oldDelegate.navy != navy ||
      oldDelegate.sage != sage ||
      oldDelegate.gold != gold;
}
