/// v7 design tokens — the single locked source of truth for the redesign.
///
/// Values are extracted verbatim from the owner-approved prototype
/// `docs/prototypes/crm-redesign-v7.html` (`:root` block + component CSS).
/// This is the Phase 0 / KVA-193 deliverable: a token layer the reskin phases
/// (P1–P7) build every screen on, so the running app converges on a single
/// design language instead of per-screen ad-hoc literals.
///
/// Backward compatibility: the existing palette already lives in
/// [TelegramColors]; these tokens reuse those exact constants where they match
/// and only ADD the v7 tokens that were missing (gold-soft / gold-line, overlay
/// surface, skeleton shimmer, scrim, on-gold text, etc.). Nothing here is
/// mounted by itself — it is consumed by [AppTheme] and the shared component
/// library, both additive in P0.
///
/// The token test `test/theme/design_tokens_test.dart` golden-locks every value
/// below against the prototype `:root`, per the migration plan §0 / §5a.
library;

import 'package:flutter/material.dart';

import 'telegram_colors.dart';

/// v7 color tokens (`:root` `--*` + component colors).
class AppColor {
  AppColor._();

  // ── Core surfaces (match TelegramColors dark palette 1:1) ────────────────
  /// `--bg:#101012`
  static const Color bg = TelegramColors.darkBg; // 0xFF101012
  /// `--surface:#1A1A1D`
  static const Color surface = TelegramColors.darkSurface; // 0xFF1A1A1D
  /// `--sidebar:#151518`
  static const Color sidebar = TelegramColors.darkSidebar; // 0xFF151518
  /// `--input:#242427`
  static const Color input = TelegramColors.darkInputBg; // 0xFF242427
  /// `--divider:#2A2A2D`
  static const Color divider = TelegramColors.darkDivider; // 0xFF2A2A2D

  // ── Text ─────────────────────────────────────────────────────────────────
  /// `--text:#FFFFFF`
  static const Color text = TelegramColors.darkTextPrimary; // 0xFFFFFFFF
  /// `--text-2:#A1A1AA`
  static const Color text2 = TelegramColors.darkTextSecondary; // 0xFFA1A1AA

  // ── Brand gold ─────────────────────────────────────────────────────────────
  /// `--gold:#C5A059`
  static const Color gold = TelegramColors.primaryGold; // 0xFFC5A059
  /// `--gold-2:#BFA37E`
  static const Color gold2 = TelegramColors.secondaryGold; // 0xFFBFA37E

  /// `--gold-soft:rgba(197,160,89,.14)` — active row / chip-on / hover fills.
  static const Color goldSoft = Color(0x24C5A059); // alpha .14 ≈ 0x24
  /// `--gold-line:rgba(197,160,89,.34)` — gold hairline borders / focus rings.
  static const Color goldLine = Color(0x57C5A059); // alpha .34 ≈ 0x57

  /// Text/icon color ON a gold fill (`.btn-primary{color:#1a1408}`).
  static const Color onGold = Color(0xFF1A1408);

  // ── Status ─────────────────────────────────────────────────────────────────
  /// `--success:#10B981`
  static const Color success = TelegramColors.success; // 0xFF10B981
  /// `--danger:#E53935` (v7 red; note: legacy [TelegramColors.danger] is
  /// #EF4444 — kept for back-compat, but v7 surfaces use this one).
  static const Color danger = Color(0xFFE53935);

  // ── Overlay chrome (toast / pop-menu share `#202024`) ──────────────────────
  /// `.toast` / `.popmenu` background `#202024` — one notch above [surface].
  static const Color overlay = Color(0xFF202024);

  /// Pop-menu item idle label color (`.pm-item{color:#e6e6ea}`).
  static const Color menuItemText = Color(0xFFE6E6EA);
  /// Pop-menu item hover fill (`.pm-item:hover{background:#2a2a30}`).
  static const Color menuItemHover = Color(0xFF2A2A30);
  /// Pop-menu destructive item label (`.pm-item.danger{color:#f08581}`).
  static const Color menuDanger = Color(0xFFF08581);
  /// Destructive hover fill `rgba(229,57,53,.1)`.
  static const Color dangerSoft = Color(0x1AE53935);

  // ── Modal scrim (`.sheet-scrim{background:rgba(8,8,10,.6)}`) ────────────────
  static const Color scrim = Color(0x9908080A); // alpha .6 ≈ 0x99

  // ── Sheet grabber (`.sheet-grab{background:#3a3a40}`) ───────────────────────
  static const Color sheetGrab = Color(0xFF3A3A40);

  // ── Skeleton shimmer (`.skel`) ─────────────────────────────────────────────
  /// `.skel{background:#1d1d21}`
  static const Color skeletonBase = Color(0xFF1D1D21);
  /// `.skel::after` sweep highlight `rgba(255,255,255,.06)`.
  static const Color skeletonHighlight = Color(0x0FFFFFFF); // alpha .06 ≈ 0x0F
}

/// v7 corner radii (`--r-card`, `--r-ctrl` + component literals).
class AppRadius {
  AppRadius._();

  /// `--r-card:14px` — cards, drawer/dialog bodies.
  static const double card = 14;
  /// `--r-ctrl:10px` — buttons, inputs, selects, search.
  static const double control = 10;
  /// `.chip{border-radius:9px}` / `.pm-item{border-radius:9px}`.
  static const double chip = 9;
  /// `.toast` / `.popmenu` `border-radius:13px`.
  static const double overlay = 13;
  /// `.sheet{border-radius:18px 18px 0 0}` — top corners of a bottom sheet.
  static const double sheet = 18;
  /// `.icon-badge` / app-bar icons `border-radius:11px`.
  static const double icon = 11;
  /// Small chrome (`.skel-line`, ticks) `border-radius:6px`.
  static const double sm = 6;
  /// Fully-rounded (`border-radius:99px`) pills / grabbers / dots.
  static const double pill = 999;
}

/// v7 spacing scale (recurring padding/gap literals in the prototype).
class AppSpace {
  AppSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  /// Drawer body padding/gap (`.drawer-body{padding:18px;gap:18px}`).
  static const double drawerBody = 18;
  /// Sheet body padding (`.sheet-body{padding:16px 20px;gap:15px}`).
  static const EdgeInsets sheetBody =
      EdgeInsets.symmetric(horizontal: 20, vertical: 16);
  static const double sheetBodyGap = 15;
}

/// v7 motion (`--ease` + per-component durations).
class AppMotion {
  AppMotion._();

  /// `--ease:cubic-bezier(0.22,1,0.36,1)` — the project's standard easing.
  static const Cubic ease = Cubic(0.22, 1.0, 0.36, 1.0);

  /// `.popmenu`/`.toast` enter (`transition … .16s`).
  static const Duration fast = Duration(milliseconds: 160);
  /// `.sheet-scrim` (`.24s`).
  static const Duration medium = Duration(milliseconds: 240);
  /// `.drawer` enter/exit (`.3s`). (`.sheet` is `.32s` in CSS but rides
  /// `showModalBottomSheet`'s built-in animation, not this token.)
  static const Duration slow = Duration(milliseconds: 300);
  /// `@keyframes shimmer` (`1.15s`).
  static const Duration shimmer = Duration(milliseconds: 1150);
}

/// v7 elevation tokens (`--sh-1`, `--sh-2`, `--sh-lift`).
///
/// Per the Magic Music operational rules, shadows/glow are forbidden on
/// primary buttons — these tokens are for floating chrome only (drawers,
/// sheets, pop-menus, toasts, lifted drag cards).
class AppShadow {
  AppShadow._();

  /// `--sh-1:0 1px 2px rgba(0,0,0,.4)`.
  static const List<BoxShadow> sh1 = [
    BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// `--sh-2:0 8px 24px rgba(0,0,0,.45)` — drawers / sheets / pop-menus.
  static const List<BoxShadow> sh2 = [
    BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// `--sh-lift:0 18px 44px rgba(0,0,0,.55)` (+ gold-line ring rendered as a
  /// [Border], not a shadow) — picked-up drag cards.
  static const List<BoxShadow> shLift = [
    BoxShadow(color: Color(0x8C000000), blurRadius: 44, offset: Offset(0, 18)),
  ];
}

/// Typography tokens. v7 uses Inter; the app does not bundle it yet, so
/// [fontFamily] is null (platform default) until the TTFs are added under
/// `fonts:` in pubspec. [target] documents the intended family.
class AppType {
  AppType._();

  /// Active app font family. `null` = platform default (Roboto/SF/Segoe).
  /// TODO(P0): bundle Inter TTFs and set this to [target].
  static const String? fontFamily = null;

  /// The v7-specified family (`font-family:'Inter'`).
  static const String target = 'Inter';
}

/// v7 stacking order (`--z-*`) — use when composing overlays in a [Stack] so
/// drawers sit above the app bar, sheets above drawers, toasts above sheets.
class AppZ {
  AppZ._();

  static const int nav = 20;
  static const int appbar = 25;
  static const int drawerBackdrop = 60;
  static const int drawer = 70;
  static const int sheetBackdrop = 80;
  static const int sheet = 90;
  static const int drag = 120;
  static const int toast = 130;
  static const int tooltip = 140;
}
