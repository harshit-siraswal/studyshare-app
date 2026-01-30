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
  
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: lightBackground,
      
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: lightSurface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
        onError: Colors.white,
      ),
      
      // AppBar - clean, white, minimal shadow
      appBarTheme: AppBarTheme(
        backgroundColor: lightBackground,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: lightTextPrimary,
        ),
        iconTheme: const IconThemeData(color: lightTextPrimary),
      ),
      
      // Cards - white with subtle border (Notion style)
      cardTheme: const CardThemeData(
        color: lightCard,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      
      // Buttons - solid primary
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightTextPrimary,
          side: const BorderSide(color: lightBorder),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      
      // Input fields - clean border style
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
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
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        hintStyle: GoogleFonts.inter(color: lightTextMuted),
        labelStyle: GoogleFonts.inter(color: lightTextSecondary),
      ),
      
      // Bottom nav - clean
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightBackground,
        selectedItemColor: primary,
        unselectedItemColor: lightTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      
      // Tab bar
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: lightTextMuted,
        indicatorColor: primary,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
      ),
      
      // Divider
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
      ),
      
      // Floating action button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: CircleBorder(),
      ),
      
      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: lightSurface,
        selectedColor: primary.withOpacity(0.1),
        labelStyle: GoogleFonts.inter(color: lightTextSecondary, fontSize: 13),
        side: const BorderSide(color: lightBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      
      // Text theme
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(color: lightTextPrimary),
        displayMedium: GoogleFonts.inter(color: lightTextPrimary),
        displaySmall: GoogleFonts.inter(color: lightTextPrimary),
        headlineLarge: GoogleFonts.inter(color: lightTextPrimary, fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.inter(color: lightTextPrimary, fontWeight: FontWeight.bold),
        headlineSmall: GoogleFonts.inter(color: lightTextPrimary, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.inter(color: lightTextPrimary, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.inter(color: lightTextPrimary, fontWeight: FontWeight.w500),
        titleSmall: GoogleFonts.inter(color: lightTextSecondary, fontWeight: FontWeight.w500),
        bodyLarge: GoogleFonts.inter(color: lightTextPrimary),
        bodyMedium: GoogleFonts.inter(color: lightTextSecondary),
        bodySmall: GoogleFonts.inter(color: lightTextMuted),
        labelLarge: GoogleFonts.inter(color: lightTextPrimary, fontWeight: FontWeight.w500),
        labelMedium: GoogleFonts.inter(color: lightTextSecondary),
        labelSmall: GoogleFonts.inter(color: lightTextMuted),
      ),
    );
  }
  
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: darkBackground,
      
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: darkSurface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimary,
        onError: Colors.white,
      ),
      
      // AppBar - pure black
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
        iconTheme: const IconThemeData(color: darkTextPrimary),
      ),
      
      // Cards - dark with subtle border
      cardTheme: const CardThemeData(
        color: darkCard,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      
      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkTextPrimary,
          side: const BorderSide(color: darkBorder),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      
      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
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
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        hintStyle: GoogleFonts.inter(color: darkTextMuted),
        labelStyle: GoogleFonts.inter(color: darkTextSecondary),
      ),
      
      // Bottom nav
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkBackground,
        selectedItemColor: primary,
        unselectedItemColor: darkTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      
      // Tab bar
      tabBarTheme: TabBarThemeData(
        labelColor: darkTextPrimary,
        unselectedLabelColor: darkTextMuted,
        indicatorColor: primary,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
      ),
      
      // Divider
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
      ),
      
      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: CircleBorder(),
      ),
      
      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        selectedColor: primary.withOpacity(0.2),
        labelStyle: GoogleFonts.inter(color: darkTextSecondary, fontSize: 13),
        side: const BorderSide(color: darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      
      // Text theme
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(color: darkTextPrimary),
        displayMedium: GoogleFonts.inter(color: darkTextPrimary),
        displaySmall: GoogleFonts.inter(color: darkTextPrimary),
        headlineLarge: GoogleFonts.inter(color: darkTextPrimary, fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.inter(color: darkTextPrimary, fontWeight: FontWeight.bold),
        headlineSmall: GoogleFonts.inter(color: darkTextPrimary, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.inter(color: darkTextPrimary, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.inter(color: darkTextPrimary, fontWeight: FontWeight.w500),
        titleSmall: GoogleFonts.inter(color: darkTextSecondary, fontWeight: FontWeight.w500),
        bodyLarge: GoogleFonts.inter(color: darkTextPrimary),
        bodyMedium: GoogleFonts.inter(color: darkTextSecondary),
        bodySmall: GoogleFonts.inter(color: darkTextMuted),
        labelLarge: GoogleFonts.inter(color: darkTextPrimary, fontWeight: FontWeight.w500),
        labelMedium: GoogleFonts.inter(color: darkTextSecondary),
        labelSmall: GoogleFonts.inter(color: darkTextMuted),
      ),
    );
  }
  
  // ============ HELPER FUNCTIONS ============
  
  /// Get the appropriate text color based on theme
  static Color getTextColor(BuildContext context, {bool primary = true, bool muted = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (muted) return isDark ? darkTextMuted : lightTextMuted;
    if (primary) return isDark ? darkTextPrimary : lightTextPrimary;
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
  
  /// Get the appropriate background color based on theme
  static Color getBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkBackground : lightBackground;
  }
  
  /// Get the appropriate surface color based on theme
  static Color getSurfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkSurface : lightSurface;
  }
}
