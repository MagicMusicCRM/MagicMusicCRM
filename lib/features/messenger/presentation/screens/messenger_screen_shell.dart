part of 'messenger_screen.dart';

extension _MessengerShell on _MessengerScreenState {
  Widget _buildMessengerShell(BuildContext context) {
    return AdaptiveMessengerShell(
      selectedChatId: _selectedChatId,
      onChatSelected: (id) {},
      showProfilePanel: _showProfilePanel,
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
      profilePanelBuilder: (context) =>
          _selectedChatId != null && _selectedChatType != null
          ? ChatInfoDialog(
              key: ValueKey('$_selectedChatType:$_selectedChatId'),
              chatId: _selectedChatId!,
              chatType: _selectedChatType!,
              userRole: widget.role,
              onClose: () => _emitState(() => _showProfilePanel = false),
              onUpdate: _loadChatList,
              onSearch: _onSearchInChat,
              onMute: _onMuteChat,
              initialIsMuted:
                  _selectedChatId != null &&
                  _mutedChatIds.contains(_selectedChatId),
              onNavigateToChat: (chat) {
                _emitState(() {
                  _showProfilePanel = false;
                });
                _selectChat(chat);
              },
              onLeftGroup: () {
                final leftId = _selectedChatId;
                _emitState(() {
                  if (leftId != null) {
                    _chatItems = removeChat(_chatItems, leftId);
                  }
                  _showProfilePanel = false;
                });
                _deselectChat();
              },
            )
          : const SizedBox.shrink(),
    );
  }
}
