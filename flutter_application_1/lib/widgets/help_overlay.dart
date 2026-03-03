import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

const double kSpotlightSizeSmall = 118;
const double kSpotlightSizeLarge = 132;

class HelpOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const HelpOverlay({super.key, required this.onDismiss});

  @override
  State<HelpOverlay> createState() => _HelpOverlayState();
}

class _HelpOverlayState extends State<HelpOverlay>
    with TickerProviderStateMixin {
  static const Duration _overlayDuration = Duration(milliseconds: 320);
  static const Duration _stepTransitionDuration = Duration(milliseconds: 240);

  late final AnimationController _overlayController;
  late final AnimationController _pulseController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _cardSlideAnimation;
  late final Animation<double> _cardScaleAnimation;
  late final Animation<double> _pulseAnimation;
  int _currentStep = 0;

  static const List<HelpStep> _steps = [
    HelpStep(
      title: 'Welcome to StudyShare!',
      description:
          'Swipe right from anywhere on the screen to open the Study Timer.',
      icon: Icons.swipe_right_rounded,
      highlightPosition: Alignment.centerLeft,
      spotlightSize: kSpotlightSizeSmall,
    ),
    HelpStep(
      title: 'Study Timer',
      description:
          'Track your study sessions with the built-in Pomodoro timer. Swipe left to close it.',
      icon: Icons.timer_rounded,
      highlightPosition: Alignment.centerLeft,
      spotlightSize: kSpotlightSizeSmall,
    ),
    HelpStep(
      title: 'Navigation',
      description:
          'Use the bottom navigation bar to switch between Home, Chats, Notices, and Profile.',
      icon: Icons.navigation_rounded,
      highlightPosition: Alignment.bottomCenter,
      spotlightSize: kSpotlightSizeLarge,
    ),
    HelpStep(
      title: 'Upload Resources',
      description:
          'Tap the + button in the center to upload study materials (for verified students).',
      icon: Icons.add_circle_rounded,
      highlightPosition: Alignment.bottomCenter,
      spotlightSize: kSpotlightSizeLarge,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _overlayController = AnimationController(
      vsync: this,
      duration: _overlayDuration,
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOut,
    );
    _cardSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _overlayController,
            curve: Curves.easeOutCubic,
          ),
        );
    _cardScaleAnimation = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _overlayController, curve: Curves.easeOutCubic),
    );
    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _overlayController.forward();
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _overlayController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      HapticFeedback.selectionClick();
      setState(() => _currentStep++);
    } else {
      _dismiss();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      HapticFeedback.selectionClick();
      setState(() => _currentStep--);
    }
  }

  Future<void> _dismiss() async {
    await _overlayController.reverse();
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final step = _steps[_currentStep];
    final spotlightAtBottom = step.highlightPosition == Alignment.bottomCenter;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        child: Stack(
          children: [
            IgnorePointer(child: _buildHighlight(step, isDark)),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: TextButton(
                        onPressed: _dismiss,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.9),
                        ),
                        child: Text(
                          'Skip',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    AnimatedPadding(
                      duration: _stepTransitionDuration,
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(
                        bottom: spotlightAtBottom ? 88 : 36,
                      ),
                      child: SlideTransition(
                        position: _cardSlideAnimation,
                        child: ScaleTransition(
                          scale: _cardScaleAnimation,
                          child: _buildCard(context, step),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, HelpStep step) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF192336), Color(0xFF2B3F62)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: _stepTransitionDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final offset = Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: Column(
          key: ValueKey<int>(_currentStep),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(step.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.title,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              step.description,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.88),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: List.generate(_steps.length, (index) {
                final isActive = index == _currentStep;
                return AnimatedContainer(
                  duration: _stepTransitionDuration,
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.only(right: 6),
                  height: 6,
                  width: isActive ? 24 : 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.35),
                  ),
                );
              }),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Step ${_currentStep + 1} of ${_steps.length}',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (_currentStep > 0)
                  Row(
                    children: [
                      TextButton(
                        onPressed: _previousStep,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          'Back',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ElevatedButton(
                  onPressed: _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF12213A),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _currentStep < _steps.length - 1 ? 'Next' : 'Finish',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlight(HelpStep step, bool isDark) {
    final glowColor = isDark ? Colors.white : const Color(0xFF6EA8FF);
    return AnimatedAlign(
      duration: _stepTransitionDuration,
      curve: Curves.easeOutCubic,
      alignment: step.highlightPosition,
      child: ScaleTransition(
        scale: _pulseAnimation,
        child: Container(
          width: step.spotlightSize,
          height: step.spotlightSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: glowColor.withValues(alpha: 0.8),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: 0.24),
                blurRadius: 26,
                spreadRadius: 6,
              ),
              BoxShadow(
                color: glowColor.withValues(alpha: 0.16),
                blurRadius: 58,
                spreadRadius: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HelpStep {
  final String title;
  final String description;
  final IconData icon;
  final Alignment highlightPosition;
  final double spotlightSize;

  const HelpStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.highlightPosition,
    required this.spotlightSize,
  });
}
