import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/study_timer_controller.dart';

class FloatingClockWidget extends StatelessWidget {
  final StudyTimerController controller;
  final VoidCallback onTap;
  
  const FloatingClockWidget({
    super.key,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      child: Container(
        width: 72, 
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Glassmorphism effect
          color: Theme.of(context).brightness == Brightness.dark 
              ? const Color(0xFF1E293B).withValues(alpha: 0.8) 
              : Colors.white.withValues(alpha: 0.9),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.15),
              blurRadius: 16,
              offset: const Offset(0, 8),
              spreadRadius: -2,
            ),
          ],
        ),
      ),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        
        return GestureDetector(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              child!, // Static background
              // Progress Circle Ring
              SizedBox(
                width: 66, 
                height: 66,
                child: CircularProgressIndicator(
                  value: controller.progress,
                  strokeWidth: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(
                    isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                  ),
                ),
              ),
              // Time Text
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controller.formattedTime,
                    style: GoogleFonts.robotoMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    controller.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ],
              ),            ],
          ),
        );      },
    );
  }
}
