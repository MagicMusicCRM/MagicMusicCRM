/// v7 design tokens — the single locked source of truth for the redesign.
///
/// Values are extracted verbatim from the owner-approved prototype
/// `docs/prototypes/crm-redesign-v7.html` (`:root` block + component CSS).
/// This is the Phase 0 / KVA-193 deliverable: a token layer the reskin phases
/// (P1–P7) build every screen on, so the running app converges on a single
/// design language instead of per-screen ad-hoc literals.
///
/// Deep Charcoal & Sophisticated Gold token source. The historical prototype
/// path is preserved exactly for active consumers; the existing palette lives in
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
  /// `--bg:#101114`
  static const Color bg = TelegramColors.darkBg; // 0xFF101114
  /// `--surface:#181B20`
  static const Color surface = TelegramColors.darkSurface; // 0xFF181B20
  /// `--sidebar:#14161A`
  static const Color sidebar = TelegramColors.darkSidebar; // 0xFF14161A
  /// `--input:#20242B`
  static const Color input = TelegramColors.darkInputBg; // 0xFF20242B
  /// `--divider:#313741`
  static const Color divider = TelegramColors.darkDivider; // 0xFF313741

  // ── Text ─────────────────────────────────────────────────────────────────
  /// `--text:#F1F3F5`
  static const Color text = TelegramColors.darkTextPrimary; // 0xFFF1F3F5
  /// `--text-2:#AAB2BF`
  static const Color text2 = TelegramColors.darkTextSecondary; // 0xFFAAB2BF

  // ── Brand gold ─────────────────────────────────────────────────────────────
  /// `--gold:#C9A85E`
  static const Color gold = TelegramColors.primaryGold; // 0xFFC9A85E
  /// `--gold-2:#D6B778`
  static const Color gold2 = TelegramColors.secondaryGold; // 0xFFD6B778

  /// `--gold-soft:rgba(201,168,94,.14)` — active row / chip-on / hover fills.
  static const Color goldSoft = Color(0x24C9A85E); // alpha .14 ≈ 0x24
  /// `--gold-line:rgba(201,168,94,.34)` — gold hairline borders / focus rings.
  static const Color goldLine = Color(0x57C9A85E); // alpha .34 ≈ 0x57

  /// Text/icon color ON a gold fill (`.btn-primary{color:#1a1408}`).
  static const Color onGold = Color(0xFF1A1408);

  // ── Work accents ───────────────────────────────────────────────────────────
  /// Work action blue: primary actions, filters, links, focused inputs.
  static const Color actionBlue = TelegramColors.actionBlue; // 0xFF3B82F6
  /// Transfer cyan: lead-to-student conversion and sync/transfer surfaces.
  static const Color transferCyan = TelegramColors.transferCyan; // 0xFF14B8A6
  /// Info violet: role/admin metadata and non-critical informational states.
  static const Color infoViolet = TelegramColors.infoViolet; // 0xFF8B5CF6

  // ── Status ─────────────────────────────────────────────────────────────────
  /// `--success:#22C55E`
  static const Color success = TelegramColors.success; // 0xFF22C55E
  /// `--warning:#F59E0B`
  static const Color warning = TelegramColors.warning; // 0xFFF59E0B
  /// `--danger:#EF4444`
  static const Color danger = TelegramColors.danger; // 0xFFEF4444

  // ── Overlay chrome (toast / pop-menu share `#20242B`) ──────────────────────
  /// `.toast` / `.popmenu` background `#20242B` — one notch above [surface].
  static const Color overlay = Color(0xFF20242B);

  /// Pop-menu item idle label color (`.pm-item{color:#e6e6ea}`).
  static const Color menuItemText = Color(0xFFE8EAED);

  /// Pop-menu item hover fill (`.pm-item:hover{background:#252A31}`).
  static const Color menuItemHover = Color(0xFF252A31);

  /// Pop-menu destructive item label (`.pm-item.danger{color:#f08581}`).
  static const Color menuDanger = Color(0xFFFCA5A5);

  /// Destructive hover fill `rgba(239,68,68,.14)`.
  static const Color dangerSoft = Color(0x24EF4444);

  // ── Modal scrim (`.sheet-scrim{background:rgba(8,8,10,.6)}`) ────────────────
  static const Color scrim = Color(0x990A0B0D); // alpha .6 ≈ 0x99

  // ── Sheet grabber (`.sheet-grab{background:#3a3a40}`) ───────────────────────
  static const Color sheetGrab = Color(0xFF3A414C);

  // ── Skeleton shimmer (`.skel`) ─────────────────────────────────────────────
  /// `.skel{background:#20242B}`
  static const Color skeletonBase = Color(0xFF20242B);

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
  static const EdgeInsets sheetBody = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );
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

  static Duration effective(BuildContext context, Duration duration) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false
      ? Duration.zero
      : duration;
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
