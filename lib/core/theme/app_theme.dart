import 'package:flutter/material.dart';

import 'design_tokens.dart';

class AppTheme {
  AppTheme._();

  // Compatibility aliases while widgets move to AppColor semantic names.
  static const Color primaryGold = AppColor.gold;
  static const Color secondaryGold = AppColor.gold2;
  static const Color softGold = AppColor.goldSoft;
  static const Color bgDark = AppColor.bg;
  static const Color surfaceDark = AppColor.surface;
  static const Color cardDark = AppColor.input;
  static const Color textPrimary = AppColor.text;
  static const Color textSecondary = AppColor.text2;
  static const Color success = AppColor.success;
  static const Color danger = AppColor.danger;
  static const Color warning = AppColor.warning;
  static const Color surfaceColor = AppColor.surface;

  /// The only runtime theme. The name is theme-neutral so new widgets do not
  /// branch between parallel design systems.
  static ThemeData get production => light;

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = base.textTheme
        .apply(
          fontFamily: 'Inter',
          bodyColor: AppColor.text,
          displayColor: AppColor.text,
        )
        .copyWith(
          titleSmall: base.textTheme.titleSmall?.copyWith(
            color: AppColor.text2,
            fontFamily: 'Inter',
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            color: AppColor.text2,
            fontFamily: 'Inter',
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            color: AppColor.text2,
            fontFamily: 'Inter',
          ),
        );

    const scheme = ColorScheme.light(
      primary: AppColor.brandSolid,
      onPrimary: AppColor.onBrand,
      primaryContainer: AppColor.selectionBg,
      onPrimaryContainer: AppColor.selectionText,
      secondary: AppColor.actionBlue,
      onSecondary: AppPalette.white,
      secondaryContainer: AppColor.infoSoft,
      onSecondaryContainer: AppColor.text,
      tertiary: AppColor.transferCyan,
      onTertiary: AppPalette.white,
      surface: AppColor.surface,
      onSurface: AppColor.text,
      onSurfaceVariant: AppColor.text2,
      surfaceContainerLowest: AppColor.surface,
      surfaceContainerLow: AppColor.surfaceSoft,
      surfaceContainer: AppColor.surfaceSoft,
      surfaceContainerHigh: AppColor.surfaceActive,
      surfaceContainerHighest: AppColor.surfaceActive,
      surfaceBright: AppColor.surface,
      surfaceDim: AppColor.surfaceSoft,
      error: AppColor.danger,
      onError: AppPalette.white,
      errorContainer: AppColor.dangerSoft,
      onErrorContainer: AppColor.danger,
      outline: AppColor.borderStrong,
      outlineVariant: AppColor.divider,
      shadow: Color(0x29302819),
      scrim: AppColor.scrim,
      inverseSurface: AppColor.text,
      onInverseSurface: AppColor.bg,
      inversePrimary: AppColor.gold2,
      surfaceTint: Colors.transparent,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColor.bg,
      canvasColor: AppColor.bg,
      disabledColor: AppColor.disabledText,
      dividerColor: AppColor.divider,
      focusColor: AppColor.focus.withValues(alpha: 0.16),
      hoverColor: AppColor.selectionHover,
      highlightColor: AppColor.selectionBg,
      splashColor: AppColor.selectionBg.withValues(alpha: 0.72),
      iconTheme: const IconThemeData(color: AppColor.text2),
      primaryIconTheme: const IconThemeData(color: AppColor.text),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      cardTheme: CardThemeData(
        color: AppColor.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColor.divider),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColor.surface,
        foregroundColor: AppColor.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColor.text,
          fontFamily: 'Inter',
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
        thumb: AppColor.text3,
        track: AppColor.surfaceSoft,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColor.surface,
        selectedItemColor: AppColor.gold,
        unselectedItemColor: AppColor.text2,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColor.surface,
        indicatorColor: AppColor.selectionBg,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColor.gold);
          }
          return const IconThemeData(color: AppColor.text2);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColor.selectionText,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: AppColor.text2,
            fontFamily: 'Inter',
            fontSize: 12,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColor.input,
        labelStyle: const TextStyle(color: AppColor.text2),
        hintStyle: const TextStyle(color: AppColor.text3),
        prefixIconColor: AppColor.text2,
        suffixIconColor: AppColor.text2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColor.borderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColor.borderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColor.focus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColor.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColor.danger, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: AppColor.borderSoft),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColor.brandSolid,
          foregroundColor: AppColor.onBrand,
          disabledBackgroundColor: AppColor.disabledSurface,
          disabledForegroundColor: AppColor.disabledText,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColor.brandSolid,
          foregroundColor: AppColor.onBrand,
          disabledBackgroundColor: AppColor.disabledSurface,
          disabledForegroundColor: AppColor.disabledText,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColor.text,
          disabledForegroundColor: AppColor.disabledText,
          side: const BorderSide(color: AppColor.borderStrong),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColor.actionBlue,
          disabledForegroundColor: AppColor.disabledText,
          elevation: 0,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColor.text2,
          disabledForegroundColor: AppColor.disabledText,
          highlightColor: AppColor.selectionBg,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColor.divider,
        thickness: 1,
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColor.overlay,
        contentTextStyle: const TextStyle(
          color: AppColor.text,
          fontFamily: 'Inter',
        ),
        actionTextColor: AppColor.actionBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: const BorderSide(color: AppColor.divider),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColor.brandSolid,
        foregroundColor: AppColor.onBrand,
        shape: CircleBorder(),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        disabledElevation: 0,
        highlightElevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColor.overlay,
        surfaceTintColor: Colors.transparent,
        textStyle: const TextStyle(color: AppColor.menuItemText),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColor.divider),
        ),
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColor.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColor.divider),
        ),
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColor.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColor.surface,
        modalBarrierColor: AppColor.scrim,
        elevation: 0,
        modalElevation: 0,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColor.surfaceSoft,
        selectedColor: AppColor.selectionBg,
        disabledColor: AppColor.disabledSurface,
        labelStyle: const TextStyle(color: AppColor.text),
        secondaryLabelStyle: const TextStyle(color: AppColor.selectionText),
        side: const BorderSide(color: AppColor.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColor.text,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: AppColor.bg, fontFamily: 'Inter'),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColor.brandSolid;
          }
          return AppColor.surface;
        }),
        checkColor: const WidgetStatePropertyAll(AppColor.onBrand),
        side: const BorderSide(color: AppColor.borderStrong),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColor.brandSolid;
          return AppColor.text2;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColor.onBrand;
          return AppColor.text3;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColor.brandSolid;
          return AppColor.divider;
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColor.brandSolid,
        linearTrackColor: AppColor.surfaceSoft,
        circularTrackColor: AppColor.surfaceSoft,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: AppColor.text,
        iconColor: AppColor.text2,
        selectedColor: AppColor.selectionText,
        selectedTileColor: AppColor.selectionBg,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColor.focus,
        selectionColor: Color(0x553B73D1),
        selectionHandleColor: AppColor.focus,
      ),
    );
  }

  /// Compile-compatible bridge for existing tests and widgets. It resolves to
  /// the same light ThemeData; there is no dark runtime design system.
  @Deprecated('Use AppTheme.production')
  static ThemeData get dark => production;

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
