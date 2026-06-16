import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/file_attachment_widget.dart';
import 'package:magic_music_crm/core/widgets/voice_player_widget.dart';
import 'package:magic_music_crm/core/widgets/voice_recorder_widget.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

class ChatWidget extends ConsumerStatefulWidget {
  final String currentUserId;

  const ChatWidget({super.key, required this.currentUserId});

  @override
  ConsumerState<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends ConsumerState<ChatWidget> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  String? _currentUserId;
  String? _selectedReceiverId;
  String _selectedName = 'Администрация';
  String? _activeChatId;
  String? _administrationChatId;

  List<Map<String, dynamic>> _teachersList = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, int> _unreadCounts = {};
  final Map<String, String> _directChatIds = {};

  bool _loading = true;
  bool _messagesLoading = false;
  bool _isRecording = false;
  bool _isSendingFile = false;
  bool _realtimeConnecting = false;
  MagicRealtimeConnection? _realtime;

  MagicMessengerService get _messenger =>
      ref.read(magicMessengerServiceProvider);

  MagicRealtimeService get _realtimeService =>
      ref.read(magicRealtimeServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final profile = await ref.read(magicAuthServiceProvider).currentProfile();
      final teachers = await ref
          .read(magicCrmServiceProvider)
          .listTeachers(limit: 100);
      final administrationChat = await _messenger.ensureAdministrationChat();

      final contacts = <String, Map<String, dynamic>>{};
      for (final teacher in teachers) {
        final userId = teacher['profile_user_id']?.toString();
        if (userId == null || userId.isEmpty) continue;

        final firstName = teacher['first_name']?.toString() ?? '';
        final lastName = teacher['last_name']?.toString() ?? '';
        final specialization = teacher['specialization']?.toString() ?? '';
        final name = '$firstName $lastName'.trim();
        contacts[userId] = {
          'id': userId,
          'name': name.isNotEmpty ? name : 'Преподаватель',
          'subtitle': specialization,
        };
      }

      if (!mounted) return;
      setState(() {
        _currentUserId = profile.userId;
        _teachersList = contacts.values.toList()
          ..sort(
            (a, b) => (a['name']?.toString() ?? '').compareTo(
              b['name']?.toString() ?? '',
            ),
          );
        _administrationChatId = administrationChat['id']?.toString();
        _unreadCounts = {'school': _readUnreadCount(administrationChat)};
        _loading = false;
      });

      await _openSelectedChat(null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Ошибка загрузки чата: $e');
    }
  }

  Future<void> _openSelectedChat(String? receiverId) async {
    setState(() {
      _selectedReceiverId = receiverId;
      _selectedName = receiverId == null
          ? 'Администрация'
          : _teachersList.firstWhere(
                  (item) => item['id'] == receiverId,
                  orElse: () => {'name': 'Преподаватель'},
                )['name']
                as String;
      _messages = [];
      _messagesLoading = true;
    });

    try {
      final chatId = await _ensureChatId(receiverId);
      final messages = await _messenger.listMessages(chatId, limit: 200);

      if (!mounted) return;
      setState(() {
        _activeChatId = chatId;
        _messages = messages;
        _messagesLoading = false;
        _unreadCounts[receiverId ?? 'school'] = 0;
      });

      _scrollToBottom();
      await _markAsRead(messages);
      await _connectRealtime(chatId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _messagesLoading = false);
      _showError('Ошибка открытия чата: $e');
    }
  }

  Future<String> _ensureChatId(String? receiverId) async {
    if (receiverId == null) {
      final existing = _administrationChatId;
      if (existing != null && existing.isNotEmpty) return existing;
      final chat = await _messenger.ensureAdministrationChat();
      final chatId = chat['id']?.toString();
      if (chatId == null || chatId.isEmpty) {
        throw StateError('Сервер не вернул чат с администрацией.');
      }
      _administrationChatId = chatId;
      return chatId;
    }

    final existing = _directChatIds[receiverId];
    if (existing != null && existing.isNotEmpty) return existing;
    final chat = await _messenger.ensureDirectChat(receiverId);
    final chatId = chat['id']?.toString();
    if (chatId == null || chatId.isEmpty) {
      throw StateError('Сервер не вернул личный чат.');
    }
    _directChatIds[receiverId] = chatId;
    return chatId;
  }

  Future<void> _connectRealtime(String chatId) async {
    if (_realtimeConnecting) return;
    _realtimeConnecting = true;
    try {
      _disconnectRealtime();
      final connection = await _realtimeService.connect();
      if (!mounted) {
        connection.dispose();
        return;
      }

      connection.joinChat(chatId);
      connection.onMessageCreated((payload) {
        if (payload['chatId'] != chatId) return;
        final message = _legacyRealtimeMessage(payload);
        if (!mounted) return;
        setState(() => _upsertMessage(message));
        _scrollToBottom();
        _markAsRead(_messages);
      });
      connection.onMessageUpdated((payload) {
        if (payload['chatId'] != chatId) return;
        final message = _legacyRealtimeMessage(payload);
        if (!mounted) return;
        setState(() => _upsertMessage(message));
      });
      _realtime = connection;
    } catch (e) {
      debugPrint('Client chat realtime unavailable: $e');
    } finally {
      _realtimeConnecting = false;
    }
  }

  Future<void> _markAsRead(List<Map<String, dynamic>> messages) async {
    final chatId = _activeChatId;
    final lastMessageId = messages.isEmpty
        ? null
        : messages.last['id']?.toString();
    if (chatId == null || lastMessageId == null || lastMessageId.isEmpty) {
      return;
    }

    await _messenger.markRead(chatId, lastReadMessageId: lastMessageId);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();

    try {
      final chatId = await _ensureChatId(_selectedReceiverId);
      final message = await _messenger.sendMessage(chatId, content: text);
      if (!mounted) return;
      setState(() => _upsertMessage(message));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Ошибка при отправке: $e');
    }
  }

  Future<void> _sendVoice(
    Uint8List bytes,
    int durationMs,
    String extension,
  ) async {
    try {
      final chatId = await _ensureChatId(_selectedReceiverId);
      final fileId = await ref
          .read(chatAttachmentServiceProvider)
          .uploadVoice(
            bytes: bytes,
            senderId: _currentUserId ?? widget.currentUserId,
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
        _isRecording = false;
        _upsertMessage({...message, 'voice_duration_ms': durationMs});
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _showError('Ошибка отправки голосового: $e');
    }
  }

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
      final chatId = await _ensureChatId(_selectedReceiverId);
      final fileId = await ref
          .read(chatAttachmentServiceProvider)
          .uploadFile(
            bytes: bytes,
            originalFileName: file.name,
            senderId: _currentUserId ?? widget.currentUserId,
            chatId: chatId,
          );

      final message = await _messenger.sendMessage(
        chatId,
        content: file.name,
        messageType: 'file',
        attachmentFileId: fileId,
      );
      if (!mounted) return;
      setState(() {
        _upsertMessage({
          ...message,
          'attachment_name': file.name,
          'attachment_size': file.size,
          'attachment_file_id': fileId,
        });
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppTheme.danger,
      ),
    );
  }

  void _disconnectRealtime() {
    final chatId = _activeChatId;
    if (chatId != null) _realtime?.leaveRoom(chatId);
    _realtime?.disconnect();
    _realtime?.dispose();
    _realtime = null;
  }

  @override
  void dispose() {
    _disconnectRealtime();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGold),
      );
    }

    if (_currentUserId == null || _currentUserId!.isEmpty) {
      return const Center(child: Text('Пожалуйста, войдите в систему'));
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            children: [
              Text(
                'Кому:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedReceiverId,
                    isExpanded: true,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: _ContactDropdownLabel(
                          title: 'Администрация',
                          unreadCount: _unreadCounts['school'] ?? 0,
                        ),
                      ),
                      ..._teachersList.map((teacher) {
                        final id = teacher['id'] as String;
                        return DropdownMenuItem<String?>(
                          value: id,
                          child: _ContactDropdownLabel(
                            title: teacher['name'] as String,
                            subtitle: teacher['subtitle']?.toString(),
                            unreadCount: _unreadCounts[id] ?? 0,
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) => _openSelectedChat(value),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _messagesLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryGold),
                )
              : _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withAlpha(80),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Напишите в $_selectedName\nесли у вас есть вопросы',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
        ),
        if (_isRecording)
          VoiceRecorderWidget(
            onVoiceRecorded: _sendVoice,
            onCancel: () {
              if (mounted) setState(() => _isRecording = false);
            },
          )
        else
          _MessageInput(
            controller: _messageController,
            isSendingFile: _isSendingFile,
            onPickFile: _pickAndSendFile,
            onSend: _sendMessage,
            onRecord: () => setState(() => _isRecording = true),
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
    return _selectedReceiverId == null ? 'Администрация' : _selectedName;
  }
}

class _ContactDropdownLabel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int unreadCount;

  const _ContactDropdownLabel({
    required this.title,
    this.subtitle,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, overflow: TextOverflow.ellipsis),
              if (subtitle?.trim().isNotEmpty == true)
                Text(
                  subtitle!.trim(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (unreadCount > 0) ...[
          const SizedBox(width: 8),
          Badge(label: Text('$unreadCount')),
        ],
      ],
    );
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isSendingFile;
  final VoidCallback onPickFile;
  final VoidCallback onSend;
  final VoidCallback onRecord;

  const _MessageInput({
    required this.controller,
    required this.isSendingFile,
    required this.onPickFile,
    required this.onSend,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
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
              icon: isSendingFile
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
              onPressed: isSendingFile ? null : onPickFile,
            ),
            Expanded(
              child: TextField(
                controller: controller,
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
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
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
                    onPressed: hasText ? onSend : onRecord,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
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
                      durationMs: message['voice_duration_ms'] as int?,
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
                      fontSize: 15,
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

int _readUnreadCount(Map<String, dynamic> chat) {
  final value = chat['unread_count'] ?? chat['unreadCount'];
  return _asInt(value) ?? 0;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
