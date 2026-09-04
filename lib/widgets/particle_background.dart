import 'dart:math' as math;
import 'package:flutter/material.dart';

class ParticleBackground extends StatefulWidget {
  const ParticleBackground({super.key});

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;
  final int _particleCount = 30;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _particles = List.generate(_particleCount, (index) => _Particle(_random));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        for (var particle in _particles) {
          particle.update();
        }
        return CustomPaint(
          size: Size.infinite,
          painter: _ParticlePainter(_particles),
        );
      },
    );
  }
}

class _Particle {
  late Offset position;
  late Offset velocity;
  final double radius = 2.0;
  final math.Random random;

  _Particle(this.random) {
    position = Offset(random.nextDouble() * 400, random.nextDouble() * 800);
    velocity = Offset(
      (random.nextDouble() - 0.5) * 0.5,
      (random.nextDouble() - 0.5) * 0.5,
    );
  }

  void update() {
    position += velocity;
    
    // Simple wrapping logic (will be refined in painter based on size)
    if (position.dx < -50) position = Offset(500, position.dy);
    if (position.dx > 500) position = Offset(-50, position.dy);
    if (position.dy < -50) position = Offset(position.dx, 900);
    if (position.dy > 900) position = Offset(position.dx, -50);
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;

  _ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1565C0).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF1565C0).withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    for (int i = 0; i < particles.length; i++) {
      final p1 = particles[i];
      
      // Keep within bounds
      if (p1.position.dx > size.width + 50) p1.position = Offset(-40, p1.position.dy);
      if (p1.position.dx < -50) p1.position = Offset(size.width + 40, p1.position.dy);
      if (p1.position.dy > size.height + 50) p1.position = Offset(p1.position.dx, -40);
      if (p1.position.dy < -50) p1.position = Offset(p1.position.dx, size.height + 40);

      canvas.drawCircle(p1.position, p1.radius, paint);

      for (int j = i + 1; j < particles.length; j++) {
        final p2 = particles[j];
        final distance = (p1.position - p2.position).distance;
        
        if (distance < 150) {
          // Adjust opacity based on distance
          linePaint.color = const Color(0xFF1565C0).withValues(
            alpha: (1.0 - (distance / 150)) * 0.1,
          );
          canvas.drawLine(p1.position, p2.position, linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
