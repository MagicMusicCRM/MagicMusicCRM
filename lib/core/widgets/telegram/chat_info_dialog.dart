import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

part 'chat_info_dialog_views.dart';
part 'chat_info_dialog_dialogs.dart';

class ChatInfoDialog extends ConsumerStatefulWidget {
  final String chatType; // 'direct', 'group', 'channel'
  final String chatId; // target user ID, group ID, or channel ID
  final String userRole; // current user role
  final VoidCallback? onClose;
  final VoidCallback? onUpdate;
  final VoidCallback? onSearch;
  final Future<void> Function(bool isMuted)? onMute;
  final Function(Map<String, dynamic> chat)? onNavigateToChat;
  final bool initialIsMuted;
  /// Called after the current user successfully leaves a group chat.
  /// The screen should remove the chat from its list and deselect it.
  final VoidCallback? onLeftGroup;

  const ChatInfoDialog({
    super.key,
    required this.chatType,
    required this.chatId,
    required this.userRole,
    this.onClose,
    this.onUpdate,
    this.onSearch,
    this.onMute,
    this.onNavigateToChat,
    this.initialIsMuted = false,
    this.onLeftGroup,
  });

  @override
  ConsumerState<ChatInfoDialog> createState() => _ChatInfoDialogState();
}

class _ChatInfoDialogState extends ConsumerState<ChatInfoDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  Map<String, dynamic>? _data;
  final List<Map<String, dynamic>> _members = [];
  late bool _isMuted;

  // History parsing
  final List<Map<String, dynamic>> _mediaMessages = [];
  final List<Map<String, dynamic>> _fileMessages = [];
  final List<Map<String, dynamic>> _linkMessages = [];
  final List<Map<String, dynamic>> _notes = [];

  bool get _canEdit {
    if (widget.chatType != 'channel') return false;
    return _isManagerOrAdminRole;
  }

  bool get _hasNotesTab {
    return widget.chatType == 'direct' && _isManagerOrAdminRole;
  }

  bool get _isManagerOrAdminRole =>
      widget.userRole == 'admin' ||
      widget.userRole == 'manager' ||
      widget.userRole == 'director' ||
      widget.userRole == 'system_admin';

  Map<String, dynamic>? get _conversationPartner {
    if (_members.isEmpty) return null;
    return _members.firstWhere(
      (member) => member['is_current_user'] != true,
      orElse: () => _members.first,
    );
  }

  String? get _notesProfileId {
    final profileId = _conversationPartner?['profile_id']?.toString();
    if (profileId == null || profileId.trim().isEmpty) return null;
    return profileId;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _hasNotesTab ? 4 : 3, vsync: this);
    _isMuted = widget.initialIsMuted;
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ChatInfoDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tabLength = _hasNotesTab ? 4 : 3;
    if (_tabController.length != tabLength) {
      _tabController.dispose();
      _tabController = TabController(length: tabLength, vsync: this);
    }
    if (oldWidget.chatId != widget.chatId ||
        oldWidget.chatType != widget.chatType ||
        oldWidget.userRole != widget.userRole) {
      _resetLoadedData();
      _isMuted = widget.initialIsMuted;
      _loadData();
    } else if (oldWidget.initialIsMuted != widget.initialIsMuted) {
      _isMuted = widget.initialIsMuted;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _resetLoadedData() {
    _data = null;
    _members.clear();
    _mediaMessages.clear();
    _fileMessages.clear();
    _linkMessages.clear();
    _notes.clear();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _resetLoadedData();
      });
    }
    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      if (widget.chatId == 'admin_chat') {
        final avatarUrl = await ref
            .read(magicSettingsServiceProvider)
            .getAdminChatAvatar();
        _data = {
          'name': 'Администрация (Чат с клиентами)',
          'avatar_url': avatarUrl,
        };
      } else if (widget.chatType == 'direct' || widget.chatType == 'group') {
        _data = await messenger.getChat(widget.chatId);
        _members
          ..clear()
          ..addAll(await messenger.listChatMembers(widget.chatId));
      } else if (widget.chatType == 'channel') {
        final channels = await messenger.listChannels();
        _data = channels
            .where((channel) => channel['id']?.toString() == widget.chatId)
            .firstOrNull;
      }
      if (_hasNotesTab) {
        await _loadNotes();
      }
      await _loadHistory();

      _isMuted = _data?['is_muted'] == true || widget.initialIsMuted;
    } catch (e) {
      debugPrint('Error loading chat info: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      if (widget.chatType == 'group' || widget.chatType == 'direct') {
        final messages = await messenger
            .listMessages(widget.chatId, limit: 100)
            .timeout(const Duration(seconds: 15));
        _parseHistory(messages.reversed.toList());
      } else if (widget.chatType == 'channel') {
        final posts = await messenger
            .listChannelPosts(widget.chatId, limit: 100)
            .timeout(const Duration(seconds: 15));
        _parseHistory(posts.reversed.toList());
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }

  void _parseHistory(dynamic res) {
    if (res == null) return;
    final List<Map<String, dynamic>> messages = List<Map<String, dynamic>>.from(
      res,
    );
    final linkRegExp = RegExp(r'(https?:\/\/[^\s]+)');

    _mediaMessages.clear();
    _fileMessages.clear();
    _linkMessages.clear();

    for (final m in messages) {
      final type = m['message_type']?.toString().toLowerCase();
      final content = m['content']?.toString() ?? '';
      final attachmentUrl =
          m['attachment_url']?.toString() ??
          m['attachment_file_id']?.toString();
      final attachmentName =
          m['attachment_name']?.toString() ??
          m['attachment_file_id']?.toString() ??
          '';
      final attachmentMimeType = m['attachment_mime_type']?.toString() ?? '';

      // 1. Link detection (from text content)
      final links = linkRegExp.allMatches(content);
      for (final match in links) {
        final link = match.group(0);
        if (link != null) {
          _linkMessages.add({'link': link, 'message': m});
        }
      }

      // 2. Attachment detection
      if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
        final isImage =
            attachmentMimeType.toLowerCase().startsWith('image/') ||
            type == 'image' ||
            type == 'photo' ||
            [
              '.jpg',
              '.jpeg',
              '.png',
              '.webp',
              '.gif',
            ].any((ext) => attachmentName.toLowerCase().endsWith(ext));

        if (isImage) {
          _mediaMessages.add(m);
        } else if (type != 'voice') {
          // Categorize everything else except voice as files
          _fileMessages.add(m);
        }
      }
    }
  }

  Future<void> _loadNotes() async {
    _notes.clear();
    final profileId = _notesProfileId;
    if (profileId == null) return;

    final notes = await ref
        .read(magicProfileAdminServiceProvider)
        .listProfileNotes(profileId);
    _notes.addAll(notes);
  }

  Future<void> _addNote() async {
    final profileId = _notesProfileId;
    if (profileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось определить профиль для заметки'),
        ),
      );
      return;
    }

    final controller = TextEditingController();
    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить заметку'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(hintText: 'Введите текст заметки'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (body == null || body.isEmpty) return;

    try {
      final note = await ref
          .read(magicProfileAdminServiceProvider)
          .createProfileNote(profileId: profileId, body: body);
      if (!mounted) return;
      setState(() {
        _notes.insert(0, note);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить заметку')),
      );
    }
  }

  Future<void> _editField(
    String field,
    String title,
    String currentValue,
  ) async {
    if (!_canEdit) return;

    final controller = TextEditingController(text: currentValue);
    final newValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Изменить $title', style: const TextStyle(fontSize: 18)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: 'Введите $title'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (newValue != null &&
        newValue.trim().isNotEmpty &&
        newValue != currentValue) {
      setState(() => _isLoading = true);
      try {
        final title = field == 'name'
            ? newValue.trim()
            : (_data?['name'] ?? _data?['title'] ?? '').toString();
        final description = field == 'description'
            ? newValue.trim()
            : _data?['description']?.toString();
        final updated = await ref
            .read(magicMessengerServiceProvider)
            .updateChannel(
              widget.chatId,
              title: title,
              description: description,
            );
        _data = updated;

        if (widget.onUpdate != null) {
          widget.onUpdate!();
        }
      } catch (e) {
        debugPrint('Edit error: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // ── Group actions ──────────────────────────────────────────────────────────

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из группы'),
        content: const Text(
          'Вы уверены, что хотите выйти из этой группы?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Выйти',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(magicMessengerServiceProvider).leaveGroup(widget.chatId);
      if (!mounted) return;
      // Close the info panel / page first.
      if (widget.onClose != null) {
        widget.onClose!();
      } else if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      // Signal the screen to remove this chat from the list.
      widget.onLeftGroup?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выйти из группы: $e')),
      );
    }
  }

  Future<void> _addMembers() async {
    if (!_isManagerOrAdminRole) return;

    final selectedIds = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _AddMembersDialog(
        existingMemberUserIds: _members
            .map((m) => m['user_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet(),
      ),
    );

    if (selectedIds == null || selectedIds.isEmpty) return;
    if (!mounted) return;

    try {
      await ref
          .read(magicMessengerServiceProvider)
          .updateGroupMembers(widget.chatId, addUserIds: selectedIds.toList());
      if (!mounted) return;
      // Reload member list to reflect the addition.
      final updated = await ref
          .read(magicMessengerServiceProvider)
          .listChatMembers(widget.chatId);
      if (!mounted) return;
      setState(() {
        _members
          ..clear()
          ..addAll(updated);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить участников: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_data == null) {
      return const Scaffold(body: Center(child: Text('Информация не найдена')));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    String name = 'Без названия';
    String description = '';
    String? subtitle = '';
    String? avatarUrl = _data?['avatar_url'];

    if (widget.chatType == 'direct') {
      final partner = _conversationPartner;
      avatarUrl =
          partner?['avatar_file_id']?.toString() ??
          partner?['avatar_url']?.toString() ??
          avatarUrl;
      name =
          partner?['_display_name']?.toString() ??
          '${_data?['first_name'] ?? ''} ${_data?['last_name'] ?? ''}'.trim();
      if (name.isEmpty) name = 'Без имени';

      final role = partner?['role'] ?? _data?['role'] ?? 'client';
      description = _roleLabel(role.toString());

      final email = partner?['email']?.toString();
      subtitle = email == null || email.isEmpty ? 'Личный чат' : email;
    } else {
      name = _data?['name'] ?? 'Без названия';
      subtitle = _members.isNotEmpty
          ? '${_members.length} участников'
          : 'Канал';
      description = _data?['description'] ?? 'Нет описания';
    }

    return Scaffold(
      backgroundColor: isDark ? TelegramColors.darkBg : TelegramColors.lightBg,
      body: DefaultTabController(
        length: _hasNotesTab ? 4 : 3,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: 300.0,
                pinned: true,
                backgroundColor: isDark
                    ? TelegramColors.darkSurface
                    : TelegramColors.lightSurface,
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  title: innerBoxIsScrolled
                      ? Text(
                          name,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 16,
                          ),
                        )
                      : null,
                  background: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 50),
                      Hero(
                        tag: 'avatar_${widget.chatId}',
                        child: TelegramAvatar(
                          name: name,
                          avatarUrl: avatarUrl,
                          uniqueId: widget.chatId,
                          radius: 50,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _canEdit
                            ? () => _editField('name', 'название', name)
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_canEdit) const SizedBox(width: 8),
                            if (_canEdit)
                              Icon(
                                Icons.edit_rounded,
                                size: 14,
                                color: TelegramColors.accent,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle ?? '',
                        style: TextStyle(
                          color: isDark
                              ? TelegramColors.darkTextSecondary
                              : TelegramColors.lightTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                leading: widget.onClose != null
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: widget.onClose,
                      )
                    : null,
              ),
              // Action buttons and info
              SliverToBoxAdapter(
                child: Container(
                  color: isDark
                      ? TelegramColors.darkBg
                      : TelegramColors.lightBg,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildActionButton(
                              Icons.chat_bubble_outline,
                              'Чат',
                              isDark,
                              onTap: () {
                                if (widget.onNavigateToChat != null &&
                                    _data != null) {
                                  // Map _data back to a chat item format expected by _selectChat
                                  final chatItem = {
                                    'id': widget.chatId == 'admin_chat'
                                        ? 'admin_chat'
                                        : widget.chatId,
                                    '_item_type': widget.chatType,
                                    'display_name': name,
                                    '_display_name': name,
                                    'avatar_url': avatarUrl,
                                    '_avatar_url': avatarUrl,
                                    '_partner_id': widget.chatType == 'direct'
                                        ? (_conversationPartner?['user_id'])
                                        : null,
                                  };
                                  widget.onNavigateToChat!(chatItem);
                                  if (Navigator.canPop(context)) {
                                    Navigator.pop(context);
                                  }
                                } else if (widget.onClose != null) {
                                  widget.onClose!();
                                }
                              },
                            ),
                            if (widget.chatType != 'channel' &&
                                widget.chatId != 'admin_chat') ...[
                              const SizedBox(width: 32),
                              _buildActionButton(
                                _isMuted
                                    ? Icons.notifications_off_outlined
                                    : Icons.notifications_none,
                                _isMuted ? 'Включить' : 'Заглушить',
                                isDark,
                                onTap: () async {
                                  final scaffoldMessenger =
                                      ScaffoldMessenger.of(context);
                                  final previousMuted = _isMuted;
                                  final newMuted = !_isMuted;
                                  setState(() {
                                    _isMuted = newMuted;
                                  });
                                  try {
                                    await widget.onMute?.call(newMuted);
                                  } catch (_) {
                                    if (!mounted) return;
                                    setState(() {
                                      _isMuted = previousMuted;
                                    });
                                    scaffoldMessenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Не удалось изменить уведомления чата',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                            if (widget.chatType == 'group' &&
                                _members.any(
                                  (m) => m['is_current_user'] == true,
                                )) ...[
                              const SizedBox(width: 32),
                              _buildActionButton(
                                Icons.exit_to_app_rounded,
                                'Выйти',
                                isDark,
                                color: Colors.red,
                                onTap: _leaveGroup,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Info section
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? TelegramColors.darkSurface
                              : TelegramColors.lightSurface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.chatType == 'direct') ...[
                              Text(
                                _conversationPartner?['phone']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ==
                                        true
                                    ? _conversationPartner!['phone'].toString()
                                    : 'Телефон не указан',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Телефон',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? TelegramColors.darkTextSecondary
                                      : TelegramColors.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            GestureDetector(
                              onTap: _canEdit
                                  ? () => _editField(
                                      'description',
                                      'описание',
                                      description,
                                    )
                                  : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        description.isEmpty
                                            ? 'Нет описания'
                                            : description,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      if (_canEdit)
                                        Icon(
                                          Icons.edit_rounded,
                                          size: 14,
                                          color: TelegramColors.accent,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.chatType == 'direct'
                                        ? 'Статус / Роль'
                                        : 'Описание',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? TelegramColors.darkTextSecondary
                                          : TelegramColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.chatType == 'group' &&
                                _members.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildMembersPreview(isDark),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              // Tabs
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(_buildTabBar(isDark)),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildMediaGrid(),
              _buildFilesList(isDark),
              _buildLinksList(isDark),
              if (_hasNotesTab) _buildNotesList(isDark),
            ],
          ),
        ),
      ),
    );
  }

}
