import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/widgets/voice_recorder_widget.dart';
import 'package:magic_music_crm/core/widgets/voice_player_widget.dart';
import 'package:magic_music_crm/core/widgets/file_attachment_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

class ChatWidget extends StatefulWidget {
  final String currentUserId;
  const ChatWidget({super.key, required this.currentUserId});

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  
  String? _selectedReceiverId; // null = Admin/School
  String _selectedName = 'Администрация';
  
  List<Map<String, dynamic>> _teachersList = [];
  List<String> _adminIds = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, int> _unreadCounts = {};
  
  bool _loading = true;
  bool _isRecording = false;
  bool _isSendingFile = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribe();
  }

  Future<void> _loadData() async {
    try {
      final studentRes = await _supabase.from('students').select('id').eq('profile_id', widget.currentUserId).maybeSingle();
      final studentId = studentRes?['id'] as String? ?? '';
      if (studentId.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final teachersRes = await _supabase
          .from('v_student_teachers')
          .select('teacher_profile_id, first_name, last_name, teacher_id')
          .eq('student_profile_id', widget.currentUserId);
          
      final now = DateTime.now();
      final todayStr = DateTime(now.year, now.month, now.day).toIso8601String();
      
      final activeLessonsRes = await _supabase
          .from('lessons')
          .select('teacher_id')
          .eq('student_id', studentId)
          .eq('status', 'planned')
          .gte('scheduled_at', todayStr);
          
      final activeGroupsRes = await _supabase
          .from('groups')
          .select('teacher_id, group_students!inner(student_id)')
          .eq('group_students.student_id', studentId);
          
      final activeTeacherIds = <String>{};
      for (final l in activeLessonsRes as List) {
        if (l['teacher_id'] != null) activeTeacherIds.add(l['teacher_id'].toString());
      }
      for (final g in activeGroupsRes as List) {
        if (g['teacher_id'] != null) activeTeacherIds.add(g['teacher_id'].toString());
      }
      
      final uniqueTeachers = <String, Map<String, dynamic>>{};
      for (final t in teachersRes) {
        final profileId = t['teacher_profile_id']?.toString();
        final tid = t['teacher_id']?.toString();
        
        if (profileId != null && activeTeacherIds.contains(tid)) {
          uniqueTeachers[profileId] = {
            'id': profileId,
            'name': '${t['first_name'] ?? ''} ${t['last_name'] ?? ''}'.trim(),
          };
        }
      }

      final adminsRes = await _supabase
          .from('profiles')
          .select('id')
          .filter('role', 'in', ['admin', 'manager']);
          
      final adminIds = (adminsRes as List).map((a) => a['id'].toString()).toList();

      final unreadRes = await _supabase.from('messages')
          .select('sender_id')
          .eq('receiver_id', widget.currentUserId)
          .eq('is_read', false);
          
      final counts = <String, int>{};
      for (final m in unreadRes) {
        final sender = m['sender_id']?.toString() ?? 'school';
        counts[sender] = (counts[sender] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _teachersList = uniqueTeachers.values.toList();
          _adminIds = adminIds;
          _unreadCounts = counts;
        });
        await _loadMessages();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final res = await _supabase
          .from('messages')
          .select()
          .or('sender_id.eq.${widget.currentUserId},receiver_id.eq.${widget.currentUserId}')
          .order('created_at', ascending: true)
          .limit(200);
      
      if (mounted) {
        setState(() {
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
    _channel = _supabase.channel('public:messages_client_${widget.currentUserId}');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        final m = payload.newRecord;
        if (m['sender_id'] == widget.currentUserId || m['receiver_id'] == widget.currentUserId) {
          if (mounted) {
            setState(() {
              _messages.add(m);
              
              if (m['receiver_id'] == widget.currentUserId && m['is_read'] == false) {
                 final sender = m['sender_id']?.toString() ?? 'school';
                 if (_selectedReceiverId != m['sender_id']) {
                   _unreadCounts[sender] = (_unreadCounts[sender] ?? 0) + 1;
                 } else {
                   _markAsRead([m]);
                 }
              }
            });
            _scrollToBottom();
          }
        }
      },
    ).subscribe();
  }

  Future<void> _markAsRead(List<Map<String, dynamic>> messages) async {
    final unreadIds = messages.where((m) {
      final isToMe = m['receiver_id'] == widget.currentUserId;
      final isFromActive = _selectedReceiverId == null 
          ? (m['sender_id'] == null || _adminIds.contains(m['sender_id']))
          : m['sender_id'] == _selectedReceiverId;
      return isToMe && isFromActive && m['is_read'] == false;
    }).map((m) => m['id'] as String).toList();

    if (unreadIds.isNotEmpty) {
      await _supabase
          .from('messages')
          .update({'is_read': true, 'read_at': DateTime.now().toIso8601String()})
          .filter('id', 'in', unreadIds);
          
      final senderKey = _selectedReceiverId ?? 'school';
      if (mounted) {
        setState(() {
          _unreadCounts[senderKey] = 0;
        });
      }
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    
    try {
      await _supabase.from('messages').insert({
        'sender_id': widget.currentUserId,
        'content': text,
        'receiver_id': _selectedReceiverId,
        'message_type': 'text',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при отправке: $e', style: const TextStyle(color: Colors.white)), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _sendVoice(Uint8List bytes, int durationMs, String extension) async {
    try {
      final url = await ChatAttachmentService.uploadVoice(
        bytes: bytes,
        senderId: widget.currentUserId,
        extension: extension,
      );

      await _supabase.from('messages').insert({
        'sender_id': widget.currentUserId,
        'receiver_id': _selectedReceiverId,
        'content': '🎤 Голосовое сообщение',
        'message_type': 'voice',
        'attachment_url': url,
        'attachment_size': bytes.length,
        'voice_duration_ms': durationMs,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки голосового: $e', style: const TextStyle(color: Colors.white)), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

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

      final url = await ChatAttachmentService.uploadFile(
        bytes: file.bytes!,
        originalFileName: file.name,
        senderId: widget.currentUserId,
      );

      await _supabase.from('messages').insert({
        'sender_id': widget.currentUserId,
        'receiver_id': _selectedReceiverId,
        'content': '📎 ${file.name}',
        'message_type': 'file',
        'attachment_url': url,
        'attachment_name': file.name,
        'attachment_size': file.size,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки файла: $e', style: const TextStyle(color: Colors.white)), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingFile = false);
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));
    }

    // Filter messages for current active chat
    final activeMessages = _messages.where((m) {
      final isFromMe = m['sender_id'] == widget.currentUserId;
      final isToMe = m['receiver_id'] == widget.currentUserId;
      if (_selectedReceiverId == null) {
        final isFromAdmin = m['sender_id'] != null && _adminIds.contains(m['sender_id']);
        return (isFromMe && m['receiver_id'] == null) || (isToMe && (m['sender_id'] == null || isFromAdmin));
      } else {
        return (isFromMe && m['receiver_id'] == _selectedReceiverId) || 
               (isToMe && m['sender_id'] == _selectedReceiverId);
      }
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            children: [
              Text('Кому:', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedReceiverId,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    items: [
                      DropdownMenuItem(
                        value: null, 
                        child: Row(
                          children: [
                            const Text('Школа (Админ)'),
                            if ((_unreadCounts['school'] ?? 0) > 0) ...[
                              const SizedBox(width: 8),
                              Badge(label: Text('${_unreadCounts['school']}')),
                            ],
                          ],
                        )
                      ),
                      ..._teachersList.map((t) {
                        final tid = t['id'] as String;
                        final count = _unreadCounts[tid] ?? 0;
                        return DropdownMenuItem(
                          value: tid,
                          child: Row(
                            children: [
                              Text(t['name'] as String),
                              if (count > 0) ...[
                                const SizedBox(width: 8),
                                Badge(label: Text('$count')),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedReceiverId = val;
                        if (val == null) {
                          _selectedName = 'Администрация';
                        } else {
                          _selectedName = _teachersList.firstWhere((t) => t['id'] == val)['name'] as String;
                        }
                      });
                      _markAsRead(_messages);
                      _scrollToBottom();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: activeMessages.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80)),
                    const SizedBox(height: 16),
                    Text('Напишите в $_selectedName\nесли у вас есть вопросы', 
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: activeMessages.length,
                itemBuilder: (context, index) {
                  final message = activeMessages[index];
                  final isMe = message['sender_id'] == widget.currentUserId;
                  
                  return _MessageBubble(
                    message: message, 
                    isMe: isMe,
                    senderName: isMe ? 'Я' : (_selectedReceiverId == null ? 'Администрация' : _selectedName),
                  );
                },
              ),
        ),
        // Input area: voice recorder OR text+buttons
        if (_isRecording)
          VoiceRecorderWidget(
            onVoiceRecorded: (bytes, durationMs, ext) async {
              await _sendVoice(bytes, durationMs, ext);
            },
            onCancel: () {
              if (mounted) setState(() => _isRecording = false);
            },
          )
        else
          Container(
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryPurple),
                          )
                        : Icon(Icons.attach_file_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    tooltip: 'Прикрепить файл',
                    onPressed: _isSendingFile ? null : _pickAndSendFile,
                  ),
                  // Text field
                  Expanded(
                    child: TextField(
                      controller: _messageController,
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
                      onSubmitted: (_) => _sendMessage(),
                      onChanged: (_) => setState(() {}), // rebuild to toggle mic/send
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Mic button (when text field empty) or Send button
                  Container(
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryPurple,
                      shape: BoxShape.circle,
                    ),
                    child: _messageController.text.trim().isEmpty
                        ? IconButton(
                            icon: const Icon(Icons.mic_rounded, color: Colors.white),
                            tooltip: 'Голосовое сообщение',
                            onPressed: () => setState(() => _isRecording = true),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send_rounded, color: Colors.white),
                            onPressed: _sendMessage,
                          ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
    final dt = DateTime.tryParse(message['created_at'] ?? '');
    final timeStr = dt != null ? DateFormat('HH:mm', 'ru').format(dt.toLocal()) : '';
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
            // Less padding for images
            padding: isImageFile
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isMe ? AppTheme.primaryPurple : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
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
