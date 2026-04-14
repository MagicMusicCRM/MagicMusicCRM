import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/services/supa_message_service.dart';

class TeacherChatWidget extends StatefulWidget {
  const TeacherChatWidget({super.key});

  @override
  State<TeacherChatWidget> createState() => _TeacherChatWidgetState();
}

class _TeacherChatWidgetState extends State<TeacherChatWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _contacts = [];
  Map<String, int> _unreadCounts = {};
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribe();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final contactsRes = await _supabase
          .from('v_teacher_students')
          .select('student_profile_id, first_name, last_name')
          .eq('teacher_profile_id', userId);
          
      final uniqueContacts = <String, Map<String, dynamic>>{};
      for (final s in contactsRes) {
        final id = s['student_profile_id']?.toString();
        if (id != null) {
          uniqueContacts[id] = {
            'id': id,
            'name': '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim(),
          };
        }
      }

      final unreadRes = await _supabase.from('messages')
          .select('sender_id')
          .eq('receiver_id', userId)
          .eq('is_read', false);
          
      final counts = <String, int>{};
      for (final m in unreadRes) {
        final sender = m['sender_id']?.toString() ?? '';
        counts[sender] = (counts[sender] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _contacts = uniqueContacts.values.toList();
          _unreadCounts = counts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribe() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _channel = _supabase.channel('public:messages_teacher_$userId');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        final newMsg = payload.newRecord;
        if (newMsg['receiver_id'] == userId && newMsg['is_read'] == false) {
          final sender = newMsg['sender_id']?.toString() ?? '';
          if (_selectedContactId != sender) {
            if (mounted) {
              setState(() {
                _unreadCounts[sender] = (_unreadCounts[sender] ?? 0) + 1;
              });
            }
          }
        }
      },
    ).subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  String? _selectedContactId;
  String? _selectedContactName;

  @override
  Widget build(BuildContext context) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const Center(child: Text('Пожалуйста, войдите в систему'));

    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));

    if (_selectedContactId != null) {
      return _ChatView(
        currentUserId: userId,
        contactId: _selectedContactId!,
        contactName: _selectedContactName ?? '',
        onBack: () => setState(() {
          _selectedContactId = null;
          _selectedContactName = null;
          // Refresh data slightly to catch unread changes
          _loadData(); 
        }),
      );
    }

    if (_contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80)),
            const SizedBox(height: 16),
            Text('Нет прикрепленных учеников', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _contacts.length,
      itemBuilder: (context, i) {
        final c = _contacts[i];
        final id = c['id'] as String;
        final name = c['name'] as String;
        final unreadCount = _unreadCounts[id] ?? 0;
        
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryPurple.withAlpha(30),
            child: Text(name.isNotEmpty ? name[0] : '?',
                style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700)),
          ),
          title: Text(name.isEmpty ? 'Безымянный ученик' : name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                  child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
  final VoidCallback onBack;
  const _ChatView({
    required this.currentUserId,
    required this.contactId,
    required this.contactName,
    required this.onBack,
  });

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _supabase = Supabase.instance.client;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribe();
  }

  Future<void> _loadMessages() async {
    try {
      final res = await _supabase
          .from('messages')
          .select()
          .or('sender_id.eq.${widget.currentUserId},receiver_id.eq.${widget.currentUserId}')
          .order('created_at', ascending: true)
          .limit(200);
      
      if (mounted) {
        setState(() {
          // Filter to just this conversation
          _messages = List<Map<String, dynamic>>.from(res).where((m) =>
            (m['sender_id'] == widget.currentUserId && m['receiver_id'] == widget.contactId) ||
            (m['sender_id'] == widget.contactId && m['receiver_id'] == widget.currentUserId)
          ).toList();
          _loading = false;
        });
        _scrollToBottom();
        _markAsRead(_messages);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribe() {
    _channel = _supabase.channel('public:messages_individual_teacher');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        final m = payload.newRecord;
        if ((m['sender_id'] == widget.currentUserId && m['receiver_id'] == widget.contactId) ||
            (m['sender_id'] == widget.contactId && m['receiver_id'] == widget.currentUserId)) {
          if (mounted) {
            setState(() => _messages.add(m));
            _scrollToBottom();
            _markAsRead([m]);
          }
        }
      },
    ).subscribe();
  }

  Future<void> _markAsRead(List<Map<String, dynamic>> messages) async {
    final unreadIds = messages
        .where((m) => m['receiver_id'] == widget.currentUserId && m['is_read'] == false)
        .map((m) => m['id'] as String)
        .toList();

    if (unreadIds.isNotEmpty) {
      await SupaMessageService.markIdsAsRead(unreadIds);
      if (mounted) {
        setState(() {
          for (final mid in unreadIds) {
            final idx = _messages.indexWhere((msg) => msg['id'] == mid);
            if (idx != -1) _messages[idx]['is_read'] = true;
          }
        });
      }
    }

    // Sync with DB
    await SupaMessageService.markMessagesAsRead(
      currentUserId: widget.currentUserId,
      chatId: widget.contactId,
      chatType: 'direct',
      isStaff: true, // Teachers are staff
    );
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    
    try {
      await _supabase.from('messages').insert({
        'sender_id': widget.currentUserId,
        'receiver_id': widget.contactId,
        'content': text,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
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
              IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: widget.onBack),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primaryPurple.withAlpha(30),
                child: Text(widget.contactName.isNotEmpty ? widget.contactName[0] : '?',
                    style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Text(widget.contactName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[i];
                    final isMe = m['sender_id'] == widget.currentUserId;
                    final dt = DateTime.tryParse(m['created_at'] ?? '');
                    final time = dt != null ? DateFormat('HH:mm').format(dt.toLocal()) : '';
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        decoration: BoxDecoration(
                          color: isMe ? AppTheme.primaryPurple : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Text(m['content'] ?? '', style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(time, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withAlpha(120))),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    m['is_read'] == true ? Icons.done_all : Icons.done,
                                    size: 12,
                                    color: m['is_read'] == true ? AppTheme.success : Theme.of(context).colorScheme.onSurface.withAlpha(120),
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
                icon: const Icon(Icons.send_rounded, color: AppTheme.primaryPurple),
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
