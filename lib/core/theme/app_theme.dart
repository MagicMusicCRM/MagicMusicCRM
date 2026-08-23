import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'telegram_colors.dart';

class AppTheme {
  // ── Live presentation aliases; remove after consumers use AppColor. ──────
  static const Color primaryGold = TelegramColors.primaryGold;
  static const Color secondaryGold = TelegramColors.secondaryGold;
  static const Color softGold = TelegramColors.softGold;
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
    final theme = ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.dark(
        primary: TelegramColors.brandGold,
        secondary: AppColor.actionBlue,
        tertiary: AppColor.transferCyan,
        surface: TelegramColors.darkSurface,
        onPrimary: AppColor.onGold,
        onSecondary: Colors.white,
        onSurface: TelegramColors.darkTextPrimary,
        error: AppColor.danger,
      ),
      scaffoldBackgroundColor: TelegramColors.darkBg,
      cardTheme: CardThemeData(
        color: TelegramColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        },
      ),
      scrollbarTheme: _scrollbarTheme(
        thumb: TelegramColors.darkTextSecondary,
        track: TelegramColors.darkDivider,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: TelegramColors.darkSurface,
        selectedItemColor: TelegramColors.brandGold,
        unselectedItemColor: TelegramColors.darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: TelegramColors.darkSurface,
        indicatorColor: TelegramColors.brandGold.withAlpha(34),
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: TelegramColors.brandGold);
          }
          return const IconThemeData(color: TelegramColors.darkTextSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: TelegramColors.brandGold,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: TelegramColors.darkTextSecondary,
            fontSize: 12,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TelegramColors.darkInputBg,
        labelStyle: const TextStyle(color: TelegramColors.darkTextSecondary),
        hintStyle: TextStyle(
          color: TelegramColors.darkTextSecondary.withAlpha(130),
        ),
        prefixIconColor: TelegramColors.darkTextSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColor.actionBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColor.actionBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColor.actionBlue,
          elevation: 0,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: TelegramColors.darkDivider,
        thickness: 1,
        space: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: TelegramColors.darkTextPrimary,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          color: TelegramColors.darkTextPrimary,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: TextStyle(
          color: TelegramColors.darkTextPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: TelegramColors.darkTextPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: TelegramColors.darkTextPrimary,
          fontWeight: FontWeight.w500,
        ),
        titleSmall: TextStyle(
          color: TelegramColors.darkTextSecondary,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(color: TelegramColors.darkTextPrimary),
        bodyMedium: TextStyle(color: TelegramColors.darkTextPrimary),
        bodySmall: TextStyle(color: TelegramColors.darkTextSecondary),
        labelLarge: TextStyle(
          color: TelegramColors.darkTextPrimary,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: TextStyle(color: TelegramColors.darkTextSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: TelegramColors.darkSurface,
        contentTextStyle: const TextStyle(
          color: TelegramColors.darkTextPrimary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColor.actionBlue,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        disabledElevation: 0,
        highlightElevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: TelegramColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TelegramColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
    );
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'Inter'),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Inter'),
    );
  }

  static ScrollbarThemeData _scrollbarTheme({
    required Color thumb,
    required Color track,
  }) {
    return ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(thumb.withValues(alpha: 0.72)),
      trackColor: WidgetStatePropertyAll(track.withValues(alpha: 0.5)),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      thickness: const WidgetStatePropertyAll(10),
      radius: const Radius.circular(AppRadius.pill),
      crossAxisMargin: 2,
      mainAxisMargin: 2,
    );
  }
}

/// A scroll behavior that removes the glow effect.
class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
