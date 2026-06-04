import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/widgets/voice_recorder_widget.dart';
import 'package:magic_music_crm/core/widgets/voice_player_widget.dart';
import 'package:magic_music_crm/core/widgets/file_attachment_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/broadcast_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

class AdminChatDashboard extends StatefulWidget {
  const AdminChatDashboard({super.key});

  @override
  State<AdminChatDashboard> createState() => _AdminChatDashboardState();
}

class _AdminChatDashboardState extends State<AdminChatDashboard> {
  String? _selectedStudentId;
  String? _selectedStudentName;
  bool _showSchoolInbox = true;

  @override
  Widget build(BuildContext context) {
    if (_selectedStudentId != null) {
      return _IndividualChatView(
        studentProfileId: _selectedStudentId!,
        studentName: _selectedStudentName ?? 'Ученик',
        onBack: () => setState(() => _selectedStudentId = null),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true, 
                      label: Text('Общий (В школу)'), 
                      icon: Icon(Icons.school_rounded)
                    ),
                    ButtonSegment(
                      value: false, 
                      label: Text('Личные чаты'), 
                      icon: Icon(Icons.person_rounded)
                    ),
                  ],
                  selected: {_showSchoolInbox},
                  onSelectionChanged: (val) => setState(() => _showSchoolInbox = val.first),
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
          child: _showSchoolInbox ? const _SchoolInbox() : _StudentChatList(
            onChatSelected: (id, name) => setState(() {
              _selectedStudentId = id;
              _selectedStudentName = name;
            }),
          ),
        ),
      ],
    );
  }
}

class _SchoolInbox extends StatefulWidget {
  const _SchoolInbox();

  @override
  State<_SchoolInbox> createState() => _SchoolInboxState();
}

class _SchoolInboxState extends State<_SchoolInbox> {
  final _supabase = Supabase.instance.client;
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
          .filter('receiver_id', 'is', null)
          .order('created_at', ascending: true)
          .limit(100);
      
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(res);
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribe() {
    _channel = _supabase.channel('public:messages_school');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        final newMsg = payload.newRecord;
        if (newMsg['receiver_id'] == null) {
          if (mounted) {
            setState(() => _messages.add(newMsg));
            _scrollToBottom();
          }
        }
      },
    ).subscribe();
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

  @override
  void dispose() {
    _channel?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = _supabase.auth.currentUser?.id;
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final m = _messages[i];
              final isMe = m['sender_id'] == userId;
              return _MessageBubble(message: m, isMe: isMe, senderName: isMe ? 'Администрация' : 'Клиент');
            },
          ),
        ),
        _MessageInputWithAttachments(
          onSend: (text) async {
            await _supabase.from('messages').insert({
              'sender_id': userId,
              'content': text,
              'receiver_id': null,
              'message_type': 'text',
            });
          },
          onSendVoice: (bytes, durationMs, ext) async {
            final url = await ChatAttachmentService.uploadVoice(
              bytes: bytes,
              senderId: userId!,
              extension: ext,
            );
            await _supabase.from('messages').insert({
              'sender_id': userId,
              'receiver_id': null,
              'content': '🎤 Голосовое сообщение',
              'message_type': 'voice',
              'attachment_url': url,
              'attachment_size': bytes.length,
              'voice_duration_ms': durationMs,
            });
          },
          onSendFile: (bytes, fileName, fileSize) async {
            final url = await ChatAttachmentService.uploadFile(
              bytes: bytes,
              originalFileName: fileName,
              senderId: userId!,
            );
            await _supabase.from('messages').insert({
              'sender_id': userId,
              'receiver_id': null,
              'content': '📎 $fileName',
              'message_type': 'file',
              'attachment_url': url,
              'attachment_name': fileName,
              'attachment_size': fileSize,
            });
          },
        ),
      ],
    );
  }
}

class _StudentChatList extends StatefulWidget {
  final Function(String, String) onChatSelected;
  const _StudentChatList({required this.onChatSelected});

  @override
  State<_StudentChatList> createState() => _StudentChatListState();
}

class _StudentChatListState extends State<_StudentChatList> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _students = [];
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
    try {
      final studentsRes = await _supabase.from('profiles').select().eq('role', 'client');
      
      final unreadRes = await _supabase.from('messages')
          .select('sender_id, receiver_id')
          .eq('is_read', false);
          
      final userId = _supabase.auth.currentUser?.id;
      final counts = <String, int>{};
      
      for (final m in unreadRes) {
        final sender = m['sender_id']?.toString() ?? '';
        final receiver = m['receiver_id']?.toString();
        if (receiver == null || receiver == userId) {
          counts[sender] = (counts[sender] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(studentsRes);
          _unreadCounts = counts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribe() {
    _channel = _supabase.channel('public:messages_unread');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        final newMsg = payload.newRecord;
        if (newMsg['is_read'] == false) {
          final userId = _supabase.auth.currentUser?.id;
          final receiver = newMsg['receiver_id']?.toString();
          if (receiver == null || receiver == userId) {
            final sender = newMsg['sender_id']?.toString() ?? '';
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView.builder(
      itemCount: _students.length,
      itemBuilder: (context, i) {
        final s = _students[i];
        final id = s['id'].toString();
        final name = '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim();
        final count = _unreadCounts[id] ?? 0;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryGold.withAlpha(40),
            child: Text(
              name.isNotEmpty ? name[0] : '?', 
              style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)
            ),
          ),
          title: Text(name.isEmpty ? 'Ученик' : name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(s['phone'] ?? '', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count > 0) 
                Badge(
                  label: Text('$count'),
                  backgroundColor: AppTheme.primaryGold,
                ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
          onTap: () {
            widget.onChatSelected(id, name);
            setState(() => _unreadCounts[id] = 0);
          },
        );
      },
    );
  }
}

class _IndividualChatView extends StatefulWidget {
  final String studentProfileId;
  final String studentName;
  final VoidCallback onBack;
  const _IndividualChatView({required this.studentProfileId, required this.studentName, required this.onBack});

  @override
  State<_IndividualChatView> createState() => _IndividualChatViewState();
}

class _IndividualChatViewState extends State<_IndividualChatView> {
  final _supabase = Supabase.instance.client;
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  List<String> _adminIds = [];
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
      final adminsRes = await _supabase.from('profiles').select('id').filter('role', 'in', ['admin', 'manager']);
      final adminIds = (adminsRes as List).map((a) => a['id'].toString()).toList();

      final res = await _supabase
          .from('messages')
          .select()
          .or('sender_id.eq.${widget.studentProfileId},receiver_id.eq.${widget.studentProfileId}')
          .order('created_at', ascending: true)
          .limit(100);
          
      if (mounted) {
        setState(() {
          _adminIds = adminIds;
          _messages = List<Map<String, dynamic>>.from(res);
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
    _channel = _supabase.channel('public:messages_individual');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        final m = payload.newRecord;
        if (m['sender_id'] == widget.studentProfileId || m['receiver_id'] == widget.studentProfileId) {
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
    final userId = _supabase.auth.currentUser?.id;
    final unreadIds = messages
        .where((m) => (m['receiver_id'] == userId || m['receiver_id'] == null) && m['is_read'] == false)
        .map((m) => m['id'] as String)
        .toList();

    if (unreadIds.isNotEmpty) {
      await _supabase
          .from('messages')
          .update({'is_read': true, 'read_at': DateTime.now().toIso8601String()})
          .filter('id', 'in', unreadIds);
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

  @override
  void dispose() {
    _channel?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Column(
        children: [
          AppBar(
            title: Text(widget.studentName),
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
          ),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    final userId = _supabase.auth.currentUser?.id;

    // Filter messages to only show those between student and any admin, or to/from school (null)
    final filteredMessages = _messages.where((m) {
      final isFromStudent = m['sender_id'] == widget.studentProfileId;
      final isToStudent = m['receiver_id'] == widget.studentProfileId;
      
      if (isFromStudent) {
        return m['receiver_id'] == null || _adminIds.contains(m['receiver_id']);
      } else if (isToStudent) {
        return m['sender_id'] == null || _adminIds.contains(m['sender_id']);
      }
      return false;
    }).toList();

    return Column(
      children: [
        AppBar(
          title: Text(widget.studentName),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: filteredMessages.length,
            itemBuilder: (context, i) {
              final m = filteredMessages[i];
              final isMe = m['sender_id'] == userId;
              return _MessageBubble(message: m, isMe: isMe, senderName: isMe ? 'Я (Админ)' : widget.studentName);
            },
          ),
        ),
        _MessageInputWithAttachments(
          onSend: (text) async {
            await _supabase.from('messages').insert({
              'sender_id': userId,
              'content': text,
              'receiver_id': widget.studentProfileId,
              'message_type': 'text',
            });
          },
          onSendVoice: (bytes, durationMs, ext) async {
            final url = await ChatAttachmentService.uploadVoice(
              bytes: bytes,
              senderId: userId!,
              extension: ext,
            );
            await _supabase.from('messages').insert({
              'sender_id': userId,
              'receiver_id': widget.studentProfileId,
              'content': '🎤 Голосовое сообщение',
              'message_type': 'voice',
              'attachment_url': url,
              'attachment_size': bytes.length,
              'voice_duration_ms': durationMs,
            });
          },
          onSendFile: (bytes, fileName, fileSize) async {
            final url = await ChatAttachmentService.uploadFile(
              bytes: bytes,
              originalFileName: fileName,
              senderId: userId!,
            );
            await _supabase.from('messages').insert({
              'sender_id': userId,
              'receiver_id': widget.studentProfileId,
              'content': '📎 $fileName',
              'message_type': 'file',
              'attachment_url': url,
              'attachment_name': fileName,
              'attachment_size': fileSize,
            });
          },
        ),
      ],
    );
  }
}

// ── Shared Widgets ──────────────────────────────────────────────────────────

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
    final dt = DateTime.tryParse(message['created_at'] ?? '');
    final timeStr = dt != null ? DateFormat('HH:mm').format(dt.toLocal()) : '';
    final messageType = message['message_type']?.toString() ?? 'text';
    final isImageFile = messageType == 'file' && 
        FileAttachmentWidget.isImage(message['attachment_name']?.toString());

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                senderName,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: isImageFile
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isMe ? AppTheme.primaryGold : Theme.of(context).colorScheme.surface,
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
                // Content based on message type
                if (messageType == 'voice')
                  SizedBox(
                    width: 220,
                    child: VoicePlayerWidget(
                      audioUrl: message['attachment_url'] ?? '',
                      durationMs: message['voice_duration_ms'] as int?,
                      isMe: isMe,
                    ),
                  )
                else if (messageType == 'file')
                  FileAttachmentWidget(
                    fileName: message['attachment_name']?.toString(),
                    fileUrl: message['attachment_url']?.toString(),
                    fileSize: message['attachment_size'] as int?,
                    isMe: isMe,
                  )
                else
                  Text(
                    message['content'] ?? '',
                    style: TextStyle(
                      color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
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
                        color: isMe ? Colors.white.withAlpha(180) : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message['is_read'] == true ? Icons.done_all : Icons.done,
                        size: 12,
                        color: message['is_read'] == true ? AppTheme.success : Colors.white.withAlpha(180),
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

/// Unified message input widget with text, file attachment, and voice recording support.
class _MessageInputWithAttachments extends StatefulWidget {
  final Future<void> Function(String text) onSend;
  final Future<void> Function(Uint8List bytes, int durationMs, String extension) onSendVoice;
  final Future<void> Function(Uint8List bytes, String fileName, int fileSize) onSendFile;
  
  const _MessageInputWithAttachments({
    required this.onSend,
    required this.onSendVoice,
    required this.onSendFile,
  });

  @override
  State<_MessageInputWithAttachments> createState() => _MessageInputWithAttachmentsState();
}

class _MessageInputWithAttachmentsState extends State<_MessageInputWithAttachments> {
  final _controller = TextEditingController();
  bool _isRecording = false;
  bool _isSendingFile = false;

  Future<void> _pickAndSendFile() async {
    if (_isSendingFile) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось прочитать файл', style: TextStyle(color: Colors.white)),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
        return;
      }

      if (file.size > ChatAttachmentService.maxFileSizeBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Файл слишком большой (макс. 25 МБ)', style: TextStyle(color: Colors.white)),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
        return;
      }

      setState(() => _isSendingFile = true);
      await widget.onSendFile(file.bytes!, file.name, file.size);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e', style: const TextStyle(color: Colors.white)), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingFile = false);
    }
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
        onVoiceRecorded: (bytes, durationMs, ext) async {
          await widget.onSendVoice(bytes, durationMs, ext);
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
            // Attach file button
            IconButton(
              icon: _isSendingFile
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryGold),
                    )
                  : Icon(Icons.attach_file_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              tooltip: 'Прикрепить файл',
              onPressed: _isSendingFile ? null : _pickAndSendFile,
            ),
            // Text field
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) {
                  final text = _controller.text.trim();
                  if (text.isNotEmpty) {
                    widget.onSend(text);
                    _controller.clear();
                  }
                },
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            // Mic or Send button
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.primaryGold,
                shape: BoxShape.circle,
              ),
              child: _controller.text.trim().isEmpty
                  ? IconButton(
                      icon: const Icon(Icons.mic_rounded, color: Colors.white),
                      tooltip: 'Голосовое сообщение',
                      onPressed: () => setState(() => _isRecording = true),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                      onPressed: () {
                        final text = _controller.text.trim();
                        if (text.isNotEmpty) {
                          widget.onSend(text);
                          _controller.clear();
                          setState(() {});
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
