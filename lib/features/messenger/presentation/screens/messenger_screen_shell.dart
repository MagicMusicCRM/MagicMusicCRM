part of 'messenger_screen.dart';

extension _MessengerShell on _MessengerScreenState {
  Widget _buildMessengerShell(BuildContext context) {
    return AdaptiveMessengerShell(
      selectedChatId: _selectedChatId,
      onChatSelected: (id) {},
      chatListBuilder: (context, isMobile, selectedId) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) {
          final isProfile = child.key == const ValueKey('profile');
          return SlideTransition(
            position: Tween<Offset>(
              begin: Offset(isProfile ? -1.0 : 1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        child: _showMyProfile
            ? ProfileScreen(
                key: const ValueKey('profile'),
                onBack: () => _emitState(() => _showMyProfile = false),
                onUpdate: _loadChatList,
              )
            : KeyedSubtree(
                key: const ValueKey('chat_list'),
                child: _buildChatList(context, isMobile),
              ),
      ),
      chatViewBuilder: (context, isMobile, selectedId) =>
          _buildChatView(context, isMobile),
    );
  }

  Future<void> _showChatInfo() async {
    final chatId = _selectedChatId;
    final chatType = _selectedChatType;
    if (chatId == null || chatType == null) return;
    await showMagicDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(dialogContext).height * 0.8,
          child: ChatInfoDialog(
            key: ValueKey('$chatType:$chatId'),
            chatId: chatId,
            chatType: chatType,
            userRole: widget.role,
            onClose: usesDesktopMagicModal(dialogContext)
                ? () => Navigator.of(dialogContext).maybePop()
                : null,
            onUpdate: _loadChatList,
            onSearch: _onSearchInChat,
            onMute: _onMuteChat,
            initialIsMuted: _mutedChatIds.contains(chatId),
            onNavigateToChat: _selectChat,
            onLeftGroup: () {
              _emitState(() => _chatItems = removeChat(_chatItems, chatId));
              _deselectChat();
            },
          ),
        ),
      ),
    );
  }
}
