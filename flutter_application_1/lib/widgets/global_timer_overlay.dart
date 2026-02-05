import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import '../controllers/study_timer_controller.dart';

/// Global Timer Overlay - Wraps the app and shows floating timer on all screens
class GlobalTimerOverlay extends StatefulWidget {
  final Widget child;
  
  /// Global key to access the overlay state from anywhere
  static final GlobalKey<_GlobalTimerOverlayState> globalKey = GlobalKey<_GlobalTimerOverlayState>();
  
  /// Get the timer controller from anywhere in the app
  static StudyTimerController? get timerController => globalKey.currentState?._timerController;
  
  /// Trigger the swirl animation from anywhere
  static void triggerSwirl(Offset startPosition) {
    globalKey.currentState?.triggerSwirlAnimation(startPosition);
  }

  /// Inform overlay about sidebar state
  static void setSidebarOpen(bool isOpen) {
    globalKey.currentState?.setSidebarOpen(isOpen);
  }

  GlobalTimerOverlay({required this.child}) : super(key: globalKey);

  @override
  State<GlobalTimerOverlay> createState() => _GlobalTimerOverlayState();
}

class _GlobalTimerOverlayState extends State<GlobalTimerOverlay>
    with SingleTickerProviderStateMixin {
  final StudyTimerController _timerController = StudyTimerController();
  Offset? _floatingPos;
  bool _showSwirl = false;
  bool _showBubble = false;
  late AnimationController _swirlController;
  Offset _swirlStart = Offset.zero;
  double _dragDistance = 0.0; // Function to track sloppy taps


  @override
  void initState() {
    super.initState();
    _swirlController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _timerController.addListener(_onTimerChange);
  }

  @override
  void dispose() {
    _timerController.removeListener(_onTimerChange);
    _swirlController.dispose();
    super.dispose();
  }

  void _onTimerChange() {
    setState(() {});
  }

  bool _isSidebarOpen = false;

  /// Update sidebar state to prevent bubble from showing when drawer is open
  void setSidebarOpen(bool isOpen) {
    setState(() {
      _isSidebarOpen = isOpen;
      // If sidebar opens, hide bubble immediately
      if (isOpen) {
        _showBubble = false;
      }
    });
  }

  /// Trigger wind swirl animation when sidebar minimizes
  void triggerSwirlAnimation(Offset startPosition) {
    setState(() {
      _swirlStart = startPosition;
      _showSwirl = true;
      _showBubble = false;
    });

    _swirlController.forward(from: 0).then((_) {
      setState(() {
        _showSwirl = false;
        // Only show bubble if sidebar is closed (it should be, but safety check)
        _showBubble = !_isSidebarOpen;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final defaultPos = Offset(screenSize.width - 88, topPadding + 16);
    final bubblePos = _floatingPos ?? defaultPos;

    // Don't show bubble if sidebar is open
    final shouldShowBubble = !_isSidebarOpen && _timerController.isRunning;

    return Stack(
      children: [
        // Main app content
        widget.child,

        // Wind Swirl Animation Layer
        if (_showSwirl)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _swirlController,
                builder: (context, _) => CustomPaint(
                  painter: _WindSwirlPainter(
                    progress: _swirlController.value,
                    startPos: _swirlStart,
                    endPos: bubblePos + const Offset(36, 36),
                  ),
                ),
              ),
            ),
          ),

        // Floating Timer Bubble
        // Case 1: Explicitly showing after animation
        if (shouldShowBubble && _showBubble)
          _buildFloatingBubble(context, bubblePos, screenSize),

        // Case 2: Auto-show if running, no swirl, and sidebar closed
        if (shouldShowBubble && !_showBubble && !_showSwirl)
          _buildFloatingBubble(context, bubblePos, screenSize),
      ],
    );
  }

  Widget _buildFloatingBubble(BuildContext context, Offset pos, Size screenSize) {
    final clampedX = pos.dx.clamp(0.0, screenSize.width - 72);
    final clampedY = pos.dy.clamp(0.0, screenSize.height - 72);
    
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 50), // Smooth interpolation
      curve: Curves.easeOut,
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        onPanStart: (_) => _dragDistance = 0.0,
        onPanUpdate: (details) {
          _dragDistance += details.delta.distance;
          setState(() {
            _floatingPos = Offset(
              (pos.dx + details.delta.dx).clamp(0, screenSize.width - 72),
              (pos.dy + details.delta.dy).clamp(0, screenSize.height - 72),
            );
          });
        },
        onPanEnd: (details) {
          // Fix for "Dialog doesn't open":
          // If the drag was very small (micro-movement/jitter), treat it as a tap.
          if (_dragDistance < 10.0) {
            _showTimerControlDialog();
          }
          // No snapping - free movement
        },
        onTap: _showTimerControlDialog, // Changed from onTapUp for better reliability
        behavior: HitTestBehavior.opaque,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.elasticOut,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            child: child,
          ),
          child: _FloatingBubbleWidget(controller: _timerController),
        ),
      ),
    );
  }

  void _showTimerControlDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 20,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Timer display
              ListenableBuilder(
                listenable: _timerController,
                builder: (context, _) => Text(
                  _timerController.formattedTime,
                  style: GoogleFonts.robotoMono(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pause/Play
                  _buildControlButton(
                    icon: _timerController.isRunning ? Icons.pause : Icons.play_arrow,
                    color: const Color(0xFF3B82F6),
                    onTap: () {
                      if (_timerController.isRunning) {
                        _timerController.pauseTimer();
                      } else {
                        _timerController.startTimer();
                      }
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 24),
                  // Stop
                  _buildControlButton(
                    icon: Icons.stop,
                    color: const Color(0xFFEF4444),
                    onTap: () {
                      _timerController.resetTimer();
                      Navigator.pop(context);
                      setState(() => _showBubble = false);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Open full timer hint
              Text(
                'Drag to move • Tap to control',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 32, color: Colors.white),
      ),
    );
  }
}

/// Floating Bubble Widget
class _FloatingBubbleWidget extends StatefulWidget {
  final StudyTimerController controller;

  const _FloatingBubbleWidget({required this.controller});

  @override
  State<_FloatingBubbleWidget> createState() => _FloatingBubbleWidgetState();
}

class _FloatingBubbleWidgetState extends State<_FloatingBubbleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, widget.controller]),
      builder: (context, _) {
        final pulseScale = 1.0 + (_pulseController.value * 0.05);
        final isRunning = widget.controller.isRunning;

        return Transform.scale(
          scale: isRunning ? pulseScale : 1.0,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isRunning
                    ? [const Color(0xFF6366F1), const Color(0xFF8B5CF6)]
                    : [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: (isRunning
                          ? const Color(0xFF8B5CF6)
                          : const Color(0xFF3B82F6))
                      .withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Progress ring
                CustomPaint(
                  size: const Size(72, 72),
                  painter: _ProgressRingPainter(
                    progress: widget.controller.progress,
                  ),
                ),
                // Timer text
                Text(
                  widget.controller.formattedTime,
                  style: GoogleFonts.robotoMono(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
                // Status icon
                Positioned(
                  bottom: 8,
                  child: Icon(
                    isRunning ? Icons.pause : Icons.play_arrow,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Progress Ring Painter
class _ProgressRingPainter extends CustomPainter {
  final double progress;

  _ProgressRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Wind Swirl Painter - Particle-based spiral animation
class _WindSwirlPainter extends CustomPainter {
  final double progress;
  final Offset startPos;
  final Offset endPos;

  _WindSwirlPainter({
    required this.progress,
    required this.startPos,
    required this.endPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final currentCenter = Offset.lerp(startPos, endPos, progress)!;
    final particleCount = 20;
    final random = math.Random(42); // Fixed seed for consistency

    for (int i = 0; i < particleCount; i++) {
      final angle = (i / particleCount) * 2 * math.pi + (progress * 6 * math.pi);
      final baseRadius = 30 + random.nextDouble() * 50;
      final radius = baseRadius * (1 - progress);

      final x = currentCenter.dx + radius * math.cos(angle);
      final y = currentCenter.dy + radius * math.sin(angle);

      final opacity = (1 - progress) * (0.3 + random.nextDouble() * 0.7);
      final particleSize = (2 + random.nextDouble() * 3) * (1 - progress * 0.5);

      final paint = Paint()
        ..color = const Color(0xFF8B5CF6).withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), particleSize, paint);
    }

    // Central glow
    final glowRadius = 40 * progress;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF8B5CF6).withValues(alpha: 0.6 * (1 - progress)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: currentCenter, radius: glowRadius));

    canvas.drawCircle(currentCenter, glowRadius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _WindSwirlPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

