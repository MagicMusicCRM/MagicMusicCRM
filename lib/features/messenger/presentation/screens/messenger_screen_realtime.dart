part of 'messenger_screen.dart';

extension _MessengerRealtime on _MessengerScreenState {
  // Legacy loading methods removed in favor of RPC get_recent_chats_v3

  // Legacy loading methods removed in favor of RPC get_recent_chats_v3

  // ── Load messages for selected chat ────────────────────────────────────────

  Future<void> _loadMessages() async {
    if (_selectedChatId == null) return;

    _currentLoadId++;
    final loadId = _currentLoadId;

    _logMessenger(
      'MessengerScreen: _loadMessages started for $_selectedChatId (LoadId: $loadId)',
    );

    _emitState(() {
      _loadingMessages = true;
      _messages = [];
    });

    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      if (_selectedChatType == 'channel') {
        final posts = await messenger
            .listChannelPosts(_selectedChatId!, limit: 100)
            .timeout(const Duration(seconds: 20));

        if (loadId != _currentLoadId) return;

        if (mounted) {
          _emitState(() {
            _messages = List<Map<String, dynamic>>.from(posts);
            _sortMessagesChronologically();
          });
        }
      } else {
        final msgs = await messenger
            .listMessages(_selectedChatId!, limit: 100)
            .timeout(const Duration(seconds: 20));

        if (loadId != _currentLoadId) return;

        if (mounted) {
          _emitState(() {
            _messages = List<Map<String, dynamic>>.from(msgs);
            _sortMessagesChronologically();
          });
          _fetchReactionsForCurrentMessages();
          _markMessagesRead();
        }
      }
    } on Exception catch (e) {
      _logMessenger('MessengerScreen error [LoadId: $loadId]: $e');
      if (mounted && loadId == _currentLoadId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки сообщений: ${e.toString()}'),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted && loadId == _currentLoadId) {
        _emitState(() => _loadingMessages = false);
        _logMessenger(
          'MessengerScreen: _loadMessages finished (LoadId: $loadId)',
        );
      }
    }
  }

  Future<void> _markMessagesRead() async {
    if (_selectedChatId == null) return;
    final chatId = _selectedChatId!;
    final previous = _unreadCounts[chatId] ?? 0;
    _emitState(() => _unreadCounts[chatId] = 0);
    // Pass the latest message ID so the server can skip the resolve query.
    final lastMsgId = _messages.isNotEmpty
        ? _messages.last['id']?.toString()
        : null;
    try {
      await ref
          .read(magicMessengerServiceProvider)
          .markRead(chatId, lastReadMessageId: lastMsgId);
    } catch (e) {
      if (mounted) _emitState(() => _unreadCounts[chatId] = previous);
      _logMessenger('MessengerScreen: Error marking messages as read: $e');
    }
  }

  // ── Realtime subscription ──────────────────────────────────────────────────

  Future<void> _connectRealtime() async {
    try {
      _realtimeConnection?.dispose();
      final connection = await ref.read(magicRealtimeServiceProvider).connect();
      _realtimeConnection = connection;
      if (_userId.isNotEmpty) connection.joinUserRoom(_userId);

      connection.onMessageCreated(_handleRealtimeMessageCreated);
      connection.onMessageUpdated(_handleRealtimeMessageUpdated);
      connection.onChannelPostCreated(_handleRealtimeChannelPostCreated);
      connection.onChatCreated(_handleRealtimeChatCreated);
      connection.onChatRemoved(_handleRealtimeChatRemoved);
      connection.onChatUpdated(_handleRealtimeChatUpdated);
      connection.onTypingStart(_handleRealtimeTypingStart);
      connection.onTypingStop(_handleRealtimeTypingStop);
      connection.onPresenceUpdated(_handleRealtimePresenceUpdated);
      // Shared settings (e.g. administration chat avatar) changing live.
      connection.onCrmChanged(_handleRealtimeCrmChanged);
      // Restore every needed subscription after a reconnect (Socket.IO only keeps
      // the server-side user/crm rooms; chat/channel rooms must be re-joined).
      connection.onConnect(_onRealtimeReconnected);

      // Subscribe to broadcast channels (Объявления) so posts arrive live even
      // when the channel is not the active conversation.
      _joinAnnouncementChannels();
      _startRealtimeFallbackPolling();
    } catch (e) {
      _logMessenger('MessengerScreen: Error connecting v3 realtime: $e');
      _startRealtimeFallbackPolling();
    }
  }

  void _markRealtimeEvent() {
    _lastRealtimeEventAt = DateTime.now();
  }

  void _startRealtimeFallbackPolling() {
    if (_realtimeFallbackTimer != null) return;
    _realtimeFallbackTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      final realtimeIsFresh =
          DateTime.now().difference(_lastRealtimeEventAt) <
          const Duration(seconds: 18);
      if (realtimeIsFresh) return;

      unawaited(_refreshSelectedMessagesSilently());

      final shouldRefreshList =
          DateTime.now().difference(_lastFallbackChatListAt) >
          const Duration(seconds: 36);
      if (shouldRefreshList) {
        _lastFallbackChatListAt = DateTime.now();
        unawaited(_loadChatList());
      }
    });
  }

  Future<void> _refreshSelectedMessagesSilently() async {
    final chatId = _selectedChatId;
    if (chatId == null || chatId.isEmpty || _loadingMessages) return;
    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      final items = _selectedChatType == 'channel'
          ? await messenger.listChannelPosts(chatId, limit: 100)
          : await messenger.listMessages(chatId, limit: 100);
      if (!mounted || _selectedChatId != chatId) return;
      _emitState(() {
        for (final item in items) {
          _upsertMessage(item);
        }
        _sortMessagesChronologically();
      });
      if (_selectedChatType != 'channel') unawaited(_markMessagesRead());
    } catch (e) {
      _logMessenger('MessengerScreen: fallback message poll failed: $e');
    }
  }

  /// Re-join all rooms after a (re)connect. Idempotent — safe on first connect.
  void _onRealtimeReconnected() {
    final connection = _realtimeConnection;
    if (connection == null) return;
    if (_userId.isNotEmpty) connection.joinUserRoom(_userId);
    final activeChat = _joinedRealtimeChatId;
    if (activeChat != null) connection.joinChat(activeChat);
    for (final channelId in _joinedChannelIds) {
      connection.joinChannel(channelId);
    }
    _joinAnnouncementChannels();
  }

  /// Join (and remember) every channel room present in the current chat list.
  void _joinAnnouncementChannels() {
    final connection = _realtimeConnection;
    if (connection == null) return;
    for (final item in _chatItems) {
      final type = (item['_item_type'] ?? item['item_type'] ?? '').toString();
      if (type != 'channel') continue;
      final id = item['id']?.toString();
      if (id == null || id.isEmpty) continue;
      connection.joinChannel(id);
      _joinedChannelIds.add(id);
    }
  }

  void _scheduleChatListReload() {
    _chatListReloadTimer?.cancel();
    _chatListReloadTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _loadChatList();
    });
  }

  void _handleRealtimeMessageCreated(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted) return;
    final message = _normalizeRealtimeMessage(payload);
    final chatId = message['chat_id']?.toString();
    final senderId = message['sender_id']?.toString();
    if (chatId == null) return;

    if (_selectedChatId == chatId) {
      _emitState(() {
        _upsertMessage(message);
      });
      if (senderId != _userId) _markMessagesRead();
    } else if (senderId != _userId) {
      _emitState(
        () => _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1,
      );
    }

    _updateChatItemLastMessage(message);
    if (senderId != _userId &&
        chatId != _selectedChatId &&
        !_mutedChatIds.contains(chatId)) {
      final senderName =
          _chatItems
              .where((c) => c['id'] == chatId)
              .firstOrNull?['_display_name'] ??
          'Новое сообщение';
      NotificationService.showLocalNotification(
        title: senderName,
        body: message['content'] ?? 'Сообщение',
        payload: {'type': 'chat', 'id': chatId},
      );
    }
  }

  void _handleRealtimeMessageUpdated(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted) return;
    final messageId = payload['id']?.toString();
    if (messageId == null) return;

    // Patch ONLY the fields the event actually carries. A reaction/pin update
    // sends just {id, reactions}; merging a fully-normalized map here would null
    // out sender/content/created_at and make the message flip to "Пользователь",
    // blank out, and jump in the sort until the next REST refresh.
    final normalized = _normalizeRealtimeMessage(payload);
    const aliases = <String, List<String>>{
      'content': ['content'],
      'message_type': ['messageType', 'message_type'],
      'attachment_file_id': ['attachmentFileId', 'attachment_file_id'],
      'attachment_name': [
        'attachmentName',
        'attachmentFileName',
        'attachment_name',
      ],
      'attachment_size': [
        'attachmentSize',
        'attachmentFileSize',
        'attachment_size',
      ],
      'attachment_mime_type': [
        'attachmentMimeType',
        'attachmentContentType',
        'attachment_mime_type',
      ],
      'reply_to_id': ['replyToId', 'reply_to_id'],
      'forwarded_from_id': ['forwardedFromId', 'forwarded_from_id'],
      'pinned_by': ['pinnedBy', 'pinned_by'],
      'pinned_at': ['pinnedAt', 'pinned_at'],
      'updated_at': ['updatedAt', 'updated_at'],
      'deleted_at': ['deletedAt', 'deleted_at'],
    };
    final patch = <String, dynamic>{};
    aliases.forEach((key, srcKeys) {
      if (srcKeys.any(payload.containsKey)) patch[key] = normalized[key];
    });
    if (payload['sender'] is Map ||
        payload.containsKey('senderId') ||
        payload.containsKey('sender_id')) {
      patch['sender_id'] = normalized['sender_id'];
      patch['profiles'] = normalized['profiles'];
    }

    _emitState(() {
      final idx = _messages.indexWhere((msg) => msg['id'] == messageId);
      if (idx != -1) {
        _messages[idx] = {..._messages[idx], ...patch};
        if (payload['reactions'] is List) {
          _messages[idx]['reactions'] = payload['reactions'];
        }
      }
      if (payload['reactions'] is List) {
        _reactionsMap[messageId] = payload['reactions'] as List<dynamic>;
      }
    });
    _fetchPinnedMessages();
  }

  void _handleRealtimeChannelPostCreated(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted) return;
    final post = _normalizeRealtimeChannelPost(payload);
    final channelId = post['channel_id']?.toString();
    if (channelId == null) return;

    if (_selectedChatId == channelId && _selectedChatType == 'channel') {
      _emitState(() {
        _upsertMessage(post);
      });
    }
    _updateChatItemLastMessage({...post, '_is_channel_post': true});
  }

  void _handleRealtimeChatCreated(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted) return;
    final service = ref.read(magicMessengerServiceProvider);
    final mapped = service.legacyChatFromSummary(payload);
    _emitState(() => _chatItems = upsertChat(_chatItems, mapped));
  }

  void _handleRealtimeChatRemoved(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted) return;
    final id = payload['id'] as String?;
    if (id == null) return;
    _emitState(() {
      _chatItems = removeChat(_chatItems, id);
      _unreadCounts.remove(id);
    });
  }

  void _handleRealtimeChatUpdated(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted) return;
    final chatId = (payload['id'] ?? payload['chatId'])?.toString();
    final readerId = payload['readerId']?.toString();
    if (chatId != null && readerId != null) {
      if (readerId == _userId) {
        _emitState(() => _unreadCounts[chatId] = 0);
      }
      return;
    }

    final userId = payload['userId']?.toString();
    if (chatId != null && userId == _userId && payload.containsKey('isMuted')) {
      final isMuted = payload['isMuted'] == true;
      _emitState(() {
        if (isMuted) {
          _mutedChatIds.add(chatId);
        } else {
          _mutedChatIds.remove(chatId);
        }
      });
      return;
    }

    // Enriched fan-out: a message landed in a chat we are not actively viewing.
    // Patch the list item (last message + unread) in place when we already know
    // the chat; only a brand-new conversation triggers a (debounced) reload.
    final lastMessageId = payload['lastMessageId']?.toString();
    if (chatId != null && lastMessageId != null) {
      final known = _chatItems.any((c) => c['id']?.toString() == chatId);
      if (!known) {
        _scheduleChatListReload();
        return;
      }
      final senderId = payload['senderId']?.toString();
      _updateChatItemLastMessage({
        'chat_id': chatId,
        'content': payload['lastMessage'],
        'created_at': payload['lastMessageAt'],
        'sender_id': senderId,
      });
      if (chatId != _selectedChatId && senderId != _userId) {
        _emitState(
          () => _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1,
        );
      }
      return;
    }

    // Assignment / archive / folder update — patch in place so folder badges
    // and the assignee chip update live without a full reload.
    // Backend never combines lastMessageId with assignedTo/archived/folder in one chat.updated; if it ever does, this branch must also run inside the fan-out branch above (it currently early-returns).
    if (payload.containsKey('assignedTo') ||
        payload.containsKey('archived') ||
        payload.containsKey('folder')) {
      _emitState(() => _chatItems = patchChat(_chatItems, payload));
      return;
    }

    // Bare chat.updated (e.g. a group change). Coalesce bursts into one reload.
    _scheduleChatListReload();
  }

  /// Shared-setting change broadcast to every socket. Currently only the
  /// administration chat avatar affects this screen — refetch the list (which
  /// reloads the avatar) when it changes.
  void _handleRealtimeCrmChanged(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted) return;
    if (payload['entity']?.toString() != 'setting') return;
    _scheduleChatListReload();
  }

  void _handleRealtimeTypingStart(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted || payload['chatId'] != _selectedChatId) return;
    final userId = payload['userId']?.toString();
    if (userId == null || userId == _userId) return;
    _emitState(() => _typingText = 'Пользователь печатает...');
  }

  void _handleRealtimeTypingStop(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted || payload['chatId'] != _selectedChatId) return;
    _emitState(() => _typingText = '');
  }

  void _handleRealtimePresenceUpdated(Map<String, dynamic> payload) {
    _markRealtimeEvent();
    if (!mounted) return;
    final userId = payload['userId']?.toString();
    if (userId == null || userId == _userId) return;
    final status = payload['status']?.toString();
    _emitState(() {
      if (status == 'offline') {
        _onlineUsers.remove(userId);
      } else {
        _onlineUsers.add(userId);
      }
    });
  }

  Map<String, dynamic> _normalizeRealtimeMessage(Map<String, dynamic> payload) {
    final sender = payload['sender'];
    final senderMap = sender is Map
        ? sender.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    return {
      'id': payload['id'],
      'chat_id': payload['chatId'] ?? payload['chat_id'],
      'sender_id': payload['senderId'] ?? payload['sender_id'],
      'content': payload['content'],
      'message_type': payload['messageType'] ?? payload['message_type'],
      'attachment_file_id':
          payload['attachmentFileId'] ?? payload['attachment_file_id'],
      'attachment_name':
          payload['attachmentName'] ??
          payload['attachmentFileName'] ??
          payload['attachment_name'],
      'attachment_size':
          payload['attachmentSize'] ??
          payload['attachmentFileSize'] ??
          payload['attachment_size'],
      'attachment_mime_type':
          payload['attachmentMimeType'] ??
          payload['attachmentContentType'] ??
          payload['attachment_mime_type'],
      'reply_to_id': payload['replyToId'] ?? payload['reply_to_id'],
      'forwarded_from_id':
          payload['forwardedFromId'] ?? payload['forwarded_from_id'],
      'pinned_by': payload['pinnedBy'] ?? payload['pinned_by'],
      'pinned_at': payload['pinnedAt'] ?? payload['pinned_at'],
      'created_at': payload['createdAt'] ?? payload['created_at'],
      'updated_at': payload['updatedAt'] ?? payload['updated_at'],
      'deleted_at': payload['deletedAt'] ?? payload['deleted_at'],
      'is_read':
          payload['isRead'] == true ||
          payload['is_read'] == true ||
          payload['read'] == true,
      if (payload['reactions'] is List) 'reactions': payload['reactions'],
      'profiles': {
        'id': senderMap['id'],
        'email': senderMap['email'],
        'first_name': senderMap['firstName'] ?? senderMap['first_name'],
        'last_name': senderMap['lastName'] ?? senderMap['last_name'],
        'role': senderMap['role'],
        'avatar_file_id':
            senderMap['avatarFileId'] ?? senderMap['avatar_file_id'],
      },
    };
  }

  Map<String, dynamic> _normalizeRealtimeChannelPost(
    Map<String, dynamic> payload,
  ) {
    return {
      'id': payload['id'],
      'channel_id': payload['channelId'] ?? payload['channel_id'],
      'author_id': payload['authorId'] ?? payload['author_id'],
      'sender_id': payload['authorId'] ?? payload['author_id'],
      'content': payload['content'],
      'attachment_file_id':
          payload['attachmentFileId'] ?? payload['attachment_file_id'],
      'message_type':
          (payload['attachmentFileId'] ?? payload['attachment_file_id']) == null
          ? 'text'
          : 'file',
      'published_at': payload['publishedAt'] ?? payload['published_at'],
      'created_at': payload['publishedAt'] ?? payload['published_at'],
      'updated_at': payload['updatedAt'] ?? payload['updated_at'],
      'is_read': true,
    };
  }

  void _updateChatItemLastMessage(Map<String, dynamic> msg) {
    final chatId = msg['chat_id']?.toString();
    final groupChatId = msg['group_chat_id']?.toString();
    final channelId = msg['channel_id']?.toString();
    final isChannel = msg['_is_channel_post'] == true;

    _emitState(() {
      for (var i = 0; i < _chatItems.length; i++) {
        final item = _chatItems[i];

        if (isChannel &&
            item['id'] == channelId &&
            item['_item_type'] == 'channel') {
          _chatItems[i] = {
            ...item,
            '_last_message': msg,
            '_last_message_time': msg['created_at'],
          };
          break;
        }

        if (chatId != null && item['id'] == chatId) {
          _chatItems[i] = {
            ...item,
            '_last_message': msg,
            '_last_message_time': msg['created_at'],
          };
          break;
        }

        if (groupChatId != null && item['id'] == groupChatId) {
          _chatItems[i] = {
            ...item,
            '_last_message': msg,
            '_last_message_time': msg['created_at'],
          };
          break;
        } else if (groupChatId == null && !isChannel) {
          if (widget.role == 'client' && item['id'] == 'admin_chat') {
            // Admin chat for clients - check if sender is from adminIds or it's my own message to null receiver
            final senderId = msg['sender_id']?.toString();
            final receiverId = msg['receiver_id']?.toString();
            bool isRelevant =
                (senderId == _userId && receiverId == null) ||
                _adminIds.contains(senderId) ||
                _adminIds.contains(receiverId);

            if (isRelevant) {
              _chatItems[i] = {
                ...item,
                '_last_message': msg,
                '_last_message_time': msg['created_at'],
              };
              break;
            }
          } else if (item['_partner_id'] == msg['sender_id'] ||
              item['_partner_id'] == msg['receiver_id']) {
            // For teachers, ignore messages to the administration queue.
            if (widget.role == 'teacher' && msg['receiver_id'] == null) {
              continue;
            }

            _chatItems[i] = {
              ...item,
              '_last_message': msg,
              '_last_message_time': msg['created_at'],
            };
            break;
          }
        }
      }
    });
  }

  // ── Typing Presence ────────────────────────────────────────────────────────

  Future<void> _joinTypingChannel(String chatId) async {
    if (_joinedRealtimeChatId != chatId) {
      if (_joinedRealtimeChatId != null) {
        _realtimeConnection?.leaveRoom(_joinedRealtimeChatId!);
      }
      _joinedRealtimeChatId = chatId;
      _realtimeConnection?.joinChat(chatId);
      if (mounted) {
        _emitState(() {
          _typingText = '';
          _onlineUsers.clear();
        });
      }
    }
    _realtimeConnection?.updatePresence();
  }

  void _leaveTypingChannel() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    if (_joinedRealtimeChatId != null) {
      _realtimeConnection?.leaveRoom(_joinedRealtimeChatId!);
      _joinedRealtimeChatId = null;
    }
    if (mounted) {
      _emitState(() {
        _typingText = '';
        _onlineUsers.clear();
      });
    }
  }

  Future<void> _trackTyping(bool isTyping, String name) async {
    final chatId = _selectedChatId;
    if (chatId == null) return;
    if (isTyping) {
      _realtimeConnection?.startTyping(chatId);
    } else {
      _realtimeConnection?.stopTyping(chatId);
    }
  }

  void _handleTyping(bool isTyping) {
    _typingStopTimer?.cancel();
    unawaited(_trackTyping(isTyping, _currentUserDisplayName));

    if (isTyping) {
      final chatId = _selectedChatId;
      _typingStopTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted || _selectedChatId != chatId) return;
        unawaited(_trackTyping(false, _currentUserDisplayName));
      });
    } else {
      _typingStopTimer = null;
    }
  }
}
