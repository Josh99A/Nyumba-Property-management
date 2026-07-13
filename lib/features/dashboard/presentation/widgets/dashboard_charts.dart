import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/nyumba_colors.dart';

class OccupancyRing extends StatelessWidget {
  const OccupancyRing({required this.rate, super.key, this.size = 184});

  final double rate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final percentage = (rate * 100).round();
    return Semantics(
      label: '$percentage percent of units are occupied',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _OccupancyPainter(rate: rate),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$percentage%',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: NyumbaColors.sageDark,
                    fontSize: size * .24,
                  ),
                ),
                Text('Occupied', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OccupancyPainter extends CustomPainter {
  const _OccupancyPainter({required this.rate});

  final double rate;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * .13;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final background = Paint()
      ..color = const Color(0xFFE8E9E7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final foreground = Paint()
      ..shader = const LinearGradient(
        colors: [NyumbaColors.sageGreen, NyumbaColors.sageDark],
      ).createShader(rect)
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
      oldDelegate.rate != rate;
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
    return Semantics(
      label: 'Monthly rent collection trend',
      child: SizedBox(
        height: 154,
        child: CustomPaint(
          painter: _TrendPainter(
            collected: collected,
            outstanding: outstanding,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.collected, required this.outstanding});

  final List<double> collected;
  final List<double> outstanding;

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
      ..color = const Color(0xFFE9E7E1)
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
        ..color = NyumbaColors.sageDark
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
        ..color = NyumbaColors.terracottaGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
      dashed: true,
    );

    final labels = ['1 May', '8 May', '15 May', '22 May', '31 May'];
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < labels.length; i++) {
      textPainter.text = TextSpan(
        text: labels[i],
        style: const TextStyle(fontSize: 10, color: NyumbaColors.mutedInk),
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
    if (!dashed) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
      return;
    }
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      final delta = end - start;
      final distance = delta.distance;
      final direction = delta / distance;
      var travelled = 0.0;
      while (travelled < distance) {
        final dashEnd = math.min(travelled + 5, distance);
        canvas.drawLine(
          start + direction * travelled,
          start + direction * dashEnd,
          paint,
        );
        travelled += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.collected != collected ||
      oldDelegate.outstanding != outstanding;
}
