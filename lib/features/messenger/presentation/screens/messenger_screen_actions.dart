part of 'messenger_screen.dart';

extension _MessengerActions on _MessengerScreenState {
  Future<void> _bootstrapMessenger() async {
    // Profile and chat list are independent — load in parallel.
    // Realtime needs _currentUserId from profile, so it waits for both.
    await Future.wait([_loadCurrentProfile(), _loadChatList()]);
    if (!mounted) return;
    await _connectRealtime();
  }

  Future<void> _loadCurrentProfile() async {
    try {
      final profile = await ref.read(magicAuthServiceProvider).currentProfile();
      final name = '${profile.firstName ?? ''} ${profile.lastName ?? ''}'
          .trim();
      if (mounted) {
        _emitState(() {
          _currentUserId = profile.userId;
          _currentUserDisplayName = name.isEmpty ? profile.email : name;
        });
      }
    } catch (e) {
      _logMessenger('MessengerScreen: Error loading v3 profile: $e');
    }
  }

  void _checkDeepLink() {
    final nav = ref.read(messengerNavigationProvider);
    if (nav != null) {
      if (mounted) {
        _logMessenger(
          'MessengerScreen: processing deep link. Partner: ${nav.partnerId}, Group: ${nav.groupChatId}',
        );
        _logMessenger(
          'MessengerScreen: chat items count: ${_chatItems.length}',
        );

        // Don't attempt matching if chat list hasn't loaded yet
        if (_chatItems.isEmpty) {
          _logMessenger(
            'MessengerScreen: chat list not loaded yet, deferring deep link',
          );
          return; // Keep the navigation state — it will be checked again after loading
        }

        // Match chat in _chatItems
        final item = _chatItems.where((c) {
          if (nav.groupChatId != null) {
            return c['id'] == nav.groupChatId;
          }
          if (nav.partnerId != null) {
            return c['_partner_id'] == nav.partnerId;
          }
          // Special case: null partnerId with no groupChatId = administration chat.
          return c['id'] == 'admin_chat';
        }).firstOrNull;

        if (item != null) {
          _logMessenger('MessengerScreen: found target chat, selecting.');
          _selectChat(item);
          // Clear ONLY after successful navigation
          Future.microtask(() {
            ref.read(messengerNavigationProvider.notifier).clear();
          });
        } else {
          _logMessenger(
            'MessengerScreen: target chat not found in items, keeping state for retry',
          );
          if (nav.partnerId != null) {
            unawaited(_openDirectChatFromNavigation(nav.partnerId!));
          }
          // DON'T clear — _loadChatList will call _checkDeepLink again after loading
        }
      }
      return;
    }

    final link = widget.initialLink;
    if (!mounted ||
        link?.entityType != EntityLinkType.chat ||
        link!.entityId == 'home' ||
        link.entityId == '__section__' ||
        _chatItems.isEmpty) {
      return;
    }
    final partnerId = link.optionalFocus?.filter['partnerId']?.toString();
    final item = _chatItems
        .where(
          (chat) =>
              chat['id']?.toString() == link.entityId ||
              (partnerId != null &&
                  chat['_partner_id']?.toString() == partnerId),
        )
        .firstOrNull;
    if (item != null) {
      _selectChat(item);
    } else if (partnerId?.isNotEmpty == true) {
      unawaited(_openDirectChatFromNavigation(partnerId!));
    }
  }

  Future<void> _openDirectChatFromNavigation(String partnerId) async {
    if (_openingNavigationPartnerId == partnerId) return;
    _openingNavigationPartnerId = partnerId;
    try {
      final chat = await ref
          .read(magicMessengerServiceProvider)
          .ensureDirectChat(partnerId);
      if (!mounted) return;
      final item = {
        ...chat,
        '_item_type': 'direct',
        '_partner_id': partnerId,
        '_display_name': chat['_display_name'] ?? chat['title'] ?? 'Личный чат',
      };
      _emitState(() {
        _chatItems = [
          if (!_chatItems.any((chatItem) => chatItem['id'] == item['id'])) item,
          ..._chatItems.where((chatItem) => chatItem['id'] != item['id']),
        ];
      });
      _selectChat(item);
      Future.microtask(() {
        ref.read(messengerNavigationProvider.notifier).clear();
      });
    } catch (e) {
      _logMessenger('MessengerScreen: Error opening direct chat from CRM: $e');
    } finally {
      if (_openingNavigationPartnerId == partnerId) {
        _openingNavigationPartnerId = null;
      }
    }
  }

  // ── CRM actions from a chat (staff only) ───────────────────────────────────

  // KVA-173/174/175 helper — floating above the input bar.
  void _showChatSnack(
    String text, {
    Color? bg,
    Duration? duration,
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 72, left: 12, right: 12),
        duration: duration ?? const Duration(seconds: 3),
        action: action,
      ),
    );
  }

  /// Resolves the CRM card behind a direct chat. The first client message already
  /// creates a lead, so chat UI never offers a second create/save action; this
  /// cache only gates the existing-card shortcut.
  Future<void> _resolveContactLink(String partnerId) async {
    if (_chatContactLinks.containsKey(partnerId)) return;
    try {
      final contact = await ref
          .read(magicCrmServiceProvider)
          .resolveContactForUser(partnerId);
      if (!mounted) return;
      final leadId = contact['leadId']?.toString();
      final studentId = contact['studentId']?.toString();
      _emitState(() {
        _chatContactLinks[partnerId] = {
          'leadId': (leadId != null && leadId.isNotEmpty) ? leadId : null,
          'studentId': (studentId != null && studentId.isNotEmpty)
              ? studentId
              : null,
        };
      });
    } catch (e) {
      _logMessenger('MessengerScreen: resolveContactForUser failed: $e');
    }
  }

  // KVA-175: open the unified client card for a given lead stub/map.
  Future<void> _openLeadCard(Map<String, dynamic> lead) async {
    if (!mounted) return;
    await showClientCard(
      context,
      entityType: 'lead',
      entityId: lead['id'].toString(),
      seed: lead,
    );
  }

  Future<void> _openContactCard() async {
    final partnerId = _selectedPartnerId;
    if (partnerId == null || partnerId.isEmpty) return;
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final contact = await crm.resolveContactForUser(partnerId);
      final studentId = contact['studentId']?.toString();
      final leadId = contact['leadId']?.toString();
      if (studentId != null && studentId.isNotEmpty) {
        if (!mounted) return;
        await showClientCard(
          context,
          entityType: 'student',
          entityId: studentId,
        );
      } else if (leadId != null && leadId.isNotEmpty) {
        if (!mounted) return;
        // KVA-175: open lead card directly in a dialog instead of redirecting.
        await _openLeadCard({'id': leadId});
      } else {
        if (!mounted) return;
        _showChatSnack(
          'Этот контакт ещё не сохранён в системе. '
          'Сохраните его как лид или ученик.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showChatSnack(
        userErrorMessage(e, fallback: 'Не удалось открыть карточку.'),
        bg: AppColor.danger,
      );
    }
  }

  String get _userId => _currentUserId ?? '';

  // ── Assignment actions (administration chats) ──────────────────────────────

  /// Optimistically patches the chat in _chatItems and triggers a rebuild.
  void _patchOpenChatAssignment(
    String chatId,
    Map<String, dynamic>? assignedTo,
  ) {
    _emitState(() {
      _chatItems = _chatItems.map((c) {
        if (c['id'] == chatId) return {...c, 'assigned_to': assignedTo};
        return c;
      }).toList();
    });
  }

  Future<void> _assignChatToMe(String chatId) async {
    final svc = ref.read(magicMessengerServiceProvider);
    // Optimistic: build a minimal assigned_to map from known current user data.
    final optimistic = {'id': _currentUserId, 'name': _currentUserDisplayName};
    _patchOpenChatAssignment(chatId, optimistic);
    try {
      final updated = await svc.assignChat(chatId);
      if (!mounted) return;
      // Apply server's authoritative assigned_to.
      _patchOpenChatAssignment(
        chatId,
        updated['assigned_to'] as Map<String, dynamic>?,
      );
    } catch (e) {
      if (!mounted) return;
      // Roll back optimistic update.
      _patchOpenChatAssignment(chatId, null);
      _showChatSnack(
        userErrorMessage(e, fallback: 'Не удалось взять чат в работу.'),
        bg: AppColor.danger,
      );
    }
  }

  Future<void> _unassignChat(String chatId) async {
    final svc = ref.read(magicMessengerServiceProvider);
    // Capture existing assigned_to BEFORE optimistic clear so we can roll back.
    final openChat = _chatItems.firstWhere(
      (c) => c['id'] == chatId,
      orElse: () => const {},
    );
    final previousAssignedTo = openChat['assigned_to'] as Map<String, dynamic>?;
    // Optimistic: clear assigned_to.
    _patchOpenChatAssignment(chatId, null);
    try {
      await svc.unassignChat(chatId);
    } catch (e) {
      if (!mounted) return;
      // Roll back to the captured value.
      _patchOpenChatAssignment(chatId, previousAssignedTo);
      _showChatSnack(
        userErrorMessage(e, fallback: 'Не удалось снять чат с работы.'),
        bg: AppColor.danger,
      );
    }
  }

  // ── Archive / unarchive actions (administration chats, manager+admin only) ──

  Future<void> _archiveChat(String chatId) async {
    // Контракт №3: PATCH /api/chats/:chatId/archive {archived:true}.
    final api = ref.read(magicApiClientProvider);
    // Optimistic: mark archived so folderOf re-buckets to Архив immediately.
    _emitState(
      () =>
          _chatItems = patchChat(_chatItems, {'id': chatId, 'archived': true}),
    );
    try {
      // Resurface is server-driven — a new client message clears archive for
      // all staff and emits chat.updated (Task 5 patchChat moves it back out
      // of Архив).
      await api.setChatArchived(chatId, archived: true);
    } catch (e) {
      if (!mounted) return;
      // Revert optimistic update on failure.
      _emitState(
        () => _chatItems = patchChat(_chatItems, {
          'id': chatId,
          'archived': false,
        }),
      );
      _showChatSnack(
        userErrorMessage(e, fallback: 'Не удалось архивировать чат.'),
        bg: AppColor.danger,
      );
    }
  }

  Future<void> _unarchiveChat(String chatId) async {
    // Контракт №3: PATCH /api/chats/:chatId/archive {archived:false}.
    final api = ref.read(magicApiClientProvider);
    // Optimistic: clear archived flag so folderOf re-buckets out of Архив.
    _emitState(
      () =>
          _chatItems = patchChat(_chatItems, {'id': chatId, 'archived': false}),
    );
    try {
      await api.setChatArchived(chatId, archived: false);
    } catch (e) {
      if (!mounted) return;
      // Revert optimistic update on failure.
      _emitState(
        () => _chatItems = patchChat(_chatItems, {
          'id': chatId,
          'archived': true,
        }),
      );
      _showChatSnack(
        userErrorMessage(e, fallback: 'Не удалось вернуть чат из архива.'),
        bg: AppColor.danger,
      );
    }
  }

  /// Shows a long-press context menu for an administration chat row
  /// (manager/admin only). Uses the same showDialog pattern as showStatusInfoDialog.
  void _showChatRowMenu(Map<String, dynamic> item) {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty) return;
    final isArchived = item['archived'] == true;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isArchived ? Icons.unarchive_rounded : Icons.archive_rounded,
                color: AppColor.gold,
              ),
              title: Text(isArchived ? 'Вернуть из архива' : 'Архивировать'),
              onTap: () {
                Navigator.pop(ctx);
                if (isArchived) {
                  _unarchiveChat(id);
                } else {
                  _archiveChat(id);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  // ── Load chat list ─────────────────────────────────────────────────────────

  Future<void> _loadChatList({bool showLoading = true}) async {
    if (mounted) {
      _emitState(() {
        _loadingChats = showLoading;
        _chatListError = null;
      });
    }
    try {
      await _loadChatListInternal().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _logMessenger('Chat list loading timed out');
      if (mounted && (showLoading || _chatItems.isEmpty)) {
        _emitState(() {
          _loadingChats = false;
          _chatListError =
              'Сервер отвечает слишком долго. Проверьте подключение и повторите загрузку.';
        });
      }
    } catch (e) {
      _logMessenger('Error loading chat list: $e');
      if (mounted && (showLoading || _chatItems.isEmpty)) {
        _emitState(() {
          _loadingChats = false;
          _chatListError =
              'Не удалось получить список чатов. Проверьте подключение и повторите загрузку.';
        });
      }
    }
  }

  Future<void> _loadChatBranches() async {
    try {
      final branches = await ref
          .read(magicCrmServiceProvider)
          .listBranches(limit: 100);
      if (mounted) _emitState(() => _chatBranches = branches);
    } catch (_) {
      // Non-fatal: the filter just won't show until a later reload succeeds.
    }
  }

  Future<void> _loadChatListInternal() async {
    final isStaff = _isStaffRole;
    final messenger = ref.read(magicMessengerServiceProvider);

    // Branch options for the inbox filter — fetched once, staff only.
    if (isStaff && _chatBranches.isEmpty) {
      unawaited(_loadChatBranches());
    }

    final rawItemsFuture = isStaff
        ? Future.wait([
            messenger.listChats(limit: 100, branchId: _chatBranchFilter),
            // The default endpoint intentionally hides archived inbox rows.
            // Load the archive explicitly so the folder survives a refresh,
            // restart and branch-filter change instead of existing only in the
            // optimistic in-memory patch made by _archiveChat.
            messenger.listChats(
              limit: 100,
              branchId: _chatBranchFilter,
              archived: true,
            ),
          ]).then((parts) => [...parts[0], ...parts[1]])
        : messenger.listChats(limit: 100);
    final channelsFuture = messenger.listChannels();
    final adminAvatarFuture = ref
        .read(magicSettingsServiceProvider)
        .getAdminChatAvatar();
    final Future<List<Map<String, dynamic>>> adminProfilesFuture =
        _isManagerOrAdminRole
        ? ref
              .read(magicProfileAdminServiceProvider)
              .listProfiles(limit: 100)
              .catchError((Object e) {
                _logMessenger(
                  'MessengerScreen: Error loading admin profiles: $e',
                );
                return <Map<String, dynamic>>[];
              })
        : Future<List<Map<String, dynamic>>>.value(
            const <Map<String, dynamic>>[],
          );

    final loadedItems = await rawItemsFuture;
    // Defence in depth for branch isolation. The server also receives branchId,
    // but an unresolved/null or stale branch must never leak into a selected
    // branch if an older server build returns it.
    // listChats deliberately returns an immutable/fixed-size page aggregate.
    // This screen appends channels and may lazily insert the administration
    // chat, so always take an owned growable copy first.
    final rawItems =
        (isStaff && _chatBranchFilter != null
                ? loadedItems.where(
                    (item) => chatMatchesBranch(item, _chatBranchFilter),
                  )
                : loadedItems)
            .toList(growable: true);
    // Ленивое создание чата с администрацией: POST уходит только когда чата
    // действительно нет в списке. Раньше он летел на каждый заход во вкладку
    // «Чат» и на каждый цикл фонового опроса — запись на сервер вхолостую.
    if (!isStaff &&
        !rawItems.any(
          (item) => (item['raw_type'] ?? item['type']) == 'administration',
        )) {
      try {
        final adminChat = await messenger.ensureAdministrationChat();
        if (!rawItems.any((item) => item['id'] == adminChat['id'])) {
          rawItems.insert(0, adminChat);
        }
      } catch (e) {
        _logMessenger('MessengerScreen: ensureAdministrationChat failed: $e');
      }
    }

    final channels = await channelsFuture;
    rawItems.addAll(channels);

    _adminAvatarUrl = await adminAvatarFuture;
    if (isStaff) {
      final adminProfiles = await adminProfilesFuture;
      _adminIds = adminProfiles
          .where(
            (profile) =>
                profile['role'] == 'admin' ||
                profile['role'] == 'manager' ||
                profile['role'] == 'director' ||
                profile['role'] == 'system_admin',
          )
          .map((profile) => profile['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } else {
      _adminIds = const [];
    }

    // 3. Map raw items to internal state
    final items = <Map<String, dynamic>>[];
    final unreadCounts = <String, int>{};
    final mutedIds = <String>{};
    final pinnedIds = <String>{};

    for (final raw in rawItems) {
      final id = raw['id'].toString();
      final itemType = raw['_item_type'] ?? raw['item_type'] ?? raw['type'];
      final lastMessage = raw['_last_message'];

      // Construct item for _chatItems list. Spread the raw (legacy-mapped)
      // chat FIRST: серверные ключи raw_type/folder/archived/slug/assigned_to/
      // branch_name — то, на чём стоят вкладки «Лиды/Ученики/Архив», меню
      // архива и read-only «Объявлений». Раньше они здесь отбрасывались, и
      // folderOf() валил все админ-чаты в «Группы и каналы».
      final item = {
        ...raw,
        'id': id,
        '_item_type': itemType,
        '_display_name': raw['_display_name'] ?? raw['display_name'],
        '_partner_id': raw['_partner_id'] ?? raw['partner_id'],
        '_partner_data': raw['_partner_data'] ?? raw['partner'],
        '_last_message': lastMessage,
        '_last_message_time':
            raw['_last_message_time'] ?? raw['last_message_created_at'],
        '_avatar_url':
            raw['_avatar_url'] ??
            raw['avatar_url'] ??
            (raw['raw_type'] == 'administration' ? _adminAvatarUrl : null),
        '_group_data': itemType == 'group' ? raw : null,
        '_channel_data': itemType == 'channel' ? raw : null,
      };
      items.add(item);

      // Update auxiliary states
      unreadCounts[id] = raw['unread_count'] ?? 0;
      if (raw['is_muted'] == true) mutedIds.add(id);
      if (raw['is_pinned'] == true) pinnedIds.add(id);
    }

    if (_selectedChatId != null) {
      unreadCounts[_selectedChatId!] = 0;
    }

    if (mounted) {
      final selectedFilteredOut =
          _chatBranchFilter != null &&
          _selectedChatId != null &&
          !items.any((item) => item['id'] == _selectedChatId);
      if (selectedFilteredOut) _leaveTypingChannel(notify: false);
      _emitState(() {
        _chatItems = items;
        _unreadCounts = unreadCounts;
        _mutedChatIds = mutedIds;
        _pinnedChatIds = pinnedIds;
        _loadingChats = false;
        _chatListError = null;

        if (selectedFilteredOut) {
          _selectedChatId = null;
          _selectedChatType = null;
          _selectedChatRawType = null;
          _selectedChatSlug = null;
          _selectedChatName = null;
          _selectedChatAvatarUrl = null;
          _selectedPartnerId = null;
          _messages = [];
          _showProfilePanel = false;
        }

        // Update selected chat info from list
        if (_selectedChatId != null) {
          try {
            final selectedItem = items.firstWhere(
              (i) => i['id'] == _selectedChatId,
            );
            _selectedChatName = selectedItem['_display_name'];
            _selectedChatRawType =
                selectedItem['raw_type']?.toString() ??
                selectedItem['_item_type']?.toString();
            _selectedChatAvatarUrl = _getAvatarUrl(selectedItem);
            _selectedPartnerId = selectedItem['_partner_id']?.toString();
          } catch (_) {}
        }
      });
      _checkDeepLink();
      // Subscribe to any channels (Объявления) discovered in this list refresh.
      _joinAnnouncementChannels();
    }
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
}
