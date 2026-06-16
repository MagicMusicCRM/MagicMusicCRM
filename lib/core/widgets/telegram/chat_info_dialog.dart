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

  Widget _buildTabBar(bool isDark) {
    return Container(
      color: isDark ? TelegramColors.darkSurface : TelegramColors.lightBg,
      child: TabBar(
        controller: _tabController,
        indicatorColor: TelegramColors.accentBlue,
        labelColor: TelegramColors.accentBlue,
        unselectedLabelColor: isDark
            ? TelegramColors.darkTextSecondary
            : TelegramColors.lightTextSecondary,
        tabs: [
          const Tab(text: 'Медиа'),
          const Tab(text: 'Файлы'),
          const Tab(text: 'Ссылки'),
          if (_hasNotesTab) const Tab(text: 'Заметки'),
        ],
      ),
    );
  }

  Widget _buildMediaGrid() {
    if (_mediaMessages.isEmpty) {
      return const Center(
        child: Text('Нет медиа', style: TextStyle(color: Colors.grey)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _mediaMessages.length,
      itemBuilder: (context, index) {
        final m = _mediaMessages[index];
        final url =
            m['attachment_url']?.toString() ??
            m['attachment_file_id']?.toString();
        if (url == null) return Container(color: Colors.grey.shade800);
        return GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (c) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: EdgeInsets.zero,
                child: InteractiveViewer(
                  child: _ResolvedNetworkImage(url: url, fit: BoxFit.contain),
                ),
              ),
            );
          },
          child: _ResolvedNetworkImage(url: url, fit: BoxFit.cover),
        );
      },
    );
  }

  Widget _buildFilesList(bool isDark) {
    if (_fileMessages.isEmpty) {
      return const Center(
        child: Text('Нет файлов', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _fileMessages.length,
      separatorBuilder: (c, i) =>
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
      itemBuilder: (context, index) {
        final m = _fileMessages[index];
        final name = m['attachment_name']?.toString() ?? 'Файл';
        final size = ChatAttachmentService.formatFileSize(
          m['attachment_size'] as int?,
        );
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TelegramColors.accentBlue.withValues(alpha: 40 / 255),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.insert_drive_file,
              color: TelegramColors.accentBlue,
            ),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(size),
          onTap: () async {
            final url =
                m['attachment_url']?.toString() ??
                m['attachment_file_id']?.toString();
            final resolved = await ref
                .read(chatAttachmentServiceProvider)
                .resolveUrl(url);
            if (resolved != null) launchUrl(Uri.parse(resolved));
          },
        );
      },
    );
  }

  Widget _buildLinksList(bool isDark) {
    if (_linkMessages.isEmpty) {
      return const Center(
        child: Text('Нет ссылок', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _linkMessages.length,
      separatorBuilder: (c, i) =>
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
      itemBuilder: (context, index) {
        final linkData = _linkMessages[index];
        final link = linkData['link'] as String;
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TelegramColors.accentBlue.withValues(alpha: 40 / 255),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.link, color: TelegramColors.accentBlue),
          ),
          title: Text(
            link,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: TelegramColors.accentBlue),
          ),
          onTap: () => launchUrl(Uri.parse(link)),
        );
      },
    );
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
                                color: TelegramColors.accentBlue,
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
                                          color: TelegramColors.accentBlue,
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

  Widget _buildActionButton(
    IconData icon,
    String label,
    bool isDark, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isDark
                    ? TelegramColors.darkSurface
                    : TelegramColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: isDark ? Colors.white : Colors.black),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? TelegramColors.darkTextSecondary
                    : TelegramColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    return switch (role) {
      'system_admin' => 'Администратор системы',
      'admin' => 'Администратор',
      'manager' => 'Управляющий',
      'teacher' => 'Преподаватель',
      _ => 'Клиент',
    };
  }

  Widget _buildMembersPreview(bool isDark) {
    final previewMembers = _members.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Участники',
          style: TextStyle(
            fontSize: 13,
            color: isDark
                ? TelegramColors.darkTextSecondary
                : TelegramColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ...previewMembers.map((member) {
          final name = member['_display_name']?.toString() ?? 'Участник';
          final role = member['role']?.toString() == 'admin'
              ? 'Администратор группы'
              : _roleLabel(member['role']?.toString() ?? 'client');
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                TelegramAvatar(
                  name: name,
                  avatarUrl: null,
                  uniqueId: member['user_id']?.toString() ?? name,
                  radius: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? TelegramColors.darkTextSecondary
                              : TelegramColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        if (_members.length > previewMembers.length)
          Text(
            'Ещё ${_members.length - previewMembers.length}',
            style: TextStyle(fontSize: 12, color: TelegramColors.accentBlue),
          ),
      ],
    );
  }

  Widget _buildNotesList(bool isDark) {
    if (_notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Заметок пока нет',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _addNote,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Добавить первую'),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.small(
        onPressed: _addNote,
        backgroundColor: TelegramColors.accentBlue,
        child: const Icon(Icons.add_comment_rounded, color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _notes.length,
        itemBuilder: (context, index) {
          final note = _notes[index];
          final author = note['author'];
          final authorName = author != null
              ? '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'
                    .trim()
              : 'Админ';
          // Fix for potential string/datetime issues
          final createdAt = note['created_at'];
          final time = createdAt != null
              ? (createdAt is String
                    ? DateFormat(
                        'dd.MM.yy HH:mm',
                      ).format(DateTime.parse(createdAt))
                    : DateFormat('dd.MM.yy HH:mm').format(createdAt))
              : 'Без даты';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      authorName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: TelegramColors.accentBlue,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  note['content'] ?? '',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final Widget _tabBar;

  @override
  double get minExtent => 48.0;
  @override
  double get maxExtent => 48.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _tabBar;
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

class _ResolvedNetworkImage extends ConsumerStatefulWidget {
  final String url;
  final BoxFit fit;

  const _ResolvedNetworkImage({required this.url, required this.fit});

  @override
  ConsumerState<_ResolvedNetworkImage> createState() =>
      _ResolvedNetworkImageState();
}

class _ResolvedNetworkImageState extends ConsumerState<_ResolvedNetworkImage> {
  String? _resolvedUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  @override
  void didUpdateWidget(covariant _ResolvedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _resolveUrl();
    }
  }

  Future<void> _resolveUrl() async {
    setState(() {
      _isLoading = true;
      _resolvedUrl = null;
    });

    try {
      final resolved = await ref
          .read(chatAttachmentServiceProvider)
          .resolveUrl(widget.url);
      if (!mounted || widget.url.isEmpty) return;
      setState(() {
        _resolvedUrl = resolved;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Media URL resolve error: $error');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_resolvedUrl == null) {
      return Container(
        color: Colors.grey.shade800,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_rounded, color: Colors.white70),
      );
    }
    return Image.network(_resolvedUrl!, fit: widget.fit);
  }
}
