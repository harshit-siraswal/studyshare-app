import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

/// A branded loading widget with a custom orbital animation.
class BrandedLoader extends StatefulWidget {
  final String? message;
  final bool showQuotes;
  final bool compact;

  const BrandedLoader({
    super.key,
    this.message,
    this.showQuotes = true,
    this.compact = false,
  });

  @override
  State<BrandedLoader> createState() => _BrandedLoaderState();
}

class _BrandedLoaderState extends State<BrandedLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _orbitController;
  int _currentQuoteIndex = 0;
  Timer? _quoteTimer;

  static const List<String> _quotes = [
    'Just a sec...',
    'Loading your resources...',
    'Preparing study materials...',
    'Getting things ready...',
    'Almost there...',
    'Fetching the latest...',
  ];

  static const List<String> _motivationalQuotes = [
    '"What should I focus on today?"',
    '"Stay curious, keep learning."',
    '"One step at a time."',
    '"Knowledge is power."',
    '"Your future self will thank you."',
  ];

  @override
  void initState() {
    super.initState();

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    if (widget.showQuotes) {
      _quoteTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        if (mounted) {
          setState(() {
            _currentQuoteIndex = (_currentQuoteIndex + 1) % _quotes.length;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _quoteTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.compact) {
      return _buildCompactLoader(isDark);
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [AppTheme.darkBackground, AppTheme.darkSurface]
              : [const Color(0xFFF0F4FF), const Color(0xFFFAFBFC)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildOrbitLoader(size: 104, isDark: isDark),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                widget.message ?? _quotes[_currentQuoteIndex],
                key: ValueKey(_currentQuoteIndex),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : AppTheme.textSecondary,
                ),
              ),
            ),
            if (widget.showQuotes) ...[
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: Text(
                    _motivationalQuotes[_currentQuoteIndex %
                        _motivationalQuotes.length],
                    key: ValueKey('quote_$_currentQuoteIndex'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppTheme.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLoader(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOrbitLoader(size: 64, isDark: isDark),
          const SizedBox(height: 14),
          Text(
            widget.message ?? 'Loading...',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.white70 : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrbitLoader({required double size, required bool isDark}) {
    const dotCount = 10;
    final dotSize = size * 0.12;
    final radius = size * 0.34;
    final dotColor = isDark ? Colors.white : AppTheme.primary;

    return AnimatedBuilder(
      animation: _orbitController,
      builder: (context, child) {
        final t = _orbitController.value;
        final pulse = 0.92 + 0.08 * math.sin(t * 2 * math.pi);

        return Transform.scale(
          scale: pulse,
          child: SizedBox(
            width: size,
            height: size,
            child: RepaintBoundary(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(size * 0.18),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: dotColor.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ...List.generate(
                    dotCount,
                    (i) => _buildAnimatedDot(
                      size: size,
                      dotSize: dotSize,
                      radius: radius,
                      dotColor: dotColor,
                      dotCount: dotCount,
                      index: i,
                      t: t,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedDot({
    required double size,
    required double dotSize,
    required double radius,
    required Color dotColor,
    required int dotCount,
    required int index,
    required double t,
  }) {
    final angle = (2 * math.pi / dotCount) * index;
    final phase = (t + index / dotCount) % 1.0;
    final opacity = 0.25 + 0.75 * Curves.easeInOut.transform(phase);
    final scale = 0.6 + 0.6 * Curves.easeInOut.transform(phase);

    return Positioned(
      left: size / 2 + radius * math.cos(angle) - dotSize / 2,
      top: size / 2 + radius * math.sin(angle) - dotSize / 2,
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 16),
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple progress indicator using app branding
class BrandedProgressIndicator extends StatelessWidget {
  final double? value;
  final String? label;

  const BrandedProgressIndicator({super.key, this.value, this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.white70 : AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: isDark
                  ? AppTheme.darkCard
                  : const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              minHeight: 6,
            ),
          ),
        ),
      ],
    );
  }
}

/// Splash widget inspired by the app logo shape and motion language.
class AppSplashAnimation extends StatefulWidget {
  final String title;
  final String subtitle;
  final String loadingLabel;

  const AppSplashAnimation({
    super.key,
    this.title = 'MyStudySpace',
    this.subtitle = 'Connect. Learn. Share.',
    this.loadingLabel = 'Preparing your study space',
  });

  @override
  State<AppSplashAnimation> createState() => _AppSplashAnimationState();
}

class _AppSplashAnimationState extends State<AppSplashAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _pulseController;
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutBack,
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topColor = isDark ? const Color(0xFF06120D) : const Color(0xFFEAF7EF);
    final bottomColor = isDark
        ? const Color(0xFF020805)
        : const Color(0xFFD8EEDD);
    final titleColor = isDark ? Colors.white : const Color(0xFF1A5B3B);
    final subtitleColor = isDark
        ? Colors.white70
        : const Color(0xFF2A6F4D).withValues(alpha: 0.9);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ),
      ),
      child: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween<double>(
                  begin: 0.86,
                  end: 1,
                ).animate(_scaleAnimation),
                child: _buildLogoOrb(isDark),
              ),
              const SizedBox(height: 28),
              Text(
                widget.title,
                style: GoogleFonts.manrope(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: subtitleColor,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 24),
              _buildLoadingLabel(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoOrb(bool isDark) {
    const orbSize = 212.0;
    const brandGreen = Color(0xFF2EA867);
    const brandGreenLight = Color(0xFF57C884);
    final glowColor = isDark ? brandGreenLight : brandGreen;

    return AnimatedBuilder(
      animation: Listenable.merge([_spinController, _pulseController]),
      builder: (context, child) {
        final pulse =
            0.97 + 0.03 * math.sin(_pulseController.value * 2 * math.pi);
        final shimmer =
            (0.5 + 0.5 * math.sin(_pulseController.value * 2 * math.pi))
                .clamp(0.0, 1.0)
                .toDouble();

        return Transform.scale(
          scale: pulse,
          child: SizedBox(
            width: orbSize,
            height: orbSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: orbSize,
                  height: orbSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [brandGreenLight, brandGreen],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withValues(
                          alpha: isDark ? 0.28 : 0.22,
                        ),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
                CustomPaint(
                  size: const Size.square(orbSize * 0.68),
                  painter: _LogoGlyphPainter(
                    progress: _spinController.value,
                    color: Colors.white,
                    shimmer: shimmer,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingLabel(bool isDark) {
    final panelColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFF53B97D).withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? Colors.white : const Color(0xFF2EA867),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            widget.loadingLabel,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF235A3D),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoGlyphPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double shimmer;

  const _LogoGlyphPainter({
    required this.progress,
    required this.color,
    required this.shimmer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const segmentCount = 12;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.31;
    final pillWidth = size.width * 0.062;
    final pillHeight = size.width * 0.175;
    final arcSize = size.width * 0.155;

    for (int i = 0; i < segmentCount; i++) {
      final angle = (2 * math.pi / segmentCount) * i;
      final wave = (math.sin((progress * 2 * math.pi) - (i * 0.55)) + 1) / 2;
      final alpha = (0.38 + (0.62 * wave * (0.55 + 0.45 * shimmer)))
          .clamp(0.0, 1.0)
          .toDouble();

      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: alpha);

      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.02
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(
          alpha: (alpha * 0.95).clamp(0.0, 1.0).toDouble(),
        );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      final pillRect = Rect.fromCenter(
        center: Offset(0, -radius),
        width: pillWidth,
        height: pillHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, Radius.circular(pillWidth / 2)),
        fillPaint,
      );

      final arcRect = Rect.fromCenter(
        center: Offset(0, -radius - (size.width * 0.1)),
        width: arcSize,
        height: arcSize,
      );
      canvas.drawArc(
        arcRect,
        math.pi * 0.8,
        math.pi * 1.55,
        false,
        strokePaint,
      );
      canvas.restore();
    }

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.016
      ..color = color.withValues(
        alpha: (0.12 + shimmer * 0.12).clamp(0.0, 1.0).toDouble(),
      );

    canvas.drawCircle(center, size.width * 0.2, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _LogoGlyphPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.shimmer != shimmer;
  }
}
