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

  // Search props
  final bool isSearchActive;
  final TextEditingController? searchController;
  final VoidCallback? onSearchToggle;
  final VoidCallback? onNextMatch;
  final VoidCallback? onPrevMatch;
  final int matchCount;
  final int currentMatchIndex; // 1-indexed for UI display
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;

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
    this.isSearchActive = false,
    this.searchController,
    this.onSearchToggle,
    this.onNextMatch,
    this.onPrevMatch,
    this.matchCount = 0,
    this.currentMatchIndex = 0,
    this.onSearchChanged,
    this.onSearchSubmitted,
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
      child: isSearchActive ? _buildSearchBar(context, isDark) : _buildNormalHeader(context, isDark),
    );
  }

  Widget _buildNormalHeader(BuildContext context, bool isDark) {
    return Row(
      children: [
        if (showBackButton)
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            splashRadius: 20,
          ),
        if (!showBackButton) const SizedBox(width: 8),
        // Avatar
        GestureDetector(
          onTap: onTitleTap,
          child: TelegramAvatar(
            name: title,
            avatarUrl: avatarUrl,
            uniqueId: uniqueId ?? title,
            radius: 20,
            icon: isChannel ? Icons.campaign_rounded : null,
          ),
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
        if (onSearchToggle != null)
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: onSearchToggle,
            splashRadius: 20,
          ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isDark) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: onSearchToggle,
          splashRadius: 20,
        ),
        Expanded(
          child: TextField(
            controller: searchController,
            autofocus: true,
            style: const TextStyle(fontSize: 16),
            onChanged: onSearchChanged,
            onSubmitted: onSearchSubmitted,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Поиск...',
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
            ),
          ),
        ),
        if (matchCount > 0) ...[
          Text(
            '$currentMatchIndex / $matchCount',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
            onPressed: onPrevMatch,
            splashRadius: 20,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: onNextMatch,
            splashRadius: 20,
          ),
        ],
      ],
    );
  }
}
