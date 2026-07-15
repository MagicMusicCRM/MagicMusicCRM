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
            messageType: msg['message_type'] ?? 'text',
            forwardedFromId: msg['sender_id'],
          );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Сообщение переслано')));
      }
    }
  }

  /// Canonical CRM tab indices visible to the current role (see
  /// [crmVisibleTabs] for the index legend + A1 hierarchy rules).
  List<int> _visibleCrmTabs(bool isDesktop) =>
      crmVisibleTabs(widget.role, isDesktop: isDesktop);

  int _maxCrmTab(bool isDesktop) => _visibleCrmTabs(isDesktop).last;

  void _handleOverviewTabChange(
    int index,
    int? subIndex, {
    required bool isDesktop,
  }) {
    final targetTab = _overviewTargetTab(index, subIndex, isDesktop: isDesktop);
    _emitState(() {
      _selectedCrmTab = targetTab.clamp(0, _maxCrmTab(isDesktop));
      if (isDesktop && targetTab == 7 && subIndex != null) {
        _selectedReportsTab = subIndex.clamp(0, 2);
      }
    });
  }

  int _overviewTargetTab(int index, int? subIndex, {required bool isDesktop}) {
    if (index == 1 && subIndex != null) {
      if (subIndex == 3 || subIndex == 4) return 2;
      return 4;
    }
    if (!isDesktop) {
      if (index == 5 || index == 7) return 4;
      if (index == 6) return 3;
    }
    return index;
  }

  Widget _buildCrmBody(
    BuildContext context, {
    required bool isDesktop,
    required int selectedTab,
  }) {
    if (selectedTab == 0) return _buildMessengerShell(context);

    if (widget.role == 'teacher') {
      return switch (selectedTab) {
        1 => const TeacherScheduleWidget(),
        2 => const TeacherStudentsWidget(),
        _ => _buildMessengerShell(context),
      };
    }

    // Operational destinations are gated on `_hasManagerAccess`; role mutation
    // controls live inside the user/profile widgets and backend policy.
    return switch (selectedTab) {
      1 when _hasManagerAccess =>
        _isAdminRole
            ? AdminOverviewWidget(
                onTabChange: (index, subIndex) => _handleOverviewTabChange(
                  index,
                  subIndex,
                  isDesktop: isDesktop,
                ),
              )
            : ManagerOverviewWidget(
                role: widget.role,
                onTabChange: (index, subIndex) => _handleOverviewTabChange(
                  index,
                  subIndex,
                  isDesktop: isDesktop,
                ),
              ),
      2 => const ScheduleWidget(),
      3 => const ClientsWidget(),
      4 when _hasManagerAccess => UserRolesWidget(
        currentRole: widget.role,
        initialSearch: _userRolesInitialSearch,
      ),
      5 when isDesktop && _hasSchoolFinanceAccess => const FinanceWidget(),
      6 when isDesktop && _hasManagerAccess => const TasksWidget(),
      7 when isDesktop && _hasManagerAccess => ReportsWidget(
        role: widget.role,
        initialTab: _selectedReportsTab,
      ),
      _ => _buildMessengerShell(context),
    };
  }

  /// Builds the v7 nav destination for a canonical CRM tab index (see
  /// [_visibleCrmTabs]). Teacher reuses 1/2 for Расписание/Ученики.
  V7NavDestination _v7DestinationForTab(int tab) {
    if (widget.role == 'teacher') {
      switch (tab) {
        case 1:
          return const V7NavDestination(
            icon: Icons.calendar_today_outlined,
            selectedIcon: Icons.calendar_today_rounded,
            label: 'Расписание',
          );
        case 2:
          return const V7NavDestination(
            icon: Icons.school_outlined,
            selectedIcon: Icons.school_rounded,
            label: 'Ученики',
          );
      }
    }
    switch (tab) {
      case 1:
        return const V7NavDestination(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          label: 'Обзор',
        );
      case 2:
        return const V7NavDestination(
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
          label: 'Расписание',
        );
      case 3:
        return V7NavDestination(
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
          label: 'Клиенты',
          badgeCount: ref.watch(appLeadsCountProvider).asData?.value ?? 0,
        );
      case 4:
        return const V7NavDestination(
          icon: Icons.manage_accounts_outlined,
          selectedIcon: Icons.manage_accounts_rounded,
          label: 'Пользователи',
        );
      case 5:
        return const V7NavDestination(
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
          label: 'Финансы',
        );
      case 6:
        return const V7NavDestination(
          icon: Icons.task_alt_outlined,
          selectedIcon: Icons.task_alt_rounded,
          label: 'Задачи',
        );
      case 7:
        return const V7NavDestination(
          icon: Icons.insert_chart_outlined_rounded,
          selectedIcon: Icons.insert_chart_rounded,
          label: 'Отчёты',
        );
      default:
        return const V7NavDestination(
          icon: Icons.chat_bubble_outline_rounded,
          selectedIcon: Icons.chat_bubble_rounded,
          label: 'Чат',
        );
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

    final filteredItems = _searchQuery.isEmpty
        ? _chatItems
        : _chatItems.where((item) {
            final name = (item['_display_name'] ?? item['display_name'] ?? '')
                .toString()
                .toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    // Sorting: Pinned first, then by last message time
    final sortedItems = List<Map<String, dynamic>>.from(filteredItems)
      ..sort((a, b) {
        final idA = (a['id'] ?? '').toString();
        final idB = (b['id'] ?? '').toString();
        final isPinnedA = _pinnedChatIds.contains(idA);
        final isPinnedB = _pinnedChatIds.contains(idB);

        if (isPinnedA && !isPinnedB) return -1;
        if (!isPinnedA && isPinnedB) return 1;

        final timeA = a['_last_message_time'] as String? ?? '';
        final timeB = b['_last_message_time'] as String? ?? '';
        return timeB.compareTo(timeA);
      });

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
                  PopupMenuItem(
                    value: 'theme',
                    child: ListTile(
                      leading: Icon(
                        isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                      ),
                      title: Text(isDark ? 'Светлая тема' : 'Тёмная тема'),
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
                  } else if (value == 'theme') {
                    ref.read(themeModeProvider.notifier).toggle();
                  } else if (value == 'logout') {
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
              if (widget.role == 'client')
                IconButton(
                  icon: const Icon(Icons.school_rounded),
                  tooltip: 'Моя школа',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ClientPortalScreen(),
                      ),
                    );
                  },
                ),
              if (canCreateGroups)
                IconButton(
                  icon: const Icon(Icons.group_add_rounded),
                  tooltip: 'Новая группа',
                  onPressed: () async {
                    final groupId = await showDialog<String>(
                      context: context,
                      builder: (_) => const CreateGroupChatDialog(),
                    );
                    if (groupId != null) {
                      await _loadChatList();
                    }
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
        // Chat list
        Expanded(
          child: _loadingChats
              ? const Center(
                  child: CircularProgressIndicator(color: AppColor.gold),
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
                          final subtitleText = assignmentText != null
                              ? '$assignmentText · $preview'
                              : preview;

                          return ChatListTile(
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
                            onLongPress:
                                _isManagerOrAdminRole && isAdministration(item)
                                ? () => _showChatRowMenu(item)
                                : null,
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
