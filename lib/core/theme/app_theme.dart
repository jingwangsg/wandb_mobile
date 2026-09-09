import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF17191C) : const Color(0xFFF7F7F7);
    final surface = dark ? const Color(0xFF25282C) : Colors.white;
    final text = dark ? const Color(0xFFF0F1F3) : const Color(0xFF2B2E35);
    final secondary = dark ? const Color(0xFFA2A7AE) : const Color(0xFF7F858E);
    final scheme = ColorScheme.fromSeed(
      seedColor: WandbColors.teal,
      brightness: brightness,
      primary: WandbColors.teal,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: secondary,
      error: WandbColors.failed,
      outlineVariant: dark ? const Color(0xFF3B3F46) : const Color(0xFFE0E2E5),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'SourceSans3',
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: 'SourceSans3',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.5,
        space: 1,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: text,
        unselectedLabelColor: secondary,
        indicatorColor: WandbColors.teal,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(
          fontFamily: 'SourceSans3',
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        dividerColor: scheme.outlineVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF2A2D32) : const Color(0xFFEEEEEF),
        hintStyle: TextStyle(color: secondary, fontSize: 17),
        prefixIconColor: secondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: WandbColors.teal,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: 'SourceSans3',
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        showDragHandle: true,
      ),
      textTheme: base.textTheme.copyWith(
        bodyLarge: TextStyle(
          fontFamily: 'SourceSans3',
          fontSize: 17,
          color: text,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'SourceSans3',
          fontSize: 16,
          color: text,
        ),
        bodySmall: TextStyle(
          fontFamily: 'SourceSans3',
          fontSize: 14,
          color: secondary,
        ),
        titleMedium: TextStyle(
          fontFamily: 'SourceSans3',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}
