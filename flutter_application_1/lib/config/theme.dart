import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ============ NOTION/X INSPIRED DESIGN SYSTEM ============
  // Notion: Clean white backgrounds, warm gray text
  // X/Twitter: Pure black/white, high contrast
  
  // Brand Colors
  static const Color primary = Color(0xFF2563EB); // Blue 600
  static const Color primaryLight = Color(0xFF3B82F6); // Blue 500
  static const Color primaryDark = Color(0xFF1D4ED8); // Blue 700
  
  // Semantic Colors
  static const Color secondary = Color(0xFF6B7280); // Gray 500
  static const Color accent = Color(0xFF8B5CF6); // Violet 500
  static const Color error = Color(0xFFDC2626); // Red 600
  static const Color success = Color(0xFF059669); // Green 600
  static const Color warning = Color(0xFFD97706); // Amber 600
  static const Color notice = Color(0xFFD946EF); // Fuchsia 500 (PurpleAccent replacement)
  static const Color noticeColor = notice; // Alias for backward compatibility
  // ============ LIGHT MODE (Notion-inspired) ============
  // Modern Clean: Soft gray background, pure white surfaces
  static const Color lightBackground = Color(0xFFF8FAFC); // Slate 50
  static const Color lightSurface = Color(0xFFFFFFFF); // Pure white
  static const Color lightCard = Color(0xFFFFFFFF); // Pure white
  static const Color lightBorder = Color(0xFFE2E8F0); // Slate 200
  
  // Light mode text
  static const Color lightTextPrimary = Color(0xFF0F172A); // Slate 900
  static const Color lightTextSecondary = Color(0xFF475569); // Slate 600
  static const Color lightTextMuted = Color(0xFF94A3B8); // Slate 400
  
  // ============ DARK MODE (X/Twitter Lights Out inspired) ============
  // Pure black background for OLED, high contrast
  static const Color darkBackground = Color(0xFF000000); // Pure black (X Lights Out)
  static const Color darkSurface = Color(0xFF0F0F0F); // Near black
  static const Color darkCard = Color(0xFF171717); // Very dark gray
  static const Color darkBorder = Color(0xFF2E2E2E); // Dark border
  
  // Dark mode text (high contrast white)
  static const Color darkTextPrimary = Color(0xFFF9FAFB); // Almost white
  static const Color darkTextSecondary = Color(0xFFD1D5DB); // Light gray
  static const Color darkTextMuted = Color(0xFF6B7280); // Gray 500
  
  // ============ UNIVERSAL HELPERS ============
  // These adapt based on theme context
  static const Color textPrimary = lightTextPrimary;
  static const Color textSecondary = lightTextSecondary;
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color textLight = darkTextPrimary;
  
  // Backward compatibility
  static const Color textDark = textLight;
  static const Color glassBorder = lightBorder;
  static const Color glassLight = Color(0x15FFFFFF);
  static const Color glassMedium = Color(0x25FFFFFF);
  
  // Legacy gradients (solid colors preferred)
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [lightSurface, lightSurface],
  );
  
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );
  
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondary, primary],
  );
  
  // ============ THEME DATA ============
  
  static ThemeData lightTheme(ColorScheme? dynamicScheme) {
    // If dynamic scheme is present, use it. Otherwise use our custom definition.
    final ColorScheme scheme = dynamicScheme ?? const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: lightSurface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
        onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: dynamicScheme != null ? scheme.surface : lightBackground,
      
      colorScheme: scheme,
      
      // AppBar - clean, white, minimal shadow
      appBarTheme: AppBarTheme(
        backgroundColor: dynamicScheme != null ? scheme.surface : lightBackground,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      
      // Cards - white with subtle border (Notion style)
      cardTheme: CardThemeData(
        color: dynamicScheme != null ? scheme.surfaceContainerLow : lightCard,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      
      // Buttons - solid primary
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: dynamicScheme != null ? scheme.outlineVariant : lightBorder),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      
      // Input fields - clean border style
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dynamicScheme != null ? scheme.surfaceContainer : lightSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        hintStyle: GoogleFonts.inter(color: lightTextMuted),
        labelStyle: GoogleFonts.inter(color: lightTextSecondary),
      ),
      
      // Bottom nav - clean
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: dynamicScheme != null ? scheme.surface : lightBackground,
        selectedItemColor: scheme.primary,
        unselectedItemColor: lightTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      
      // Tab bar
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: lightTextMuted,
        indicatorColor: scheme.primary,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
      ),
      
      // Divider
      dividerTheme: DividerThemeData(
        color: dynamicScheme != null ? scheme.outlineVariant : lightBorder,
        thickness: 1,
      ),
      
      // Floating action button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: const CircleBorder(),
      ),
      
      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: dynamicScheme != null ? scheme.surfaceContainer : lightSurface,
        selectedColor: scheme.primary.withValues(alpha: 0.1),
        labelStyle: GoogleFonts.inter(color: lightTextSecondary, fontSize: 13),
        side: BorderSide(color: dynamicScheme != null ? scheme.outlineVariant : lightBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      
      // Text theme
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(color: scheme.onSurface),
        displayMedium: GoogleFonts.inter(color: scheme.onSurface),
        displaySmall: GoogleFonts.inter(color: scheme.onSurface),
        headlineLarge: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.bold),
        headlineSmall: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.w500),
        titleSmall: GoogleFonts.inter(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
        bodyLarge: GoogleFonts.inter(color: scheme.onSurface),
        bodyMedium: GoogleFonts.inter(color: scheme.onSurfaceVariant),
        bodySmall: GoogleFonts.inter(color: scheme.onSurfaceVariant), // Muted
        labelLarge: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.w500),
        labelMedium: GoogleFonts.inter(color: scheme.onSurfaceVariant),
        labelSmall: GoogleFonts.inter(color: scheme.onSurfaceVariant),
      ),
    );
  }
  
  static ThemeData darkTheme(ColorScheme? dynamicScheme) {
    
    final ColorScheme scheme = dynamicScheme ?? const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: darkSurface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimary,
        onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: dynamicScheme != null ? scheme.surface : darkBackground,
      
      colorScheme: scheme,
      
      // AppBar - pure black
      appBarTheme: AppBarTheme(
        backgroundColor: dynamicScheme != null ? scheme.surface : darkBackground,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      
      // Cards - dark with subtle border
      cardTheme: CardThemeData(
        color: dynamicScheme != null ? scheme.surfaceContainer : darkCard,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      
      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: dynamicScheme != null ? scheme.outlineVariant : darkBorder),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      
      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dynamicScheme != null ? scheme.surfaceContainer : darkCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        hintStyle: GoogleFonts.inter(color: darkTextMuted),
        labelStyle: GoogleFonts.inter(color: darkTextSecondary),
      ),
      
      // Bottom nav
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: dynamicScheme != null ? scheme.surface : darkBackground,
        selectedItemColor: scheme.primary,
        unselectedItemColor: darkTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      
      // Tab bar
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: darkTextMuted,
        indicatorColor: scheme.primary,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
      ),
      
      // Divider
      dividerTheme: DividerThemeData(
        color: dynamicScheme != null ? scheme.outlineVariant : darkBorder,
        thickness: 1,
      ),
      
      // FAB
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: const CircleBorder(),
      ),
      
      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: dynamicScheme != null ? scheme.surfaceContainerHigh : darkCard,
        selectedColor: scheme.primary.withValues(alpha: 0.2),
        labelStyle: GoogleFonts.inter(color: darkTextSecondary, fontSize: 13),
        side: BorderSide(color: dynamicScheme != null ? scheme.outlineVariant : darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      
      // Text theme
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(color: scheme.onSurface),
        displayMedium: GoogleFonts.inter(color: scheme.onSurface),
        displaySmall: GoogleFonts.inter(color: scheme.onSurface),
        headlineLarge: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.bold),
        headlineSmall: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.w500),
        titleSmall: GoogleFonts.inter(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
        bodyLarge: GoogleFonts.inter(color: scheme.onSurface),
        bodyMedium: GoogleFonts.inter(color: scheme.onSurfaceVariant),
        bodySmall: GoogleFonts.inter(color: scheme.onSurfaceVariant),
        labelLarge: GoogleFonts.inter(color: scheme.onSurface, fontWeight: FontWeight.w500),
        labelMedium: GoogleFonts.inter(color: scheme.onSurfaceVariant),
        labelSmall: GoogleFonts.inter(color: scheme.onSurfaceVariant),
      ),
    );
  }
  
  // ============ HELPER FUNCTIONS ============
  
  /// Get the appropriate text color based on theme
  static Color getTextColor(BuildContext context, {bool isPrimary = true, bool muted = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (muted) return isDark ? darkTextMuted : lightTextMuted;
    if (isPrimary) return isDark ? darkTextPrimary : lightTextPrimary;
    return isDark ? darkTextSecondary : lightTextSecondary;
  }

  /// Get the appropriate card color based on theme
  static Color getCardColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkCard : lightCard;
  }
  
  /// Get the appropriate border color based on theme
  static Color getBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkBorder : lightBorder;
  }

  /// Get the appropriate muted text color based on theme
  static Color getMutedColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkTextMuted : lightTextMuted;
  }
  
  /// Get the appropriate background color based on theme
  static Color getBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkBackground : lightBackground;
  }
  
  /// Get the appropriate surface color based on theme
  static Color getSurfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkSurface : lightSurface;
  }
}
