import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class TeacherChatWidget extends StatefulWidget {
  const TeacherChatWidget({super.key});

  @override
  State<TeacherChatWidget> createState() => _TeacherChatWidgetState();
}

class _TeacherChatWidgetState extends State<TeacherChatWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = true;
  String? _selectedContactId;
  String? _selectedContactName;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Get unique people who've exchanged messages with this teacher
      final sent = await _supabase
          .from('messages')
          .select('receiver_id, profiles!messages_receiver_id_fkey(id, first_name, last_name)')
          .eq('sender_id', userId);
      final received = await _supabase
          .from('messages')
          .select('sender_id, profiles!messages_sender_id_fkey(id, first_name, last_name)')
          .eq('receiver_id', userId);

      final seen = <String>{};
      final contacts = <Map<String, dynamic>>[];

      for (final m in sent) {
        final p = m['profiles'] as Map<String, dynamic>?;
        if (p != null && p['id'] != userId && seen.add(p['id'] as String)) {
          contacts.add(p);
        }
      }
      for (final m in received) {
        final p = m['profiles'] as Map<String, dynamic>?;
        if (p != null && p['id'] != userId && seen.add(p['id'] as String)) {
          contacts.add(p);
        }
      }

      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));
    }

    if (_selectedContactId != null) {
      return _ChatView(
        currentUserId: _supabase.auth.currentUser!.id,
        contactId: _selectedContactId!,
        contactName: _selectedContactName ?? '',
        onBack: () => setState(() {
          _selectedContactId = null;
          _selectedContactName = null;
        }),
      );
    }

    if (_contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 64, color: AppTheme.textSecondary.withAlpha(80)),
            const SizedBox(height: 16),
            const Text('Нет сообщений', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Переписка появится после первых сообщений', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _contacts.length,
      itemBuilder: (context, i) {
        final c = _contacts[i];
        final name = '${c['first_name'] ?? ''} ${c['last_name'] ?? ''}'.trim();
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryPurple.withAlpha(30),
            child: Text(name.isNotEmpty ? name[0] : '?',
                style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700)),
          ),
          title: Text(name.isEmpty ? 'Пользователь' : name),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
          onTap: () => setState(() {
            _selectedContactId = c['id'] as String;
            _selectedContactName = name;
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

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((data) {
          if (!mounted) return;
          final filtered = data.where((m) =>
            (m['sender_id'] == widget.currentUserId && m['receiver_id'] == widget.contactId) ||
            (m['sender_id'] == widget.contactId && m['receiver_id'] == widget.currentUserId)
          ).toList();
          setState(() {
            _messages = List<Map<String, dynamic>>.from(filtered);
            _loading = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(_scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            }
          });
        });
  }

  Future<void> _loadMessages() async {
    final data = await _supabase.from('messages').select()
        .or('and(sender_id.eq.${widget.currentUserId},receiver_id.eq.${widget.contactId}),and(sender_id.eq.${widget.contactId},receiver_id.eq.${widget.currentUserId})')
        .order('created_at');
    if (mounted) {
      setState(() {
        _messages = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await _supabase.from('messages').insert({
      'sender_id': widget.currentUserId,
      'receiver_id': widget.contactId,
      'content': text,
    });
  }

  @override
  void dispose() {
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
          color: AppTheme.surfaceDark,
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
                          color: isMe ? AppTheme.primaryPurple : AppTheme.cardDark,
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
                            Text(time, style: TextStyle(fontSize: 10, color: AppTheme.textPrimary.withAlpha(120))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: AppTheme.surfaceDark,
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
