import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/widgets/avatar_cropper_dialog.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class ChatInfoDialog extends ConsumerStatefulWidget {
  final String chatType; // 'direct', 'group', 'channel'
  final String chatId; // target user ID, group ID, or channel ID
  final String userRole; // current user role
  final VoidCallback? onClose;
  final VoidCallback? onUpdate;

  const ChatInfoDialog({
    super.key,
    required this.chatType,
    required this.chatId,
    required this.userRole,
    this.onClose,
    this.onUpdate,
  });

  @override
  ConsumerState<ChatInfoDialog> createState() => _ChatInfoDialogState();
}

class _ChatInfoDialogState extends ConsumerState<ChatInfoDialog> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  
  bool _isLoading = true;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _members = [];

  // History parsing
  final List<Map<String, dynamic>> _mediaMessages = [];
  final List<Map<String, dynamic>> _fileMessages = [];
  final List<Map<String, dynamic>> _linkMessages = [];
  final List<Map<String, dynamic>> _notes = [];

  bool get _canEdit {
    if (widget.chatType == 'direct') return false;
    return widget.userRole == 'admin' || widget.userRole == 'manager';
  }

  bool get _isAdmin {
    return widget.userRole == 'admin' || widget.userRole == 'manager';
  }

  bool get _hasNotesTab {
    return _isAdmin && widget.chatType == 'direct';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _hasNotesTab ? 4 : 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      if (widget.chatType == 'direct') {
        final res = await _supabase.from('profiles').select().eq('id', widget.chatId).maybeSingle();
        _data = res;
      } else if (widget.chatType == 'group') {
        final res = await _supabase.from('group_chats').select().eq('id', widget.chatId).maybeSingle();
        _data = res;
        await _loadGroupMembers();
      } else if (widget.chatType == 'channel') {
        final res = await _supabase.from('channels').select().eq('id', widget.chatId).maybeSingle();
        _data = res;
      }
      if (_hasNotesTab) {
        await _loadNotes();
      }
      await _loadHistory();
    } catch (e) {
      debugPrint('Error loading chat info: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadGroupMembers() async {
    final memberships = await _supabase
        .from('group_chat_members')
        .select('user_id, role, profiles(id, first_name, last_name, avatar_url, role)')
        .eq('group_chat_id', widget.chatId);
    
    _members = List<Map<String, dynamic>>.from(memberships);
  }

  Future<void> _loadHistory() async {
    try {
      if (widget.chatType == 'group') {
        final res = await _supabase.from('messages').select().eq('group_chat_id', widget.chatId).order('created_at', ascending: false);
        _parseHistory(res);
      } else if (widget.chatType == 'channel') {
        final res = await _supabase.from('channel_posts').select().eq('channel_id', widget.chatId).order('created_at', ascending: false);
        _parseHistory(res);
      } else if (widget.chatType == 'direct') {
        final userId = _supabase.auth.currentUser?.id;
        if (userId != null) {
          final res = await _supabase.from('messages').select()
              .or('and(sender_id.eq.$userId,receiver_id.eq.${widget.chatId}),and(sender_id.eq.${widget.chatId},receiver_id.eq.$userId)')
              .order('created_at', ascending: false);
          _parseHistory(res);
        }
      }
    } catch(e) {
      debugPrint('Error loading history: $e');
    }
  }

  void _parseHistory(dynamic res) {
    if (res == null) return;
    final List<Map<String, dynamic>> messages = List<Map<String, dynamic>>.from(res);
    final linkRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    
    for (final m in messages) {
      final type = m['message_type']?.toString();
      final content = m['content']?.toString() ?? '';
      
      if (type == 'file') {
        final ext = ((m['attachment_name']?.toString() ?? '').toLowerCase());
        if (ext.endsWith('.jpg') || ext.endsWith('.png') || ext.endsWith('.jpeg') || ext.endsWith('.webp')) {
          _mediaMessages.add(m);
        } else {
          _fileMessages.add(m);
        }
      }
      
      final links = linkRegExp.allMatches(content);
      for (final match in links) {
        _linkMessages.add({
          'link': match.group(0),
          'message': m,
        });
      }
    }
  }

  Future<void> _loadNotes() async {
    try {
      final res = await _supabase
          .from('profile_notes')
          .select('*, author:profiles!author_id(first_name, last_name, avatar_url)')
          .eq('profile_id', widget.chatId)
          .order('created_at', ascending: false);
      _notes.clear();
      _notes.addAll(List<Map<String, dynamic>>.from(res));
    } catch (e) {
      debugPrint('Error loading notes: $e');
    }
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить заметку'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Введите текст заметки...'),
          maxLines: 5,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    if (content != null && content.trim().isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final authorId = _supabase.auth.currentUser?.id;
        if (authorId == null) return;

        await _supabase.from('profile_notes').insert({
          'profile_id': widget.chatId,
          'author_id': authorId,
          'content': content.trim(),
        });

        await _loadNotes();
      } catch (e) {
        debugPrint('Error adding note: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppTheme.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _changeAvatar() async {
    if (!_canEdit) return;

    final bytes = await AvatarCropperDialog.pickAndCropAvatar(context);
    if (bytes == null) return;

    setState(() => _isLoading = true);
    try {
      final ex = 'avatar_${widget.chatId}.png';
      final url = await ChatAttachmentService.uploadAvatar(
        bytes: bytes,
        fileName: ex,
      );

      final table = widget.chatType == 'group' ? 'group_chats' : 'channels';
      
      if (_data?['avatar_url'] != null) {
        await ChatAttachmentService.deleteAvatar(_data!['avatar_url']);
      }

      await _supabase.from(table).update({'avatar_url': url}).eq('id', widget.chatId);

      _data?['avatar_url'] = url;

      if (widget.chatType == 'group') {
        ref.invalidate(userGroupChatsProvider);
      } else {
        ref.invalidate(channelsProvider);
      }

      if (widget.onUpdate != null) {
        widget.onUpdate!();
      }

    } catch (e) {
      debugPrint('Avatar upload error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editField(String field, String title, String currentValue) async {
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Сохранить')),
        ],
      ),
    );

    if (newValue != null && newValue.trim().isNotEmpty && newValue != currentValue) {
      setState(() => _isLoading = true);
      try {
        final table = widget.chatType == 'group' ? 'group_chats' : 'channels';
        await _supabase.from(table).update({field: newValue.trim()}).eq('id', widget.chatId);
        _data?[field] = newValue.trim();

        if (widget.chatType == 'group') ref.invalidate(userGroupChatsProvider);
        if (widget.chatType == 'channel') ref.invalidate(channelsProvider);

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
        unselectedLabelColor: isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary,
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
      return const Center(child: Text('Нет медиа', style: TextStyle(color: Colors.grey)));
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
        final url = m['attachment_url']?.toString();
        if (url == null) return Container(color: Colors.grey.shade800);
        return GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (c) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: EdgeInsets.zero,
                child: InteractiveViewer(child: Image.network(url)),
              )
            );
          },
          child: Image.network(url, fit: BoxFit.cover),
        );
      },
    );
  }

  Widget _buildFilesList(bool isDark) {
    if (_fileMessages.isEmpty) {
      return const Center(child: Text('Нет файлов', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _fileMessages.length,
      separatorBuilder: (c, i) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
      itemBuilder: (context, index) {
        final m = _fileMessages[index];
        final name = m['attachment_name']?.toString() ?? 'Файл';
        final size = ChatAttachmentService.formatFileSize(m['attachment_size'] as int?);
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TelegramColors.accentBlue.withValues(alpha: 40 / 255), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.insert_drive_file, color: TelegramColors.accentBlue),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(size),
          onTap: () {
            final url = m['attachment_url']?.toString();
            if (url != null) launchUrl(Uri.parse(url));
          },
        );
      },
    );
  }

  Widget _buildLinksList(bool isDark) {
    if (_linkMessages.isEmpty) {
      return const Center(child: Text('Нет ссылок', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _linkMessages.length,
      separatorBuilder: (c, i) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
      itemBuilder: (context, index) {
        final linkData = _linkMessages[index];
        final link = linkData['link'] as String;
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TelegramColors.accentBlue.withValues(alpha: 40 / 255), shape: BoxShape.circle),
            child: Icon(Icons.link, color: TelegramColors.accentBlue),
          ),
          title: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: TelegramColors.accentBlue)),
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
    String name = 'N/A';
    String description = '';
    String? subtitle = '';
    String? avatarUrl = _data?['avatar_url'];

    if (widget.chatType == 'direct') {
      name = '${_data?['first_name'] ?? ''} ${_data?['last_name'] ?? ''}'.trim();
      if (name.isEmpty) name = 'Без имени';
      
      final role = _data?['role'] ?? 'client';
      description = role == 'admin' ? 'Администратор'
          : role == 'manager' ? 'Управляющий'
          : role == 'teacher' ? 'Преподаватель'
          : 'Клиент (Ученик)';

      subtitle = 'Телефон: ${_data?['phone'] ?? 'Нет номера'}';
    } else {
      name = _data?['name'] ?? 'Без названия';
      subtitle = _members.isNotEmpty ? '${_members.length} участников' : 'Канал';
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
                backgroundColor: isDark ? TelegramColors.darkSurface : TelegramColors.lightSurface,
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  title: innerBoxIsScrolled 
                    ? Text(name, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16))
                    : null,
                    background: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 50),
                      GestureDetector(
                        onTap: _changeAvatar,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Hero(
                              tag: 'avatar_${widget.chatId}',
                              child: TelegramAvatar(
                                name: name,
                                avatarUrl: avatarUrl,
                                uniqueId: widget.chatId,
                                radius: 50,
                              ),
                            ),
                            if (_canEdit)
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.4),
                                ),
                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 30),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _editField('name', 'название', name),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            if (_canEdit) const SizedBox(width: 8),
                            if (_canEdit) Icon(Icons.edit_rounded, size: 14, color: TelegramColors.accentBlue),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle ?? '', style: TextStyle(color: isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                leading: widget.onClose != null
                    ? IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose)
                    : null,
                actions: [
                  IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
                ],
              ),
              // Action buttons and info
              SliverToBoxAdapter(
                child: Container(
                  color: isDark ? TelegramColors.darkBg : TelegramColors.lightBg,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildActionButton(Icons.chat_bubble_outline, 'Чат', isDark),
                            _buildActionButton(Icons.notifications_none, 'Заглушить', isDark),
                            _buildActionButton(Icons.search, 'Поиск', isDark),
                          ],
                        ),
                      ),
                      // Info section
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? TelegramColors.darkSurface : TelegramColors.lightSurface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.chatType == 'direct') ...[
                              Text(_data?['phone'] ?? '+0(000)000-00-00', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Text('Телефон', style: TextStyle(fontSize: 13, color: isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary)),
                              const SizedBox(height: 16),
                            ],
                            GestureDetector(
                              onTap: widget.chatType != 'direct' ? () => _editField('description', 'описание', description) : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(description.isEmpty ? 'Нет описания' : description, style: const TextStyle(fontSize: 16)),
                                      if (_canEdit) Icon(Icons.edit_rounded, size: 14, color: TelegramColors.accentBlue),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(widget.chatType == 'direct' ? 'Статус / Роль' : 'Описание', style: TextStyle(fontSize: 13, color: isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary)),
                                ],
                              ),
                            ),
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
                delegate: _SliverAppBarDelegate(
                  _buildTabBar(isDark),
                ),
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

  Widget _buildActionButton(IconData icon, String label, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isDark ? TelegramColors.darkSurface : TelegramColors.lightSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: isDark ? Colors.white : Colors.black),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12, color: isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary)),
      ],
    );
  }

  Widget _buildNotesList(bool isDark) {
    if (_notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Заметок пока нет', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _addNote,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Добавить первую'),
            ),
          ],
        )
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
              ? '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'.trim()
              : 'Админ';
          // Fix for potential string/datetime issues
          final createdAt = note['created_at'];
          final time = createdAt != null 
              ? (createdAt is String 
                  ? DateFormat('dd.MM.yy HH:mm').format(DateTime.parse(createdAt))
                  : DateFormat('dd.MM.yy HH:mm').format(createdAt))
              : 'N/A';
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(authorName, style: TextStyle(fontWeight: FontWeight.bold, color: TelegramColors.accentBlue, fontSize: 13)),
                    Text(time, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(note['content'] ?? '', style: const TextStyle(fontSize: 14)),
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _tabBar;
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
