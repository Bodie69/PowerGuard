import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class SparklineChart extends StatelessWidget {
  const SparklineChart({
    super.key,
    required this.data,
    this.color = Colors.blue,
    this.lineWidth = 2.0,
  });

  final List<double> data;
  final Color color;
  final double lineWidth;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SparklinePainter(
          data: data,
          color: color,
          lineWidth: lineWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.data,
    required this.color,
    required this.lineWidth,
  });

  final List<double> data;
  final Color color;
  final double lineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final double min = data.reduce((a, b) => a < b ? a : b);
    final double max = data.reduce((a, b) => a > b ? a : b);
    final double range = max - min == 0 ? 1 : max - min;

    final double width = size.width;
    final double height = size.height;
    final double stepX = width / (data.length - 1);

    final List<Offset> points = [];
    for (int i = 0; i < data.length; i++) {
      final double x = i * stepX;
      final double y = height - ((data[i] - min) / range * height);
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw area gradient
    final areaPath = Path.from(path)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();

    final gradient = ui.Gradient.linear(
      Offset(0, 0),
      Offset(0, height),
      [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
    );

    canvas.drawPath(areaPath, Paint()..shader = gradient);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}
