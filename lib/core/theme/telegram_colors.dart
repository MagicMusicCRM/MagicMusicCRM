import 'package:flutter/material.dart';

/// Telegram-inspired color palette for MagicMusic Messenger.
/// Preserves brand purple while adopting Telegram's visual language.
class TelegramColors {
  TelegramColors._();

  // ── Brand ──────────────────────────────────────────────────────────────────
  static const Color brandPurple = Color(0xFF7C3AED);
  static const Color brandPurpleLight = Color(0xFF9B5FFF);
  static const Color brandGold = Color(0xFFD97706);

  // ── Dark Theme (MagicMusic Original Style) ─────────────────────────────────
  // Adjusted for better contrast and CRM aesthetics
  static const Color darkBg = Color(0xFF13131A); // Deep dark background
  static const Color darkSurface = Color(0xFF1C1C26); // Lighter surface for cards/panels
  static const Color darkChatBg = Color(0xFF13131A); // Match background
  static const Color darkSidebar = Color(0xFF17171F); // Sidebar color
  static const Color darkInputBg = Color(0xFF282836); // Input fields
  static const Color darkDivider = Color(0xFF282836); // Subtle borders
  static const Color darkOutgoingBubble = brandPurple; // Brand purple for my messages
  static const Color darkIncomingBubble = Color(0xFF282836); // Dark surface for incoming
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFA1A1AA); // Zinc-400
  static const Color darkChatListActive = Color(0xFF282836); // Active chat tile
  static const Color darkChatListHover = Color(0xFF21212E); 
  static const Color darkUnreadBadge = brandPurple;
  static const Color darkOnlineDot = Color(0xFF10B981);
  static const Color darkMutedBadge = Color(0xFF3F3F46);

  // ── Light Theme (MagicMusic Original Style) ────────────────────────────────
  static const Color lightBg = Color(0xFFF4F4F5); // Zinc-100
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightChatBg = Color(0xFFF4F4F5);
  static const Color lightSidebar = Color(0xFFFFFFFF);
  static const Color lightInputBg = Color(0xFFF4F4F5);
  static const Color lightDivider = Color(0xFFE4E4E7);
  static const Color lightOutgoingBubble = brandPurple;
  static const Color lightIncomingBubble = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF18181B); // Zinc-900
  static const Color lightTextSecondary = Color(0xFF71717A); // Zinc-500
  static const Color lightChatListActive = Color(0xFFE4E4E7);
  static const Color lightChatListHover = Color(0xFFF4F4F5);
  static const Color lightUnreadBadge = brandPurple;
  static const Color lightOnlineDot = Color(0xFF10B981);
  static const Color lightMutedBadge = Color(0xFFA1A1AA);

  // ── Shared Accent ──────────────────────────────────────────────────────────
  static const Color accentBlue = brandPurple; // Using purple instead of Telegram blue
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color link = brandPurpleLight;

  // ── Avatar Gradient Colors (deterministic by user ID) ──────────────────────
  static const List<List<Color>> avatarGradients = [
    [Color(0xFFFF885E), Color(0xFFFF516A)], // Red-orange
    [Color(0xFFFFCD6B), Color(0xFFFFA346)], // Amber
    [Color(0xFF82E37D), Color(0xFF2BAF49)], // Green
    [Color(0xFF5BCBE3), Color(0xFF3392CC)], // Cyan
    [Color(0xFF7B91FF), Color(0xFF5B6AF0)], // Blue
    [Color(0xFFE47EDE), Color(0xFFBB60D9)], // Purple
    [Color(0xFFFF7EB3), Color(0xFFFF5D8F)], // Pink
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
