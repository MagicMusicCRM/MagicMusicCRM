import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'avatar_widget.dart';

/// Telegram-style chat area header with back button, avatar, name, and subtitle.
class ChatHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final String? uniqueId;
  final bool isChannel;
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onTitleTap;
  final List<Widget>? actions;

  const ChatHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.uniqueId,
    this.isChannel = false,
    this.showBackButton = false,
    this.onBack,
    this.onTitleTap,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? TelegramColors.darkSurface : TelegramColors.lightBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? TelegramColors.darkDivider : TelegramColors.lightDivider,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              splashRadius: 20,
            ),
          if (!showBackButton) const SizedBox(width: 8),
          // Avatar
          TelegramAvatar(
            name: title,
            avatarUrl: avatarUrl,
            uniqueId: uniqueId ?? title,
            radius: 20,
            icon: isChannel ? Icons.campaign_rounded : null,
          ),
          const SizedBox(width: 12),
          // Title + subtitle
          Expanded(
            child: GestureDetector(
              onTap: onTitleTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? TelegramColors.darkTextSecondary
                            : TelegramColors.lightTextSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Actions
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}
