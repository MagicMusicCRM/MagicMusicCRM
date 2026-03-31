import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';

/// Adaptive two-panel (desktop) / single-panel (mobile) messenger layout.
/// Emulates Telegram Desktop on wide screens and Telegram Mobile on narrow screens.
class AdaptiveMessengerShell extends StatefulWidget {
  /// Builder for the chat list panel (left side on desktop).
  final Widget Function(BuildContext context, bool isMobile, String? selectedChatId)
      chatListBuilder;

  /// Builder for the chat view panel (middle/right side on desktop).
  /// Receives the selected chat data.
  final Widget Function(BuildContext context, bool isMobile, String? selectedChatId)?
      chatViewBuilder;

  /// Builder for the right-side profile panel (desktop only).
  final Widget Function(BuildContext context)? profilePanelBuilder;

  /// Builder for an empty state when no chat is selected (desktop only).
  final Widget Function(BuildContext context)? emptyStateBuilder;

  /// Callback when a chat is selected from the list.
  final ValueChanged<String?>? onChatSelected;

  /// Currently selected chat ID (controlled externally).
  final String? selectedChatId;
  
  /// Controls the visibility of the profile panel sliding from the right.
  final bool showProfilePanel;

  /// Width breakpoint for mobile/desktop switch.
  final double breakpoint;

  /// Left panel width for desktop mode.
  final double sidebarWidth;

  const AdaptiveMessengerShell({
    super.key,
    required this.chatListBuilder,
    this.chatViewBuilder,
    this.profilePanelBuilder,
    this.emptyStateBuilder,
    this.onChatSelected,
    this.selectedChatId,
    this.showProfilePanel = false,
    this.breakpoint = 768,
    this.sidebarWidth = 320,
  });

  @override
  State<AdaptiveMessengerShell> createState() => _AdaptiveMessengerShellState();
}

class _AdaptiveMessengerShellState extends State<AdaptiveMessengerShell> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= widget.breakpoint;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        if (isDesktop) {
          return _buildDesktopLayout(context, isDark);
        } else {
          return _buildMobileLayout(context);
        }
      },
    );
  }

  Widget _buildDesktopLayout(BuildContext context, bool isDark) {
    final dividerColor = isDark ? TelegramColors.darkDivider : TelegramColors.lightDivider;

    return Row(
      children: [
        // Left panel — chat list
        SizedBox(
          width: widget.sidebarWidth,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? TelegramColors.darkSidebar : TelegramColors.lightSidebar,
              border: Border(right: BorderSide(color: dividerColor, width: 0.5)),
            ),
            child: widget.chatListBuilder(context, false, widget.selectedChatId),
          ),
        ),
        // Middle panel — chat view or empty state
        Expanded(
          child: widget.selectedChatId != null && widget.chatViewBuilder != null
              ? widget.chatViewBuilder!(context, false, widget.selectedChatId)
              : widget.emptyStateBuilder?.call(context) ?? _defaultEmptyState(context, isDark),
        ),
        // Right sliding panel — profile view
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.fastOutSlowIn,
          width: widget.showProfilePanel ? 380 : 0,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: dividerColor, width: 0.5)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: 380,
              child: widget.showProfilePanel && widget.profilePanelBuilder != null
                  ? widget.profilePanelBuilder!(context)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    // On mobile, if a chat is selected, show only the chat view
    if (widget.selectedChatId != null && widget.chatViewBuilder != null) {
      return widget.chatViewBuilder!(context, true, widget.selectedChatId);
    }
    // Otherwise show the chat list
    return widget.chatListBuilder(context, true, widget.selectedChatId);
  }

  Widget _defaultEmptyState(BuildContext context, bool isDark) {
    return Container(
      color: isDark ? TelegramColors.darkChatBg : TelegramColors.lightChatBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 80,
              color: isDark
                  ? TelegramColors.darkTextSecondary.withAlpha(60)
                  : TelegramColors.lightTextSecondary.withAlpha(60),
            ),
            const SizedBox(height: 16),
            Text(
              'Выберите чат',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? TelegramColors.darkTextSecondary
                    : TelegramColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'для начала общения',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? TelegramColors.darkTextSecondary.withAlpha(100)
                    : TelegramColors.lightTextSecondary.withAlpha(100),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
