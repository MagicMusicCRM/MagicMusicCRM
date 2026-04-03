import 'package:flutter/material.dart';

/// Legacy color palette mapped to strict dark/gold style for MagicMusic CRM.
class TelegramColors {
  TelegramColors._();

  // ── Brand ──────────────────────────────────────────────────────────────────
  static const Color primaryGold = Color(0xFFC5A059); // Sophisticated Gold (Original)
  static const Color secondaryGold = Color(0xFFBFA37E); // Muted Gold / Beige
  static const Color premiumGold = Color(0xFFC5A059); 
  static const Color softGold = Color(0xFFBFA37E);
  
  // Backward compatibility aliases
  static const Color brandGold = primaryGold;
  static const Color brandGoldLight = secondaryGold;

  // ── Dark Theme (MagicMusic Real Style) ─────────────────────────────────
  static const Color darkBg = Color(0xFF101012); // Deep Charcoal
  static const Color darkSurface = Color(0xFF1A1A1D); // Surface for cards/panels
  static const Color darkChatBg = Color(0xFF101012); 
  static const Color darkSidebar = Color(0xFF151518);
  static const Color darkInputBg = Color(0xFF242427);
  static const Color darkDivider = Color(0xFF2A2A2D);
  static const Color darkOutgoingBubble = primaryGold; // Brand gold for messages
  static const Color darkIncomingBubble = Color(0xFF27272A); // Dark surface for incoming
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFA1A1AA); // Zinc-400
  static const Color darkChatListActive = Color(0xFF27272A); // Active chat tile
  static const Color darkChatListHover = Color(0xFF212124); 
  static const Color darkUnreadBadge = brandGold;
  static const Color darkOnlineDot = Color(0xFF10B981);
  static const Color darkMutedBadge = Color(0xFF3F3F46);

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
  static const Color lightUnreadBadge = brandGold;
  static const Color lightOnlineDot = Color(0xFF10B981);
  static const Color lightMutedBadge = Color(0xFFA1A1AA);

  // ── Shared Accent ──────────────────────────────────────────────────────────
  static const Color accentBlue = brandGold; // Using gold instead of previous purple
  static const Color brandPurple = brandGold; // Alias to prevent breakage 
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color link = brandGoldLight;

  // ── Avatar Gradient Colors (deterministic by user ID) ──────────────────────
  static const List<List<Color>> avatarGradients = [
    [Color(0xFFFF885E), Color(0xFFFF516A)], // Red-orange
    [Color(0xFFFFCD6B), Color(0xFFFFA346)], // Amber
    [brandGoldLight, brandGold], // Gold
    [Color(0xFF5BCBE3), Color(0xFF3392CC)], // Cyan
    [Color(0xFF82E37D), Color(0xFF2BAF49)], // Green
    [Color(0xFFE47EDE), Color(0xFFBB60D9)], // Pink
    [Color(0xFFFACC15), Color(0xFFCA8A04)], // Yellow
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
