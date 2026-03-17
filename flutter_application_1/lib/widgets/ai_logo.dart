import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme.dart';

class AiLogo extends StatefulWidget {
  final double size;
  final bool animate;

  const AiLogo({
    super.key,
    this.size = 40,
    this.animate = true,
  });

  @override
  State<AiLogo> createState() => _AiLogoState();
}

class _AiLogoState extends State<AiLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _rotation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
      ),
    );

    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AiLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _AiLogoPainter(
              rotation: widget.animate ? _rotation.value : 0,
              pulse: widget.animate ? _pulse.value : 1.0,
            ),
          );
        },
      ),
    );
  }
}

class _AiLogoPainter extends CustomPainter {
  final double rotation;
  final double pulse;

  _AiLogoPainter({required this.rotation, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.width * 0.28;

    final baseGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppTheme.primary,
        AppTheme.primary.withValues(alpha: 0.75),
      ],
    );

    final basePaint = Paint()
      ..shader = baseGradient.createShader(rect)
      ..style = PaintingStyle.fill;

    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(rrect, basePaint);

    // Glow ring
    final ringRect = rect.deflate(size.width * 0.08);
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.04);

    canvas.drawArc(
      ringRect,
      rotation,
      math.pi * 0.6,
      false,
      ringPaint,
    );

    // Inner S mark
    final sPaint = Paint()
      ..color = Colors.white.withValues(alpha: pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round;

    final topArc = Rect.fromCenter(
      center: Offset(size.width * 0.53, size.height * 0.38),
      width: size.width * 0.55,
      height: size.height * 0.38,
    );
    final bottomArc = Rect.fromCenter(
      center: Offset(size.width * 0.47, size.height * 0.62),
      width: size.width * 0.55,
      height: size.height * 0.38,
    );

    final sPath = Path()
      ..addArc(topArc, math.pi * 0.15, math.pi * 1.1)
      ..addArc(bottomArc, math.pi * 1.15, math.pi * 1.1);

    canvas.drawPath(sPath, sPaint);
  }

  @override
  bool shouldRepaint(covariant _AiLogoPainter oldDelegate) {
    return oldDelegate.rotation != rotation || oldDelegate.pulse != pulse;
  }
}
