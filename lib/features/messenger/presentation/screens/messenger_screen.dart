import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/adaptive_messenger_shell.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_list_tile.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_header.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_search_bar.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_bubble.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_input.dart';
import 'package:magic_music_crm/core/widgets/telegram/date_separator.dart';
import 'package:magic_music_crm/core/widgets/telegram/create_group_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_dialog.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/providers/theme_provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:typed_data';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:magic_music_crm/core/widgets/telegram/send_file_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/user_roles_widget.dart';


/// Unified Telegram-style messenger screen used by all roles.
class MessengerScreen extends ConsumerStatefulWidget {
  final String role; // 'client', 'admin', 'manager', 'teacher'
  const MessengerScreen({super.key, required this.role});

  @override
  ConsumerState<MessengerScreen> createState() => _MessengerScreenState();
}

class _MessengerScreenState extends ConsumerState<MessengerScreen> {
  final _supabase = Supabase.instance.client;
  String? _selectedChatId;
  String? _selectedChatType; // 'direct', 'group', 'channel'
  String? _selectedChatName;
  String? _selectedChatAvatarUrl;

  // Data
  List<Map<String, dynamic>> _chatItems = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, int> _unreadCounts = {};
  List<String> _adminIds = [];
  bool _loadingChats = true;
  bool _loadingMessages = false;
  String _searchQuery = '';
  int _selectedCrmTab = 0;
  bool _showProfilePanel = false;
  bool _showMyProfile = false;

  // Realtime
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _groupMessagesChannel;

  @override
  void initState() {
    super.initState();
    _loadChatList();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    _groupMessagesChannel?.unsubscribe();
    super.dispose();
  }

  String get _userId => _supabase.auth.currentUser?.id ?? '';

  // ── Load chat list ─────────────────────────────────────────────────────────

  Future<void> _loadChatList() async {
    try {
      final items = <Map<String, dynamic>>[];

      // Load admin IDs
      final adminsRes = await _supabase
          .from('profiles')
          .select('id')
          .inFilter('role', ['admin', 'manager']);
      _adminIds = (adminsRes as List).map((a) => a['id'].toString()).toList();

      if (widget.role == 'client') {
        await _loadClientChats(items);
      } else {
        await _loadStaffChats(items);
      }

      // Load group chats for all roles
      await _loadGroupChats(items);

      // Load channels
      await _loadChannels(items);

      // Load unread counts
      await _loadUnreadCounts();

      // Sort: chats first by last message time, then channels
      items.sort((a, b) {
        final aType = a['_item_type'] as String;
        final bType = b['_item_type'] as String;
        // Channels always at bottom
        if (aType == 'channel' && bType != 'channel') return 1;
        if (aType != 'channel' && bType == 'channel') return -1;
        // Sort by last message time
        final aTime = a['_last_message_time'] as String? ?? '';
        final bTime = b['_last_message_time'] as String? ?? '';
        if (aTime.isEmpty && bTime.isEmpty) return 0;
        if (aTime.isEmpty) return 1;
        if (bTime.isEmpty) return -1;
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _chatItems = items;
          _loadingChats = false;

          // Also update selected chat info if it's in the list
          if (_selectedChatId != null) {
            try {
              final selectedItem = items.firstWhere((i) => i['id'] == _selectedChatId);
              _selectedChatName = selectedItem['_display_name'];
              _selectedChatAvatarUrl = _getAvatarUrl(selectedItem);
            } catch (_) {
              // Not found in new list, keep old or deselect
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading chat list: $e');
      if (mounted) setState(() => _loadingChats = false);
    }
  }

  Future<void> _loadClientChats(List<Map<String, dynamic>> items) async {
    // Client sees one "Администрация" chat
    final lastMsg = await _supabase
        .from('messages')
        .select()
        .or('sender_id.eq.$_userId,receiver_id.eq.$_userId')
        .isFilter('group_chat_id', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    items.add({
      'id': 'admin_chat',
      '_item_type': 'direct',
      '_display_name': 'Администрация',
      '_partner_id': null, // Messages to school
      '_last_message': lastMsg,
      '_last_message_time': lastMsg?['created_at'],
      '_icon': Icons.support_agent_rounded,
    });
  }

  Future<void> _loadStaffChats(List<Map<String, dynamic>> items) async {
    // Admin/Manager/Teacher sees individual client conversations
    final clientProfiles = await _supabase
        .from('profiles')
        .select()
        .eq('role', 'client')
        .order('first_name');

    for (final client in clientProfiles) {
      final cid = client['id'] as String;
      final lastMsg = await _supabase
          .from('messages')
          .select()
          .or('and(sender_id.eq.$cid,or(receiver_id.eq.$_userId,receiver_id.is.null)),and(sender_id.eq.$_userId,receiver_id.eq.$cid)')
          .isFilter('group_chat_id', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (lastMsg != null) {
        final name = '${client['first_name'] ?? ''} ${client['last_name'] ?? ''}'.trim();
        items.add({
          'id': cid,
          '_item_type': 'direct',
          '_display_name': name.isEmpty ? 'Ученик' : name,
          '_partner_id': cid,
          '_last_message': lastMsg,
          '_last_message_time': lastMsg['created_at'],
          '_profile': client,
        });
      }
    }
  }

  Future<void> _loadGroupChats(List<Map<String, dynamic>> items) async {
    try {
      final memberships = await _supabase
          .from('group_chat_members')
          .select('group_chat_id')
          .eq('user_id', _userId);

      final groupIds = (memberships as List)
          .map((m) => m['group_chat_id'] as String)
          .toList();

      if (groupIds.isEmpty) return;

      final groups = await _supabase
          .from('group_chats')
          .select()
          .inFilter('id', groupIds);

      for (final group in groups) {
        final gid = group['id'] as String;
        final lastMsg = await _supabase
            .from('messages')
            .select()
            .eq('group_chat_id', gid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        items.add({
          'id': gid,
          '_item_type': 'group',
          '_display_name': group['name'] ?? 'Группа',
          '_last_message': lastMsg,
          '_last_message_time': lastMsg?['created_at'],
          '_group_data': group,
        });
      }
    } catch (e) {
      debugPrint('Error loading group chats: $e');
    }
  }

  Future<void> _loadChannels(List<Map<String, dynamic>> items) async {
    try {
      final channels = await _supabase.from('channels').select();
      for (final ch in channels) {
        final lastPost = await _supabase
            .from('channel_posts')
            .select()
            .eq('channel_id', ch['id'])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        items.add({
          'id': ch['id'],
          '_item_type': 'channel',
          '_display_name': ch['name'] ?? 'Канал',
          '_last_message': lastPost != null
              ? {'content': lastPost['content'], 'created_at': lastPost['created_at']}
              : null,
          '_last_message_time': lastPost?['created_at'],
          '_channel_data': ch,
        });
      }
    } catch (e) {
      debugPrint('Error loading channels: $e');
    }
  }

  Future<void> _loadUnreadCounts() async {
    try {
      final unread = await _supabase
          .from('messages')
          .select('sender_id, group_chat_id')
          .eq('receiver_id', _userId)
          .eq('is_read', false);

      final unreadSchool = await _supabase
          .from('messages')
          .select('sender_id')
          .isFilter('receiver_id', null)
          .eq('is_read', false);

      final counts = <String, int>{};

      for (final m in unread) {
        final gid = m['group_chat_id']?.toString();
        if (gid != null) {
          counts[gid] = (counts[gid] ?? 0) + 1;
        } else {
          final sender = m['sender_id']?.toString() ?? '';
          counts[sender] = (counts[sender] ?? 0) + 1;
        }
      }

      // For client: count school unread
      if (widget.role == 'client') {
        int adminUnread = 0;
        for (final m in unread) {
          if (_adminIds.contains(m['sender_id']?.toString())) {
            adminUnread++;
          }
        }
        counts['admin_chat'] = adminUnread;
      } else {
        // For staff: count per client
        for (final m in unreadSchool) {
          final sender = m['sender_id']?.toString() ?? '';
          if (!_adminIds.contains(sender)) {
            counts[sender] = (counts[sender] ?? 0) + 1;
          }
        }
      }

      if (mounted) setState(() => _unreadCounts = counts);
    } catch (e) {
      debugPrint('Error loading unread counts: $e');
    }
  }

  // ── Load messages for selected chat ────────────────────────────────────────

  Future<void> _loadMessages() async {
    if (_selectedChatId == null) return;
    setState(() => _loadingMessages = true);

    try {
      if (_selectedChatType == 'channel') {
        final posts = await _supabase
            .from('channel_posts')
            .select('*, profiles:author_id(first_name, last_name)')
            .eq('channel_id', _selectedChatId!)
            .order('created_at', ascending: true)
            .limit(500);

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(posts).map((p) => {
              ...p,
              'sender_id': p['author_id'],
              'message_type': p['message_type'] ?? 'text',
              'is_read': true,
            }).toList();
            _loadingMessages = false;
          });
        }
      } else if (_selectedChatType == 'group') {
        final msgs = await _supabase
            .from('messages')
            .select()
            .eq('group_chat_id', _selectedChatId!)
            .order('created_at', ascending: true)
            .limit(500);

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(msgs);
            _loadingMessages = false;
          });
          _markMessagesRead();
        }
      } else {
        // Direct chat
        final chatItem = _chatItems.firstWhere(
          (c) => c['id'] == _selectedChatId,
          orElse: () => {},
        );
        final partnerId = chatItem['_partner_id'] as String?;

        List<dynamic> msgs;
        if (widget.role == 'client') {
          // Client: all messages where I'm sender or receiver, and no group_chat_id
          msgs = await _supabase
              .from('messages')
              .select()
              .or('sender_id.eq.$_userId,receiver_id.eq.$_userId')
              .isFilter('group_chat_id', null)
              .order('created_at', ascending: true)
              .limit(500);

          // Filter to show only admin/school conversations
          msgs = msgs.where((m) {
            final isFromMe = m['sender_id'] == _userId;
            final isToMe = m['receiver_id'] == _userId;
            if (isFromMe) return m['receiver_id'] == null || _adminIds.contains(m['receiver_id']);
            if (isToMe) return m['sender_id'] == null || _adminIds.contains(m['sender_id']);
            return false;
          }).toList();
        } else if (partnerId != null) {
          msgs = await _supabase
              .from('messages')
              .select()
              .or('and(sender_id.eq.$partnerId,or(receiver_id.eq.$_userId,receiver_id.is.null)),and(sender_id.eq.$_userId,receiver_id.eq.$partnerId),and(sender_id.eq.$partnerId,receiver_id.is.null)')
              .isFilter('group_chat_id', null)
              .order('created_at', ascending: true)
              .limit(500);

          // Filter to only show relevant messages
          msgs = msgs.where((m) {
            final isFromPartner = m['sender_id'] == partnerId;
            final isFromMe = m['sender_id'] == _userId;
            if (isFromPartner) {
              return m['receiver_id'] == null || m['receiver_id'] == _userId || _adminIds.contains(m['receiver_id']);
            }
            if (isFromMe) return m['receiver_id'] == partnerId;
            return false;
          }).toList();
        } else {
          msgs = [];
        }

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(msgs);
            _loadingMessages = false;
          });
          _markMessagesRead();
        }
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  Future<void> _markMessagesRead() async {
    try {
      final unreadIds = _messages
          .where((m) =>
              m['receiver_id'] == _userId &&
              m['is_read'] == false)
          .map((m) => m['id'] as String)
          .toList();

      // Also mark school messages (receiver_id null) as read for staff
      if (widget.role != 'client' && _selectedChatType == 'direct') {
        final chatItem = _chatItems.firstWhere(
          (c) => c['id'] == _selectedChatId,
          orElse: () => {},
        );
        final partnerId = chatItem['_partner_id'] as String?;
        if (partnerId != null) {
          final schoolMsgIds = _messages
              .where((m) =>
                  m['sender_id'] == partnerId &&
                  m['receiver_id'] == null &&
                  m['is_read'] == false)
              .map((m) => m['id'] as String)
              .toList();
          unreadIds.addAll(schoolMsgIds);
        }
      }

      if (unreadIds.isNotEmpty) {
        await _supabase
            .from('messages')
            .update({'is_read': true, 'read_at': DateTime.now().toIso8601String()})
            .inFilter('id', unreadIds);

        if (mounted) {
          setState(() {
            _unreadCounts[_selectedChatId!] = 0;
          });
        }
      }
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  // ── Realtime subscription ──────────────────────────────────────────────────

  void _subscribeToMessages() {
    _messagesChannel = _supabase.channel('messenger_$_userId');
    _messagesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        final m = payload.newRecord;
        final senderId = m['sender_id']?.toString();
        final receiverId = m['receiver_id']?.toString();
        final groupChatId = m['group_chat_id']?.toString();

        // Check if this message is relevant to the current user
        final isRelevant = senderId == _userId ||
            receiverId == _userId ||
            receiverId == null ||
            (groupChatId != null && _chatItems.any((c) => c['id'] == groupChatId));

        if (!isRelevant) return;

        if (mounted) {
          // If viewing this chat, add to messages
          if (_selectedChatId != null) {
            bool addToView = false;
            if (groupChatId != null && groupChatId == _selectedChatId) {
              addToView = true;
            } else if (groupChatId == null && _selectedChatType == 'direct') {
              final chatItem = _chatItems.firstWhere(
                (c) => c['id'] == _selectedChatId,
                orElse: () => {},
              );
              final partnerId = chatItem['_partner_id'] as String?;
              if (widget.role == 'client') {
                addToView = senderId == _userId ||
                    (senderId != null && _adminIds.contains(senderId));
              } else if (partnerId != null) {
                addToView = senderId == partnerId || senderId == _userId;
              }
            }

            if (addToView) {
              setState(() => _messages.add(m));
              if (m['receiver_id'] == _userId) _markMessagesRead();
            }
          }

          // Update unread counts
          if (m['receiver_id'] == _userId && m['is_read'] == false) {
            final key = groupChatId ?? senderId ?? '';
            if (key != _selectedChatId) {
              setState(() {
                _unreadCounts[key] = (_unreadCounts[key] ?? 0) + 1;
              });
            }
          }

          // Refresh chat list item's last message
          _updateChatItemLastMessage(m);
        }
      },
    ).subscribe();
  }

  void _updateChatItemLastMessage(Map<String, dynamic> msg) {
    final groupChatId = msg['group_chat_id']?.toString();
    setState(() {
      for (var i = 0; i < _chatItems.length; i++) {
        final item = _chatItems[i];
        if (groupChatId != null && item['id'] == groupChatId) {
          _chatItems[i] = {
            ...item,
            '_last_message': msg,
            '_last_message_time': msg['created_at'],
          };
          break;
        } else if (groupChatId == null) {
          if (widget.role == 'client' && item['id'] == 'admin_chat') {
            _chatItems[i] = {
              ...item,
              '_last_message': msg,
              '_last_message_time': msg['created_at'],
            };
            break;
          } else if (item['_partner_id'] == msg['sender_id'] ||
              item['_partner_id'] == msg['receiver_id']) {
            _chatItems[i] = {
              ...item,
              '_last_message': msg,
              '_last_message_time': msg['created_at'],
            };
            break;
          }
        }
      }
    });
  }

  // ── Send message ───────────────────────────────────────────────────────────

  Future<void> _sendTextMessage(String text) async {
    if (_selectedChatType == 'channel') {
      await _supabase.from('channel_posts').insert({
        'channel_id': _selectedChatId,
        'author_id': _userId,
        'content': text,
        'message_type': 'text',
      });
      _loadMessages(); // Refresh channel posts
      return;
    }

    String? receiverId;
    String? groupChatId;

    if (_selectedChatType == 'group') {
      groupChatId = _selectedChatId;
    } else {
      final chatItem = _chatItems.firstWhere(
        (c) => c['id'] == _selectedChatId,
        orElse: () => {},
      );
      receiverId = chatItem['_partner_id'] as String?;
    }

    await _supabase.from('messages').insert({
      'sender_id': _userId,
      'content': text,
      'receiver_id': receiverId,
      'group_chat_id': groupChatId,
      'message_type': 'text',
    });
  }

  Future<void> _sendVoiceMessage(Uint8List bytes, int durationMs, String ext) async {
    final url = await ChatAttachmentService.uploadVoice(
      bytes: bytes,
      senderId: _userId,
      extension: ext,
    );

    String? receiverId;
    String? groupChatId;
    if (_selectedChatType == 'group') {
      groupChatId = _selectedChatId;
    } else {
      final chatItem = _chatItems.firstWhere(
        (c) => c['id'] == _selectedChatId,
        orElse: () => {},
      );
      receiverId = chatItem['_partner_id'] as String?;
    }

    await _supabase.from('messages').insert({
      'sender_id': _userId,
      'receiver_id': receiverId,
      'group_chat_id': groupChatId,
      'content': '🎤 Голосовое сообщение',
      'message_type': 'voice',
      'attachment_url': url,
      'attachment_size': bytes.length,
      'voice_duration_ms': durationMs,
    });
  }

  Future<void> _sendFileMessage(Uint8List bytes, String fileName, int fileSize, {String? caption}) async {
    final url = await ChatAttachmentService.uploadFile(
      bytes: bytes,
      originalFileName: fileName,
      senderId: _userId,
    );

    String? receiverId;
    String? groupChatId;
    if (_selectedChatType == 'group') {
      groupChatId = _selectedChatId;
    } else {
      final chatItem = _chatItems.firstWhere(
        (c) => c['id'] == _selectedChatId,
        orElse: () => {},
      );
      receiverId = chatItem['_partner_id'] as String?;
    }

    await _supabase.from('messages').insert({
      'sender_id': _userId,
      'receiver_id': receiverId,
      'group_chat_id': groupChatId,
      'content': caption?.isNotEmpty == true ? caption : '📎 $fileName',
      'message_type': 'file',
      'attachment_url': url,
      'attachment_name': fileName,
      'attachment_size': fileSize,
    });
  }

  void _showSendFileDialog(Uint8List bytes, String fileName, int fileSize) {
    showDialog(
      context: context,
      builder: (context) => SendFileDialog(
        fileName: fileName,
        fileSize: fileSize,
        fileBytes: bytes,
        onSend: (caption) => _sendFileMessage(bytes, fileName, fileSize, caption: caption),
      ),
    );
  }

  // ── Chat selection ─────────────────────────────────────────────────────────

  void _selectChat(Map<String, dynamic> item) {
    final id = item['id'] as String;
    final type = item['_item_type'] as String;
    final avatarUrl = _getAvatarUrl(item);
            
    setState(() {
      _selectedChatId = id;
      _selectedChatType = type;
      _selectedChatName = item['_display_name'] as String?;
      _selectedChatAvatarUrl = avatarUrl;
      _messages = [];
    });
    _loadMessages();
  }

  void _deselectChat() {
    setState(() {
      _selectedChatId = null;
      _selectedChatType = null;
      _selectedChatName = null;
      _selectedChatAvatarUrl = null;
      _messages = [];
      _showProfilePanel = false;
    });
  }

  // ── Check channel post permission ──────────────────────────────────────────

  Future<bool> _canPostToChannel(String channelId) async {
    if (widget.role == 'manager') return true;
    try {
      final perm = await _supabase
          .from('channel_permissions')
          .select()
          .eq('channel_id', channelId)
          .eq('user_id', _userId)
          .maybeSingle();
      return perm?['can_post'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String? _getAvatarUrl(Map<String, dynamic> item) {
    final type = item['_item_type'] as String?;
    if (type == 'direct') {
      final profile = item['_profile'];
      return profile is Map ? profile['avatar_url']?.toString() : null;
    } else if (type == 'group') {
      final groupData = item['_group_data'];
      return groupData is Map ? groupData['avatar_url']?.toString() : null;
    } else if (type == 'channel') {
      final channelData = item['_channel_data'];
      return channelData is Map ? channelData['avatar_url']?.toString() : null;
    }
    return null;
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return '';
    final dt = DateTime.tryParse(isoTime);
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(local.year, local.month, local.day);

    if (msgDate == today) return DateFormat('HH:mm', 'ru').format(local);
    if (today.difference(msgDate).inDays == 1) return 'Вчера';
    if (today.difference(msgDate).inDays < 7) return DateFormat('EE', 'ru').format(local);
    return DateFormat('dd.MM', 'ru').format(local);
  }

  String _messagePreview(Map<String, dynamic>? msg) {
    if (msg == null) return 'Нет сообщений';
    final type = msg['message_type']?.toString() ?? 'text';
    if (type == 'voice') return '🎤 Голосовое';
    if (type == 'file') return '📎 ${msg['attachment_name'] ?? 'Файл'}';
    return msg['content']?.toString() ?? '';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  Widget _buildMessengerShell(BuildContext context) {
    return AdaptiveMessengerShell(
      selectedChatId: _selectedChatId,
      onChatSelected: (id) {},
      showProfilePanel: _showProfilePanel,
      chatListBuilder: (context, isMobile, selectedId) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) {
          final isProfile = child.key == const ValueKey('profile');
          return SlideTransition(
            position: Tween<Offset>(
              begin: Offset(isProfile ? -1.0 : 1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        child: _showMyProfile
            ? ProfileScreen(
                key: const ValueKey('profile'),
                onBack: () => setState(() => _showMyProfile = false),
                onUpdate: _loadChatList,
              )
            : KeyedSubtree(
                key: const ValueKey('chat_list'),
                child: _buildChatList(context, isMobile),
              ),
      ),
      chatViewBuilder: (context, isMobile, selectedId) => _buildChatView(context, isMobile),
      profilePanelBuilder: (context) => _selectedChatId != null && _selectedChatType != null
          ? ChatInfoDialog(
              chatId: _selectedChatId!,
              chatType: _selectedChatType!,
              userRole: widget.role,
              onClose: () => setState(() => _showProfilePanel = false),
              onUpdate: _loadChatList,
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role == 'client') {
      // Clients only see the chat shell directly, no CRM navigation
      return Scaffold(
        body: _buildMessengerShell(context),
      );
    }

    // Staff view with CRM navigation
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget bodyContent;
    if (_selectedCrmTab == 0) {
      bodyContent = _buildMessengerShell(context);
    } else if (isDesktop && _selectedCrmTab == 4) { // 'Users' on Desktop is 4th index (0=Chat, 1=Dashboard, 2=Schedule, 3=Leads, 4=Users, 5=Finance)
      bodyContent = const UserRolesWidget();
    } else if (!isDesktop && _selectedCrmTab == 3) { // 'Users' on Mobile is 3rd index (0=Chat, 1=Dashboard, 2=Schedule, 3=Users)
      bodyContent = const UserRolesWidget();
    } else {
      bodyContent = _buildUnderConstruction(isDark);
    }

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: isDark ? TelegramColors.darkSidebar : TelegramColors.lightSidebar,
              selectedIndex: _selectedCrmTab,
              useIndicator: true,
              indicatorColor: TelegramColors.brandPurple.withAlpha(51),
              onDestinationSelected: (idx) {
                setState(() => _selectedCrmTab = idx);
              },
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  selectedIcon: Icon(Icons.chat_bubble_rounded, color: TelegramColors.brandPurple),
                  label: Text('Чат'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard_rounded, color: TelegramColors.brandPurple),
                  label: Text('Обзор'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.calendar_today_outlined),
                  selectedIcon: Icon(Icons.calendar_today_rounded, color: TelegramColors.brandPurple),
                  label: Text('Расписание'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.people_outline_rounded),
                  selectedIcon: Icon(Icons.people_rounded, color: TelegramColors.brandPurple),
                  label: Text('Лиды'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.manage_accounts_outlined),
                  selectedIcon: Icon(Icons.manage_accounts_rounded, color: TelegramColors.brandPurple),
                  label: Text('Пользователи'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet_rounded, color: TelegramColors.brandPurple),
                  label: Text('Финансы'),
                ),
              ],
            ),
            VerticalDivider(
              thickness: 1, 
              width: 1,
              color: isDark ? TelegramColors.darkDivider : TelegramColors.lightDivider,
            ),
            Expanded(child: bodyContent),
          ],
        ),
      );
    } else {
      return Scaffold(
        body: bodyContent,
        bottomNavigationBar: _selectedCrmTab == 0 && _selectedChatId != null
            ? null // Hide bar in chat view
            : BottomNavigationBar(
                currentIndex: _selectedCrmTab,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: TelegramColors.brandPurple,
                unselectedItemColor: isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary,
                backgroundColor: isDark ? TelegramColors.darkSidebar : TelegramColors.lightSidebar,
                onTap: (idx) {
                  setState(() => _selectedCrmTab = idx);
                },
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: 'Чат'),
                  BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Обзор'),
                  BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: 'Распис.'),
                  BottomNavigationBarItem(icon: Icon(Icons.manage_accounts_rounded), label: 'Пользов.'),
                ],
              ),
      );
    }
  }

  Widget _buildUnderConstruction(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_rounded, size: 64, color: TelegramColors.brandPurple.withAlpha(127)),
          const SizedBox(height: 16),
          Text(
            'Данный раздел находится в разработке',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? TelegramColors.darkTextSecondary : TelegramColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Chat List Panel ────────────────────────────────────────────────────────

  Widget _buildChatList(BuildContext context, bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canCreateGroups = widget.role == 'admin' || widget.role == 'manager';

    final filteredItems = _searchQuery.isEmpty
        ? _chatItems
        : _chatItems.where((item) {
            final name = (item['_display_name'] as String? ?? '').toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    return Column(
      children: [
        // Header
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? TelegramColors.darkSurface : TelegramColors.lightBg,
            border: Border(
              bottom: BorderSide(
                color: isDark ? TelegramColors.darkDivider : TelegramColors.lightDivider,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // Hamburger menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.menu_rounded),
                offset: const Offset(0, 48),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'profile',
                    child: ListTile(
                      leading: Icon(Icons.person_outline_rounded),
                      title: Text('Профиль'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'theme',
                    child: ListTile(
                      leading: Icon(
                        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      ),
                      title: Text(isDark ? 'Светлая тема' : 'Тёмная тема'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout_rounded, color: TelegramColors.danger),
                      title: Text('Выйти', style: TextStyle(color: TelegramColors.danger)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'profile') {
                    if (MediaQuery.of(context).size.width >= 768) {
                      setState(() => _showMyProfile = true);
                    } else {
                      context.push('/profile');
                    }
                  } else if (value == 'theme') {
                    ref.read(themeModeProvider.notifier).toggle();
                  } else if (value == 'logout') {
                    await _supabase.auth.signOut();
                    if (context.mounted) context.go('/login');
                  }
                },
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'MagicMusic',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              if (canCreateGroups)
                IconButton(
                  icon: const Icon(Icons.group_add_rounded),
                  tooltip: 'Новая группа',
                  onPressed: () async {
                    final groupId = await showDialog<String>(
                      context: context,
                      builder: (_) => const CreateGroupChatDialog(),
                    );
                    if (groupId != null) {
                      await _loadChatList();
                    }
                  },
                ),
            ],
          ),
        ),
        // Search
        ChatSearchBar(
          onChanged: (q) => setState(() => _searchQuery = q),
        ),
        // Chat list
        Expanded(
          child: _loadingChats
              ? const Center(
                  child: CircularProgressIndicator(color: TelegramColors.accentBlue),
                )
              : filteredItems.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'Ничего не найдено'
                            : 'Нет чатов',
                        style: TextStyle(
                          color: isDark
                              ? TelegramColors.darkTextSecondary
                              : TelegramColors.lightTextSecondary,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadChatList,
                      color: TelegramColors.accentBlue,
                      child: ListView.builder(
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final id = item['id'] as String;
                          final type = item['_item_type'] as String;
                          final name = item['_display_name'] as String? ?? '';
                          final lastMsg = item['_last_message'] as Map<String, dynamic>?;
                          final unread = _unreadCounts[id] ?? 0;
                          final avatarUrl = _getAvatarUrl(item);

                          return ChatListTile(
                            title: name,
                            subtitle: _messagePreview(lastMsg),
                            time: _formatTime(item['_last_message_time'] as String?),
                            unreadCount: unread,
                            isSelected: _selectedChatId == id,
                            isChannel: type == 'channel',
                            uniqueId: id,
                            avatarUrl: avatarUrl,
                            channelIcon: type == 'channel'
                                ? Icons.campaign_rounded
                                : type == 'group'
                                    ? Icons.group_rounded
                                    : null,
                            onTap: () => _selectChat(item),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  // ── Chat View Panel ────────────────────────────────────────────────────────

  Widget _buildChatView(BuildContext context, bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isChannel = _selectedChatType == 'channel';
    final isGroup = _selectedChatType == 'group';

    return DropTarget(
      onDragDone: (details) async {
        if (details.files.isEmpty) return;
        for (final file in details.files) {
          final bytes = await file.readAsBytes();
          final size = await file.length();
          if (size > ChatAttachmentService.maxFileSizeBytes) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Файл слишком большой (макс. 25 МБ)'),
                  backgroundColor: TelegramColors.danger,
                ),
              );
            }
            continue;
          }
          _showSendFileDialog(bytes, file.name, size);
        }
      },
      child: Container(
        color: isDark ? TelegramColors.darkChatBg : TelegramColors.lightChatBg,
        child: Column(
          children: [
          ChatHeader(
            title: _selectedChatName ?? '',
            subtitle: isChannel
                ? 'Канал'
                : isGroup
                    ? 'Группа'
                    : widget.role == 'client'
                        ? 'Поддержка'
                        : 'Личный чат',
            uniqueId: _selectedChatId,
            avatarUrl: _selectedChatAvatarUrl,
            isChannel: isChannel,
            showBackButton: isMobile,
            onBack: _deselectChat,
            onTitleTap: () {
              if (_selectedChatId == null || _selectedChatType == null) return;
              if (widget.role == 'client' && _selectedChatType == 'direct') return; // Do not show school admin profile
              
              if (MediaQuery.of(context).size.width >= 768) {
                setState(() => _showProfilePanel = !_showProfilePanel);
              } else {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatInfoDialog(
                    chatId: _selectedChatId!,
                    chatType: _selectedChatType!,
                    userRole: widget.role,
                    onUpdate: _loadChatList,
                  ),
                ));
              }
            },
          ),
          Expanded(
            child: _loadingMessages
                ? const Center(
                    child: CircularProgressIndicator(color: TelegramColors.accentBlue),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isChannel
                                  ? Icons.campaign_outlined
                                  : Icons.chat_bubble_outline_rounded,
                              size: 64,
                              color: isDark
                                  ? TelegramColors.darkTextSecondary.withAlpha(60)
                                  : TelegramColors.lightTextSecondary.withAlpha(60),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isChannel
                                  ? 'Пока нет публикаций'
                                  : 'Начните общение!',
                              style: TextStyle(
                                color: isDark
                                    ? TelegramColors.darkTextSecondary
                                    : TelegramColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _MessageListView(
                        messages: _messages,
                        currentUserId: _userId,
                        isGroupChat: isGroup,
                        isChannel: isChannel,
                        chatItems: _chatItems,
                        adminIds: _adminIds,
                        role: widget.role,
                        selectedChatName: _selectedChatName,
                      ),
          ),
          // Input (not for channels unless user has permission)
          if (!isChannel)
            MessageInput(
              onSendText: _sendTextMessage,
              onSendVoice: _sendVoiceMessage,
              onSendFile: (bytes, name, size, {caption}) async {
                _showSendFileDialog(bytes, name, size);
              },
            )
          else
            FutureBuilder<bool>(
              future: _canPostToChannel(_selectedChatId!),
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return MessageInput(
                    onSendText: _sendTextMessage,
                    onSendFile: (bytes, name, size, {caption}) async {
                      _showSendFileDialog(bytes, name, size);
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
        ],
      ),
    ),
  );
}
}

// ── Message List with Date Separators ────────────────────────────────────────

class _MessageListView extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final String currentUserId;
  final bool isGroupChat;
  final bool isChannel;
  final List<Map<String, dynamic>> chatItems;
  final List<String> adminIds;
  final String role;
  final String? selectedChatName;

  const _MessageListView({
    required this.messages,
    required this.currentUserId,
    required this.isGroupChat,
    required this.isChannel,
    required this.chatItems,
    required this.adminIds,
    required this.role,
    this.selectedChatName,
  });

  @override
  State<_MessageListView> createState() => _MessageListViewState();
}

class _MessageListViewState extends State<_MessageListView> {
  final _scrollController = ScrollController();
  // Cache for sender names (profile lookups)
  final Map<String, String> _senderNameCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(_MessageListView old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  String _getSenderName(Map<String, dynamic> msg) {
    final senderId = msg['sender_id']?.toString() ?? '';
    if (senderId == widget.currentUserId) return 'Вы';

    if (_senderNameCache.containsKey(senderId)) {
      return _senderNameCache[senderId]!;
    }

    // Check if message has embedded profile data
    final profiles = msg['profiles'];
    if (profiles != null && profiles is Map) {
      final name = '${profiles['first_name'] ?? ''} ${profiles['last_name'] ?? ''}'.trim();
      if (name.isNotEmpty) {
        _senderNameCache[senderId] = name;
        return name;
      }
    }

    if (widget.adminIds.contains(senderId)) return 'Администрация';
    return widget.selectedChatName ?? 'Пользователь';
  }

  bool _shouldShowDate(int index) {
    if (index == 0) return true;
    final curr = DateTime.tryParse(widget.messages[index]['created_at'] ?? '');
    final prev = DateTime.tryParse(widget.messages[index - 1]['created_at'] ?? '');
    if (curr == null || prev == null) return false;
    return curr.toLocal().day != prev.toLocal().day ||
        curr.toLocal().month != prev.toLocal().month ||
        curr.toLocal().year != prev.toLocal().year;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) {
        final msg = widget.messages[index];
        final isMe = msg['sender_id'] == widget.currentUserId;

        return Column(
          children: [
            if (_shouldShowDate(index))
              DateSeparator(
                date: DateTime.tryParse(msg['created_at'] ?? '')?.toLocal() ??
                    DateTime.now(),
              ),
            MessageBubble(
              message: msg,
              isMe: isMe,
              senderName: _getSenderName(msg),
              showSenderName: widget.isGroupChat || widget.isChannel,
              isGroupChat: widget.isGroupChat,
            ),
          ],
        );
      },
    );
  }
}
