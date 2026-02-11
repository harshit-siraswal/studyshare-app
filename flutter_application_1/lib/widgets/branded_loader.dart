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
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
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
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF0F5FE8),
      child: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1).animate(_scaleAnimation),
            child: _buildRotatingLogo(),
          ),
        ),
      ),
    );
  }

  Widget _buildRotatingLogo() {
    const logoSize = 128.0;
    return Container(
      width: logoSize,
      height: logoSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 28,
            spreadRadius: 3,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: RotationTransition(
          turns: _spinController,
          child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
        ),
      ),
    );
  }
}
