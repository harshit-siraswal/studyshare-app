import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../config/theme.dart';

/// A branded loading widget inspired by Alma's loading screen.
/// Features animated app logo with gradient pulse and rotating motivational quotes.
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
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotateAnimation;
  
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
    
    // Pulse animation for the logo glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Gentle rotation for visual interest
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    
    _rotateAnimation = Tween<double>(begin: 0, end: 1).animate(_rotateController);
    
    // Rotate quotes every 2.5 seconds
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
    _pulseController.dispose();
    _rotateController.dispose();
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
            // Animated Logo with glow
            _buildAnimatedLogo(isDark),
            
            const SizedBox(height: 32),
            
            // Loading message
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
              const SizedBox(height: 48),
              
              // Motivational quote
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: Text(
                    _motivationalQuotes[_currentQuoteIndex % _motivationalQuotes.length],
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

  Widget _buildAnimatedLogo(bool isDark) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.3 * _pulseAnimation.value),
                blurRadius: 30 * _pulseAnimation.value,
                spreadRadius: 5 * _pulseAnimation.value,
              ),
              BoxShadow(
                color: AppTheme.accent.withOpacity(0.2 * _pulseAnimation.value),
                blurRadius: 40 * _pulseAnimation.value,
                spreadRadius: 10 * _pulseAnimation.value,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AnimatedBuilder(
              animation: _rotateAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: 0.9 + (0.1 * _pulseAnimation.value),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to gradient icon if image fails
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppTheme.primary, AppTheme.accent],
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.auto_stories_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactLoader(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.2 * _pulseAnimation.value),
                      blurRadius: 16 * _pulseAnimation.value,
                      spreadRadius: 2 * _pulseAnimation.value,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.primary, AppTheme.accent],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.auto_stories_rounded,
                          size: 28,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
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
}

/// Simple progress indicator using app branding
class BrandedProgressIndicator extends StatelessWidget {
  final double? value;
  final String? label;

  const BrandedProgressIndicator({
    super.key,
    this.value,
    this.label,
  });

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
              backgroundColor: isDark ? AppTheme.darkCard : const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              minHeight: 6,
            ),
          ),
        ),
      ],
    );
  }
}
