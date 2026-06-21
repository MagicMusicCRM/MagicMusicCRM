import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Golden-locks the v7 design tokens against the owner-approved prototype
/// `docs/prototypes/crm-redesign-v7.html` `:root` (migration plan §0 / §5a).
/// If a value here drifts from the prototype, this test must be the deliberate
/// place it changes.
void main() {
  group('AppColor — v7 :root palette', () {
    test('core surfaces + text', () {
      expect(AppColor.bg, const Color(0xFF101012)); // --bg
      expect(AppColor.surface, const Color(0xFF1A1A1D)); // --surface
      expect(AppColor.sidebar, const Color(0xFF151518)); // --sidebar
      expect(AppColor.input, const Color(0xFF242427)); // --input
      expect(AppColor.divider, const Color(0xFF2A2A2D)); // --divider
      expect(AppColor.text, const Color(0xFFFFFFFF)); // --text
      expect(AppColor.text2, const Color(0xFFA1A1AA)); // --text-2
    });

    test('brand gold + derived tokens', () {
      expect(AppColor.gold, const Color(0xFFC5A059)); // --gold
      expect(AppColor.gold2, const Color(0xFFBFA37E)); // --gold-2
      expect(AppColor.goldSoft, const Color(0x24C5A059)); // rgba(.,.,.,.14)
      expect(AppColor.goldLine, const Color(0x57C5A059)); // rgba(.,.,.,.34)
      expect(AppColor.onGold, const Color(0xFF1A1408)); // .btn-primary color
    });

    test('status colors', () {
      expect(AppColor.success, const Color(0xFF10B981)); // --success
      expect(AppColor.danger, const Color(0xFFE53935)); // --danger (v7)
    });

    test('overlay chrome (toast / pop-menu / sheet / skeleton / scrim)', () {
      expect(AppColor.overlay, const Color(0xFF202024)); // .toast/.popmenu bg
      expect(AppColor.menuItemText, const Color(0xFFE6E6EA)); // .pm-item
      expect(AppColor.menuItemHover, const Color(0xFF2A2A30)); // .pm-item:hover
      expect(AppColor.menuDanger, const Color(0xFFF08581)); // .pm-item.danger
      expect(AppColor.dangerSoft, const Color(0x1AE53935)); // danger hover
      expect(AppColor.scrim, const Color(0x9908080A)); // .sheet-scrim
      expect(AppColor.sheetGrab, const Color(0xFF3A3A40)); // .sheet-grab
      expect(AppColor.skeletonBase, const Color(0xFF1D1D21)); // .skel
      expect(AppColor.skeletonHighlight, const Color(0x0FFFFFFF)); // .skel::after
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

    test('card radius tracks --r-card (14)', () {
      final darkShape = AppTheme.dark.cardTheme.shape;
      expect(darkShape, isA<RoundedRectangleBorder>());
      expect(
        (darkShape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(AppRadius.card),
      );
    });

    test('legacy AppTheme.danger alias is unchanged (back-compat)', () {
      // Existing screens/tests depend on the legacy alias staying #EF4444.
      expect(AppTheme.danger, const Color(0xFFEF4444));
    });
  });
}
