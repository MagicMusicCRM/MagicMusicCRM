import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';

/// Telegram-style search bar for chat list.
class ChatSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final String hint;

  const ChatSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.onTap,
    this.hint = 'Поиск',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          onTap: onTap,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark
                  ? TelegramColors.darkTextSecondary
                  : TelegramColors.lightTextSecondary,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 20,
              color: isDark
                  ? TelegramColors.darkTextSecondary
                  : TelegramColors.lightTextSecondary,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            filled: true,
            fillColor: isDark
                ? TelegramColors.darkInputBg
                : TelegramColors.lightInputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ),
    );
  }
}
