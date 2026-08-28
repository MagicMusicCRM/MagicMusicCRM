/// Owner-approved light design tokens — the single presentation source of truth.
///
/// The values come from the approved light design stand. Presentation code
/// consumes semantic [AppColor] aliases; raw values stay in [AppPalette].
///
/// The token test `test/theme/design_tokens_test.dart` golden-locks every value
/// below against the prototype `:root`, per the migration plan §0 / §5a.
library;

import 'package:flutter/material.dart';

/// Primitive palette. Product widgets must consume [AppColor], not this class.
class AppPalette {
  AppPalette._();

  static const Color white = Color(0xFFFFFFFF);
  static const Color paper50 = Color(0xFFFCFBF8);
  static const Color paper100 = Color(0xFFF7F4EE);
  static const Color paper150 = Color(0xFFF3F0E9);
  static const Color paper200 = Color(0xFFEBE6DC);
  static const Color ink950 = Color(0xFF181915);
  static const Color ink800 = Color(0xFF34352F);
  static const Color ink600 = Color(0xFF6D6D66);
  static const Color ink450 = Color(0xFF96948B);
  static const Color gold800 = Color(0xFF765417);
  static const Color gold700 = Color(0xFF8F681B);
  static const Color gold600 = Color(0xFFA97D25);
  static const Color gold500 = Color(0xFFBD9136);
  static const Color gold100 = Color(0xFFF7EDCF);
  static const Color blue600 = Color(0xFF3B73D1);
  static const Color green600 = Color(0xFF267A56);
  static const Color green100 = Color(0xFFE7F5EE);
  static const Color red600 = Color(0xFFB94A42);
  static const Color red100 = Color(0xFFFBECEB);
  static const Color amber600 = Color(0xFFA16816);
  static const Color amber100 = Color(0xFFFFF3DC);
  static const Color purple600 = Color(0xFF7154A2);
  static const Color purple100 = Color(0xFFF1ECFA);
}

/// Semantic colors used by the production UI.
class AppColor {
  AppColor._();

  // ── Surfaces and borders ─────────────────────────────────────────────────
  static const Color bg = AppPalette.paper50;
  static const Color surface = AppPalette.white;
  static const Color surfaceSoft = AppPalette.paper100;
  static const Color surfaceActive = Color(0xFFF3EAD8);
  static const Color sidebar = AppPalette.paper150;
  static const Color input = AppPalette.paper100;
  static const Color divider = Color(0xFFDFDBD2);
  static const Color borderSoft = Color(0xFFEBE7DF);
  static const Color borderStrong = Color(0xFFCFC7B8);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color text = AppPalette.ink950;
  static const Color text2 = AppPalette.ink600;
  static const Color text3 = AppPalette.ink450;
  static const Color disabledText = Color(0xFF8A8880);
  static const Color disabledSurface = Color(0xFFEFEDE8);

  // ── Brand and selection ──────────────────────────────────────────────────
  static const Color brand = AppPalette.gold600;
  static const Color brandHover = AppPalette.gold700;
  static const Color brandSolid = AppPalette.gold800;
  static const Color brandSolidHover = Color(0xFF62450F);
  static const Color onBrand = Color(0xFFFFFAF0);
  static const Color selectionBg = Color(0xFFF3E8D0);
  static const Color selectionHover = Color(0xFFF8F1E4);
  static const Color selectionText = Color(0xFF594214);
  static const Color selectionBorder = Color(0xFFDCC58E);

  // Compatibility names while existing widgets migrate to semantic aliases.
  static const Color gold = brand;
  static const Color gold2 = AppPalette.gold500;
  static const Color goldSoft = AppPalette.gold100;
  static const Color goldLine = selectionBorder;

  /// Dark text used on medium-gold selected states (`4.75:1`).
  static const Color onGold = text;

  // ── Work accents ───────────────────────────────────────────────────────────
  /// Work action blue: links, focused inputs and non-brand commands.
  static const Color actionBlue = AppPalette.blue600;
  static const Color focus = AppPalette.blue600;
  static const Color infoSoft = Color(0xFFEAF1FC);

  /// Transfer cyan: lead-to-student conversion and sync/transfer surfaces.
  static const Color transferCyan = Color(0xFF14B8A6);

  /// Info violet: role/admin metadata and non-critical informational states.
  static const Color infoViolet = AppPalette.purple600;
  static const Color infoVioletSoft = AppPalette.purple100;

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color success = AppPalette.green600;
  static const Color successSoft = AppPalette.green100;
  static const Color warning = AppPalette.amber600;
  static const Color warningSoft = AppPalette.amber100;
  static const Color danger = AppPalette.red600;
  static const Color dangerSoft = AppPalette.red100;

  // ── Overlay chrome ────────────────────────────────────────────────────────
  static const Color overlay = AppPalette.white;
  static const Color menuItemText = text;
  static const Color menuItemHover = surfaceSoft;
  static const Color menuDanger = danger;
  static const Color scrim = Color(0x66181915);
  static const Color sheetGrab = borderStrong;
  static const Color skeletonBase = AppPalette.paper200;
  static const Color skeletonHighlight = Color(0x99FFFFFF);
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

  /// Subtle resting surface shadow.
  static const List<BoxShadow> sh1 = [
    BoxShadow(color: Color(0x0A302819), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Drawers, sheets and pop-menus.
  static const List<BoxShadow> sh2 = [
    BoxShadow(color: Color(0x29302819), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Picked-up drag cards.
  static const List<BoxShadow> shLift = [
    BoxShadow(color: Color(0x3D302819), blurRadius: 44, offset: Offset(0, 18)),
  ];
}
