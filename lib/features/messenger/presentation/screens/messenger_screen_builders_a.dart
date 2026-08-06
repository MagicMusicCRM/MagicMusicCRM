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

  /// Canonical destinations are derived from the server effective snapshot.
  List<int> _visibleCrmTabs(bool isDesktop) {
    final snapshot = _accessSnapshot;
    if (snapshot == null) return const [0];
    return crmVisibleTabsForCapabilities(snapshot, isDesktop: isDesktop);
  }

  void _handleOverviewTabChange(
    int index,
    int? subIndex, {
    required bool isDesktop,
  }) {
    final targetTab = _overviewTargetTab(index, subIndex);
    final reportsTab = index == 5 ? 1 : subIndex;
    final visibleTabs = _visibleCrmTabs(isDesktop);
    // Canonical tab ids are sparse and role-specific (admin is [0, 6, 2, 3]),
    // so numeric clamping can silently route Tasks (6) to Clients (3).
    _selectCrmTab(
      crmResolveVisibleTab(
        visibleTabs: visibleTabs,
        requestedTab: targetTab,
        currentTab: _selectedCrmTab,
      ),
    );
    _emitState(() {
      if (isDesktop && targetTab == 7 && reportsTab != null) {
        _selectedReportsTab = reportsTab.clamp(0, 5);
      }
    });
  }

  int _overviewTargetTab(int index, int? subIndex) {
    if (index == 5) return 7;
    if (index == 1 && subIndex != null) {
      if (subIndex == 3 || subIndex == 4) return 2;
      return 8;
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

    final access = _accessSnapshot;
    return switch (selectedTab) {
      1
          when access?.allows('report.status.read') == true ||
              access?.allows('system.settings.manage') == true =>
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
      2 when access?.allows('schedule.lesson.read.assigned') == true =>
        ScheduleWidget(
          initialLink: widget.initialLink,
          initialViewState: widget.initialViewState,
          canWrite: access?.allows('schedule.lesson.write') == true,
        ),
      3 when access?.allows('crm.client.read.basic') == true =>
        const ClientsWidget(),
      5
          when isDesktop &&
              access?.allows('commerce.school_finance.read') == true =>
        const FinanceWidget(),
      6 when access?.allows('workflow.task.read') == true => SharedTasksV4Panel(
        initialLink: widget.initialLink,
        canWrite: _accessSnapshot?.allows('workflow.task.write') == true,
      ),
      7 when isDesktop && access?.allows('report.status.read') == true =>
        ReportsWidget(
          role: widget.role,
          initialTab: _selectedReportsTab,
          initialLink: widget.initialLink,
          initialViewState: widget.initialViewState,
          accessSnapshot: _accessSnapshot,
        ),
      8
          when access?.allows('system.settings.manage') == true ||
              access?.allows('config.crm.read') == true =>
        SystemSettingsWorkspace(
          role: widget.role,
          initialArea: widget.initialLink?.entityType == EntityLinkType.user
              ? 'users'
              : widget.initialLink?.optionalFocus?.focus == 'users'
              ? 'users'
              : widget.initialLink?.rawEntityType == 'configuration'
              ? 'crm'
              : null,
          initialUserSearch: _userRolesInitialSearch,
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
        return V7NavDestination(
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
          label: 'Расписание',
          badgeCount: _unseenFor(CrmSection.schedule),
        );
      case 3:
        return V7NavDestination(
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
          label: 'Клиенты',
          badgeCount: _unseenFor(CrmSection.clients),
        );
      case 5:
        return V7NavDestination(
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
          label: 'Финансы',
          badgeCount: _unseenFor(CrmSection.finance),
        );
      case 6:
        return V7NavDestination(
          icon: Icons.task_alt_outlined,
          selectedIcon: Icons.task_alt_rounded,
          label: 'Задачи',
          badgeCount: _unseenFor(CrmSection.tasks),
        );
      case 7:
        return const V7NavDestination(
          icon: Icons.insert_chart_outlined_rounded,
          selectedIcon: Icons.insert_chart_rounded,
          label: 'Аналитика',
        );
      case 8:
        return const V7NavDestination(
          icon: Icons.tune_outlined,
          selectedIcon: Icons.tune_rounded,
          label: 'Настройки',
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
