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
          // If we are not on the chat tab, switch to it
          if (_selectedCrmTab != 0) {
            _emitState(() => _selectedCrmTab = 0);
          }
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
        _selectedCrmTab = 0;
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
        duration: duration ?? const Duration(seconds: 4),
        action: action,
      ),
    );
  }

  Future<void> _saveContactFromChat(String as) async {
    final partnerId = _selectedPartnerId;
    if (partnerId == null || partnerId.isEmpty) return;
    final label = as == 'lead' ? 'лид' : 'ученик';
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .saveContactFromChat(userId: partnerId, as: as);
      if (!mounted) return;
      final created = result['created'] == true;
      final leadId = result['leadId']?.toString() ?? '';
      // KVA-175: offer to open the lead card straight from the snackbar.
      final leadStub = <String, dynamic>{'id': leadId};
      _showChatSnack(
        created
            ? 'Контакт сохранён как $label'
            : 'Контакт уже был сохранён как $label',
        bg: Colors.green,
        action: (as == 'lead' && leadId.isNotEmpty)
            ? SnackBarAction(
                label: 'Открыть карточку',
                textColor: Colors.white,
                onPressed: () => _openLeadCard(leadStub),
              )
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      _showChatSnack('Не удалось сохранить: $e', bg: AppColor.danger);
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
          'Этот контакт ещё не сохранён в CRM. '
          'Сохраните его как лид или ученик.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showChatSnack('Не удалось открыть карточку: $e', bg: AppColor.danger);
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
      _showChatSnack('Не удалось взять в работу: $e', bg: AppColor.danger);
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
      _showChatSnack('Не удалось снять с работы: $e', bg: AppColor.danger);
    }
  }

  // ── Archive / unarchive actions (administration chats, manager+admin only) ──

  Future<void> _archiveChat(String chatId) async {
    final svc = ref.read(magicMessengerServiceProvider);
    // Optimistic: mark archived so folderOf re-buckets to Архив immediately.
    _emitState(
      () =>
          _chatItems = patchChat(_chatItems, {'id': chatId, 'archived': true}),
    );
    try {
      // Resurface is server-driven — a new client message clears archive for
      // all staff and emits chat.updated (Task 5 patchChat moves it back out
      // of Архив).
      await svc.archiveChat(chatId);
    } catch (e) {
      if (!mounted) return;
      // Revert optimistic update on failure.
      _emitState(
        () => _chatItems = patchChat(_chatItems, {
          'id': chatId,
          'archived': false,
        }),
      );
      _showChatSnack('Не удалось архивировать чат: $e', bg: AppColor.danger);
    }
  }

  Future<void> _unarchiveChat(String chatId) async {
    final svc = ref.read(magicMessengerServiceProvider);
    // Optimistic: clear archived flag so folderOf re-buckets out of Архив.
    _emitState(
      () =>
          _chatItems = patchChat(_chatItems, {'id': chatId, 'archived': false}),
    );
    try {
      await svc.unarchiveChat(chatId);
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
        'Не удалось вернуть чат из архива: $e',
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

  Future<void> _loadChatList() async {
    try {
      // Set a global timeout for the entire loading process
      await _loadChatListInternal().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _logMessenger('Chat list loading timed out');
          if (mounted) _emitState(() => _loadingChats = false);
        },
      );
    } catch (e) {
      _logMessenger('Error loading chat list: $e');
      if (mounted) _emitState(() => _loadingChats = false);
    }
  }

  Future<void> _loadChatListInternal() async {
    final isStaff = _isStaffRole;
    final messenger = ref.read(magicMessengerServiceProvider);

    final rawItemsFuture = messenger.listChats(limit: 100);
    final channelsFuture = messenger.listChannels();
    final adminAvatarFuture = ref
        .read(magicSettingsServiceProvider)
        .getAdminChatAvatar();
    final Future<Map<String, dynamic>?> adminChatFuture = isStaff
        ? Future<Map<String, dynamic>?>.value(null)
        : messenger.ensureAdministrationChat();
    final Future<List<Map<String, dynamic>>> adminProfilesFuture = isStaff
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

    final rawItems = await rawItemsFuture;
    final adminChat = await adminChatFuture;
    if (adminChat != null) {
      if (!rawItems.any((item) => item['id'] == adminChat['id'])) {
        rawItems.insert(0, adminChat);
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

      // Construct item for _chatItems list
      final item = {
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
      _emitState(() {
        _chatItems = items;
        _unreadCounts = unreadCounts;
        _mutedChatIds = mutedIds;
        _pinnedChatIds = pinnedIds;
        _loadingChats = false;

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
}
