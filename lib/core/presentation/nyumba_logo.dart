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
                  Text(
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
                  Text(
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
    final stroke = size.width * .09;
    final roofPaint = Paint()
      ..color = navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round;
    final bodyPaint = Paint()
      ..color = sage
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * .78
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(size.width * .12, size.height * .43)
        ..lineTo(size.width * .5, size.height * .12)
        ..lineTo(size.width * .88, size.height * .43),
      roofPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .24, size.height * .43)
        ..lineTo(size.width * .24, size.height * .82)
        ..quadraticBezierTo(
          size.width * .24,
          size.height * .9,
          size.width * .33,
          size.height * .9,
        )
        ..lineTo(size.width * .72, size.height * .9)
        ..moveTo(size.width * .76, size.height * .43)
        ..lineTo(size.width * .76, size.height * .72),
      bodyPaint,
    );

    final detailPaint = Paint()
      ..color = sage
      ..strokeWidth = stroke * .62
      ..strokeCap = StrokeCap.round;
    for (final y in [.55, .68, .81]) {
      canvas.drawCircle(
        Offset(size.width * .37, size.height * y),
        stroke * .34,
        detailPaint,
      );
      canvas.drawLine(
        Offset(size.width * .48, size.height * y),
        Offset(size.width * (y == .81 ? .62 : .68), size.height * y),
        detailPaint,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .66, size.height * .73)
        ..lineTo(size.width * .82, size.height * .73)
        ..lineTo(size.width * .66, size.height * .9)
        ..close(),
      Paint()..color = gold,
    );
  }

  @override
  bool shouldRepaint(covariant _NyumbaMarkPainter oldDelegate) =>
      oldDelegate.navy != navy ||
      oldDelegate.sage != sage ||
      oldDelegate.gold != gold;
}
