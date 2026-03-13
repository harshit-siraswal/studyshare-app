import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../controllers/study_timer_controller.dart';
import '../config/theme.dart';

class StudyTimerDialog extends StatelessWidget {
  const StudyTimerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Consumer<StudyTimerController>(
          builder: (context, controller, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final textColor = isDark ? Colors.white : const Color(0xFF1E293B);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Study Timer',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          color: textColor.withValues(alpha: 0.7),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Timer Display
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 200,
                      width: 200,
                      child: CircularProgressIndicator(
                        value: controller.progress,
                        strokeWidth: 12,
                        backgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          controller.formattedTime,
                          style: GoogleFonts.spaceMono(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            letterSpacing: -1,
                          ),
                        ),
                        if (controller.isRunning)
                          Text(
                            'Focused',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TimeControlButton(
                      icon: Icons.refresh_rounded,
                      onTap: controller.resetTimer,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 16),
                    // Play/Pause Button
                    GestureDetector(
                      onTap: () {
                        if (controller.isRunning) {
                          controller.pauseTimer();
                        } else {
                          controller.startTimer();
                        }
                      },
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary,
                              AppTheme.primary.withValues(alpha: 0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          controller.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _TimeControlButton(
                      icon: Icons.add_rounded,
                      onTap: () => controller.addTime(5 * 60), // Add 5 minutes
                      isDark: isDark,
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                
                // Duration Selection
                if (!controller.isRunning)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [15, 25, 45, 60].map((mins) {
                        final isSelected = controller.selectedMinutes == mins;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () => controller.setDuration(mins),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected 
                                  ? AppTheme.primary 
                                  : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$mins m',
                                style: GoogleFonts.outfit(
                                  color: isSelected ? Colors.white : textColor.withValues(alpha: 0.7),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TimeControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  const _TimeControlButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isDark ? Colors.white : Colors.black87,
          size: 24,
        ),
      ),
    );
  }
}
