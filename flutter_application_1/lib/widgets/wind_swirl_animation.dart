import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../config/theme.dart';

class WindSwirlAnimation extends StatefulWidget {
  final double size;
  final VoidCallback onCompleted;

  const WindSwirlAnimation({
    super.key,
    this.size = 50.0,
    required this.onCompleted,
  });

  @override
  State<WindSwirlAnimation> createState() => _WindSwirlAnimationState();
}

class _WindSwirlAnimationState extends State<WindSwirlAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500), // Total animation time
      vsync: this,
    )..forward().then((_) {
      if (mounted) {
        widget.onCompleted();
      }
    });
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Wind color: Light Blue/Purple tint tailored for theme
    final Color windColor = isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _WindSwirlPainter(
              progress: _controller.value,
              color: windColor,
            ),
          ),
        );
      },
    );
  }
}

class _WindSwirlPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WindSwirlPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // As progress goes 0 -> 1, the swirl spins and fades out at the end
    // Scale effect is handled by the parent transition usually, but we can do some internal movement
    
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.08;

    // Draw 3 arcs rotating at different speeds
    for (int i = 0; i < 3; i++) {
        final startAngle = (i * 120) * (math.pi / 180) + (progress * (i + 2) * math.pi * 2);
        final sweepAngle = math.pi * 0.6 * (1 - progress); // Arcs get smaller as they speed up? or fix size
        
        paint.color = color.withValues(alpha: (1 - progress).clamp(0.0, 1.0)); // Fade out
        
        final currentRadius = radius * (0.5 + (i * 0.2)); // Nested circles
        
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: currentRadius),
          startAngle,
          sweepAngle,
          false,
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_WindSwirlPainter oldDelegate) => 
      oldDelegate.progress != progress || oldDelegate.color != color;
}
