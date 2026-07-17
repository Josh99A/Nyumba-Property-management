import 'package:flutter/material.dart';

/// The standard four-color Google "G" used beside Google authentication.
///
/// The paths use Google's 18x18 logo geometry and scale without a raster asset,
/// keeping the mark sharp on every platform and display density.
class GoogleGLogo extends StatelessWidget {
  const GoogleGLogo({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: const _GoogleGLogoPainter(),
      ),
    );
  }
}

class _GoogleGLogoPainter extends CustomPainter {
  const _GoogleGLogoPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 18, size.height / 18);

    _draw(
      canvas,
      Path()
        ..moveTo(17.64, 9.2045)
        ..relativeCubicTo(0, -.638, -.0573, -1.2518, -.1636, -1.8409)
        ..lineTo(9, 7.3636)
        ..relativeLineTo(0, 3.4818)
        ..relativeLineTo(4.8436, 0)
        ..relativeCubicTo(-.2086, 1.125, -.8427, 2.0782, -1.7964, 2.7164)
        ..relativeLineTo(0, 2.2582)
        ..relativeLineTo(2.9091, 0)
        ..relativeCubicTo(1.7027, -1.5673, 2.6837, -3.8741, 2.6837, -6.6155)
        ..close(),
      _blue,
    );
    _draw(
      canvas,
      Path()
        ..moveTo(9, 18)
        ..relativeCubicTo(2.43, 0, 4.4673, -.8064, 5.9564, -2.18)
        ..relativeLineTo(-2.9091, -2.2582)
        ..relativeCubicTo(-.8064, .54, -1.8364, .8591, -3.0473, .8591)
        ..relativeCubicTo(-2.3441, 0, -4.3286, -1.5845, -5.0364, -3.7104)
        ..lineTo(.9564, 10.7105)
        ..relativeLineTo(0, 2.3327)
        ..cubicTo(2.4373, 15.9836, 5.4818, 18, 9, 18)
        ..close(),
      _green,
    );
    _draw(
      canvas,
      Path()
        ..moveTo(3.9636, 10.7105)
        ..relativeCubicTo(-.18, -.54, -.2827, -1.1168, -.2827, -1.7105)
        ..cubicTo(3.6809, 8.4063, 3.7836, 7.8295, 3.9636, 7.2895)
        ..lineTo(3.9636, 4.9568)
        ..lineTo(.9564, 4.9568)
        ..cubicTo(.3473, 6.1732, 0, 7.5491, 0, 9)
        ..cubicTo(0, 10.4509, .3473, 11.8268, .9564, 13.0432)
        ..relativeLineTo(3.0072, -2.3327)
        ..close(),
      _yellow,
    );
    _draw(
      canvas,
      Path()
        ..moveTo(9, 3.5791)
        ..relativeCubicTo(1.3214, 0, 2.5077, .4541, 3.4427, 1.3459)
        ..relativeLineTo(2.5814, -2.5814)
        ..cubicTo(13.4636, .8918, 11.4264, 0, 9, 0)
        ..cubicTo(5.4818, 0, 2.4373, 2.0164, .9564, 4.9568)
        ..relativeLineTo(3.0073, 2.3327)
        ..cubicTo(4.6714, 5.1636, 6.6559, 3.5791, 9, 3.5791)
        ..close(),
      _red,
    );

    canvas.restore();
  }

  void _draw(Canvas canvas, Path path, Color color) {
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GoogleGLogoPainter oldDelegate) => false;
}
