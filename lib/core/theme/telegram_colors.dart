import 'package:flutter/material.dart';

/// Retained presentation aliases map to the live Deep Charcoal & Sophisticated
/// Gold palette and are removed only after their consumers use AppColor directly.
class TelegramColors {
  TelegramColors._();

  // ── Brand ──────────────────────────────────────────────────────────────────
  static const Color primaryGold = Color(0xFFC9A85E); // Brand gold
  static const Color secondaryGold = Color(0xFFD6B778); // Soft brand gold
  static const Color premiumGold = Color(0xFFC9A85E);
  static const Color softGold = Color(0xFFD6B778);

  // Live presentation aliases; remove only after all consumers use AppColor.
  static const Color brandGold = primaryGold;

  // ── Work accents ───────────────────────────────────────────────────────────
  static const Color actionBlue = Color(0xFF3B82F6);
  static const Color transferCyan = Color(0xFF14B8A6);
  static const Color infoViolet = Color(0xFF8B5CF6);

  // ── Dark Theme (MagicMusic Real Style) ─────────────────────────────────────
  static const Color darkBg = Color(0xFF101114); // App background
  static const Color darkSurface = Color(0xFF181B20); // Cards/panels
  static const Color darkChatBg = Color(0xFF101114);
  static const Color darkSidebar = Color(0xFF14161A);
  static const Color darkInputBg = Color(0xFF20242B);
  static const Color darkDivider = Color(0xFF313741);
  static const Color darkOutgoingBubble =
      primaryGold; // Brand gold for messages
  static const Color darkIncomingBubble = Color(0xFF20242B);
  static const Color darkTextPrimary = Color(0xFFF1F3F5);
  static const Color darkTextSecondary = Color(0xFFAAB2BF);
  static const Color darkChatListActive = Color(0xFF20242B);
  static const Color darkChatListHover = Color(0xFF252A31);
  static const Color darkUnreadBadge = actionBlue;
  static const Color darkOnlineDot = Color(0xFF22C55E);
  static const Color darkMutedBadge = Color(0xFF3A414C);

  // ── Light Theme (MagicMusic Real Style) ────────────────────────────────
  static const Color lightBg = Color(0xFFF4F4F5); // Zinc-100
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightChatBg = Color(0xFFF4F4F5);
  static const Color lightSidebar = Color(0xFFFFFFFF);
  static const Color lightInputBg = Color(0xFFF4F4F5);
  static const Color lightDivider = Color(0xFFE4E4E7);
  static const Color lightOutgoingBubble = brandGold;
  static const Color lightIncomingBubble = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF18181B); // Zinc-900
  static const Color lightTextSecondary = Color(0xFF71717A); // Zinc-500
  static const Color lightChatListActive = Color(0xFFE4E4E7);
  static const Color lightChatListHover = Color(0xFFF4F4F5);
  static const Color lightUnreadBadge = actionBlue;
  static const Color lightOnlineDot = Color(0xFF22C55E);
  static const Color lightMutedBadge = Color(0xFFA1A1AA);

  // ── Shared Accent ──────────────────────────────────────────────────────────
  static const Color accent = actionBlue;
  static const Color success = Color(0xFF22C55E);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color link = actionBlue;

  // ── Avatar Gradient Colors (deterministic by user ID) ──────────────────────
  static const List<List<Color>> avatarGradients = [
    [Color(0xFFFF512F), Color(0xFFDD2476)], // Crimson / Pink
    [Color(0xFF4568DC), Color(0xFFB06AB3)], // Indigo / Purple
    [Color(0xFF3B82F6), Color(0xFF14B8A6)], // Blue / Cyan
    [Color(0xFF14B8A6), Color(0xFF22C55E)], // Green / Teal
    [Color(0xFFF09819), Color(0xFFEDDE5D)], // Orange / Yellow
    [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // Deep Purple
    [Color(0xFFD31027), Color(0xFFEA384D)], // Red
    [Color(0xFF000428), Color(0xFF004E92)], // Midnight Blue
    [Color(0xFF833ab4), Color(0xFFfd1d1d)], // Instagram-like Red/Purple
    [Color(0xFFf9d423), Color(0xFFff4e50)], // Sunset
    [Color(0xFFC9A85E), Color(0xFFD6B778)], // Brand Gold (Last)
  ];

  /// Get a deterministic avatar gradient based on a string (user ID).
  static List<Color> avatarGradientFor(String id) {
    final hash = id.hashCode.abs();
    return avatarGradients[hash % avatarGradients.length];
  }

  /// Get initials from a name string.
  static String initialsFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
