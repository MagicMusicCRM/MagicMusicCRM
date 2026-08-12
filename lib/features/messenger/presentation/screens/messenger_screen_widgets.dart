part of 'messenger_screen.dart';

// Message list view (date separators, pagination) and presence banner.
// Part-of keeps these private widgets in the messenger_screen library.

class _MessageListView extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final String currentUserId;
  final bool isGroupChat;
  final bool isChannel;
  final bool isAdministrationChat;
  final List<Map<String, dynamic>> chatItems;
  final List<String> adminIds;
  final String role;
  final String? selectedChatName;

  final Function(Map<String, dynamic>)? onReply;
  final Function(Map<String, dynamic>)? onEdit;
  final Function(Map<String, dynamic>)? onDelete;
  final Function(Map<String, dynamic>)? onForward;
  final Function(Map<String, dynamic>)? onPin;
  final Function(String, String)? onReact;
  final Map<String, List<dynamic>>? reactionsMap;

  const _MessageListView({
    super.key,
    required this.messages,
    required this.currentUserId,
    required this.isGroupChat,
    required this.isChannel,
    required this.isAdministrationChat,
    required this.chatItems,
    required this.adminIds,
    required this.role,
    this.selectedChatName,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onForward,
    this.onPin,
    this.onReact,
    this.reactionsMap,
  });

  @override
  State<_MessageListView> createState() => _MessageListViewState();
}

class _MessageListViewState extends State<_MessageListView> {
  final ScrollController _scrollController = ScrollController();
  // KVA-174: replaced _showScrollToBottom with _isAtBottom + _unreadCount.
  bool _isAtBottom = true;
  int _unreadCount = 0;
  String? _highlightedMessageId;
  bool _isJumping = false;

  // Cache for sender names (profile lookups)
  final Map<String, String> _senderNameCache = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // KVA-174: track whether the list is scrolled to (near) the bottom.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom =
        _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 80;
    if (atBottom && !_isAtBottom) {
      setState(() {
        _isAtBottom = true;
        _unreadCount = 0;
      });
    } else if (!atBottom && _isAtBottom) {
      setState(() => _isAtBottom = false);
    }
  }

  void _jumpToMessage(String messageId) {
    if (!mounted) return;

    final index = widget.messages.indexWhere(
      (m) => m['id'].toString() == messageId,
    );
    if (index == -1) return;

    setState(() {
      _isJumping = true;
      _highlightedMessageId = null; // Reset highlight before new jump
    });

    final targetKey = GlobalObjectKey(messageId);
    final context = targetKey.currentContext;

    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      _startHighlight(messageId);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _isJumping = false);
      });
    } else {
      // Heuristic jump to general area
      final estimate = index * 120.0;
      _scrollController
          .animateTo(
            estimate,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          )
          .then((_) {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final newContext = targetKey.currentContext;
              if (newContext != null) {
                Scrollable.ensureVisible(
                  newContext,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: 0.5,
                );
              }
              _startHighlight(messageId);
              Future.delayed(const Duration(milliseconds: 600), () {
                if (mounted) setState(() => _isJumping = false);
              });
            });
          });
    }
  }

  void _startHighlight(String messageId) {
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  @override
  void didUpdateWidget(_MessageListView old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length) {
      if (!_isJumping) {
        if (_isAtBottom) {
          // KVA-174: auto-scroll only when already at the bottom.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        } else {
          // KVA-174: count unseen messages while scrolled up — by the actual
          // number added so a burst/batch delivery isn't undercounted.
          final added = widget.messages.length - old.messages.length;
          if (added > 0) setState(() => _unreadCount += added);
        }
      }
    }
  }

  void _scrollToBottom() {
    if (_isJumping || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  String _getSenderName(Map<String, dynamic> msg) {
    final senderId = msg['sender_id']?.toString() ?? '';
    if (senderId == widget.currentUserId) return 'Вы';

    if (_senderNameCache.containsKey(senderId)) {
      return _senderNameCache[senderId]!;
    }

    // Check if message has embedded profile data
    final profiles = msg['profiles'];
    if (profiles != null && profiles is Map) {
      final name =
          '${profiles['first_name'] ?? ''} ${profiles['last_name'] ?? ''}'
              .trim();
      if (name.isNotEmpty) {
        _senderNameCache[senderId] = name;
        return name;
      }
    }

    if (widget.adminIds.contains(senderId)) return 'Администрация';
    return 'Пользователь';
  }

  String? _getSenderRole(Map<String, dynamic> msg) {
    final profiles = msg['profiles'];
    if (profiles is Map) return profiles['role']?.toString();
    return null;
  }

  String? _getSenderAvatarUrl(Map<String, dynamic> msg) {
    final profiles = msg['profiles'];
    if (profiles is Map) {
      return profiles['avatar_file_id']?.toString() ??
          profiles['avatar_url']?.toString();
    }
    return null;
  }

  bool get _canSeeAdministrationAuthors {
    return widget.role == 'admin' ||
        widget.role == 'manager' ||
        widget.role == 'director' ||
        widget.role == 'system_admin';
  }

  String? _getForwardedName(Map<String, dynamic> msg) {
    if (msg['forwarded_from_id'] == null) return null;

    final forwardedId = msg['forwarded_from_id'].toString();

    // Check embedded forwarded_profiles from our enriched query
    final fProfiles = msg['forwarded_profiles'];
    if (fProfiles != null && fProfiles is Map) {
      final name =
          '${fProfiles['first_name'] ?? ''} ${fProfiles['last_name'] ?? ''}'
              .trim();
      if (name.isNotEmpty) return name;
    }

    if (widget.adminIds.contains(forwardedId)) return 'Администрация';
    return 'Пользователь';
  }

  bool _shouldShowDate(int index) {
    if (index == 0) return true;
    final curr = DateTime.tryParse(widget.messages[index]['created_at'] ?? '');
    final prev = DateTime.tryParse(
      widget.messages[index - 1]['created_at'] ?? '',
    );
    if (curr == null || prev == null) return false;
    return curr.toLocal().day != prev.toLocal().day ||
        curr.toLocal().month != prev.toLocal().month ||
        curr.toLocal().year != prev.toLocal().year;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canAdminDelete =
        widget.role == 'admin' ||
        widget.role == 'manager' ||
        widget.role == 'director' ||
        widget.role == 'system_admin';

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          itemCount: widget.messages.length,
          itemBuilder: (context, index) {
            final msg = widget.messages[index];
            final isMe = msg['sender_id'] == widget.currentUserId;

            // Resolve replied message from current list
            Map<String, dynamic>? repliedMsg;
            final replyId = msg['reply_to_id']?.toString();
            if (replyId != null) {
              try {
                repliedMsg = widget.messages.firstWhere(
                  (m) => m['id'].toString() == replyId,
                );
              } catch (_) {
                // Not in current list (already deleted or too old)
              }
            }

            return Column(
              key: GlobalObjectKey(msg['id'].toString()),
              children: [
                if (_shouldShowDate(index))
                  DateSeparator(
                    date:
                        DateTime.tryParse(msg['created_at'] ?? '')?.toLocal() ??
                        DateTime.now(),
                  ),
                MessageBubble(
                  message: msg,
                  isMe: isMe,
                  senderName: _getSenderName(msg),
                  senderRole: _getSenderRole(msg),
                  senderAvatarUrl: _getSenderAvatarUrl(msg),
                  showSenderName:
                      widget.isGroupChat ||
                      widget.isChannel ||
                      (widget.isAdministrationChat &&
                          _canSeeAdministrationAuthors),
                  isGroupChat: widget.isGroupChat,
                  repliedMessage: repliedMsg,
                  onReply: () => widget.onReply?.call(msg),
                  onEdit: () => widget.onEdit?.call(msg),
                  onDelete: () => widget.onDelete?.call(msg),
                  onForward:
                      msg['message_type'] == 'text' && msg['deleted_at'] == null
                      ? () => widget.onForward?.call(msg)
                      : null,
                  onPin: () => widget.onPin?.call(msg),
                  onReact: (emoji) => widget.onReact?.call(msg['id'], emoji),
                  reactions: widget.reactionsMap?[msg['id'].toString()],
                  isHighlighted: _highlightedMessageId == msg['id'].toString(),
                  forwardedFromName: _getForwardedName(msg),
                  onJumpToReplied: () {
                    if (repliedMsg != null) {
                      _jumpToMessage(repliedMsg['id'].toString());
                    }
                  },
                  canDeleteOthers: canAdminDelete,
                ),
              ],
            );
          },
        ),
        // KVA-174: scroll-to-bottom button with unread badge.
        if (!_isAtBottom)
          Positioned(
            bottom: AppSpace.md,
            right: AppSpace.md,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                FloatingActionButton.small(
                  heroTag: 'scroll_to_bottom',
                  tooltip: 'К новым сообщениям',
                  onPressed: () {
                    setState(() => _unreadCount = 0);
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  backgroundColor: cs.surface,
                  foregroundColor: AppColor.gold,
                  elevation: 4,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
                if (_unreadCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpace.xs),
                      decoration: const BoxDecoration(
                        color: AppColor.danger,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PresenceBanner extends StatelessWidget {
  final String? chatId;
  final String? chatType;
  final String? partnerId;
  final Set<String> onlineUserIds;
  final String currentUserId;

  const _PresenceBanner({
    this.chatId,
    this.chatType,
    this.partnerId,
    required this.onlineUserIds,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (chatId == null) return const SizedBox.shrink();
    if (chatType != 'direct') return const SizedBox.shrink();

    final peerId = partnerId;
    if (peerId == null || peerId.isEmpty || peerId == currentUserId) {
      return const SizedBox.shrink();
    }
    if (!onlineUserIds.contains(peerId)) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const text = 'Собеседник в сети';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      color: Colors.amber.withAlpha(25),
      child: Row(
        children: [
          const Icon(
            Icons.remove_red_eye_rounded,
            size: 14,
            color: Colors.amber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
