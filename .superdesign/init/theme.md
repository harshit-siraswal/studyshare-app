# Theme

## `flutter_application_1/lib/config/theme.dart`

> Note: `flutter_application_1` is the current package name from `pubspec.yaml`; update this path reference if the package name changes.

```dart
class AppTheme {
  static const Color primary = Color(0xFF2563EB);
  static const Color error = Color(0xFFDC2626);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);

  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF0F0F0F);
  static const Color darkCard = Color(0xFF171717);
  static const Color darkBorder = Color(0xFF2E2E2E);
  static const Color darkTextPrimary = Color(0xFFF9FAFB);
  static const Color darkTextSecondary = Color(0xFFD1D5DB);
  static const Color darkTextMuted = Color(0xFF6B7280);

  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);
}
```

## Typography Coverage
- All primary UI surfaces (main navigation, chat/message panes, assistant output cards, and settings dialogs) use `GoogleFonts.inter`.

## App package notes
- Flutter app, no Tailwind/CSS pipeline.
- Shared motion is widget-driven with `AnimatedContainer`, `AnimatedSize`, and controller-based pulses.
