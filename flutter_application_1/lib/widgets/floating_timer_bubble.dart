import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/study_timer_controller.dart';

/// Floating Timer Bubble - Draggable circular timer widget
/// Shows live countdown and can be tapped to show controls
class FloatingTimerBubble extends StatefulWidget {
  final StudyTimerController controller;
  final VoidCallback? onExpand;
  final VoidCallback? onClose;
  final Offset? initialPosition;

  const FloatingTimerBubble({
    super.key,
    required this.controller,
    this.onExpand,
    this.onClose,
    this.initialPosition,
  });

  @override
  State<FloatingTimerBubble> createState() => _FloatingTimerBubbleState();
}

class _FloatingTimerBubbleState extends State<FloatingTimerBubble>
    with SingleTickerProviderStateMixin {
  late Offset _position;
  late AnimationController _pulseController;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition ?? const Offset(20, 100);
    
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

  void _showControlDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => TimerControlDialog(
        controller: widget.controller,
        onExpand: widget.onExpand,
        onClose: widget.onClose,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _position.dx.clamp(0, screenSize.width - 72),
      top: _position.dy.clamp(0, screenSize.height - 72),
      child: GestureDetector(
        onTap: _showControlDialog,
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(0, screenSize.width - 72),
              (_position.dy + details.delta.dy).clamp(0, screenSize.height - 72),
            );
          });
        },
        onPanEnd: (_) => setState(() => _isDragging = false),
        child: AnimatedBuilder(          animation: Listenable.merge([_pulseController, widget.controller]),
          builder: (context, child) {
            final pulseScale = 1.0 + (_pulseController.value * 0.05);
            final isRunning = widget.controller.isRunning;
            
            return Transform.scale(
              scale: _isDragging ? 1.1 : (isRunning ? pulseScale : 1.0),
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
                      color: (isRunning ? const Color(0xFF8B5CF6) : const Color(0xFF3B82F6))
                          .withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
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
                    // Progress ring
                    CustomPaint(
                      size: const Size(72, 72),
                      painter: _ProgressRingPainter(
                        progress: widget.controller.progress,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    // Play/Pause indicator icon
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
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ProgressRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Draw progress arc
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
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Timer Control Dialog - Shows pause/stop controls
class TimerControlDialog extends StatelessWidget {
  final StudyTimerController controller;  final VoidCallback? onExpand;
  final VoidCallback? onClose;

  const TimerControlDialog({
    super.key,
    required this.controller,
    this.onExpand,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
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
              child: Semantics(
                label: 'Close dialog',
                button: true,
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
            ),
            
            // Timer display
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Text(
                controller.formattedTime,
                style: GoogleFonts.robotoMono(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Control buttons
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pause/Play button
                  _ControlButton(
                    icon: controller.isRunning ? Icons.pause : Icons.play_arrow,
                    color: const Color(0xFF3B82F6),
                    onTap: () {
                      if (controller.isRunning) {
                        controller.pauseTimer();
                      } else {
                        controller.startTimer();
                      }
                    },
                  ),
                  
                  const SizedBox(width: 24),
                  
                  // Stop button
                  _ControlButton(
                    icon: Icons.stop,
                    color: const Color(0xFFEF4444),
                    onTap: () {
                      controller.resetTimer();
                      Navigator.pop(context);
                      onClose?.call();
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Resume full timer button
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                onExpand?.call();
              },
              child: Text(
                'RESUME FULL TIMER',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF3B82F6),
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
        child: Icon(
          icon,
          size: 32,
          color: Colors.white,
        ),
      ),
    );
  }
}
