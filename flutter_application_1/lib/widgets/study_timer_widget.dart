import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../controllers/study_timer_controller.dart';

class StudyTimerWidget extends StatelessWidget {
  final StudyTimerController controller;
  final VoidCallback? onMinimize;

  const StudyTimerWidget({
    super.key,
    required this.controller,
    this.onMinimize,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isRunning = controller.isRunning;
        
        return Container(
          color: isDark ? AppTheme.darkSurface : AppTheme.lightCard,
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : AppTheme.lightSurface,
                    borderRadius: const BorderRadius.only(topRight: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.timer_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Study Timer',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.textLight : AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      // Minimize Button
                      if (onMinimize != null)
                        IconButton(
                          icon: const Icon(Icons.open_in_new_rounded), // Use open_in_new to signify popping out
                          onPressed: onMinimize,
                          tooltip: 'Floating Mode',
                          color: AppTheme.textMuted,
                        ),
                    ],
                  ),
                ),
                
                Divider(
                  height: 1, 
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
                
                // Timer display
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Circular progress
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 160,
                              height: 160,
                              child: CircularProgressIndicator(
                                value: controller.progress,
                                strokeWidth: 8,
                                backgroundColor: isDark ? AppTheme.darkCard : AppTheme.lightBorder,
                                valueColor: AlwaysStoppedAnimation(
                                  isRunning ? AppTheme.primary : AppTheme.secondary,
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  StudyTimerController.formatTime(controller.remainingSeconds),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AppTheme.textLight : AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  isRunning ? 'Focus Mode' : 'Ready',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Control buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Reset
                            IconButton(
                              onPressed: controller.resetTimer,
                              icon: const Icon(Icons.refresh_rounded),
                              color: AppTheme.textMuted,
                              iconSize: 24,
                            ),
                            const SizedBox(width: 12),
                            // Play/Pause
                            ElevatedButton(
                              onPressed: isRunning ? controller.pauseTimer : controller.startTimer,
                              style: ElevatedButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(16),
                                backgroundColor: AppTheme.primary,
                              ),
                              child: Icon(
                                isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Add 5 mins
                            IconButton(
                              onPressed: () => controller.addTime(300),
                              icon: const Icon(Icons.add_rounded),
                              color: AppTheme.textMuted,
                              iconSize: 24,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Custom time button
                        if (!isRunning) ...[
                          Text(
                            'Tap to set duration',
                            style: GoogleFonts.inter(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _showCustomTimeDialog(context, controller),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.primary.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_rounded, size: 18, color: AppTheme.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${controller.selectedMinutes} min',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.arrow_drop_down_rounded, size: 18, color: AppTheme.primary),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Stats footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : AppTheme.lightSurface,
                    borderRadius: const BorderRadius.only(bottomRight: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStat(
                          context,
                          icon: Icons.check_circle_rounded,
                          value: '${controller.sessionCount}',
                          label: 'Sessions',
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                      ),
                      Expanded(
                        child: _buildStat(
                          context,
                          icon: Icons.schedule_rounded,
                          value: '${controller.totalMinutes}',
                          label: 'Minutes',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCustomTimeDialog(BuildContext context, StudyTimerController controller) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? AppTheme.darkSurface 
            : Colors.white,
        title: Text(
          'Set Custom Time',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter minutes (e.g., 35)',
            suffix: Text('min', style: GoogleFonts.inter(color: AppTheme.textMuted)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final minutes = int.tryParse(textController.text);
              if (minutes == null || minutes <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a positive number')),
                );
                return;
              }
              final success = controller.setDuration(minutes);
              if (success) {
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid duration. Please try a different value.')),
                );
              }
            },            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Set', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) => textController.dispose());
  }

  Widget _buildStat(BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.inter(
                color: isDark ? AppTheme.textLight : AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
