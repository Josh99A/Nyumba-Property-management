import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/presentation/motion.dart';

/// X-axis labels for a monthly series ending at [now]'s month.
///
/// The series is plotted oldest-to-newest, so index 0 is `monthCount - 1`
/// months ago. Up to five labels are placed at the fraction of the axis where
/// their data point actually sits — the axis previously showed days of the
/// current month under a ten-month series, which read as a lie about what the
/// line meant.
@visibleForTesting
List<({double position, String label})> monthAxisLabels(
  int monthCount,
  DateTime now,
) {
  if (monthCount <= 0) return const [];
  final format = DateFormat('MMM');
  String monthAt(int index) =>
      format.format(DateTime(now.year, now.month - (monthCount - 1 - index)));
  if (monthCount == 1) return [(position: 0.5, label: monthAt(0))];

  final last = monthCount - 1;
  final indices = <int>{
    0,
    (last * 0.25).round(),
    (last * 0.5).round(),
    (last * 0.75).round(),
    last,
  }.toList()..sort();
  return [
    for (final index in indices)
      (position: index / last, label: monthAt(index)),
  ];
}

class OccupancyRing extends StatelessWidget {
  const OccupancyRing({required this.rate, super.key, this.size = 184});

  final double rate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final percentage = (rate * 100).round();
    final palette = context.nyumba;
    // The reading inside the ring takes its size from the ring, so the system
    // text scale would otherwise apply twice and push the label out of the
    // circle. Grow the graphic with the reader's scale instead, and keep the
    // label within the ring's inner square.
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    final dimension = size * textScale;
    return Semantics(
      label: '$percentage percent of rental spaces are occupied',
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          begin: NyumbaMotion.reducedMotion(context) ? rate : 0,
          end: rate,
        ),
        duration: NyumbaMotion.chart,
        curve: NyumbaMotion.easeOut,
        builder: (context, animatedRate, _) => SizedBox.square(
          dimension: dimension,
          child: CustomPaint(
            painter: _OccupancyPainter(
              rate: animatedRate,
              trackColor: palette.divider,
              gradientColors: [palette.sageGreen, palette.sageDark],
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(dimension * .2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(animatedRate * 100).round()}%',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: palette.sageDark,
                              fontSize: size * .24,
                            ),
                      ),
                      Text(
                        'Occupied',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OccupancyPainter extends CustomPainter {
  const _OccupancyPainter({
    required this.rate,
    required this.trackColor,
    required this.gradientColors,
  });

  final double rate;
  final Color trackColor;
  final List<Color> gradientColors;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * .13;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final background = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final foreground = Paint()
      ..shader = LinearGradient(colors: gradientColors).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2, false, background);
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * rate.clamp(0, 1),
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(covariant _OccupancyPainter oldDelegate) =>
      oldDelegate.rate != rate ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.gradientColors != gradientColors;
}

class RentTrendChart extends StatelessWidget {
  const RentTrendChart({
    required this.collected,
    required this.outstanding,
    super.key,
  });

  final List<double> collected;
  final List<double> outstanding;

  @override
  Widget build(BuildContext context) {
    final palette = context.nyumba;
    return Semantics(
      label: 'Monthly rent collection trend',
      child: SizedBox(
        height: 154,
        child: TweenAnimationBuilder<double>(
          tween: Tween(
            begin: NyumbaMotion.reducedMotion(context) ? 1 : 0,
            end: 1,
          ),
          duration: NyumbaMotion.chart,
          curve: NyumbaMotion.easeOut,
          builder: (context, progress, _) => CustomPaint(
            painter: _TrendPainter(
              collected: collected,
              outstanding: outstanding,
              progress: progress,
              collectedColor: palette.sageDark,
              outstandingColor: palette.terracottaGold,
              gridColor: palette.divider,
              labelColor: palette.mutedInk,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.collected,
    required this.outstanding,
    required this.collectedColor,
    required this.outstandingColor,
    required this.gridColor,
    required this.labelColor,
    this.progress = 1,
  });

  final List<double> collected;
  final List<double> outstanding;
  final Color collectedColor;
  final Color outstandingColor;
  final Color gridColor;
  final Color labelColor;

  /// Fraction of each line's length drawn, animating the chart in.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const top = 8.0;
    const right = 8.0;
    const bottom = 22.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + (chart.height * i / 3);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    _drawLine(
      canvas,
      chart,
      collected,
      Paint()
        ..color = collectedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    _drawLine(
      canvas,
      chart,
      outstanding,
      Paint()
        ..color = outstandingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
      dashed: true,
    );

    final labels = monthAxisLabels(collected.length, DateTime.now());
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (final entry in labels) {
      textPainter.text = TextSpan(
        text: entry.label,
        style: TextStyle(fontSize: 10, color: labelColor),
      );
      textPainter.layout();
      final x = chart.left + chart.width * entry.position;
      textPainter.paint(
        canvas,
        Offset(
          (x - textPainter.width / 2).clamp(0, size.width - textPainter.width),
          size.height - 16,
        ),
      );
    }
  }

  void _drawLine(
    Canvas canvas,
    Rect chart,
    List<double> values,
    Paint paint, {
    bool dashed = false,
  }) {
    if (values.length < 2) return;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      points.add(
        Offset(
          chart.left + chart.width * i / (values.length - 1),
          chart.bottom - chart.height * values[i].clamp(0, 1),
        ),
      );
    }
    final fullPath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      fullPath.lineTo(point.dx, point.dy);
    }
    final path = progress >= 1 ? fullPath : _partialPath(fullPath);

    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      var travelled = 0.0;
      while (travelled < metric.length) {
        final dashEnd = math.min(travelled + 5, metric.length);
        canvas.drawPath(metric.extractPath(travelled, dashEnd), paint);
        travelled += 9;
      }
    }
  }

  Path _partialPath(Path fullPath) {
    final result = Path();
    for (final ui.PathMetric metric in fullPath.computeMetrics()) {
      result.addPath(
        metric.extractPath(0, metric.length * progress.clamp(0, 1)),
        Offset.zero,
      );
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.collected != collected ||
      oldDelegate.outstanding != outstanding ||
      oldDelegate.progress != progress ||
      oldDelegate.collectedColor != collectedColor ||
      oldDelegate.outstandingColor != outstandingColor;
}
