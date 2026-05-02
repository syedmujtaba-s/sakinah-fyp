import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Tiled 8-point Islamic star pattern. Light, decorative, code-drawn so it
/// scales crisply on every density. Used as a faint atmospheric layer behind
/// the dashboard hero card.
class GeometricPatternPainter extends CustomPainter {
  final Color color;
  final double tile;
  final double opacity;

  const GeometricPatternPainter({
    required this.color,
    this.tile = 56,
    this.opacity = 0.18,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final cols = (size.width / tile).ceil() + 1;
    final rows = (size.height / tile).ceil() + 1;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cx = c * tile;
        final cy = r * tile;
        _drawStar(canvas, Offset(cx, cy), tile / 2.4, stroke);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    // 8-point star: two overlapping squares rotated 45°
    for (var i = 0; i < 16; i++) {
      final angle = (math.pi / 8) * i;
      final radius = i.isEven ? r : r * 0.55;
      final x = center.dx + radius * math.cos(angle - math.pi / 2);
      final y = center.dy + radius * math.sin(angle - math.pi / 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant GeometricPatternPainter old) =>
      old.color != color || old.tile != tile || old.opacity != opacity;
}
