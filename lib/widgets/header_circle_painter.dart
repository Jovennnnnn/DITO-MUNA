import 'dart:math' as math;
import 'package:flutter/material.dart';

class HeaderCirclePainter extends CustomPainter {
  final double animationValue;
  HeaderCirclePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(20)
      ..style = PaintingStyle.fill;

    _drawCircle(canvas, Offset(size.width * 0.1, size.height * 0.2), 100 * (1 + 0.1 * math.sin(animationValue * 2 * math.pi)), paint);
    _drawCircle(canvas, Offset(size.width * 0.8, size.height * 0.8), 150 * (1 + 0.15 * math.cos(animationValue * 2 * math.pi)), paint);
    _drawCircle(canvas, Offset(size.width * 0.5, size.height * 0.4), 50 * (1 + 0.05 * math.sin(animationValue * 2 * math.pi + 1)), paint);
  }

  void _drawCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(HeaderCirclePainter oldDelegate) => true;
}
