part of 'messenger_screen.dart';

extension _MessengerBuildersA on _MessengerScreenState {
  // ── Build ──────────────────────────────────────────────────────────────────

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

  void _onForwardMessage(Map<String, dynamic> msg) async {
    final targetChat = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переслать...'),
        content: SizedBox(
          width: 400,
          height: 500,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: _chatItems.length,
                  itemBuilder: (context, index) {
                    final item = _chatItems[index];
                    // Robust name resolution
                    String name = 'Чат';
                    if (item['_display_name'] != null &&
                        item['_display_name'].toString().isNotEmpty) {
                      name = item['_display_name'].toString();
                    } else if (item['display_name'] != null &&
                        item['display_name'].toString().isNotEmpty) {
                      name = item['display_name'].toString();
                    } else if (item['profiles'] != null) {
                      final p = item['profiles'];
                      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
                          .trim();
                    } else if (item['_partner_data'] != null) {
                      final p = item['_partner_data'];
                      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
                          .trim();
                    } else if (item['name'] != null) {
                      name = item['name'].toString();
                    }
                    if (name.trim().isEmpty) name = 'Без имени';

                    return ListTile(
                      leading: TelegramAvatar(
                        name: name,
                        avatarUrl: item['_avatar_url'] ?? item['avatar_url'],
                        uniqueId: item['id'].toString(),
                        radius: 18,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, {
                        ...item,
                        'resolved_name': name,
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (targetChat != null) {
      if (!mounted) return;
      final targetName = targetChat['resolved_name'] ?? 'Чат';

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Переслать сообщение?'),
          content: Text('Переслать сообщение в чат "$targetName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.gold,
                foregroundColor: AppColor.onGold,
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              child: const Text(
                'Переслать',
                style: TextStyle(color: AppColor.onGold),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      final targetId = targetChat['id'].toString();
      await ref
          .read(magicMessengerServiceProvider)
          .sendMessage(
            targetId,
            content: msg['content'] ?? '',
            messageType: 'text',
            forwardedFromId: msg['id']?.toString(),
          );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Сообщение переслано')));
      }
    }
  }

  // ── Chat List Panel ────────────────────────────────────────────────────────

  Widget _buildChatList(BuildContext context, bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? AppColor.divider
        : TelegramColors.lightDivider;
    final secondaryText = isDark
        ? AppColor.text2
        : TelegramColors.lightTextSecondary;
    final canCreateGroups = _isManagerOrAdminRole;

    final filteredItems = filterChatsByQuery(_chatItems, _searchQuery);

    final sortedItems = sortChatsPinnedFirst(filteredItems, _pinnedChatIds);

    return Column(
      children: [
        // Header
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(
            color: isDark ? AppColor.surface : TelegramColors.lightBg,
            border: Border(bottom: BorderSide(color: dividerColor, width: 0.5)),
          ),
          child: Row(
            children: [
              // Hamburger menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.menu_rounded),
                offset: const Offset(0, 48),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'profile',
                    child: ListTile(
                      leading: Icon(Icons.person_outline_rounded),
                      title: Text('Профиль'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(
                        Icons.logout_rounded,
                        color: AppColor.danger,
                      ),
                      title: Text(
                        'Выйти',
                        style: TextStyle(color: AppColor.danger),
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'profile') {
                    if (MediaQuery.of(context).size.width >= 768) {
                      _emitState(() => _showMyProfile = true);
                    } else {
                      if (mounted) {
                        context.push('/profile');
                      }
                    }
                  } else if (value == 'logout') {
                    final canLogout = await requestWorkspaceDirtyExit(
                      context,
                      reason: DirtyFormExitReason.logout,
                    );
                    if (!canLogout) return;
                    await ref.read(magicAuthServiceProvider).signOut();
                    if (context.mounted) context.go('/login');
                  }
                },
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'MagicMusic',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              if (widget.role == 'client' && widget.onOpenSchool != null)
                IconButton(
                  icon: const Icon(Icons.school_rounded),
                  tooltip: 'Моя школа',
                  onPressed: widget.onOpenSchool,
                ),
              if (canCreateGroups)
                PopupMenuButton<String>(
                  tooltip: 'Создать чат или канал',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'group',
                      child: ListTile(
                        leading: Icon(Icons.group_add_rounded),
                        title: Text('Новая группа'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'channel',
                      child: ListTile(
                        leading: Icon(Icons.campaign_rounded),
                        title: Text('Новый канал'),
                      ),
                    ),
                  ],
                  onSelected: (value) async {
                    Object? result;
                    if (value == 'group') {
                      result = await showDialog<String>(
                        context: context,
                        builder: (_) => const CreateGroupChatDialog(),
                      );
                    } else if (value == 'channel') {
                      result = await ChannelEditorDialog.show(context);
                    }
                    if (result != null) await _loadChatList();
                  },
                ),
            ],
          ),
        ),
        // Search
        ChatSearchBar(onChanged: (q) => _emitState(() => _searchQuery = q)),
        // Folder bar — staff (manager/admin) only
        if (showInboxFolders(widget.role))
          InboxFolderBar(
            selected: _selectedFolder,
            unread: {
              for (final f in InboxFolder.values)
                f: unreadForFolder(_chatItems, _unreadCounts, f),
            },
            onSelected: (f) => _emitState(() => _selectedFolder = f),
          ),
        // Branch filter — staff only. «Все филиалы» + one per branch. With a
        // concrete branch selected, only exact branch matches are rendered.
        if (showInboxFolders(widget.role) && _chatBranches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                Icon(
                  Icons.apartment_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String?>(
                    value: _chatBranchFilter,
                    isExpanded: true,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    hint: const Text('Все филиалы'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Все филиалы'),
                      ),
                      for (final b in _chatBranches)
                        DropdownMenuItem<String?>(
                          value: b['id'].toString(),
                          child: Text(
                            b['name']?.toString() ?? 'Филиал',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      _emitState(() => _chatBranchFilter = v);
                      _loadChatList();
                    },
                  ),
                ),
              ],
            ),
          ),
        // Chat list
        Expanded(
          child: _loadingChats
              ? const Center(
                  child: CircularProgressIndicator(color: AppColor.gold),
                )
              : _chatListError != null
              ? MagicPageState(
                  kind: MagicPageStateKind.error,
                  title: 'Не удалось загрузить чаты',
                  message: _chatListError,
                  actionLabel: 'Повторить',
                  onAction: _loadChatList,
                )
              : Builder(
                  builder: (context) {
                    // For staff: show administration chats in the selected folder
                    // first, then groups/channels/direct (non-inbox) chats below a
                    // section header — but ONLY for non-archive tabs. Архив shows
                    // only archived administration chats (no groups/channels).
                    // For non-staff: use sortedItems unchanged.
                    const kSectionHeader = {
                      '_section_header': 'Группы и каналы',
                    };
                    List<Map<String, dynamic>> listItems;
                    if (showInboxFolders(widget.role)) {
                      final folderChats = chatsInFolder(
                        sortedItems,
                        _selectedFolder,
                      );
                      if (_selectedFolder == InboxFolder.archive) {
                        // Архив: only archived administration chats, no groups.
                        listItems = folderChats;
                      } else {
                        final extras = nonInboxChats(sortedItems);
                        listItems = [
                          ...folderChats,
                          if (extras.isNotEmpty) kSectionHeader,
                          ...extras,
                        ];
                      }
                    } else {
                      listItems = sortedItems;
                    }

                    if (listItems.isEmpty) {
                      return Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'Ничего не найдено'
                              : 'Нет чатов',
                          style: TextStyle(color: secondaryText),
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _loadChatList,
                      color: AppColor.gold,
                      child: ListView.builder(
                        itemCount: listItems.length,
                        itemBuilder: (context, index) {
                          final item = listItems[index];

                          // Section header sentinel — rendered as a non-tappable label.
                          if (item.containsKey('_section_header')) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Text(
                                item['_section_header'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: secondaryText,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            );
                          }

                          final id = (item['id'] ?? '').toString();
                          final type =
                              (item['_item_type'] ??
                                      item['item_type'] ??
                                      'individual')
                                  .toString();
                          final name =
                              (item['_display_name'] ??
                                      item['display_name'] ??
                                      'Аноним')
                                  .toString();
                          final lastMsg =
                              item['_last_message'] as Map<String, dynamic>?;
                          final unread = _unreadCounts[id] ?? 0;
                          final avatarUrl = _getAvatarUrl(item);

                          // For staff: always show the work marker so new client
                          // messages clearly surface as not taken yet.
                          final assignee = _isStaffRole
                              ? assigneeName(item)
                              : null;
                          final preview = _messagePreview(lastMsg);
                          final isAdminChat = isAdministration(item);
                          final assignmentText = !_isStaffRole || !isAdminChat
                              ? null
                              : assignee != null
                              ? 'ведёт: $assignee'
                              : 'Никто не взял в работу';
                          // Филиал чата в подзаголовке (персоналу). При активном
                          // фильтре сюда доходят только точные branch-id matches.
                          final branchName = _isStaffRole && isAdminChat
                              ? (item['branch_name'] ?? '').toString().trim()
                              : '';
                          final subtitleText = [
                            ?assignmentText,
                            if (branchName.isNotEmpty) branchName,
                            preview,
                          ].join(' · ');

                          final canManageInboxChat =
                              _isManagerOrAdminRole && isAdministration(item);
                          final tile = ChatListTile(
                            title: name,
                            subtitle: subtitleText,
                            time: _formatTime(
                              item['_last_message_time'] as String?,
                            ),
                            unreadCount: unread,
                            isSelected: _selectedChatId == id,
                            isChannel: type == 'channel',
                            uniqueId: id,
                            avatarUrl: avatarUrl,
                            channelIcon: type == 'channel'
                                ? Icons.campaign_rounded
                                : type == 'group'
                                ? Icons.group_rounded
                                : null,
                            onTap: () => _selectChat(item),
                            isMuted: _mutedChatIds.contains(id),
                            statusIcon: _buildStatusIcon(item, isDark),
                            onStatusTap: () =>
                                showStatusInfoDialog(context, item),
                            // Archive long-press: manager/admin only, administration chats only.
                            onLongPress: canManageInboxChat
                                ? () => _showChatRowMenu(item)
                                : null,
                          );
                          if (!canManageInboxChat) return tile;
                          // Windows-десктоп: долгое нажатие мышью никто не
                          // находит — правый клик открывает то же меню строки
                          // (архивировать / вернуть из архива).
                          return GestureDetector(
                            onSecondaryTapDown: (_) => _showChatRowMenu(item),
                            child: tile,
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
