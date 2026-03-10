import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Centralised SnackBar helper used across all screens.
///
/// Replace raw [ScaffoldMessenger.showSnackBar] calls with these static
/// helpers to guarantee consistent styling, colour, and duration.
abstract class AppSnackBar {
  static const Duration _short = Duration(seconds: 3);
  static const Duration _long = Duration(seconds: 5);

  // ------------------------------------------------------------------
  // Core presenter
  // ------------------------------------------------------------------

  static void _show(
    BuildContext context, {
    required String message,
    required Color background,
    required IconData icon,
    Duration duration = _short,
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: background,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: duration,
          action: action,
        ),
      );
  }

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      background: AppTheme.primary,
      icon: Icons.check_circle_outline_rounded,
      duration: _short,
    );
  }

  static void error(BuildContext context, String message) {
    _show(
      context,
      message: message,
      background: AppTheme.error,
      icon: Icons.error_outline_rounded,
      duration: _long,
    );
  }

  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      background: const Color(0xFF475569),
      icon: Icons.info_outline_rounded,
      duration: _short,
    );
  }

  static void warning(BuildContext context, String message) {
    _show(
      context,
      message: message,
      background: const Color(0xFFF59E0B),
      icon: Icons.warning_amber_rounded,
      duration: _long,
    );
  }

  // ------------------------------------------------------------------
  // Convenience helpers
  // ------------------------------------------------------------------

  /// Show a user-friendly version of an exception message.
  static void exception(BuildContext context, Object error) {
    final raw = error.toString();
    const prefix = 'Exception: ';
    final msg = raw.startsWith(prefix)
        ? raw.substring(prefix.length).trim()
        : raw.trim();
    error_(context, msg.isEmpty ? 'Something went wrong.' : msg);
  }

  // Alias to avoid keyword collision
  static void error_(BuildContext context, String message) =>
      error(context, message);
}
