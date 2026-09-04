import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnalogGauge extends StatelessWidget {
  const AnalogGauge({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.unit,
    this.color = Colors.blue,
  });

  final double value;
  final double min;
  final double max;
  final String label;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve space for the text label and spacing
        const textHeight = 24.0;
        const spacing = 4.0;
        
        // Handle unbounded height (e.g. inside ScrollView)
        final double maxHeight = constraints.maxHeight.isFinite 
            ? constraints.maxHeight 
            : 200.0;
            
        final availableHeight = maxHeight - textHeight - spacing;
        
        // The gauge is semi-circular, so height is radius and width is 2*radius.
        // Aspect ratio is 2.0 ideally, but let's use 1.6 to match previous look.
        final targetHeight = math.min(availableHeight, constraints.maxWidth / 1.6);
        final targetWidth = targetHeight * 1.6;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: targetWidth,
              height: targetHeight,
              child: CustomPaint(
                painter: _GaugePainter(
                  value: value,
                  min: min,
                  max: max,
                  color: color,
                  themeColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  textColor: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: spacing),
            SizedBox(
              height: textHeight,
              child: Text(
                '${label.isNotEmpty ? "$label: " : ""}${value.toStringAsFixed(1)} $unit',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.themeColor,
    required this.textColor,
  });

  final double value;
  final double min;
  final double max;
  final Color color;
  final Color themeColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.9);
    final radius = math.min(size.width / 2, size.height * 0.9);

    // Draw background arc
    final bgPaint = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.15
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - (bgPaint.strokeWidth / 2)),
      math.pi,
      math.pi,
      false,
      bgPaint,
    );

    // Draw value arc
    final valPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.15
      ..strokeCap = StrokeCap.round;

    final progress = (value - min) / (max - min);
    final clampedProgress = progress.clamp(0.0, 1.0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - (valPaint.strokeWidth / 2)),
      math.pi,
      math.pi * clampedProgress,
      false,
      valPaint,
    );

    // Draw needle
    final needlePaint = Paint()
      ..color = textColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final needleAngle = math.pi + (math.pi * clampedProgress);
    final needleLength = radius * 0.8;
    final needleEnd = Offset(
      center.dx + needleLength * math.cos(needleAngle),
      center.dy + needleLength * math.sin(needleAngle),
    );

    canvas.drawLine(center, needleEnd, needlePaint);

    // Draw center dot
    canvas.drawCircle(center, 6, Paint()..color = textColor);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.min != min ||
        oldDelegate.max != max ||
        oldDelegate.color != color;
  }
}
