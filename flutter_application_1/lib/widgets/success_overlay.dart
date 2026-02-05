import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../config/theme.dart';

class SuccessOverlay extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const SuccessOverlay({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  @override
  State<SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<SuccessOverlay> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _particleController;
  late AnimationController _pulseController;
  
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;
  late Animation<double> _checkStrokeAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  final List<_Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    
    // Generate celebration particles
    for (int i = 0; i < 20; i++) {
      _particles.add(_Particle(
        angle: _random.nextDouble() * 2 * pi,
        speed: 100 + _random.nextDouble() * 150,
        color: [
          AppTheme.primary,
          AppTheme.accent,
          AppTheme.success,
          Colors.amber,
          Colors.pink,
        ][_random.nextInt(5)],
        size: 4 + _random.nextDouble() * 6,
      ));
    }

    // Main animation controller
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Particle explosion controller
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Pulse effect controller
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Card scale with bounce
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
      ),
    );

    // Fade in background
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
      ),
    );

    // Check mark stroke drawing animation
    _checkStrokeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.35, 0.65, curve: Curves.easeInOut),
      ),
    );

    // Check icon pop-in
    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.6, 0.8, curve: Curves.elasticOut),
      ),
    );

    // Pulse ring animation
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOut,
      ),
    );

    // Start animations
    _mainController.forward();
    _particleController.forward();
    
    // Start pulse after initial animation
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _pulseController.repeat(reverse: true);
      }
    });

    // Auto-dismiss
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _particleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final successLabel = AppLocalizations.of(context)!.success;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: Listenable.merge([_mainController, _particleController, _pulseController]),
        builder: (context, child) {
          return Container(
            color: Colors.black.withValues(alpha: 0.6 * _fadeAnimation.value),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Celebration particles
                ..._particles.map((particle) {
                  final progress = _particleController.value;
                  final x = cos(particle.angle) * particle.speed * progress;
                  final y = sin(particle.angle) * particle.speed * progress - 
                           (50 * progress * progress); // Add gravity effect
                  
                  return Positioned(
                    left: MediaQuery.of(context).size.width / 2 + x,
                    top: MediaQuery.of(context).size.height / 2 + y - 40,
                    child: Opacity(
                      opacity: (1 - progress).clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: progress * 4 * pi,
                        child: Container(
                          width: particle.size,
                          height: particle.size,
                          decoration: BoxDecoration(
                            color: particle.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                
                // Main card
                Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.success.withValues(alpha: 0.3),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      label: '$successLabel ${widget.message}',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Animated success circle with pulse ring
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // Pulse rings
                              if (_checkAnimation.value > 0.5) ...[
                                Transform.scale(
                                  scale: _pulseAnimation.value * 1.2,
                                  child: Container(
                                    width: 90,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppTheme.success.withValues(
                                          alpha: (1 - (_pulseAnimation.value - 1) * 2).clamp(0.0, 0.3),
                                        ),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              // Main circle
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppTheme.success,
                                      AppTheme.success.withValues(alpha: 0.8),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.success.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: CustomPaint(
                                  painter: _CheckPainter(
                                    progress: _checkStrokeAnimation.value,
                                    checkScale: _checkAnimation.value,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          
                          // Success title with shimmer effect
                          ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                colors: [
                                  AppTheme.success,
                                  AppTheme.success.withValues(alpha: 0.7),
                                  AppTheme.success,
                                ],
                                stops: [
                                  0.0,
                                  _mainController.value,
                                  1.0,
                                ],
                              ).createShader(bounds);
                            },
                            child: Text(
                              successLabel,
                              style: GoogleFonts.inter(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          // Message with fade-in
                          Opacity(
                            opacity: _checkAnimation.value.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1 - _checkAnimation.value)),
                              child: Text(
                                widget.message,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: isDark ? AppTheme.textMuted : Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Decorative dots
                          Opacity(
                            opacity: _checkAnimation.value.clamp(0.0, 1.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(3, (i) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: AppTheme.success.withValues(alpha: 0.6 - i * 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Particle for celebration effect
class _Particle {
  final double angle;
  final double speed;
  final Color color;
  final double size;

  _Particle({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
  });
}

/// Custom painter for animated checkmark
class _CheckPainter extends CustomPainter {
  final double progress;
  final double checkScale;

  _CheckPainter({required this.progress, required this.checkScale});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Draw the checkmark stroke by stroke
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (checkScale > 0) {
      final scale = checkScale.clamp(0.0, 1.0);
      
      // Checkmark path points (relative to center)
      final start = Offset(center.dx - 16 * scale, center.dy + 2 * scale);
      final mid = Offset(center.dx - 4 * scale, center.dy + 14 * scale);
      final end = Offset(center.dx + 18 * scale, center.dy - 10 * scale);

      final path = Path();
      
      if (progress < 0.5) {
        // First stroke (going down to mid)
        final t = progress * 2;
        path.moveTo(start.dx, start.dy);
        path.lineTo(
          start.dx + (mid.dx - start.dx) * t,
          start.dy + (mid.dy - start.dy) * t,
        );
      } else {
        // Full first stroke + partial second stroke
        path.moveTo(start.dx, start.dy);
        path.lineTo(mid.dx, mid.dy);
        
        final t = (progress - 0.5) * 2;
        path.lineTo(
          mid.dx + (end.dx - mid.dx) * t,
          mid.dy + (end.dy - mid.dy) * t,
        );
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.checkScale != checkScale;
  }
}
