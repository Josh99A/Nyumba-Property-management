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
    // The "document under a roof" brand mark, matching the app icon: a navy
    // roof with a chimney and gable window over a sage checklist document with
    // a gold folded corner. Geometry is sampled from the production icon and
    // expressed in image-permille coordinates (0..1000), then mapped into this
    // square with a small margin. Colours are theme-aware (see build()), so the
    // document "paper" is simply the surface showing through rather than a
    // baked-in ivory canvas.
    final w = size.width;
    const sc = 0.90 / 550.0; // permille (of the source icon) -> box fraction
    double px(double x) => w * (0.5 + (x - 500) * sc);
    double py(double y) => w * (0.05 + (y - 205) * sc);
    double sw(double d) => w * d * sc; // a permille stroke width -> pixels

    // Document paper: left edge + rounded bottom (an L), plus a short right
    // edge. Drawn first so the roof overhangs it.
    final docPaint = Paint()
      ..color = sage
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw(30)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(px(330), py(445))
        ..lineTo(px(330), py(712))
        ..quadraticBezierTo(px(330), py(732), px(360), py(732))
        ..lineTo(px(545), py(732)),
      docPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(px(685), py(445))
        ..lineTo(px(685), py(618)),
      docPaint,
    );

    // Checklist: three sage bullets, each with a line.
    final linePaint = Paint()
      ..color = sage
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw(22)
      ..strokeCap = StrokeCap.round;
    final bulletPaint = Paint()..color = sage;
    const rowYs = [505.0, 570.0, 632.0];
    const lineEnds = [605.0, 605.0, 555.0];
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(px(405), py(rowYs[i])), sw(15), bulletPaint);
      canvas.drawLine(
        Offset(px(450), py(rowYs[i])),
        Offset(px(lineEnds[i]), py(rowYs[i])),
        linePaint,
      );
    }

    // Gold folded corner at the document's bottom-right.
    canvas.drawPath(
      Path()
        ..moveTo(px(585), py(640))
        ..lineTo(px(700), py(640))
        ..lineTo(px(585), py(750))
        ..close(),
      Paint()..color = gold,
    );

    // Navy roof band, overhanging the paper.
    final roofPaint = Paint()
      ..color = navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw(80)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(px(285), py(412))
        ..lineTo(px(500), py(225))
        ..lineTo(px(712), py(407)),
      roofPaint,
    );

    // Chimney on the right slope.
    final navyFill = Paint()..color = navy;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(px(628), py(272), px(672), py(360)),
        topLeft: Radius.circular(sw(6)),
        topRight: Radius.circular(sw(6)),
      ),
      navyFill,
    );

    // 2x2 window in the gable.
    void pane(double x, double y) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(px(x), py(y), px(x + 30), py(y + 33)),
        Radius.circular(sw(4)),
      ),
      navyFill,
    );
    pane(460, 357);
    pane(505, 357);
    pane(460, 410);
    pane(505, 410);
  }

  @override
  bool shouldRepaint(covariant _NyumbaMarkPainter oldDelegate) =>
      oldDelegate.navy != navy ||
      oldDelegate.sage != sage ||
      oldDelegate.gold != gold;
}
