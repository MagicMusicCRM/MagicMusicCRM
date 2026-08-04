part of 'messenger_screen.dart';

extension _MessengerMessaging on _MessengerScreenState {
  // ── Send message ───────────────────────────────────────────────────────────

  /// Pass [sort]: false when upserting a batch — sort once after the loop
  /// instead of re-sorting the whole list per message (O(n²·log n) on the
  /// 100-message fallback poll).
  void _upsertMessage(Map<String, dynamic> message, {bool sort = true}) {
    final id = message['id']?.toString();
    if (id == null || id.isEmpty) return;
    final index = _messages.indexWhere((item) => item['id']?.toString() == id);
    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] = {..._messages[index], ...message};
    }
    if (sort) _sortMessagesChronologically();
  }

  void _sortMessagesChronologically() {
    // Decorate-sort-undecorate: parse each created_at ONCE per sort instead of
    // O(n log n) DateTime.tryParse calls inside the comparator.
    final decorated = [
      for (final m in _messages)
        (
          DateTime.tryParse(m['created_at']?.toString() ?? ''),
          m['id']?.toString() ?? '',
          m,
        ),
    ];
    decorated.sort((a, b) {
      final aCreated = a.$1;
      final bCreated = b.$1;
      if (aCreated == null && bCreated == null) return a.$2.compareTo(b.$2);
      if (aCreated == null) return 1;
      if (bCreated == null) return -1;
      final byDate = aCreated.compareTo(bCreated);
      if (byDate != 0) return byDate;
      return a.$2.compareTo(b.$2);
    });
    for (var i = 0; i < decorated.length; i++) {
      _messages[i] = decorated[i].$3;
    }
  }

  void _applySentMessage(Map<String, dynamic> message, {bool channel = false}) {
    if (!mounted) return;
    _emitState(() {
      _upsertMessage(message);
      if (message['id'] != null) _hiddenPinnedBars.remove(message['id']);
    });
    _updateChatItemLastMessage(
      channel ? {...message, '_is_channel_post': true} : message,
    );
  }

  void _removeMessageById(String messageId) {
    if (!mounted) return;
    _emitState(() {
      _messages.removeWhere((item) => item['id']?.toString() == messageId);
    });
  }

  Map<String, dynamic> _optimisticTextMessage(
    String text, {
    String? replyToId,
  }) {
    final now = DateTime.now().toIso8601String();
    return {
      'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
      'chat_id': _selectedChatId,
      'sender_id': _userId,
      'sender_name': _currentUserDisplayName,
      'content': text,
      'message_type': 'text',
      'created_at': now,
      'reply_to_id': replyToId,
      'is_read': false,
      '_pending': true,
    };
  }

  Future<void> _sendTextMessage(
    String text, {
    String? replyToId,
    String? editingMessageId,
  }) async {
    if (_selectedChatId == null) return;
    final messenger = ref.read(magicMessengerServiceProvider);

    if (_selectedChatType == 'channel') {
      final optimistic = _optimisticTextMessage(text);
      _applySentMessage(optimistic, channel: true);
      try {
        final post = await messenger.createChannelPost(
          _selectedChatId!,
          content: text,
        );
        _removeMessageById(optimistic['id'].toString());
        _applySentMessage(post, channel: true);
      } catch (e) {
        _removeMessageById(optimistic['id'].toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось опубликовать сообщение: $e')),
          );
        }
      }
      return;
    }

    if (editingMessageId != null) {
      try {
        final updated = await messenger.updateMessage(
          editingMessageId,
          content: text,
        );
        if (!mounted) return;
        _emitState(() {
          final index = _messages.indexWhere(
            (message) => message['id']?.toString() == editingMessageId,
          );
          if (index != -1) {
            _messages[index] = {..._messages[index], ...updated};
          }
          _editingMessage = null;
        });
      } catch (e) {
        if (mounted) {
          _emitState(() => _editingMessage = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось изменить сообщение: $e')),
          );
        }
      }
      return;
    }

    final optimistic = _optimisticTextMessage(text, replyToId: replyToId);
    _applySentMessage(optimistic);
    try {
      final message = await messenger.sendMessage(
        _selectedChatId!,
        content: text,
        replyToId: replyToId,
      );

      if (!mounted) return;
      _emitState(() => _replyingTo = null);
      _removeMessageById(optimistic['id'].toString());
      _applySentMessage(message);
    } catch (e) {
      _removeMessageById(optimistic['id'].toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить сообщение: $e')),
        );
      }
    }
  }

  void _deleteMessage(Map<String, dynamic> msg) async {
    final mid = msg['id'].toString();
    final isMe = msg['sender_id'] == _userId;

    if (!isMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Вы можете удалять только свои сообщения'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление сообщения'),
        content: const Text(
          'Вы уверены, что хотите удалить это сообщение для всех?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: AppColor.danger),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final updated = await ref
            .read(magicMessengerServiceProvider)
            .deleteMessage(mid, mode: isMe ? 'own' : 'moderated');
        // Apply the server response locally so the message shows as deleted
        // immediately, independent of realtime delivery.
        if (mounted) {
          _emitState(() {
            final idx = _messages.indexWhere((m) => m['id'] == mid);
            if (idx != -1) _messages[idx] = {..._messages[idx], ...updated};
          });
        }
      } catch (e) {
        _logMessenger('Error deleting message: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось удалить сообщение: $e')),
          );
        }
      }
    }
  }

  Future<void> _sendVoiceMessage(
    Uint8List bytes,
    int durationMs,
    String ext,
  ) async {
    if (_selectedChatId == null) return;
    final fileId = await ref
        .read(chatAttachmentServiceProvider)
        .uploadVoice(
          bytes: bytes,
          senderId: _userId,
          extension: ext,
          chatId: _selectedChatId!,
        );

    final message = await ref
        .read(magicMessengerServiceProvider)
        .sendMessage(
          _selectedChatId!,
          content: '🎤 Голосовое сообщение',
          messageType: 'voice',
          attachmentFileId: fileId,
        );
    _applySentMessage({...message, 'voice_duration_ms': durationMs});
  }

  Future<void> _sendFileMessage(
    Uint8List bytes,
    String fileName,
    int fileSize, {
    String? caption,
  }) async {
    if (_selectedChatId == null) return;
    final mimeType = lookupMimeType(fileName, headerBytes: bytes);
    final messageType = mimeType?.startsWith('image/') == true
        ? 'image'
        : 'file';
    final fileId = await ref
        .read(chatAttachmentServiceProvider)
        .uploadFile(
          bytes: bytes,
          originalFileName: fileName,
          senderId: _userId,
          chatId: _selectedChatId!,
        );

    final content = caption?.isNotEmpty == true ? caption!.trim() : fileName;
    final message = await ref
        .read(magicMessengerServiceProvider)
        .sendMessage(
          _selectedChatId!,
          content: content,
          messageType: messageType,
          attachmentFileId: fileId,
        );
    _applySentMessage({
      ...message,
      'message_type': messageType,
      'attachment_file_id': fileId,
      'attachment_name': fileName,
      'attachment_size': fileSize,
      'attachment_mime_type': mimeType,
    });
  }

  void _showSendFileDialog(Uint8List bytes, String fileName, int fileSize) {
    showDialog(
      context: context,
      builder: (context) => SendFileDialog(
        fileName: fileName,
        fileSize: fileSize,
        fileBytes: bytes,
        onSend: (caption) =>
            _sendFileMessage(bytes, fileName, fileSize, caption: caption),
      ),
    );
  }

  // ── Chat selection ─────────────────────────────────────────────────────────

  void _selectChat(Map<String, dynamic> item) {
    String id = (item['id'] ?? '').toString();
    final type = (item['_item_type'] ?? item['item_type'] ?? 'direct')
        .toString();
    final rawType = (item['raw_type'] ?? type).toString();

    // Robust ID resolution:
    // If the ID looks like a user ID (e.g. from profile), try to find an existing chat session first
    if (type == 'direct' && id.isNotEmpty) {
      final existingChat = _chatItems
          .where((c) => c['id'] == id || c['_partner_id'] == id)
          .toList();

      if (existingChat.isNotEmpty) {
        // Use the existing chat's ID (the UUID for the conversation)
        id = existingChat.first['id'].toString();
      }
    }

    if (id == _selectedChatId && _loadingMessages) return;

    final avatarUrl = _getAvatarUrl(item);
    final partnerId =
        item['_partner_id']?.toString() ?? item['partner_id']?.toString();
    final name =
        (item['_display_name'] ??
                item['display_name'] ??
                item['name'] ??
                'Аноним')
            .toString();

    _emitState(() {
      _selectedChatId = id;
      _selectedChatType = type;
      _selectedChatRawType = rawType;
      _selectedChatSlug = item['slug']?.toString() ?? item['_slug']?.toString();
      _selectedChatName = name;
      _selectedChatAvatarUrl = avatarUrl;
      _selectedPartnerId = partnerId;
      _messages = [];
      _onlineUsers.clear();
    });

    // Resolve the existing CRM card shortcut. Lead/student creation is never
    // offered from chat: the first incoming message already creates the lead.
    if (_isManagerOrAdminRole &&
        type == 'direct' &&
        partnerId != null &&
        partnerId.isNotEmpty) {
      unawaited(_resolveContactLink(partnerId));
    }

    _loadMessages();
    if (type == 'channel') {
      // Channels use a dedicated channel room; typing/presence/reactions do not
      // apply. Keep it subscribed (don't leave) so posts keep arriving live.
      _realtimeConnection?.joinChannel(id);
      _joinedChannelIds.add(id);
    } else {
      _joinTypingChannel(id);
      _joinPresenceChannel(id);
      _joinReactionsChannel(id);
    }
    _fetchPinnedMessages();
  }

  Future<void> _joinReactionsChannel(String chatId) async {
    _realtimeConnection?.joinChat(chatId);
  }

  Future<void> _joinPresenceChannel(String chatId) async {
    _realtimeConnection?.joinChat(chatId);
    _realtimeConnection?.updatePresence();
  }

  void _deselectChat() {
    _leaveTypingChannel();
    _emitState(() {
      _selectedChatId = null;
      _selectedChatType = null;
      _selectedChatRawType = null;
      _selectedChatSlug = null;
      _selectedChatName = null;
      _selectedChatAvatarUrl = null;
      _selectedPartnerId = null;
      _messages = [];
      _showProfilePanel = false;
    });
  }

  bool _hasInternalBackState({required bool includeCrmTabs}) {
    return _showMyProfile ||
        _showProfilePanel ||
        _isSearchingInChat ||
        _selectedChatId != null ||
        (includeCrmTabs && _selectedCrmTab != 0);
  }

  void _consumeBackNavigation({required bool includeCrmTabs}) {
    if (_showMyProfile) {
      _emitState(() => _showMyProfile = false);
      return;
    }

    if (_showProfilePanel) {
      _emitState(() => _showProfilePanel = false);
      return;
    }

    if (_isSearchingInChat) {
      _emitState(() {
        _isSearchingInChat = false;
        _chatSearchController.clear();
        _searchResults.clear();
        _currentMatchIndex = 0;
      });
      return;
    }

    if (_selectedChatId != null) {
      _deselectChat();
      return;
    }

    if (includeCrmTabs && _selectedCrmTab != 0) {
      _selectCrmTab(0);
    }
  }

  Future<void> _onMuteChat(bool isMuted) async {
    if (_selectedChatId == null || _selectedChatType == null) return;
    final chatId = _selectedChatId!;
    final wasMuted = _mutedChatIds.contains(chatId);
    try {
      _emitState(() {
        if (isMuted) {
          _mutedChatIds.add(chatId);
        } else {
          _mutedChatIds.remove(chatId);
        }
        _chatItems = _chatItems
            .map(
              (item) =>
                  item['id'] == chatId ? {...item, 'is_muted': isMuted} : item,
            )
            .toList();
      });
      await ref
          .read(magicMessengerServiceProvider)
          .setChatMute(chatId, isMuted: isMuted);
    } catch (e) {
      _logMessenger('Error muting chat: $e');
      if (mounted) {
        _emitState(() {
          if (wasMuted) {
            _mutedChatIds.add(chatId);
          } else {
            _mutedChatIds.remove(chatId);
          }
          _chatItems = _chatItems
              .map(
                (item) => item['id'] == chatId
                    ? {...item, 'is_muted': wasMuted}
                    : item,
              )
              .toList();
        });
      }
      rethrow;
    }
  }

  // ── Check channel post permission ──────────────────────────────────────────

  bool _canPostToChannel() {
    return _isManagerOrAdminRole;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String? _getAvatarUrl(Map<String, dynamic> item) {
    if (item.containsKey('_avatar_url')) return item['_avatar_url'] as String?;

    final type = (item['_item_type'] ?? item['item_type']) as String?;
    if (type == 'direct') {
      final profile = item['_profile'] ?? item['profile'];
      return profile is Map ? profile['avatar_url']?.toString() : null;
    } else if (type == 'group') {
      final groupData = item['_group_data'] ?? item['group_data'];
      return groupData is Map ? groupData['avatar_url']?.toString() : null;
    } else if (type == 'channel') {
      final channelData = item['_channel_data'] ?? item['channel_data'];
      return channelData is Map ? channelData['avatar_url']?.toString() : null;
    }
    return null;
  }

  Future<void> _fetchReactionsForCurrentMessages() async {
    if (_messages.isEmpty) return;
    final nextMap = <String, List<dynamic>>{};
    for (final message in _messages) {
      final reactions = message['reactions'];
      if (reactions is List) {
        nextMap[message['id'].toString()] = reactions;
      }
    }
    if (mounted) _emitState(() => _reactionsMap = nextMap);
  }

  void _applyReactionsToMessage(String messageId, List<dynamic> reactions) {
    final idx = _messages.indexWhere((m) => m['id'] == messageId);
    if (idx != -1) {
      _messages[idx] = {..._messages[idx], 'reactions': reactions};
    }
  }

  // True if the aggregated reaction list marks `emoji` as reacted by me.
  // Tolerates the legacy per-user shape ({user_id, emoji}) as a fallback.
  bool _reactionMine(List<dynamic> list, String emoji) => list.any(
    (r) =>
        r is Map &&
        r['emoji'] == emoji &&
        (r['reactedByMe'] == true || r['user_id'] == _userId),
  );

  Future<void> _toggleReaction(String messageId, String emoji) async {
    final messenger = ref.read(magicMessengerServiceProvider);
    final previous = List<dynamic>.from(_reactionsMap[messageId] ?? const []);
    final hasMine = _reactionMine(previous, emoji);

    // Optimistic update in the aggregated shape {emoji,count,reactedByMe} so the
    // chip reflects instantly. The server response is applied as authoritative
    // state below.
    final optimistic = <Map<String, dynamic>>[];
    var found = false;
    for (final r in previous) {
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r);
      if (m['emoji']?.toString() == emoji) {
        found = true;
        final c = (m['count'] as num?)?.toInt() ?? 1;
        final next = hasMine ? c - 1 : c + 1;
        if (next <= 0) continue; // drop the chip when it hits zero
        m['count'] = next;
        m['reactedByMe'] = !hasMine;
      }
      optimistic.add(m);
    }
    if (!found && !hasMine) {
      optimistic.add({'emoji': emoji, 'count': 1, 'reactedByMe': true});
    }
    _emitState(() {
      _reactionsMap = {..._reactionsMap, messageId: optimistic};
      _applyReactionsToMessage(messageId, optimistic);
    });

    try {
      final result = hasMine
          ? await messenger.removeReaction(messageId: messageId, emoji: emoji)
          : await messenger.setReaction(messageId: messageId, emoji: emoji);
      final reactions = result['reactions'];
      if (reactions is List && mounted) {
        // Server returns aggregated counts without reactedByMe; re-apply my own
        // flag — the toggled emoji reflects my new state, others keep theirs.
        final merged = reactions.map((r) {
          final m = Map<String, dynamic>.from(r as Map);
          final e = m['emoji']?.toString() ?? '';
          m['reactedByMe'] = e == emoji ? !hasMine : _reactionMine(previous, e);
          return m;
        }).toList();
        _emitState(() {
          _reactionsMap = {..._reactionsMap, messageId: merged};
          _applyReactionsToMessage(messageId, merged);
        });
      }
    } catch (e) {
      _logMessenger('Error toggling reaction: $e');
      // Revert the optimistic change on failure.
      if (mounted) {
        _emitState(() {
          _reactionsMap = {..._reactionsMap, messageId: previous};
          _applyReactionsToMessage(messageId, previous);
        });
      }
    }
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return '';
    final dt = DateTime.tryParse(isoTime);
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(local.year, local.month, local.day);

    if (msgDate == today) return DateFormat('HH:mm', 'ru').format(local);
    if (today.difference(msgDate).inDays == 1) return 'Вчера';
    if (today.difference(msgDate).inDays < 7) {
      return DateFormat('EE', 'ru').format(local);
    }
    return DateFormat('dd.MM', 'ru').format(local);
  }

  String _messagePreview(Map<String, dynamic>? msg) {
    if (msg == null) return 'Нет сообщений';
    return msg['content']?.toString() ?? '';
  }
}
