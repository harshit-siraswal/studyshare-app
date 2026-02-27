import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Global key to wrap the entire app's scaffold/body to take a screenshot.
final GlobalKey appBoundaryKey = GlobalKey();

double _getDevicePixelRatio(BuildContext context) {
  final mediaQuery = MediaQuery.maybeOf(context);
  if (mediaQuery != null && mediaQuery.devicePixelRatio > 0) {
    return mediaQuery.devicePixelRatio;
  }
  final views = ui.PlatformDispatcher.instance.views;
  if (views.isNotEmpty && views.first.devicePixelRatio > 0) {
    return views.first.devicePixelRatio;
  }
  return 1.0;
}

/// Full-screen sun-setting / moon-rising theme transition.
Future<void> animateThemeTransition(
  BuildContext context,
  Offset tapOffset,
  VoidCallback toggleTheme,
) async {
  // Capture current screen as a screenshot
  final boundary =
      appBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    toggleTheme();
    return;
  }

  var pixelRatio = _getDevicePixelRatio(context);
  ui.Image? image;
  try {
    image = await boundary.toImage(pixelRatio: pixelRatio);
  } catch (e) {
    toggleTheme();
    return;
  }

  final overlayState = Overlay.maybeOf(context);
  if (overlayState == null) {
    toggleTheme();
    return;
  }

  // Detect: are we going TO dark or TO light?
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // If currently light, we're switching TO dark (sun sets)
  // If currently dark, we're switching TO light (sun rises)
  final toDark = !isDark;

  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) {
      return _SunMoonTransition(
        image: image!,
        toDark: toDark,
        onEnd: () {
          overlayEntry.remove();
        },
      );
    },
  );

  overlayState.insert(overlayEntry);

  // Actually update the theme underneath the overlay
  toggleTheme();
}

// ─────────────────────────────────────────────────────────────
//  Full-screen Sun/Moon Transition Animation
// ─────────────────────────────────────────────────────────────

class _SunMoonTransition extends StatefulWidget {
  final ui.Image image;
  final bool toDark;
  final VoidCallback onEnd;

  const _SunMoonTransition({
    required this.image,
    required this.toDark,
    required this.onEnd,
  });

  @override
  State<_SunMoonTransition> createState() => _SunMoonTransitionState();
}

class _SunMoonTransitionState extends State<_SunMoonTransition>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
    _controller.forward().then((_) {
      if (mounted) widget.onEnd();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    widget.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final t = _animation.value;

        return Stack(
          children: [
            // Layer 0: The screenshot of the old theme (fades out)
            Opacity(
              opacity: (1.0 - t).clamp(0.0, 1.0),
              child: SizedBox.expand(
                child: RawImage(image: widget.image, fit: BoxFit.cover),
              ),
            ),

            // Layer 1: Sky gradient overlay
            Positioned.fill(
              child: CustomPaint(
                painter: _SkyGradientPainter(
                  progress: t,
                  toDark: widget.toDark,
                ),
              ),
            ),

            // Layer 2: Horizon line
            Positioned(
              left: 0,
              right: 0,
              bottom: size.height * 0.30,
              child: Opacity(
                opacity: _horizonOpacity(t),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.toDark
                          ? [
                              Colors.transparent,
                              const Color(0xFFFF6B35),
                              const Color(0xFFFFD700),
                              const Color(0xFFFF6B35),
                              Colors.transparent,
                            ]
                          : [
                              Colors.transparent,
                              const Color(0xFFFFB347),
                              const Color(0xFFFFF8DC),
                              const Color(0xFFFFB347),
                              Colors.transparent,
                            ],
                    ),
                  ),
                ),
              ),
            ),

            // Layer 3: Sun or Moon
            _buildCelestialBody(size, t),

            // Layer 4: Stars (only when going to dark)
            if (widget.toDark) _buildStars(size, t),
          ],
        );
      },
    );
  }

  double _horizonOpacity(double t) {
    // Horizon visible from t=0.1 to t=0.7
    if (t < 0.1) return t / 0.1;
    if (t > 0.7) return 1.0 - ((t - 0.7) / 0.3);
    return 1.0;
  }

  Widget _buildCelestialBody(Size size, double t) {
    final horizonY = size.height * 0.70;
    final bodySize = size.width * 0.18;
    final centerX = size.width / 2;

    if (widget.toDark) {
      // Sun sets down past the horizon, moon rises from below
      // Phase 1 (0-0.5): Sun descends
      // Phase 2 (0.5-1.0): Moon rises
      if (t < 0.55) {
        // Sun going down
        final sunT = (t / 0.55).clamp(0.0, 1.0);
        final sunY = _lerpDouble(-bodySize * 0.5, horizonY + bodySize, sunT);
        final sunOpacity = (1.0 - (sunT * 1.2)).clamp(0.0, 1.0);
        return Positioned(
          left: centerX - bodySize / 2,
          top: sunY,
          child: Opacity(
            opacity: sunOpacity,
            child: _SunWidget(size: bodySize),
          ),
        );
      } else {
        // Moon coming up
        final moonT = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
        final moonY = _lerpDouble(horizonY + bodySize, size.height * 0.15, moonT);
        final moonOpacity = moonT.clamp(0.0, 1.0);
        return Positioned(
          left: centerX - bodySize / 2,
          top: moonY,
          child: Opacity(
            opacity: moonOpacity,
            child: _MoonWidget(size: bodySize),
          ),
        );
      }
    } else {
      // Light mode: Moon sets, Sun rises
      if (t < 0.55) {
        final moonT = (t / 0.55).clamp(0.0, 1.0);
        final moonY = _lerpDouble(-bodySize * 0.5, horizonY + bodySize, moonT);
        final moonOpacity = (1.0 - (moonT * 1.2)).clamp(0.0, 1.0);
        return Positioned(
          left: centerX - bodySize / 2,
          top: moonY,
          child: Opacity(
            opacity: moonOpacity,
            child: _MoonWidget(size: bodySize),
          ),
        );
      } else {
        final sunT = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
        final sunY = _lerpDouble(horizonY + bodySize, size.height * 0.15, sunT);
        final sunOpacity = sunT.clamp(0.0, 1.0);
        return Positioned(
          left: centerX - bodySize / 2,
          top: sunY,
          child: Opacity(
            opacity: sunOpacity,
            child: _SunWidget(size: bodySize),
          ),
        );
      }
    }
  }

  Widget _buildStars(Size size, double t) {
    final starOpacity = ((t - 0.5) / 0.5).clamp(0.0, 1.0);
    if (starOpacity <= 0) return const SizedBox.shrink();

    return Positioned.fill(
      child: Opacity(
        opacity: starOpacity,
        child: CustomPaint(
          painter: _StarsPainter(opacity: starOpacity),
        ),
      ),
    );
  }

  double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

// ─────────────────────────────────────────────────────────────
//  Sun Widget (Radial glow + circle)
// ─────────────────────────────────────────────────────────────

class _SunWidget extends StatelessWidget {
  final double size;
  const _SunWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFFD700).withValues(alpha: 0.6),
                  const Color(0xFFFF8C00).withValues(alpha: 0.3),
                  const Color(0xFFFF6347).withValues(alpha: 0.1),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.4, 0.7, 1.0],
              ),
            ),
          ),
          // Core
          Container(
            width: size * 0.55,
            height: size * 0.55,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0xFFFFF8DC),
                  Color(0xFFFFD700),
                  Color(0xFFFF8C00),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x80FFD700),
                  blurRadius: 30,
                  spreadRadius: 10,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Moon Widget (Crescent-style)
// ─────────────────────────────────────────────────────────────

class _MoonWidget extends StatelessWidget {
  final double size;
  const _MoonWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFE8E8FF).withValues(alpha: 0.3),
                  const Color(0xFFB0C4DE).withValues(alpha: 0.15),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Moon body
          Container(
            width: size * 0.5,
            height: size * 0.5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment(-0.3, -0.3),
                colors: [
                  Color(0xFFF5F5FF),
                  Color(0xFFD4D4E8),
                  Color(0xFFB8B8D0),
                ],
                stops: [0.0, 0.6, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x40E8E8FF),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          // Crescent shadow
          Positioned(
            right: size * 0.2,
            child: Container(
              width: size * 0.4,
              height: size * 0.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A1A2E).withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Sky Gradient Painter
// ─────────────────────────────────────────────────────────────

class _SkyGradientPainter extends CustomPainter {
  final double progress;
  final bool toDark;

  _SkyGradientPainter({required this.progress, required this.toDark});

  @override
  void paint(Canvas canvas, Size size) {
    // Fade in the sky overlay; strongest at mid-animation
    final opacity = _bellCurve(progress) * 0.85;
    if (opacity <= 0) return;

    final List<Color> colors;
    if (toDark) {
      // Sunset gradient: orange -> purple -> deep navy
      final phase = progress;
      if (phase < 0.5) {
        colors = [
          Color.lerp(const Color(0x00000000), const Color(0xFFFF6B35), phase * 2)!,
          Color.lerp(const Color(0x00000000), const Color(0xFFFF8E53), phase * 2)!,
          Color.lerp(const Color(0x00000000), const Color(0xFF7B2FF7), phase * 2)!,
          Color.lerp(const Color(0x00000000), const Color(0xFF1A1A2E), phase * 2)!,
        ];
      } else {
        final p2 = (phase - 0.5) * 2;
        colors = [
          Color.lerp(const Color(0xFFFF6B35), const Color(0xFF0D0D1A), p2)!,
          Color.lerp(const Color(0xFFFF8E53), const Color(0xFF1A1A2E), p2)!,
          Color.lerp(const Color(0xFF7B2FF7), const Color(0xFF16213E), p2)!,
          Color.lerp(const Color(0xFF1A1A2E), const Color(0xFF0F3460), p2)!,
        ];
      }
    } else {
      // Sunrise gradient: deep navy -> orange -> light blue
      final phase = progress;
      if (phase < 0.5) {
        colors = [
          Color.lerp(const Color(0x00000000), const Color(0xFF1A1A2E), phase * 2)!,
          Color.lerp(const Color(0x00000000), const Color(0xFF7B2FF7), phase * 2)!,
          Color.lerp(const Color(0x00000000), const Color(0xFFFF8E53), phase * 2)!,
          Color.lerp(const Color(0x00000000), const Color(0xFFFFB347), phase * 2)!,
        ];
      } else {
        final p2 = (phase - 0.5) * 2;
        colors = [
          Color.lerp(const Color(0xFF1A1A2E), const Color(0xFF87CEEB), p2)!,
          Color.lerp(const Color(0xFF7B2FF7), const Color(0xFFADD8E6), p2)!,
          Color.lerp(const Color(0xFFFF8E53), const Color(0xFFFFF8DC), p2)!,
          Color.lerp(const Color(0xFFFFB347), const Color(0x00000000), p2)!,
        ];
      }
    }

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..color = Colors.white.withValues(alpha: opacity);

    canvas.drawRect(rect, paint);
  }

  double _bellCurve(double t) {
    // Peaks at t=0.5, fades at edges
    return math.sin(t * math.pi);
  }

  @override
  bool shouldRepaint(_SkyGradientPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

// ─────────────────────────────────────────────────────────────
//  Stars Painter (procedural stars)
// ─────────────────────────────────────────────────────────────

class _StarsPainter extends CustomPainter {
  final double opacity;
  _StarsPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42); // Deterministic seed for consistent star positions
    final paint = Paint()..color = Colors.white.withValues(alpha: opacity * 0.8);

    for (int i = 0; i < 60; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * 0.6; // Stars mostly in upper area
      final radius = rng.nextDouble() * 1.5 + 0.5;

      // Twinkle effect: vary brightness
      final twinkle = (math.sin(i * 1.5 + opacity * math.pi * 2) + 1) / 2;
      paint.color = Colors.white.withValues(alpha: opacity * 0.4 * twinkle + opacity * 0.3);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter oldDelegate) => opacity != oldDelegate.opacity;
}
