import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'avatar_widget.dart';

/// Telegram-style chat list tile with avatar, name, last message, time, and unread badge.
class ChatListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? time;
  final int unreadCount;
  final bool isSelected;
  final bool isChannel;
  final bool isMuted;
  final String? avatarUrl;
  final String? uniqueId;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final IconData? channelIcon;
  final Widget? statusIcon;
  final VoidCallback? onStatusTap;

  const ChatListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.time,
    this.unreadCount = 0,
    this.isSelected = false,
    this.isChannel = false,
    this.isMuted = false,
    this.avatarUrl,
    this.uniqueId,
    this.onTap,
    this.onLongPress,
    this.channelIcon,
    this.statusIcon,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = isDark
        ? TelegramColors.darkChatListActive
        : TelegramColors.lightChatListActive;
    final hoverColor = isDark
        ? TelegramColors.darkChatListHover
        : TelegramColors.lightChatListHover;
    final textSecondary = isDark
        ? TelegramColors.darkTextSecondary
        : TelegramColors.lightTextSecondary;

    return Material(
      color: isSelected ? selectedColor.withAlpha(40) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        hoverColor: hoverColor,
        splashColor: selectedColor.withAlpha(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Avatar
              TelegramAvatar(
                name: title,
                avatarUrl: avatarUrl,
                uniqueId: uniqueId ?? title,
                radius: 26,
                icon: isChannel ? (channelIcon ?? Icons.campaign_rounded) : null,
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top row: name + time
                    Row(
                      children: [
                        if (isChannel)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.campaign_rounded,
                              size: 16,
                              color: TelegramColors.accentBlue,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                          const SizedBox(width: 4),
                          if (isMuted)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.notifications_off_rounded,
                                size: 14,
                                color: textSecondary,
                              ),
                            ),
                          Text(
                            time!,
                            style: TextStyle(
                              color: unreadCount > 0
                                  ? TelegramColors.accentBlue
                                  : textSecondary,
                              fontSize: 12,
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        if (statusIcon != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: GestureDetector(
                              onTap: onStatusTap,
                              child: statusIcon,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Bottom row: message preview + badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 14,
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isMuted
                                  ? (isDark
                                      ? TelegramColors.darkMutedBadge
                                      : TelegramColors.lightMutedBadge)
                                  : TelegramColors.accentBlue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            constraints: const BoxConstraints(minWidth: 22),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
