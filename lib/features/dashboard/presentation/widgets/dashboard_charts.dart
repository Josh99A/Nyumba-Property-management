import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../app/theme/nyumba_colors.dart';
import '../../../../core/presentation/motion.dart';

class OccupancyRing extends StatelessWidget {
  const OccupancyRing({required this.rate, super.key, this.size = 184});

  final double rate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final percentage = (rate * 100).round();
    final palette = context.nyumba;
    return Semantics(
      label: '$percentage percent of units are occupied',
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          begin: NyumbaMotion.reducedMotion(context) ? rate : 0,
          end: rate,
        ),
        duration: NyumbaMotion.chart,
        curve: NyumbaMotion.easeOut,
        builder: (context, animatedRate, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _OccupancyPainter(
              rate: animatedRate,
              trackColor: palette.divider,
              gradientColors: [palette.sageGreen, palette.sageDark],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(animatedRate * 100).round()}%',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
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

    final labels = _monthLabels();
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < labels.length; i++) {
      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(fontSize: 10, color: labelColor),
      );
      textPainter.layout();
      final x = chart.left + chart.width * i / (labels.length - 1);
      textPainter.paint(
        canvas,
        Offset(
          (x - textPainter.width / 2).clamp(0, size.width - textPainter.width),
          size.height - 16,
        ),
      );
    }
  }

  List<String> _monthLabels() {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final format = DateFormat('d MMM');
    return [
      for (final day in [1, 8, 15, 22, lastDay])
        format.format(DateTime(now.year, now.month, day)),
    ];
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
