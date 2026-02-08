import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HelpOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  
  const HelpOverlay({
    super.key,
    required this.onDismiss,
  });

  @override
  State<HelpOverlay> createState() => _HelpOverlayState();
}

class _HelpOverlayState extends State<HelpOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  int _currentStep = 0;

  final List<HelpStep> _steps = [
    HelpStep(
      title: 'Welcome to MyStudySpace!',
      description: 'Swipe right from anywhere on the screen to open the Study Timer.',
      icon: Icons.swipe_right_rounded,
      highlightPosition: Alignment.centerLeft,
    ),
    HelpStep(
      title: 'Study Timer',
      description: 'Track your study sessions with the built-in Pomodoro timer. Swipe left to close it.',
      icon: Icons.timer_rounded,
      highlightPosition: Alignment.centerLeft,
    ),
    HelpStep(
      title: 'Navigation',
      description: 'Use the bottom navigation bar to switch between Home, Chats, Notices, and Profile.',
      icon: Icons.navigation_rounded,
      highlightPosition: Alignment.bottomCenter,
    ),
    HelpStep(
      title: 'Upload Resources',
      description: 'Tap the + button in the center to upload study materials (for verified students).',
      icon: Icons.add_circle_rounded,
      highlightPosition: Alignment.bottomCenter,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _dismiss();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStep];

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.black54, // Dim background
        child: Stack(
          children: [
            // Highlight spot
            _buildHighlight(step.highlightPosition),

            // Card Overlay
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end, // Position at bottom usually, or dynamic
                  children: [
                     // Spacer to push it down or flexible based on highlight? 
                     // For simplicity and matching the "floating card" look, let's place it near bottom
                     // but allow it to be flexible. The reference image has it floating.
                     const Spacer(), 
                     if (step.highlightPosition == Alignment.bottomCenter) const Spacer(), // Push up if highlight is bottom

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155), // Slate 700 - Dark Blue/Grey
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Title with Icon
                          Row(
                            children: [
                              ExcludeSemantics(
                                child: Icon(step.icon, color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 12),                              Expanded(
                                child: Text(
                                  step.title,
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),                          // Description
                          Text(
                            step.description,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Footer: Counter + Buttons
                          Row(
                            children: [
                              Text(
                                '${_currentStep + 1}/${_steps.length}',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              
                              // Back Button
                              if (_currentStep > 0)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: TextButton(
                                    onPressed: _previousStep,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Back'),
                                  ),
                                ),

                              // Next / Finish Button
                              OutlinedButton(
                                onPressed: _nextStep,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white, width: 1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                                child: Text(
                                  _currentStep < _steps.length - 1 ? 'Next' : 'Finish',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 100), // Space from bottom
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlight(Alignment alignment) {
    // Spotlight effect
    return Align(
      alignment: alignment,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              // Simple highlighter effect
              color: Colors.white.withValues(alpha: 0.1),
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
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

  HelpStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.highlightPosition,
  });
}
