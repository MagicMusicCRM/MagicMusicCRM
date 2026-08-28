import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Compile-compatible aliases for Telegram-style widgets.
///
/// Both historical light/dark names resolve to the single production palette.
/// New widgets must use [AppColor] directly.
class TelegramColors {
  TelegramColors._();

  static const Color primaryGold = AppColor.gold;
  static const Color secondaryGold = AppColor.gold2;
  static const Color premiumGold = AppColor.gold;
  static const Color softGold = AppColor.goldSoft;
  static const Color brandGold = AppColor.gold;

  static const Color actionBlue = AppColor.actionBlue;
  static const Color transferCyan = AppColor.transferCyan;
  static const Color infoViolet = AppColor.infoViolet;

  static const Color darkBg = AppColor.bg;
  static const Color darkSurface = AppColor.surface;
  static const Color darkChatBg = AppColor.bg;
  static const Color darkSidebar = AppColor.sidebar;
  static const Color darkInputBg = AppColor.input;
  static const Color darkDivider = AppColor.divider;
  static const Color darkOutgoingBubble = AppColor.brandSolid;
  static const Color darkIncomingBubble = AppColor.surfaceSoft;
  static const Color darkTextPrimary = AppColor.text;
  static const Color darkTextSecondary = AppColor.text2;
  static const Color darkChatListActive = AppColor.selectionBg;
  static const Color darkChatListHover = AppColor.selectionHover;
  static const Color darkUnreadBadge = AppColor.actionBlue;
  static const Color darkOnlineDot = AppColor.success;
  static const Color darkMutedBadge = AppColor.borderStrong;

  static const Color lightBg = AppColor.bg;
  static const Color lightSurface = AppColor.surface;
  static const Color lightChatBg = AppColor.bg;
  static const Color lightSidebar = AppColor.sidebar;
  static const Color lightInputBg = AppColor.input;
  static const Color lightDivider = AppColor.divider;
  static const Color lightOutgoingBubble = AppColor.brandSolid;
  static const Color lightIncomingBubble = AppColor.surfaceSoft;
  static const Color lightTextPrimary = AppColor.text;
  static const Color lightTextSecondary = AppColor.text2;
  static const Color lightChatListActive = AppColor.selectionBg;
  static const Color lightChatListHover = AppColor.selectionHover;
  static const Color lightUnreadBadge = AppColor.actionBlue;
  static const Color lightOnlineDot = AppColor.success;
  static const Color lightMutedBadge = AppColor.borderStrong;

  static const Color accent = AppColor.actionBlue;
  static const Color success = AppColor.success;
  static const Color danger = AppColor.danger;
  static const Color warning = AppColor.warning;
  static const Color link = AppColor.actionBlue;

  // Media/avatar colors are intentional decorative exceptions, not UI chrome.
  static const List<List<Color>> avatarGradients = [
    [Color(0xFFFF512F), Color(0xFFDD2476)],
    [Color(0xFF4568DC), Color(0xFFB06AB3)],
    [Color(0xFF3B82F6), Color(0xFF14B8A6)],
    [Color(0xFF14B8A6), Color(0xFF22C55E)],
    [Color(0xFFF09819), Color(0xFFEDDE5D)],
    [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
    [Color(0xFFD31027), Color(0xFFEA384D)],
    [Color(0xFF000428), Color(0xFF004E92)],
    [Color(0xFF833AB4), Color(0xFFFD1D1D)],
    [Color(0xFFF9D423), Color(0xFFFF4E50)],
    [AppColor.gold, AppColor.gold2],
  ];

  static List<Color> avatarGradientFor(String id) {
    final hash = id.hashCode.abs();
    return avatarGradients[hash % avatarGradients.length];
  }

  static String initialsFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
