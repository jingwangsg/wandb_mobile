import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: WandbColors.darkBg,
      colorScheme: ColorScheme.dark(
        primary: WandbColors.yellow,
        secondary: WandbColors.yellow,
        surface: WandbColors.surface,
        error: WandbColors.failed,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: WandbColors.darkBg,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: WandbColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: WandbColors.darkBg,
        selectedItemColor: WandbColors.yellow,
        unselectedItemColor: Colors.white54,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: WandbColors.surfaceElevated,
        selectedColor: WandbColors.yellow.withValues(alpha: 0.3),
        labelStyle: GoogleFonts.inter(fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WandbColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        // Monospace for metric values
        labelSmall: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          color: Colors.white70,
        ),
        bodySmall: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: Colors.white70,
        ),
      ),
      dividerColor: Colors.white12,
    );
  }

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.light(
        primary: WandbColors.yellow,
        secondary: WandbColors.yellow,
        surface: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
    );
  }
}
