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
  late final Stream<List<Map<String, dynamic>>> _contactsStream;

  @override
  void initState() {
    super.initState();
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      _contactsStream = _supabase
          .from('messages')
          .stream(primaryKey: ['id'])
          .map((data) {
            final seen = <String>{};
            final contacts = <Map<String, dynamic>>[];
            
            // Collect unique chat partners
            for (final m in data) {
              final String? otherId = m['sender_id'] == userId ? m['receiver_id'] : m['sender_id'];
              if (otherId != null && otherId != userId && seen.add(otherId)) {
                // We'll need profiles for these IDs. In a stream, we can't easily join.
                // For now, we'll store the IDs and load profile info separately or use a view.
                contacts.add({'id': otherId});
              }
            }
            return contacts;
          });
    }
  }

  // Helper to load profile info for a list of IDs
  Future<Map<String, dynamic>> _getProfile(String id) async {
    final res = await _supabase.from('profiles').select().eq('id', id).single();
    return res;
  }

  // Helper to get unread count for a contact
  Stream<int> _unreadCountStream(String contactId) {
    final userId = _supabase.auth.currentUser?.id;
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .map((data) => data.where((m) => 
            m['sender_id'] == contactId && 
            m['receiver_id'] == userId && 
            m['is_read'] == false
        ).length);
  }

  String? _selectedContactId;
  String? _selectedContactName;

  @override
  Widget build(BuildContext context) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const Center(child: Text('Пожалуйста, войдите в систему'));

    if (_selectedContactId != null) {
      return _ChatView(
        currentUserId: userId,
        contactId: _selectedContactId!,
        contactName: _selectedContactName ?? '',
        onBack: () => setState(() {
          _selectedContactId = null;
          _selectedContactName = null;
        }),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _contactsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));
        }
        
        final contacts = snapshot.data ?? [];

        if (contacts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 64, color: AppTheme.textSecondary.withAlpha(80)),
                const SizedBox(height: 16),
                const Text('Нет сообщений', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: contacts.length,
          itemBuilder: (context, i) {
            final c = contacts[i];
            return FutureBuilder<Map<String, dynamic>>(
              future: _getProfile(c['id']),
              builder: (context, profSnap) {
                if (!profSnap.hasData) return const SizedBox.shrink();
                final p = profSnap.data!;
                final name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
                
                return StreamBuilder<int>(
                  stream: _unreadCountStream(c['id']),
                  builder: (context, unreadSnap) {
                    final unreadCount = unreadSnap.data ?? 0;
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryPurple.withAlpha(30),
                        child: Text(name.isNotEmpty ? name[0] : '?',
                            style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700)),
                      ),
                      title: Text(name.isEmpty ? 'Пользователь' : name),
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
                          const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                        ],
                      ),
                      onTap: () => setState(() {
                        _selectedContactId = c['id'] as String;
                        _selectedContactName = name;
                      }),
                    );
                  }
                );
              },
            );
          },
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
    _messagesStream();
  }

  void _messagesStream() {
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

          // Mark incoming as read
          _markAsRead();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        });
  }

  Future<void> _markAsRead() async {
    final unreadIds = _messages
        .where((m) => m['receiver_id'] == widget.currentUserId && m['is_read'] == false)
        .map((m) => m['id'] as String)
        .toList();

    if (unreadIds.isNotEmpty) {
      await _supabase
          .from('messages')
          .update({'is_read': true, 'read_at': DateTime.now().toIso8601String()})
          .filter('id', 'in', unreadIds);
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
