import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // For unawaited
import '../config/theme.dart';

/// Onboarding overlay widget for first-time user guided tour.
/// Shows spotlight highlights on key features with descriptive tooltips.
class OnboardingOverlay extends StatefulWidget {
  final List<OnboardingStep> steps;
  final VoidCallback? onComplete;
  final Widget child;

  const OnboardingOverlay({
    super.key,
    required this.steps,
    required this.child,
    this.onComplete,
  });

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();

  /// Check if the user has completed onboarding
  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_completed_onboarding') ?? false;
  }

  /// Mark onboarding as complete
  static Future<void> setOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_onboarding', true);
  }

  /// Reset onboarding for testing
  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_onboarding', false);
  }
}

class _OnboardingOverlayState extends State<OnboardingOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  bool _isVisible = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < widget.steps.length - 1) {
      _animController.reverse().then((_) {
        setState(() => _currentStep++);
        _animController.forward();
      });
    } else {
      _completeOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _animController.reverse().then((_) {
        setState(() => _currentStep--);
        _animController.forward();
      });
    }
  }

  void _skipOnboarding() {
    _completeOnboarding();
  }

  void _completeOnboarding() {
    // Fire and forget
    unawaited(OnboardingOverlay.setOnboardingComplete()); 
    setState(() => _isVisible = false);
    widget.onComplete?.call();
  }



  Rect? _spotlightRect;

  @override
  void didUpdateWidget(OnboardingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Check bounds since the steps list might have shrunk
    if (widget.steps.isEmpty) {
      if (_currentStep != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _currentStep = 0);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateSpotlight(); // clear spotlight
      });
      return; 
    }
    
    if (_currentStep >= widget.steps.length) {
      // Clamp
      WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _currentStep = widget.steps.length - 1);
      });
      // We can't access widget.steps[_currentStep] yet safely if we just scheduled a setState
      // But _updateSpotlight uses _currentStep, so we should update it after frame
      _updateSpotlight(); 
      return;
    }

    // Now safe to access widget.steps[_currentStep]
    if (_currentStep < oldWidget.steps.length) {
      if (widget.steps[_currentStep].targetKey != oldWidget.steps[_currentStep].targetKey) {
        _updateSpotlight();
      }
    } else {
      _updateSpotlight();
    }
  }
  void _updateSpotlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      final targetKey = widget.steps[_currentStep].targetKey;
      if (targetKey == null) {
        setState(() => _spotlightRect = null);
        return;
      }
      
      final renderBox = targetKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) {
         setState(() => _spotlightRect = null);
         return;
      }

      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      
      // Add padding around the spotlight
      const padding = 8.0;
      final rect = Rect.fromLTWH(
        position.dx - padding,
        position.dy - padding,
        size.width + padding * 2,
        size.height + padding * 2,
      );
      
      setState(() => _spotlightRect = rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Schedule spotlight update if needed
    if (_isVisible && widget.steps.isNotEmpty && _spotlightRect == null && widget.steps[_currentStep].targetKey != null) {
      _updateSpotlight();
    }
    
    if (!_isVisible || widget.steps.isEmpty) {
      return widget.child;
    }

    final currentStepData = widget.steps[_currentStep];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        widget.child,
        
        // Semi-transparent overlay
        Positioned.fill(
          child: GestureDetector(
            onTap: _nextStep,
            child: Container(
              color: Colors.black.withValues(alpha: 0.75),
            ),
          ),
        ),
        
        // Spotlight cutout if target key is provided
        if (_spotlightRect != null)
          Positioned.fill(
            child: CustomPaint(
              painter: SpotlightPainter(
                spotlightRect: _spotlightRect!,
                borderRadius: 16,
              ),
            ),
          ),
        
        // Tooltip card
        Positioned(
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).padding.bottom + 100,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: _buildTooltipCard(currentStepData, isDark),
            ),
          ),
        ),
        
        // Skip button
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          right: 20,
          child: TextButton(
            onPressed: _skipOnboarding,
            child: Text(
              'Skip',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        
        // Progress indicator
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 40,
          left: 0,
          right: 0,
          child: _buildProgressIndicator(),
        ),
      ],
    );
  }


  Widget _buildTooltipCard(OnboardingStep step, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primary, AppTheme.accent],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  step.icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  step.title,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Description
          Text(
            step.description,
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.5,
              color: isDark ? Colors.white70 : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          
          // Navigation buttons
          Row(
            children: [
              if (_currentStep > 0)
                TextButton(
                  onPressed: _previousStep,
                  child: Text(
                    'Back',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentStep == widget.steps.length - 1 ? 'Get Started' : 'Next',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.steps.length, (index) {
        final isActive = index == _currentStep;
        final isPast = index < _currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive || isPast ? AppTheme.primary : Colors.white30,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

/// Data class for each onboarding step
class OnboardingStep {
  final String title;
  final String description;
  final IconData icon;
  final GlobalKey? targetKey;

  const OnboardingStep({
    required this.title,
    required this.description,
    required this.icon,
    this.targetKey,
  });
}

/// Custom painter for the spotlight effect
class SpotlightPainter extends CustomPainter {
  final Rect spotlightRect;
  final double borderRadius;

  SpotlightPainter({
    required this.spotlightRect,
    this.borderRadius = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.75);
    
    // Draw the dark overlay with a cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(spotlightRect, Radius.circular(borderRadius)))
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, paint);
    
    // Draw a glowing border around the spotlight
    final borderPaint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(spotlightRect, Radius.circular(borderRadius)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant SpotlightPainter oldDelegate) {
    return spotlightRect != oldDelegate.spotlightRect ||
           borderRadius != oldDelegate.borderRadius;
  }}

/// Default onboarding steps for MyStudySpace
List<OnboardingStep> getDefaultOnboardingSteps() {
  return const [
    OnboardingStep(
      title: 'Welcome to MyStudySpace! 📚',
      description: 'Your all-in-one study companion. Let\'s take a quick tour of the main features.',
      icon: Icons.auto_stories_rounded,
    ),
    OnboardingStep(
      title: 'Focus Timer ⏱️',
      description: 'Use the Pomodoro timer to manage your study sessions. Track your progress and stay motivated!',
      icon: Icons.timer_rounded,
    ),
    OnboardingStep(
      title: 'Notices & Updates 📢',
      description: 'Stay updated with important college announcements, exam schedules, and event notifications.',
      icon: Icons.campaign_rounded,
    ),
    OnboardingStep(
      title: 'Study Rooms 💬',
      description: 'Join subject-specific rooms to discuss, share resources, and collaborate with your peers.',
      icon: Icons.forum_rounded,
    ),
    OnboardingStep(
      title: 'Resources Library 📖',
      description: 'Access notes, videos, and PYQs organized by semester, branch, and subject. You can also upload your own!',
      icon: Icons.folder_rounded,
    ),
  ];
}
