import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/core/widgets/file_attachment_widget.dart';
import 'package:magic_music_crm/core/widgets/voice_player_widget.dart';
import 'package:magic_music_crm/core/widgets/voice_recorder_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/broadcast_dialog.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/lead_detail_dialog.dart';

// Bottom margin used for all floating SnackBars so they appear above the
// message-input bar (~72 dp tall) and never obscure it.  KVA-173.
const _kSnackBarBottomMargin = EdgeInsets.only(
  bottom: 72,
  left: 12,
  right: 12,
);

class AdminChatDashboard extends ConsumerStatefulWidget {
  const AdminChatDashboard({super.key});

  @override
  ConsumerState<AdminChatDashboard> createState() => _AdminChatDashboardState();
}

class _AdminChatDashboardState extends ConsumerState<AdminChatDashboard> {
  String? _selectedStudentUserId;
  String? _selectedStudentName;
  bool _showSchoolInbox = true;

  @override
  Widget build(BuildContext context) {
    if (_selectedStudentUserId != null) {
      return _ChatView(
        title: _selectedStudentName ?? 'Ученик',
        targetUserId: _selectedStudentUserId,
        showHeader: true,
        onBack: () => setState(() {
          _selectedStudentUserId = null;
          _selectedStudentName = null;
        }),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('В школу'),
                      icon: Icon(Icons.school_rounded),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Личные чаты'),
                      icon: Icon(Icons.person_rounded),
                    ),
                  ],
                  selected: {_showSchoolInbox},
                  onSelectionChanged: (value) =>
                      setState(() => _showSchoolInbox = value.first),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: () => BroadcastDialog.show(context),
                icon: const Icon(Icons.campaign_rounded),
                tooltip: 'Массовая рассылка',
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold.withAlpha(30),
                  foregroundColor: AppTheme.primaryGold,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _showSchoolInbox
              ? const _ChatView(title: 'Администрация школы')
              : _StudentChatList(
                  onChatSelected: (id, name) => setState(() {
                    _selectedStudentUserId = id;
                    _selectedStudentName = name;
                  }),
                ),
        ),
      ],
    );
  }
}

class _StudentChatList extends ConsumerStatefulWidget {
  final void Function(String userId, String name) onChatSelected;

  const _StudentChatList({required this.onChatSelected});

  @override
  ConsumerState<_StudentChatList> createState() => _StudentChatListState();
}

class _StudentChatListState extends ConsumerState<_StudentChatList> {
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final profiles = await ref
          .read(magicProfileAdminServiceProvider)
          .listProfiles(role: 'client', limit: 100);
      if (!mounted) return;
      setState(() {
        _students = profiles.where((profile) {
          final userId = profile['user_id']?.toString();
          return userId != null && userId.isNotEmpty;
        }).toList()..sort((a, b) => _profileName(a).compareTo(_profileName(b)));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // KVA-173: floating so the toast never hides the input bar.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки учеников: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          margin: _kSnackBarBottomMargin,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGold),
      );
    }

    if (_students.isEmpty) {
      return Center(
        child: Text(
          'Ученики не найдены',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _students.length,
      itemBuilder: (context, index) {
        final student = _students[index];
        final userId = student['user_id'].toString();
        final name = _profileName(student);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryGold.withAlpha(40),
            child: Text(
              name.isNotEmpty ? name[0] : '?',
              style: const TextStyle(
                color: AppTheme.primaryGold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            name.isEmpty ? 'Ученик' : name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            student['phone']?.toString().isNotEmpty == true
                ? student['phone'].toString()
                : student['email']?.toString() ?? '',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onTap: () => widget.onChatSelected(userId, name),
        );
      },
    );
  }
}

class _ChatView extends ConsumerStatefulWidget {
  final String title;
  final String? targetUserId;
  final bool showHeader;
  final VoidCallback? onBack;

  const _ChatView({
    required this.title,
    this.targetUserId,
    this.showHeader = false,
    this.onBack,
  });

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _currentUserId;
  String? _chatId;
  MagicRealtimeConnection? _realtime;
  bool _realtimeConnecting = false;

  // KVA-174: track whether the list is at the bottom and how many new
  // messages arrived while the user was scrolled away.
  bool _isAtBottom = true;
  int _unreadCount = 0;

  // Threshold in pixels — within this distance of maxScrollExtent is
  // considered "at the bottom".
  static const double _atBottomThreshold = 80.0;

  MagicMessengerService get _messenger =>
      ref.read(magicMessengerServiceProvider);

  MagicRealtimeService get _realtimeService =>
      ref.read(magicRealtimeServiceProvider);

  @override
  void initState() {
    super.initState();
    // KVA-174: listen for scroll position to track near-bottom state.
    _scrollController.addListener(_onScroll);
    _loadMessages();
  }

  // KVA-174: called on every scroll event — update _isAtBottom and clear
  // the unread badge when the user reaches the bottom.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - _atBottomThreshold;
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        if (atBottom) _unreadCount = 0;
      });
    } else if (atBottom && _unreadCount > 0) {
      setState(() => _unreadCount = 0);
    }
  }

  Future<void> _loadMessages() async {
    try {
      final profile = await ref.read(magicAuthServiceProvider).currentProfile();
      final chatId = await _ensureChatId();
      final messages = await _messenger.listMessages(chatId, limit: 100);

      if (!mounted) return;
      setState(() {
        _currentUserId = profile.userId;
        _messages = messages;
        _loading = false;
      });
      _scrollToBottom();
      await _markAsRead(messages);
      await _connectRealtime(chatId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // KVA-173: floating so the toast never hides the input bar.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки чата: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          margin: _kSnackBarBottomMargin,
        ),
      );
    }
  }

  Future<String> _ensureChatId() async {
    final existing = _chatId;
    if (existing != null && existing.isNotEmpty) return existing;

    final targetUserId = widget.targetUserId;
    final chat = targetUserId == null
        ? await _messenger.ensureAdministrationChat()
        : await _messenger.ensureDirectChat(targetUserId);
    final chatId = chat['id']?.toString();
    if (chatId == null || chatId.isEmpty) {
      throw StateError('Сервер не вернул идентификатор чата.');
    }
    _chatId = chatId;
    return chatId;
  }

  Future<void> _connectRealtime(String chatId) async {
    if (_realtime != null || _realtimeConnecting) return;
    _realtimeConnecting = true;
    try {
      final connection = await _realtimeService.connect();
      if (!mounted) {
        connection.dispose();
        return;
      }

      connection.joinChat(chatId);
      connection.onMessageCreated((payload) {
        if (payload['chatId'] != chatId) return;
        if (!mounted) return;
        setState(() {
          _upsertMessage(_legacyRealtimeMessage(payload));
          // KVA-174: increment unread badge only while scrolled away from
          // the bottom.
          if (!_isAtBottom) _unreadCount++;
        });
        // KVA-174: only auto-scroll when the user is already near the bottom.
        if (_isAtBottom) _scrollToBottom();
        _markAsRead(_messages);
      });
      connection.onMessageUpdated((payload) {
        if (payload['chatId'] != chatId) return;
        if (!mounted) return;
        setState(() => _upsertMessage(_legacyRealtimeMessage(payload)));
      });
      _realtime = connection;
    } catch (e) {
      debugPrint('Admin chat realtime unavailable: $e');
    } finally {
      _realtimeConnecting = false;
    }
  }

  Future<void> _markAsRead(List<Map<String, dynamic>> messages) async {
    final chatId = _chatId;
    final lastMessageId = messages.isEmpty
        ? null
        : messages.last['id']?.toString();
    if (chatId == null || lastMessageId == null || lastMessageId.isEmpty) {
      return;
    }
    await _messenger.markRead(chatId, lastReadMessageId: lastMessageId);
  }

  Future<void> _sendText(String text) async {
    try {
      final chatId = await _ensureChatId();
      final message = await _messenger.sendMessage(chatId, content: text);
      if (!mounted) return;
      setState(() => _upsertMessage(message));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Ошибка отправки: $e');
    }
  }

  Future<void> _sendVoice(
    Uint8List bytes,
    int durationMs,
    String extension,
  ) async {
    try {
      final chatId = await _ensureChatId();
      final fileId = await ref
          .read(chatAttachmentServiceProvider)
          .uploadVoice(
            bytes: bytes,
            senderId: _currentUserId ?? '',
            chatId: chatId,
            extension: extension,
          );
      final message = await _messenger.sendMessage(
        chatId,
        content: 'Голосовое сообщение',
        messageType: 'voice',
        attachmentFileId: fileId,
      );
      if (!mounted) return;
      setState(() {
        _upsertMessage({...message, 'voice_duration_ms': durationMs});
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Ошибка отправки голосового: $e');
    }
  }

  Future<void> _sendFile(Uint8List bytes, String fileName, int fileSize) async {
    try {
      final chatId = await _ensureChatId();
      final fileId = await ref
          .read(chatAttachmentServiceProvider)
          .uploadFile(
            bytes: bytes,
            originalFileName: fileName,
            senderId: _currentUserId ?? '',
            chatId: chatId,
          );
      final message = await _messenger.sendMessage(
        chatId,
        content: fileName,
        messageType: 'file',
        attachmentFileId: fileId,
      );
      if (!mounted) return;
      setState(() {
        _upsertMessage({
          ...message,
          'attachment_file_id': fileId,
          'attachment_name': fileName,
          'attachment_size': fileSize,
        });
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Ошибка отправки файла: $e');
    }
  }

  void _upsertMessage(Map<String, dynamic> message) {
    final id = message['id']?.toString();
    if (id == null || id.isEmpty) return;
    final index = _messages.indexWhere((item) => item['id'] == id);
    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] = {..._messages[index], ...message};
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // KVA-175: save the chat partner into CRM as a lead, then offer to open the
  // created lead card via a floating SnackBar action.
  Future<void> _saveContactFromChat() async {
    final partnerId = widget.targetUserId;
    if (partnerId == null || partnerId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .saveContactFromChat(userId: partnerId, as: 'lead');
      if (!mounted) return;
      final created = result['created'] == true;
      final leadId = result['leadId']?.toString() ?? '';
      // Build a minimal lead map so LeadDetailDialog can open immediately
      // (the dialog loads its own full data; we only need `id`).
      final leadStub = <String, dynamic>{'id': leadId};
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            created
                ? 'Контакт сохранён как лид'
                : 'Контакт уже был сохранён как лид',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          margin: _kSnackBarBottomMargin,
          action: leadId.isNotEmpty
              ? SnackBarAction(
                  label: 'Открыть карточку',
                  textColor: Colors.white,
                  onPressed: () => _openLeadCard(leadStub),
                )
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось сохранить контакт: $e');
    }
  }

  // KVA-175: open the lead detail dialog for a given lead map.
  Future<void> _openLeadCard(Map<String, dynamic> lead) async {
    if (!mounted) return;
    // We need the status list for LeadDetailDialog.  Use the cached provider.
    List<StatusRecord> statuses = [];
    try {
      final raw = await ref.read(leadStatusesProvider.future);
      for (final r in raw) {
        final key = r['key'].toString();
        final label = r['label'].toString();
        final color = statusColorFromValue(r['color']);
        statuses.add((key, label, color));
      }
    } catch (_) {
      // Dialog still opens; it will fetch its own data.
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => LeadDetailDialog(lead: lead, allStatuses: statuses),
    );
  }

  void _showError(String message) {
    // KVA-173: floating so the toast never hides the input bar.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        margin: _kSnackBarBottomMargin,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    final chatId = _chatId;
    if (chatId != null) _realtime?.leaveRoom(chatId);
    _realtime?.disconnect();
    _realtime?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Column(
        children: [
          if (widget.showHeader)
            AppBar(
              title: Text(widget.title),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
            ),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (widget.showHeader)
          AppBar(
            title: Text(widget.title),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
            ),
            // KVA-175: save-contact action, shown only for direct (student) chats.
            actions: widget.targetUserId != null
                ? [
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      tooltip: 'Сохранить контакт как лид',
                      onPressed: _saveContactFromChat,
                    ),
                  ]
                : null,
          ),
        Expanded(
          child: Stack(
            children: [
              _messages.isEmpty
                  ? Center(
                      child: Text(
                        'Нет сообщений',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final isMe = message['sender_id'] == _currentUserId;
                        return _MessageBubble(
                          message: message,
                          isMe: isMe,
                          senderName: isMe ? 'Я' : _senderName(message),
                        );
                      },
                    ),
              // KVA-174: scroll-to-bottom FAB with unread badge.
              if (!_isAtBottom)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: GestureDetector(
                    onTap: () {
                      // Clear the badge on intent; let _onScroll flip
                      // _isAtBottom once the animation actually reaches the
                      // bottom, so an interrupted scroll can't leave it stuck.
                      setState(() => _unreadCount = 0);
                      _scrollToBottom();
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 28,
                          ),
                        ),
                        if (_unreadCount > 0)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryGold,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(10),
                                ),
                              ),
                              child: Text(
                                _unreadCount > 99 ? '99+' : '$_unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        _MessageInputWithAttachments(
          onSend: _sendText,
          onSendVoice: _sendVoice,
          onSendFile: _sendFile,
        ),
      ],
    );
  }

  String _senderName(Map<String, dynamic> message) {
    final profiles = message['profiles'];
    if (profiles is Map) {
      final firstName = profiles['first_name']?.toString() ?? '';
      final lastName = profiles['last_name']?.toString() ?? '';
      final name = '$firstName $lastName'.trim();
      if (name.isNotEmpty) return name;
    }
    return widget.targetUserId == null ? 'Клиент' : widget.title;
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final String senderName;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(message['created_at']?.toString() ?? '');
    final timeStr = dt != null
        ? DateFormat('HH:mm', 'ru').format(dt.toLocal())
        : '';
    final messageType = message['message_type']?.toString() ?? 'text';
    final attachmentUrl =
        message['attachment_url']?.toString() ??
        message['attachment_file_id']?.toString();
    final isImageFile =
        messageType == 'file' &&
        FileAttachmentWidget.isImage(message['attachment_name']?.toString());

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                senderName,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: isImageFile
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isMe
                  ? AppTheme.primaryGold
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (messageType == 'voice')
                  SizedBox(
                    width: 220,
                    child: VoicePlayerWidget(
                      audioUrl: attachmentUrl ?? '',
                      durationMs: _asInt(message['voice_duration_ms']),
                      isMe: isMe,
                    ),
                  )
                else if (messageType == 'file')
                  FileAttachmentWidget(
                    fileName: message['attachment_name']?.toString(),
                    fileUrl: attachmentUrl,
                    fileSize: _asInt(message['attachment_size']),
                    isMe: isMe,
                  )
                else
                  Text(
                    message['content']?.toString() ?? '',
                    style: TextStyle(
                      color: isMe
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: isMe
                            ? Colors.white.withAlpha(180)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message['is_read'] == true
                            ? Icons.done_all
                            : Icons.done,
                        size: 12,
                        color: message['is_read'] == true
                            ? AppTheme.success
                            : Colors.white.withAlpha(180),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageInputWithAttachments extends StatefulWidget {
  final Future<void> Function(String text) onSend;
  final Future<void> Function(Uint8List bytes, int durationMs, String extension)
  onSendVoice;
  final Future<void> Function(Uint8List bytes, String fileName, int fileSize)
  onSendFile;

  const _MessageInputWithAttachments({
    required this.onSend,
    required this.onSendVoice,
    required this.onSendFile,
  });

  @override
  State<_MessageInputWithAttachments> createState() =>
      _MessageInputWithAttachmentsState();
}

class _MessageInputWithAttachmentsState
    extends State<_MessageInputWithAttachments> {
  final _controller = TextEditingController();
  bool _isRecording = false;
  bool _isSendingFile = false;

  Future<void> _pickAndSendFile() async {
    if (_isSendingFile) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.size > ChatAttachmentService.maxFileSizeBytes) {
        _showError('Файл слишком большой (макс. 25 МБ)');
        return;
      }

      setState(() => _isSendingFile = true);
      final bytes = await _readPickedFileBytes(file);
      if (bytes == null) return;
      await widget.onSendFile(bytes, file.name, file.size);
    } catch (e) {
      _showError('Ошибка отправки файла: $e');
    } finally {
      if (mounted) setState(() => _isSendingFile = false);
    }
  }

  Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes;
    final path = file.path;
    if (path == null || path.isEmpty) {
      _showError('Не удалось прочитать файл');
      return null;
    }
    return File(path).readAsBytes();
  }

  void _showError(String message) {
    if (!mounted) return;
    // KVA-173: floating so the toast never hides the input bar.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        margin: _kSnackBarBottomMargin,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isRecording) {
      return VoiceRecorderWidget(
        onVoiceRecorded: (bytes, durationMs, extension) async {
          await widget.onSendVoice(bytes, durationMs, extension);
          if (mounted) setState(() => _isRecording = false);
        },
        onCancel: () {
          if (mounted) setState(() => _isRecording = false);
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: _isSendingFile
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryGold,
                      ),
                    )
                  : Icon(
                      Icons.attach_file_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              tooltip: 'Прикрепить файл',
              onPressed: _isSendingFile ? null : _pickAndSendFile,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Введите сообщение...',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryGold,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      hasText ? Icons.send_rounded : Icons.mic_rounded,
                      color: Colors.white,
                    ),
                    tooltip: hasText ? 'Отправить' : 'Голосовое сообщение',
                    onPressed: hasText
                        ? _sendText
                        : () => setState(() => _isRecording = true),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await widget.onSend(text);
  }
}

Map<String, dynamic> _legacyRealtimeMessage(Map<String, dynamic> item) {
  final sender = item['sender'];
  final senderMap = sender is Map<String, dynamic>
      ? sender
      : const <String, dynamic>{};
  return {
    'id': item['id'],
    'chat_id': item['chatId'],
    'sender_id': item['senderId'],
    'content': item['content'],
    'message_type': item['messageType'],
    'attachment_file_id': item['attachmentFileId'],
    'attachment_name':
        item['attachmentName'] ??
        item['attachmentFileName'] ??
        item['fileName'],
    'attachment_size': item['attachmentSize'] ?? item['attachmentFileSize'],
    'attachment_mime_type': item['attachmentMimeType'],
    'voice_duration_ms': item['voiceDurationMs'],
    'reply_to_id': item['replyToId'],
    'forwarded_from_id': item['forwardedFromId'],
    'pinned_by': item['pinnedBy'],
    'pinned_at': item['pinnedAt'],
    'created_at': item['createdAt'],
    'updated_at': item['updatedAt'],
    'deleted_at': item['deletedAt'],
    'is_read': item['isRead'] == true,
    'profiles': {
      'id': senderMap['id'],
      'first_name': senderMap['firstName'],
      'last_name': senderMap['lastName'],
    },
  };
}

String _profileName(Map<String, dynamic> profile) {
  final firstName = profile['first_name']?.toString() ?? '';
  final lastName = profile['last_name']?.toString() ?? '';
  final name = '$firstName $lastName'.trim();
  if (name.isNotEmpty) return name;
  return profile['email']?.toString() ?? '';
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
