import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

class TeacherChatWidget extends ConsumerStatefulWidget {
  const TeacherChatWidget({super.key});

  @override
  ConsumerState<TeacherChatWidget> createState() => _TeacherChatWidgetState();
}

class _TeacherChatWidgetState extends ConsumerState<TeacherChatWidget> {
  List<Map<String, dynamic>> _contacts = [];
  Map<String, int> _unreadCounts = {};
  bool _loading = true;
  String? _currentUserId;
  String? _selectedContactId;
  String? _selectedContactName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final profile = await ref.read(magicAuthServiceProvider).currentProfile();
      final students = await ref
          .read(magicCrmServiceProvider)
          .listStudents(limit: 100);

      final uniqueContacts = <String, Map<String, dynamic>>{};
      for (final student in students) {
        final targetUserId = student['profile_user_id']?.toString();
        if (targetUserId == null || targetUserId.isEmpty) continue;

        final firstName = student['first_name']?.toString() ?? '';
        final lastName = student['last_name']?.toString() ?? '';
        final email = student['email']?.toString() ?? '';
        final name = '$firstName $lastName'.trim();
        uniqueContacts[targetUserId] = {
          'id': targetUserId,
          'name': name.isNotEmpty ? name : email,
        };
      }

      if (!mounted) return;
      setState(() {
        _currentUserId = profile.userId;
        _contacts = uniqueContacts.values.toList()
          ..sort(
            (a, b) => (a['name']?.toString() ?? '').compareTo(
              b['name']?.toString() ?? '',
            ),
          );
        _unreadCounts = const {};
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _currentUserId;
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGold),
      );
    }

    if (currentUserId == null || currentUserId.isEmpty) {
      return const Center(child: Text('Пожалуйста, войдите в систему'));
    }

    if (_selectedContactId != null) {
      return _ChatView(
        currentUserId: currentUserId,
        contactId: _selectedContactId!,
        contactName: _selectedContactName ?? '',
        messenger: ref.read(magicMessengerServiceProvider),
        realtime: ref.read(magicRealtimeServiceProvider),
        onBack: () => setState(() {
          _selectedContactId = null;
          _selectedContactName = null;
          _loadData();
        }),
      );
    }

    if (_contacts.isEmpty) {
      return Center(
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
              'Нет прикрепленных учеников',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _contacts.length,
      itemBuilder: (context, i) {
        final contact = _contacts[i];
        final id = contact['id'] as String;
        final name = contact['name'] as String;
        final unreadCount = _unreadCounts[id] ?? 0;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryGold.withAlpha(30),
            child: Text(
              name.isNotEmpty ? name[0] : '?',
              style: const TextStyle(
                color: AppTheme.primaryGold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(name.isEmpty ? 'Безымянный ученик' : name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          onTap: () => setState(() {
            _selectedContactId = id;
            _selectedContactName = name;
            _unreadCounts[id] = 0;
          }),
        );
      },
    );
  }
}

class _ChatView extends StatefulWidget {
  final String currentUserId;
  final String contactId;
  final String contactName;
  final MagicMessengerService messenger;
  final MagicRealtimeService realtime;
  final VoidCallback onBack;

  const _ChatView({
    required this.currentUserId,
    required this.contactId,
    required this.contactName,
    required this.messenger,
    required this.realtime,
    required this.onBack,
  });

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _chatId;
  MagicRealtimeConnection? _realtime;
  bool _realtimeConnecting = false;
  Timer? _fallbackPollTimer;
  DateTime _lastRealtimeEventAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final chatId = await _ensureChatId();
      final messages = await widget.messenger.listMessages(chatId, limit: 100);

      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _scrollToBottom();
      await _markAsRead(messages);
      await _connectRealtime(chatId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки чата: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<String> _ensureChatId() async {
    final existing = _chatId;
    if (existing != null) return existing;

    final chat = await widget.messenger.ensureDirectChat(widget.contactId);
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
      final connection = await widget.realtime.connect();
      if (!mounted) {
        connection.dispose();
        return;
      }
      connection.joinChat(chatId);
      connection.onMessageCreated((payload) {
        _markRealtimeEvent();
        if (payload['chatId'] != chatId) return;
        if (!mounted) return;
        setState(() {
          final message = _legacyRealtimeMessage(payload);
          final exists = _messages.any((item) => item['id'] == message['id']);
          if (!exists) _messages.add(message);
        });
        _scrollToBottom();
        _markAsRead(_messages);
      });
      connection.onMessageUpdated((payload) {
        _markRealtimeEvent();
        if (payload['chatId'] != chatId) return;
        if (!mounted) return;
        setState(() {
          final message = _legacyRealtimeMessage(payload);
          final index = _messages.indexWhere(
            (item) => item['id'] == message['id'],
          );
          if (index == -1) {
            _messages.add(message);
          } else {
            _messages[index] = {..._messages[index], ...message};
          }
        });
      });
      _realtime = connection;
      _startFallbackPolling();
    } catch (e) {
      debugPrint('Teacher chat realtime unavailable: $e');
      _startFallbackPolling();
    } finally {
      _realtimeConnecting = false;
    }
  }

  void _markRealtimeEvent() {
    _lastRealtimeEventAt = DateTime.now();
  }

  void _startFallbackPolling() {
    if (_fallbackPollTimer != null) return;
    _fallbackPollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      final realtimeIsFresh =
          DateTime.now().difference(_lastRealtimeEventAt) <
          const Duration(seconds: 18);
      if (realtimeIsFresh) return;
      unawaited(_refreshMessagesSilently());
    });
  }

  Future<void> _refreshMessagesSilently() async {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty || _loading) return;
    try {
      final messages = await widget.messenger.listMessages(chatId, limit: 100);
      if (!mounted || _chatId != chatId) return;
      setState(() {
        for (final message in messages) {
          _upsertMessage(message);
        }
        _sortMessages();
      });
      await _markAsRead(_messages);
    } catch (e) {
      debugPrint('Teacher chat fallback poll failed: $e');
    }
  }

  Future<void> _markAsRead(List<Map<String, dynamic>> messages) async {
    if (messages.isEmpty) return;
    final chatId = _chatId;
    final lastMessageId = messages.last['id']?.toString();
    if (chatId == null || lastMessageId == null || lastMessageId.isEmpty) {
      return;
    }

    await widget.messenger.markRead(chatId, lastReadMessageId: lastMessageId);
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

  void _sortMessages() {
    _messages.sort((a, b) {
      final left =
          DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final right =
          DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return left.compareTo(right);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    try {
      final chatId = await _ensureChatId();
      final message = await widget.messenger.sendMessage(chatId, content: text);
      if (!mounted) return;
      setState(() => _messages.add(message));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка отправки: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  void dispose() {
    _fallbackPollTimer?.cancel();
    final chatId = _chatId;
    if (chatId != null) _realtime?.leaveRoom(chatId);
    _realtime?.disconnect();
    _realtime?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Назад',
                onPressed: widget.onBack,
              ),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primaryGold.withAlpha(30),
                child: Text(
                  widget.contactName.isNotEmpty ? widget.contactName[0] : '?',
                  style: const TextStyle(
                    color: AppTheme.primaryGold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.contactName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryGold),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final message = _messages[i];
                    final isMe = message['sender_id'] == widget.currentUserId;
                    final createdAt = message['created_at']?.toString();
                    final dt = DateTime.tryParse(createdAt ?? '');
                    final time = dt != null
                        ? DateFormat('HH:mm', 'ru').format(dt.toLocal())
                        : '';
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.72,
                        ),
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
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              message['content']?.toString() ?? '',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withAlpha(120),
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
                                        : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withAlpha(120),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'Сообщение...'),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.send_rounded,
                  color: AppTheme.primaryGold,
                ),
                tooltip: 'Отправить',
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
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
    'reply_to_id': item['replyToId'],
    'forwarded_from_id': item['forwardedFromId'],
    'pinned_by': item['pinnedBy'],
    'pinned_at': item['pinnedAt'],
    'created_at': item['createdAt'],
    'updated_at': item['updatedAt'],
    'deleted_at': item['deletedAt'],
    'is_read':
        item['isRead'] == true ||
        item['is_read'] == true ||
        item['read'] == true,
    'profiles': {
      'id': senderMap['id'],
      'first_name': senderMap['firstName'],
      'last_name': senderMap['lastName'],
    },
  };
}
