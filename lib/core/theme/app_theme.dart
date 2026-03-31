import 'package:flutter/material.dart';
import 'telegram_colors.dart';

class AppTheme {
  // ── Legacy brand references (kept for compatibility) ────────────────────
  static const Color primaryPurple = TelegramColors.brandPurple;
  static const Color secondaryGold = TelegramColors.brandGold;
  static const Color bgDark = TelegramColors.darkBg;
  static const Color surfaceDark = TelegramColors.darkSurface;
  static const Color cardDark = TelegramColors.darkInputBg;
  static const Color textPrimary = TelegramColors.darkTextPrimary;
  static const Color textSecondary = TelegramColors.darkTextSecondary;
  static const Color success = TelegramColors.success;
  static const Color danger = TelegramColors.danger;
  static const Color warning = TelegramColors.warning;
  static const Color surfaceColor = cardDark;

  // ── Dark Theme (Telegram-inspired) ─────────────────────────────────────
  static ThemeData get dark {
    return ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.dark(
        primary: TelegramColors.accentBlue,
        secondary: TelegramColors.brandPurple,
        surface: TelegramColors.darkSurface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: TelegramColors.darkTextPrimary,
        error: TelegramColors.danger,
      ),
      scaffoldBackgroundColor: TelegramColors.darkBg,
      cardTheme: CardThemeData(
        color: TelegramColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TelegramColors.darkSurface,
        foregroundColor: TelegramColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: TelegramColors.darkTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: TelegramColors.darkSurface,
        selectedItemColor: TelegramColors.accentBlue,
        unselectedItemColor: TelegramColors.darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: TelegramColors.darkSurface,
        indicatorColor: TelegramColors.accentBlue.withAlpha(30),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: TelegramColors.accentBlue);
          }
          return const IconThemeData(color: TelegramColors.darkTextSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: TelegramColors.accentBlue, fontWeight: FontWeight.w600, fontSize: 12);
          }
          return const TextStyle(color: TelegramColors.darkTextSecondary, fontSize: 12);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TelegramColors.darkInputBg,
        labelStyle: const TextStyle(color: TelegramColors.darkTextSecondary),
        hintStyle: TextStyle(color: TelegramColors.darkTextSecondary.withAlpha(130)),
        prefixIconColor: TelegramColors.darkTextSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: TelegramColors.accentBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TelegramColors.accentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: TelegramColors.accentBlue),
      ),
      dividerTheme: const DividerThemeData(
        color: TelegramColors.darkDivider,
        thickness: 1,
        space: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: TelegramColors.darkTextPrimary, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(color: TelegramColors.darkTextPrimary, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(color: TelegramColors.darkTextPrimary, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: TelegramColors.darkTextPrimary, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: TelegramColors.darkTextPrimary, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(color: TelegramColors.darkTextSecondary, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: TelegramColors.darkTextPrimary),
        bodyMedium: TextStyle(color: TelegramColors.darkTextPrimary),
        bodySmall: TextStyle(color: TelegramColors.darkTextSecondary),
        labelLarge: TextStyle(color: TelegramColors.darkTextPrimary, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: TelegramColors.darkTextSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: TelegramColors.darkSurface,
        contentTextStyle: const TextStyle(color: TelegramColors.darkTextPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: TelegramColors.accentBlue,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: TelegramColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TelegramColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // ── Light Theme (Telegram-inspired) ────────────────────────────────────
  static ThemeData get light {
    return ThemeData.light(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.light(
        primary: TelegramColors.accentBlue,
        secondary: TelegramColors.brandPurple,
        surface: TelegramColors.lightSurface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: TelegramColors.lightTextPrimary,
        error: TelegramColors.danger,
      ),
      scaffoldBackgroundColor: TelegramColors.lightBg,
      cardTheme: CardThemeData(
        color: TelegramColors.lightBg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TelegramColors.lightBg,
        foregroundColor: TelegramColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: TelegramColors.lightTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TelegramColors.lightInputBg,
        labelStyle: const TextStyle(color: TelegramColors.lightTextSecondary),
        hintStyle: TextStyle(color: TelegramColors.lightTextSecondary.withAlpha(130)),
        prefixIconColor: TelegramColors.lightTextSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: TelegramColors.accentBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TelegramColors.accentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: TelegramColors.accentBlue),
      ),
      dividerTheme: const DividerThemeData(
        color: TelegramColors.lightDivider,
        thickness: 0.5,
        space: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: TelegramColors.lightTextPrimary, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(color: TelegramColors.lightTextPrimary, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(color: TelegramColors.lightTextPrimary, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: TelegramColors.lightTextPrimary, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: TelegramColors.lightTextPrimary, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(color: TelegramColors.lightTextSecondary, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: TelegramColors.lightTextPrimary),
        bodyMedium: TextStyle(color: TelegramColors.lightTextPrimary),
        bodySmall: TextStyle(color: TelegramColors.lightTextSecondary),
        labelLarge: TextStyle(color: TelegramColors.lightTextPrimary, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: TelegramColors.lightTextSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: TelegramColors.lightBg,
        contentTextStyle: const TextStyle(color: TelegramColors.lightTextPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: TelegramColors.accentBlue,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: TelegramColors.lightBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TelegramColors.lightBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
