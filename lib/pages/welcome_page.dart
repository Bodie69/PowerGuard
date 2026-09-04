import 'package:flutter/material.dart';
import '../widgets/particle_background.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    // FORCED VISIBILITY FIX: Using standard colors and safe font weights.
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // IoT Particle Animation in Background
          const ParticleBackground(),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Logo Circle
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      size: 64,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Title - Force Black
                  const Text(
                    'PowerGuard IoT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Description - Force Dark Grey
                  const Text(
                    'Real-time overcurrent monitoring and remote power management in COMLAB, from anywhere.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF333333),
                      height: 1.4,
                    ),
                  ),
                  const Spacer(),
                  
                  // Button - Force Blue with White Text
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: onGetStarted,
                      child: const Text(
                        'GET STARTED',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
