import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Golden-locks the v7 design tokens against the owner-approved palette.
/// If a value here drifts from the prototype, this test must be the deliberate
/// place it changes.
void main() {
  group('AppColor — v7 :root palette', () {
    test('core surfaces + text', () {
      expect(AppColor.bg, const Color(0xFF101114)); // --bg
      expect(AppColor.surface, const Color(0xFF181B20)); // --surface
      expect(AppColor.sidebar, const Color(0xFF14161A)); // --sidebar
      expect(AppColor.input, const Color(0xFF20242B)); // --input
      expect(AppColor.divider, const Color(0xFF313741)); // --divider
      expect(AppColor.text, const Color(0xFFF1F3F5)); // --text
      expect(AppColor.text2, const Color(0xFFAAB2BF)); // --text-2
    });

    test('brand gold + derived tokens', () {
      expect(AppColor.gold, const Color(0xFFC9A85E)); // --gold
      expect(AppColor.gold2, const Color(0xFFD6B778)); // --gold-2
      expect(AppColor.goldSoft, const Color(0x24C9A85E)); // rgba(.,.,.,.14)
      expect(AppColor.goldLine, const Color(0x57C9A85E)); // rgba(.,.,.,.34)
      expect(AppColor.onGold, const Color(0xFF1A1408)); // .btn-primary color
    });

    test('work accents', () {
      expect(AppColor.actionBlue, const Color(0xFF3B82F6));
      expect(AppColor.transferCyan, const Color(0xFF14B8A6));
      expect(AppColor.infoViolet, const Color(0xFF8B5CF6));
    });

    test('status colors', () {
      expect(AppColor.success, const Color(0xFF22C55E)); // --success
      expect(AppColor.warning, const Color(0xFFF59E0B)); // --warning
      expect(AppColor.danger, const Color(0xFFEF4444)); // --danger
    });

    test('overlay chrome (toast / pop-menu / sheet / skeleton / scrim)', () {
      expect(AppColor.overlay, const Color(0xFF20242B)); // .toast/.popmenu bg
      expect(AppColor.menuItemText, const Color(0xFFE8EAED)); // .pm-item
      expect(AppColor.menuItemHover, const Color(0xFF252A31)); // .pm-item:hover
      expect(AppColor.menuDanger, const Color(0xFFFCA5A5)); // .pm-item.danger
      expect(AppColor.dangerSoft, const Color(0x24EF4444)); // danger hover
      expect(AppColor.scrim, const Color(0x990A0B0D)); // .sheet-scrim
      expect(AppColor.sheetGrab, const Color(0xFF3A414C)); // .sheet-grab
      expect(AppColor.skeletonBase, const Color(0xFF20242B)); // .skel
      expect(
        AppColor.skeletonHighlight,
        const Color(0x0FFFFFFF),
      ); // .skel::after
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

  group('AppTheme — v7 token alignment (no regression elsewhere)', () {
    test('error color tracks v7 --danger', () {
      expect(AppTheme.dark.colorScheme.error, AppColor.danger);
      expect(AppTheme.light.colorScheme.error, AppColor.danger);
    });

    test(
      'primary actions use action blue while navigation keeps brand gold',
      () {
        expect(AppTheme.dark.colorScheme.primary, AppColor.gold);
        expect(AppTheme.dark.colorScheme.secondary, AppColor.actionBlue);
        expect(AppTheme.dark.colorScheme.tertiary, AppColor.transferCyan);
      },
    );

    test('card radius tracks --r-card (14)', () {
      final darkShape = AppTheme.dark.cardTheme.shape;
      expect(darkShape, isA<RoundedRectangleBorder>());
      expect(
        (darkShape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(AppRadius.card),
      );
    });

    test('legacy AppTheme.danger alias stays red semantic token', () {
      expect(AppTheme.danger, const Color(0xFFEF4444));
    });
  });
}
