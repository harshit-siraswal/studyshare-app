import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../config/theme.dart';

class KineticDotsLoader extends StatefulWidget {
  final int dots;
  final bool compact;
  final String? label;

  const KineticDotsLoader({
    super.key,
    this.dots = 4,
    this.compact = false,
    this.label,
  });

  @override
  State<KineticDotsLoader> createState() => _KineticDotsLoaderState();
}

class _KineticDotsLoaderState extends State<KineticDotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dotCount = widget.dots.clamp(1, 8);
    final dotSize = widget.compact ? 10.0 : 14.0;
    final trackHeight = widget.compact ? 34.0 : 50.0;
    final spacing = widget.compact ? 6.0 : 10.0;
    final travel = widget.compact ? 18.0 : 28.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: trackHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(dotCount, (index) {
                  final delay = index * 0.15;
                  final progress = (_controller.value - delay) % 1.0;
                  final normalized = progress < 0 ? progress + 1.0 : progress;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: spacing / 2),
                    child: _buildDot(
                      progress: normalized,
                      dotSize: dotSize,
                      travel: travel,
                    ),
                  );
                }),
              ),
            ),
            if (widget.label != null && widget.label!.trim().isNotEmpty) ...[
              SizedBox(height: widget.compact ? 4 : 8),
              Text(
                widget.label!,
                style: TextStyle(
                  fontSize: widget.compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDot({
    required double progress,
    required double dotSize,
    required double travel,
  }) {
    final bounce = math.sin(math.pi * progress).clamp(0.0, 1.0).toDouble();
    final translateY = -travel * bounce;

    final impactWindow = 0.12;
    final impact = progress < impactWindow
        ? 1 - (progress / impactWindow)
        : progress > (1 - impactWindow)
        ? 1 - ((1 - progress) / impactWindow)
        : 0.0;
    final stretch = 0.12 * bounce;
    final squash = 0.36 * impact;
    final scaleX = 1 + squash - (stretch * 0.35);
    final scaleY = 1 - squash + stretch;

    final shadowScale = 1.3 - (0.8 * bounce);
    final shadowOpacity = (0.58 - (0.42 * bounce)).clamp(0.1, 0.62).toDouble();

    double ripplePhase = -1;
    if (progress <= 0.34) {
      ripplePhase = progress / 0.34;
    } else if (progress >= 0.92) {
      ripplePhase = (1 - progress) / 0.08;
    }
    final hasRipple = ripplePhase >= 0;
    final rippleScale = hasRipple ? (0.55 + (ripplePhase * 1.1)) : 0.55;
    final rippleOpacity = hasRipple
        ? (0.72 * (1 - ripplePhase)).clamp(0.0, 0.72).toDouble()
        : 0.0;

    return SizedBox(
      width: dotSize * 2.2,
      height: dotSize + travel + 10,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          if (hasRipple)
            Transform.translate(
              offset: const Offset(0, 1),
              child: Opacity(
                opacity: rippleOpacity,
                child: Transform.scale(
                  scale: rippleScale,
                  child: Container(
                    width: dotSize * 1.9,
                    height: dotSize * 0.5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.65),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Opacity(
            opacity: shadowOpacity,
            child: Transform.scale(
              scale: shadowScale,
              child: Container(
                width: dotSize * 1.1,
                height: dotSize * 0.34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: AppTheme.primary.withValues(alpha: 0.66),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.scale(
              scaleX: scaleX,
              scaleY: scaleY,
              child: SizedBox(
                width: dotSize,
                height: dotSize,
                child: Stack(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF67E8F9), Color(0xFF2563EB)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.45),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: dotSize * 0.2,
                      left: dotSize * 0.2,
                      child: Container(
                        width: dotSize * 0.24,
                        height: dotSize * 0.24,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
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
  }
}
