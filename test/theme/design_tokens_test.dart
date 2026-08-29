import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Locks the owner-approved Quiet Graphite foundation and semantic contrast.
void main() {
  group('AppColor — approved light semantic palette', () {
    test('core surfaces + text', () {
      expect(AppColor.bg, const Color(0xFFEFF0ED));
      expect(AppColor.surface, const Color(0xFFF7F7F5));
      expect(AppColor.surfaceSoft, const Color(0xFFF1F2EF));
      expect(AppColor.surfaceActive, const Color(0xFFF1F2EF));
      expect(AppColor.sidebar, const Color(0xFFE8EAE6));
      expect(AppColor.input, const Color(0xFFF7F7F5));
      expect(AppColor.divider, const Color(0xFFDFE2DC));
      expect(AppColor.borderStrong, const Color(0xFFBCC2BA));
      expect(AppColor.text, const Color(0xFF1C1F1B));
      expect(AppColor.text2, const Color(0xFF626760));
      expect(AppColor.text3, const Color(0xFF858A83));
    });

    test('one brand gold + neutral selection tokens', () {
      expect(AppColor.gold, const Color(0xFF765417));
      expect(AppColor.gold2, const Color(0xFF765417));
      expect(AppColor.goldSoft, const Color(0xFFE6E7E2));
      expect(AppColor.goldLine, const Color(0xFFBEC4BC));
      expect(AppColor.onGold, const Color(0xFFFFFAF0));
      expect(AppColor.onBrand, const Color(0xFFFFFAF0));
      expect(AppColor.brandSolid, const Color(0xFF765417));
      expect(AppColor.brandSolidHover, const Color(0xFF62450F));
      expect(AppColor.selectionBg, const Color(0xFFE1E4DF));
      expect(AppColor.selectionHover, const Color(0xFFE9ECE7));
      expect(AppColor.selectionText, const Color(0xFF242823));
      expect(AppColor.selectionBorder, const Color(0xFFBEC4BC));
    });

    test('work accents', () {
      expect(AppColor.actionBlue, const Color(0xFF3B73D1));
      expect(AppColor.transferCyan, const Color(0xFF14B8A6));
      expect(AppColor.infoViolet, const Color(0xFF7154A2));
    });

    test('status colors', () {
      expect(AppColor.success, const Color(0xFF267A56));
      expect(AppColor.warning, const Color(0xFFA16816));
      expect(AppColor.danger, const Color(0xFFB94A42));
    });

    test('overlay chrome (toast / pop-menu / sheet / skeleton / scrim)', () {
      expect(AppColor.overlay, const Color(0xFFF7F7F5));
      expect(AppColor.menuItemText, const Color(0xFF1C1F1B));
      expect(AppColor.menuItemHover, const Color(0xFFF1F2EF));
      expect(AppColor.menuDanger, const Color(0xFFB94A42));
      expect(AppColor.dangerSoft, const Color(0xFFFBECEB));
      expect(AppColor.scrim, const Color(0x661C1F1B));
      expect(AppColor.sheetGrab, const Color(0xFFBCC2BA));
      expect(AppColor.skeletonBase, const Color(0xFFDFE2DC));
      expect(AppColor.skeletonHighlight, const Color(0x99F7F7F5));
    });

    test('critical foreground pairs meet WCAG contrast', () {
      _expectContrast(AppColor.text, AppColor.bg, 4.5);
      _expectContrast(AppColor.text2, AppColor.bg, 4.5);
      _expectContrast(AppColor.onGold, AppColor.gold, 4.5);
      _expectContrast(AppColor.onBrand, AppColor.brandSolid, 4.5);
      _expectContrast(AppColor.selectionText, AppColor.selectionBg, 4.5);
      _expectContrast(AppColor.actionBlue, AppColor.surface, 3);
      _expectContrast(AppColor.danger, AppColor.surface, 4.5);
      _expectContrast(AppColor.success, AppColor.surface, 4.5);
    });
  });

  group('AppRadius — v7 radii', () {
    test('card / control + component literals', () {
      expect(AppRadius.card, 14); // --r-card
      expect(AppRadius.control, 10); // --r-ctrl
      expect(AppRadius.chip, 9); // .chip / .pm-item
      expect(AppRadius.overlay, 13); // .toast / .popmenu
      expect(AppRadius.sheet, 18); // .sheet top corners
      expect(AppRadius.icon, 11); // .icon-badge
      expect(AppRadius.sm, 6); // .skel-line
      expect(AppRadius.pill, 999); // border-radius:99px
    });
  });

  group('AppMotion — v7 easing + durations', () {
    test('ease curve = cubic-bezier(0.22,1,0.36,1)', () {
      expect(AppMotion.ease, const Cubic(0.22, 1.0, 0.36, 1.0));
    });

    test('durations', () {
      expect(AppMotion.fast, const Duration(milliseconds: 160));
      expect(AppMotion.medium, const Duration(milliseconds: 240));
      expect(AppMotion.slow, const Duration(milliseconds: 300));
      expect(AppMotion.shimmer, const Duration(milliseconds: 1150));
    });
  });

  group('AppTheme — single light production theme', () {
    test('production surfaces use semantic light tokens', () {
      final theme = AppTheme.production;

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, AppColor.bg);
      expect(theme.colorScheme.surface, AppColor.surface);
      expect(theme.colorScheme.onSurface, AppColor.text);
      expect(theme.colorScheme.onSurfaceVariant, AppColor.text2);
      expect(theme.colorScheme.surfaceContainerLowest, AppColor.bg);
      expect(theme.colorScheme.surfaceContainerLow, AppColor.surfaceSoft);
      expect(theme.colorScheme.surfaceContainer, AppColor.surfaceSoft);
      expect(theme.colorScheme.surfaceContainerHigh, AppColor.surfaceActive);
      expect(theme.colorScheme.surfaceContainerHighest, AppColor.surfaceActive);
      expect(theme.colorScheme.shadow, const Color(0xFF1C1F1B));
      expect(theme.cardTheme.color, AppColor.surface);
      expect(theme.inputDecorationTheme.fillColor, AppColor.input);
      expect(theme.dialogTheme.backgroundColor, AppColor.surface);
      expect(theme.snackBarTheme.backgroundColor, AppColor.overlay);
    });

    test('workspace canvas is quietly distinct from elevated surfaces', () {
      final theme = AppTheme.production;
      final canvas = theme.colorScheme.surfaceContainerLowest;

      expect(canvas, AppColor.bg);
      expect(canvas.computeLuminance(), lessThan(0.9));
      _expectContrast(AppColor.surface, canvas, 1.05);
    });

    test('primary actions and navigation keep their distinct semantics', () {
      expect(AppTheme.production.colorScheme.primary, AppColor.brandSolid);
      expect(AppTheme.production.colorScheme.secondary, AppColor.actionBlue);
      expect(AppTheme.production.colorScheme.tertiary, AppColor.transferCyan);
      expect(
        AppTheme.production.bottomNavigationBarTheme.selectedItemColor,
        AppColor.gold,
      );
    });

    test('card radius tracks --r-card (14)', () {
      final shape = AppTheme.production.cardTheme.shape;
      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(AppRadius.card),
      );
    });

    test('legacy AppTheme.danger alias stays red semantic token', () {
      expect(AppTheme.danger, const Color(0xFFB94A42));
    });

    test('legacy dark getter resolves to the single production theme', () {
      expect(AppTheme.dark.brightness, Brightness.light);
      expect(AppTheme.dark.colorScheme.surface, AppColor.surface);
    });
  });
}

void _expectContrast(Color foreground, Color background, double minimum) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  final ratio = (lighter + 0.05) / (darker + 0.05);

  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason: '$foreground on $background has contrast $ratio',
  );
}
