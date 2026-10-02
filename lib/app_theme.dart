import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ===========================================================================
  // FG ACADEMY BRAND
  // ===========================================================================

  static const Color fgNavyBlue = Color(0xFF092A57);
  static const Color navy700 = Color(0xFF123D73);
  static const Color navy500 = Color(0xFF3166A1);

  static const Color fgGold = Color(0xFFD6B247);
  static const Color goldDark = Color(0xFFB88B16);
  static const Color goldSoft = Color(0xFFFFF4CF);

  // Warm academic paper-style background.
  static const Color backgroundLight = Color(0xFFF2F5F8);
  static const Color academyIvory = Color(0xFFFFFBF0);

  static const Color surface = Color(0xFFFEFEFD);
  static const Color surfaceSoft = Color(0xFFF7F9FC);

  static const Color border = Color(0xFFD8E0EA);

  static const Color textPrimary = Color(0xFF142038);
  static const Color textSecondary = Color(0xFF536173);

  static const Color success = Color(0xFF147A4F);
  static const Color danger = Color(0xFFC63B4B);
  static const Color warning = Color(0xFFBD750B);
  static const Color info = Color(0xFF2766AA);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [fgNavyBlue, navy700],
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFE6C65D), fgGold, Color(0xFFB98E1A)],
  );

  // ===========================================================================
  // GLOBAL THEME
  // ===========================================================================

  static ThemeData get officialTheme {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

    final poppins = GoogleFonts.poppinsTextTheme(base.textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      scaffoldBackgroundColor: backgroundLight,

      colorScheme: ColorScheme.fromSeed(
        seedColor: fgNavyBlue,
        brightness: Brightness.light,
        primary: fgNavyBlue,
        secondary: fgGold,
        surface: surface,
        error: danger,
      ),

      textTheme: poppins.copyWith(
        displaySmall: poppins.displaySmall?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
        ),

        headlineLarge: poppins.headlineLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
        ),

        headlineMedium: poppins.headlineMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
        ),

        headlineSmall: poppins.headlineSmall?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 22,
        ),

        titleLarge: poppins.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 19,
        ),

        titleMedium: poppins.titleMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),

        titleSmall: poppins.titleSmall?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),

        bodyLarge: poppins.bodyLarge?.copyWith(
          color: textPrimary,
          fontSize: 16,
          height: 1.45,
        ),

        bodyMedium: poppins.bodyMedium?.copyWith(
          color: textPrimary,
          fontSize: 14.5,
          height: 1.45,
        ),

        // Sir ki readability ke liye intentionally 12 se neeche nahi.
        bodySmall: poppins.bodySmall?.copyWith(
          color: textSecondary,
          fontSize: 12.5,
          height: 1.4,
        ),

        labelLarge: poppins.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),

        labelMedium: poppins.labelMedium?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),

        labelSmall: poppins.labelSmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),

      appBarTheme: AppBarTheme(
        toolbarHeight: 52,
        backgroundColor: fgNavyBlue,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        titleTextStyle: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      cardTheme: CardThemeData(
        color: surface.withValues(alpha: 0.97),
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: fgNavyBlue.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border.withValues(alpha: 0.9)),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: fgNavyBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: fgNavyBlue.withValues(alpha: 0.42),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fgNavyBlue,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: fgNavyBlue,
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.95),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 14,
        ),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: TextStyle(
          color: textSecondary.withValues(alpha: 0.78),
          fontSize: 13,
        ),
        prefixIconColor: fgNavyBlue,
        suffixIconColor: textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: fgNavyBlue, width: 1.7),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: Colors.white.withValues(alpha: 0.98),
        surfaceTintColor: Colors.transparent,
        indicatorColor: fgNavyBlue.withValues(alpha: 0.10),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);

          return GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? fgNavyBlue : textSecondary,
          );
        }),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: fgNavyBlue,
        indicatorColor: Colors.white.withValues(alpha: 0.13),
        selectedIconTheme: const IconThemeData(color: fgGold, size: 25),
        unselectedIconTheme: const IconThemeData(
          color: Colors.white70,
          size: 23,
        ),
      ),

      dividerTheme: const DividerThemeData(color: border, thickness: 1),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: fgGold,
        foregroundColor: fgNavyBlue,
        elevation: 2,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: fgNavyBlue.withValues(alpha: 0.11),
        checkmarkColor: fgNavyBlue,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: fgNavyBlue,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );
  }
}
