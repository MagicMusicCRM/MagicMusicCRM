part of 'messenger_screen.dart';

extension _MessengerBuildersB on _MessengerScreenState {
  // ── Chat View Panel ────────────────────────────────────────────────────────

  Widget _buildChatView(BuildContext context, bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText = isDark
        ? AppColor.text2
        : TelegramColors.lightTextSecondary;
    final isChannel = _selectedChatType == 'channel';
    final isGroup = _selectedChatType == 'group';
    // «Объявления» is a group chat everyone reads but only управляющий/директор
    // may post to.
    final isAnnouncements = _selectedChatSlug == 'announcements';
    // Read-only для текущего пользователя: «Объявления» без права письма или
    // канал без права публикации. Клиент просто читает — ни композера, ни
    // подсказки, ни приёма файлов перетаскиванием.
    final isReadOnlyForMe =
        (!isChannel && isAnnouncements && !_isManagerTier) ||
        (isChannel && !_canPostToChannel());

    return DropTarget(
      onDragDone: (details) async {
        if (details.files.isEmpty) return;
        // В read-only разговор файлы не принимаем — как и композер, приём
        // перетаскиванием скрыт от тех, кто не может писать.
        if (isReadOnlyForMe) return;
        final messenger = ScaffoldMessenger.of(context);
        if (isChannel) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Вложения в каналах пока недоступны'),
              backgroundColor: AppColor.danger,
            ),
          );
          return;
        }
        for (final file in details.files) {
          final size = await file.length();
          if (size > ChatAttachmentService.maxFileSizeBytes) {
            if (mounted) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Файл слишком большой (макс. 25 МБ)'),
                  backgroundColor: AppColor.danger,
                ),
              );
            }
            continue;
          }
          final bytes = await file.readAsBytes();
          _showSendFileDialog(bytes, file.name, size);
        }
      },
      child: Container(
        color: isDark ? TelegramColors.darkChatBg : TelegramColors.lightChatBg,
        child: Column(
          children: [
            ChatHeader(
              title: _selectedChatName ?? '',
              subtitle: _selectedChatType == 'direct'
                  ? (_selectedPartnerId != null &&
                            _onlineUsers.contains(_selectedPartnerId)
                        ? 'в сети'
                        : widget.role == 'client'
                        ? 'Поддержка'
                        : 'не в сети')
                  : _selectedChatType == 'group'
                  // Neutral label — the previous "{tracked}+1 в сети" was a
                  // fabricated estimate (a 30-member group could show "1 в сети").
                  ? 'Групповой чат'
                  : isChannel
                  ? 'Канал'
                  : widget.role == 'client'
                  ? 'Поддержка'
                  : 'Личный чат',
              uniqueId: _selectedChatId,
              avatarUrl: _selectedChatAvatarUrl,
              isChannel: isChannel,
              showBackButton: isMobile,
              onBack: _deselectChat,
              actions: [
                if (_pinnedMessages.isNotEmpty &&
                    _hiddenPinnedBars.contains(_selectedChatId))
                  IconButton(
                    icon: const Icon(
                      Icons.push_pin_rounded,
                      size: 20,
                      color: AppColor.gold,
                    ),
                    tooltip: 'Показать закрепленные',
                    onPressed: () => _emitState(
                      () => _hiddenPinnedBars.remove(_selectedChatId),
                    ),
                  ),
                // The first incoming message already creates a lead. A direct
                // chat therefore exposes only an existing-card shortcut; no
                // «save as lead/student» action exists, even while resolution is
                // pending or failed (otherwise a fast click can create a duplicate).
                if (_isManagerOrAdminRole &&
                    _selectedChatType == 'direct' &&
                    (_selectedPartnerId?.isNotEmpty ?? false))
                  Builder(
                    builder: (context) {
                      final link = _chatContactLinks[_selectedPartnerId];
                      final linkedStudentId = link?['studentId'];
                      final linkedLeadId = link?['leadId'];
                      final isLinked =
                          linkedStudentId != null || linkedLeadId != null;
                      if (!isLinked) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(
                          Icons.badge_outlined,
                          size: 20,
                          color: AppColor.gold,
                        ),
                        tooltip: 'Открыть карточку клиента',
                        onPressed: _openContactCard,
                      );
                    },
                  ),
                // Assignment actions for administration (inbox) chats.
                if (_selectedChatId != null &&
                    canShowAssignActions(
                      _isManagerOrAdminRole,
                      _chatItems.firstWhere(
                        (c) => c['id'] == _selectedChatId,
                        orElse: () => const {},
                      ),
                    ))
                  Builder(
                    builder: (context) {
                      final openChat = _chatItems.firstWhere(
                        (c) => c['id'] == _selectedChatId,
                        orElse: () => const {},
                      );
                      final assignedToId =
                          (openChat['assigned_to'] as Map?)?['id']?.toString();
                      final isAssignedToMe =
                          assignedToId != null &&
                          assignedToId == _currentUserId;
                      final isAssigned = assignedToId != null;
                      final isArchived = openChat['archived'] == true;
                      return PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.assignment_ind_rounded,
                          size: 20,
                          color: AppColor.gold,
                        ),
                        tooltip: 'Действия с чатом',
                        itemBuilder: (_) => [
                          // Advisory marker: any staff member can mark that they
                          // started working the chat. This is not an exclusive
                          // lock; the history/audit tells who acted when.
                          if (!isAssignedToMe)
                            const PopupMenuItem(
                              value: 'assign_me',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.assignment_turned_in_outlined,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Взять в работу'),
                                ],
                              ),
                            ),
                          // Manager-tier may clear anyone's marker; others only their own.
                          if (isAssigned && (isAssignedToMe || _isManagerTier))
                            const PopupMenuItem(
                              value: 'unassign',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.assignment_return_outlined,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Снять с работы'),
                                ],
                              ),
                            ),
                          // #4: архив прямо из шапки открытого чата — жест
                          // долгого нажатия по строке на Windows не находили.
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'toggle_archive',
                            child: Row(
                              children: [
                                Icon(
                                  isArchived
                                      ? Icons.unarchive_rounded
                                      : Icons.archive_rounded,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isArchived ? 'Вернуть из архива' : 'В архив',
                                ),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) async {
                          final chatId = _selectedChatId;
                          if (chatId == null) return;
                          if (value == 'assign_me') {
                            await _assignChatToMe(chatId);
                          } else if (value == 'unassign') {
                            await _unassignChat(chatId);
                          } else if (value == 'toggle_archive') {
                            if (isArchived) {
                              await _unarchiveChat(chatId);
                            } else {
                              await _archiveChat(chatId);
                            }
                          }
                        },
                      );
                    },
                  ),
              ],
              onTitleTap: () {
                if (_selectedChatId == null || _selectedChatType == null) {
                  return;
                }

                if (MediaQuery.of(context).size.width >= 768) {
                  _emitState(() => _showProfilePanel = !_showProfilePanel);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatInfoDialog(
                        key: ValueKey('$_selectedChatType:$_selectedChatId'),
                        chatId: _selectedChatId!,
                        chatType: _selectedChatType!,
                        userRole: widget.role,
                        onUpdate: _loadChatList,
                        onSearch: _onSearchInChat,
                        onMute: _onMuteChat,
                        initialIsMuted:
                            _selectedChatId != null &&
                            _mutedChatIds.contains(_selectedChatId),
                        onNavigateToChat: (chat) {
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
                      ),
                    ),
                  );
                }
              },
              isSearchActive: _isSearchingInChat,
              searchController: _chatSearchController,
              onSearchToggle: _onSearchInChat,
              onSearchChanged: (val) => _performSearch(val),
              onSearchSubmitted: (val) => _performSearch(val, jump: true),
              matchCount: _searchResults.length,
              currentMatchIndex: _currentMatchIndex + 1,
              onNextMatch: _nextSearchMatch,
              onPrevMatch: _prevSearchMatch,
            ),
            if (_pinnedMessages.isNotEmpty) _buildPinnedBar(),
            _PresenceBanner(
              chatId: _selectedChatId,
              chatType: _selectedChatType,
              partnerId: _selectedPartnerId,
              onlineUserIds: _onlineUsers,
              currentUserId: _userId,
            ),
            Expanded(
              child: _loadingMessages
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColor.gold),
                    )
                  : _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isChannel
                                ? Icons.campaign_outlined
                                : Icons.chat_bubble_outline_rounded,
                            size: 64,
                            color: secondaryText.withAlpha(60),
                          ),
                          const SizedBox(height: AppSpace.md),
                          Text(
                            isChannel
                                ? 'Пока нет публикаций'
                                : 'Начните общение!',
                            style: TextStyle(color: secondaryText),
                          ),
                        ],
                      ),
                    )
                  : _MessageListView(
                      key: _messagesActionKey,
                      messages: _messages,
                      currentUserId: _userId,
                      isGroupChat: isGroup,
                      isChannel: isChannel,
                      isAdministrationChat:
                          _selectedChatRawType == 'administration',
                      chatItems: _chatItems,
                      adminIds: _adminIds,
                      role: widget.role,
                      selectedChatName: _selectedChatName,
                      onReply: (msg) => _emitState(() {
                        _replyingTo = msg;
                        _editingMessage = null;
                      }),
                      onEdit: (msg) => _emitState(() {
                        _editingMessage = msg;
                        _replyingTo = null;
                      }),
                      onDelete: _deleteMessage,
                      onForward: _onForwardMessage,
                      onPin: (msg) => _togglePin(
                        msg['id'].toString(),
                        msg['pinned_at'] == null,
                      ),
                      onReact: _toggleReaction,
                      reactionsMap: _reactionsMap,
                    ),
            ),
            // Input (not for channels unless user has permission). «Объявления»
            // is read-only for everyone except управляющий/директор.
            // #18: клиент просто читает — композер скрыт целиком, без подсказки
            // (ни поля ввода, ни голосового, ни скрепки). Подсказку «кто может
            // писать» оставляем только персоналу без права письма.
            if (!isChannel && isAnnouncements && !_isManagerTier)
              (widget.role == 'client'
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Text(
                        'В «Объявления» пишут только управляющий и директор',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: secondaryText),
                      ),
                    ))
            else if (!isChannel)
              Column(
                children: [
                  if (_typingText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpace.lg,
                        bottom: AppSpace.xs,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _typingText,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: secondaryText,
                          ),
                        ),
                      ),
                    ),
                  MessageInput(
                    replyingTo: _replyingTo,
                    editingMessage: _editingMessage,
                    onCancelMode: () => _emitState(() {
                      _replyingTo = null;
                      _editingMessage = null;
                    }),
                    onSendText: _sendTextMessage,
                    onSendVoice: _sendVoiceMessage,
                    onTyping: _handleTyping,
                    onSendFile: (bytes, name, size, {caption}) async {
                      _showSendFileDialog(bytes, name, size);
                    },
                  ),
                ],
              )
            else if (_canPostToChannel())
              MessageInput(
                onSendText: _sendTextMessage,
                onTyping: _handleTyping,
              ),
          ],
        ),
      ),
    );
  }

  Widget? _buildStatusIcon(Map<String, dynamic> item, bool isDark) {
    if (!_isManagerOrAdminRole) return null;
    if (item['_item_type'] != 'group') return null;

    final respondedAt = item['_group_data']?['responded_at'];
    if (respondedAt == null) {
      return Icon(
        Icons.help_outline_rounded,
        size: 18,
        color: Colors.amber.shade700,
      );
    } else {
      return const Icon(
        Icons.check_circle_rounded,
        size: 18,
        color: Colors.green,
      );
    }
  }

  // ── Pinned Bar ────────────────────────────────────────────────────────────

  Widget _buildPinnedBar() {
    if (_pinnedMessages.isEmpty ||
        _hiddenPinnedBars.contains(_selectedChatId)) {
      return const SizedBox.shrink();
    }

    final lastPinned = _pinnedMessages.first;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content =
        lastPinned['content']?.toString() ??
        (lastPinned['message_type'] == 'file' ? '📁 Файл' : 'Вложение');

    return Container(
      width: double.infinity,
      color: cs.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_pinnedMessages.length == 1) {
              _jumpToMessage(_pinnedMessages.first['id'].toString());
            } else {
              _showPinnedMessagesDialog();
            }
          },
          child: Row(
            children: [
              Container(
                width: 2,
                height: 35,
                decoration: BoxDecoration(
                  color: AppColor.gold,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _pinnedMessages.length > 1
                          ? 'Закрепленные сообщения'
                          : 'Закрепленное сообщение',
                      style: const TextStyle(
                        color: AppColor.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface.withAlpha(isDark ? 178 : 222),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (_pinnedMessages.length > 1)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.xs + 2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.goldSoft,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      '${_pinnedMessages.length}',
                      style: const TextStyle(
                        color: AppColor.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Скрыть панель',
                onPressed: () {
                  if (_selectedChatId != null) {
                    _emitState(() => _hiddenPinnedBars.add(_selectedChatId!));
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPinnedMessagesDialog() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          _pinnedDialogSetState = setDialogState;

          return AlertDialog(
            backgroundColor: cs.surface,
            title: const Row(
              children: [
                Icon(Icons.pin_drop_rounded, color: AppColor.gold),
                SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'Закрепленные сообщения',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: _pinnedMessages.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('Пусто', textAlign: TextAlign.center),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _pinnedMessages.length,
                      separatorBuilder: (_, _) => Divider(
                        color: isDark
                            ? AppColor.divider
                            : TelegramColors.lightDivider,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final msg = _pinnedMessages[index];
                        final content =
                            msg['content']?.toString() ??
                            (msg['message_type'] == 'file'
                                ? '📁 Файл'
                                : 'Сообщение');

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          title: Text(
                            content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Открепить',
                            onPressed: () async {
                              await _togglePin(msg['id'].toString(), false);
                              if (_pinnedMessages.isEmpty) {
                                if (context.mounted) Navigator.pop(context);
                              } else {
                                setDialogState(() {});
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _jumpToMessage(msg['id'].toString());
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _pinnedDialogSetState = null;
                  Navigator.pop(context);
                },
                child: const Text('Закрыть'),
              ),
            ],
          );
        },
      ),
    ).then((_) => _pinnedDialogSetState = null);
  }

  Future<void> _fetchPinnedMessages() async {
    if (_selectedChatId == null) return;
    final pinned = _messages
        .where((message) => message['pinned_at'] != null)
        .toList()
        .reversed
        .toList();
    if (mounted) {
      _emitState(() => _pinnedMessages = pinned);
      if (_pinnedDialogSetState != null) {
        _pinnedDialogSetState!(() {});
      }
    }
  }

  void _onSearchInChat() {
    _emitState(() {
      _isSearchingInChat = !_isSearchingInChat;
      if (!_isSearchingInChat) {
        _chatSearchController.clear();
        _searchResults.clear();
        _currentMatchIndex = 0;
      }
    });
  }

  void _performSearch(String query, {bool jump = false}) {
    if (query.isEmpty) {
      _emitState(() {
        _searchResults.clear();
        _currentMatchIndex = 0;
      });
      return;
    }

    final results = _messages
        .where(
          (m) => (m['content']?.toString() ?? '').toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();

    _emitState(() {
      _searchResults = results;
      if (results.isNotEmpty) {
        if (jump) {
          _currentMatchIndex = 0;
          _jumpToMessage(results.first['id']);
        }
      } else {
        _currentMatchIndex = 0;
      }
    });
  }

  void _nextSearchMatch() {
    if (_searchResults.isEmpty) return;
    _emitState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _searchResults.length;
      _jumpToMessage(_searchResults[_currentMatchIndex]['id']);
    });
  }

  void _prevSearchMatch() {
    if (_searchResults.isEmpty) return;
    _emitState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _searchResults.length) %
          _searchResults.length;
      _jumpToMessage(_searchResults[_currentMatchIndex]['id']);
    });
  }

  Future<void> _togglePin(String messageId, bool pin) async {
    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      final updated = pin
          ? await messenger.pinMessage(messageId)
          : await messenger.unpinMessage(messageId);
      if (mounted) {
        _emitState(() {
          final index = _messages.indexWhere((m) => m['id'] == messageId);
          if (index != -1) _messages[index] = updated;
        });
      }
      await _fetchPinnedMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка при закреплении: $e')));
      }
    }
  }

  void _jumpToMessage(String messageId) {
    if (_messagesActionKey.currentState != null) {
      _messagesActionKey.currentState!._jumpToMessage(messageId);
    }
  }
}
