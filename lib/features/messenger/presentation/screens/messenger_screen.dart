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
import 'package:magic_music_crm/core/services/notification_service.dart';
import 'package:magic_music_crm/core/services/supa_message_service.dart';
import 'package:magic_music_crm/core/services/supa_settings_service.dart';
import 'package:magic_music_crm/core/services/supa_messenger_service.dart';
import 'package:magic_music_crm/core/providers/theme_provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:typed_data';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:magic_music_crm/core/widgets/telegram/send_file_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/user_roles_widget.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';


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
  String? _adminAvatarUrl;

  // Data
  List<Map<String, dynamic>> _chatItems = [];
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _pinnedMessages = [];
  Map<String, List<dynamic>> _reactionsMap = {};
  RealtimeChannel? _reactionsChannel;
  Map<String, int> _unreadCounts = {};
  Set<String> _mutedChatIds = {};
  Set<String> _pinnedChatIds = {};
  bool _loadingChats = true;
  bool _loadingMessages = false;
  String _searchQuery = '';
  int _selectedCrmTab = 0;
  bool _showProfilePanel = false;
  bool _showMyProfile = false;
  int _currentLoadId = 0;
  List<String> _adminIds = [];
  bool _isSearchingInChat = false;
  final _chatSearchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];

  // Wave 1 Lifecycle State
  Map<String, dynamic>? _replyingTo;
  Map<String, dynamic>? _editingMessage;

  // Realtime
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _groupMessagesChannel;
  RealtimeChannel? _typingChannel;
  RealtimeChannel? _presenceChannel;
  RealtimeChannel? _profilesChannel;
  RealtimeChannel? _groupsChannel;
  String _typingText = '';
  Set<String> _onlineUsers = {};
  bool _scrollAtBottom = true;

  @override
  void initState() {
    super.initState();
    _loadChatList();
    _subscribeToMessages();
    _subscribeToProfiles();
    _subscribeToGroups();
    _subscribeToReactions();
    
    // Check for pending navigation from notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDeepLink();
    });
  }

  void _checkDeepLink() {
    final nav = ref.read(messengerNavigationProvider);
    if (nav != null) {
      if (mounted) {
        debugPrint('🎯 MESSENGER: Processing deep link. Partner: ${nav.partnerId}, Group: ${nav.groupChatId}');
        debugPrint('🎯 MESSENGER: Chat items count: ${_chatItems.length}');
        
        // Don't attempt matching if chat list hasn't loaded yet
        if (_chatItems.isEmpty) {
          debugPrint('🎯 MESSENGER: Chat list not loaded yet, deferring deep link');
          return; // Keep the navigation state — it will be checked again after loading
        }

        // Match chat in _chatItems
        final item = _chatItems.where((c) {
          if (nav.groupChatId != null) {
            return c['id'] == nav.groupChatId;
          }
          if (nav.partnerId != null) {
            return c['_partner_id'] == nav.partnerId;
          }
          // Special case: null partnerId with no groupChatId = Administration chat
          return c['id'] == 'admin_chat';
        }).firstOrNull;
        
        if (item != null) {
          debugPrint('🎯 MESSENGER: Found target chat, selecting...');
          _selectChat(item);
          // If we are not on the chat tab, switch to it
          if (_selectedCrmTab != 0) {
            setState(() => _selectedCrmTab = 0);
          }
          // Clear ONLY after successful navigation
          Future.microtask(() {
            ref.read(messengerNavigationProvider.notifier).clear();
          });
        } else {
           debugPrint('🎯 MESSENGER: Target chat not found in items, keeping state for retry');
           // DON'T clear — _loadChatList will call _checkDeepLink again after loading
        }
      }
    }
  }


  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    _groupMessagesChannel?.unsubscribe();
    _profilesChannel?.unsubscribe();
    _groupsChannel?.unsubscribe();
    _leaveTypingChannel();
    super.dispose();
  }

  String get _userId => _supabase.auth.currentUser?.id ?? '';

  // ── Load chat list ─────────────────────────────────────────────────────────

  Future<void> _loadChatList() async {
    try {
      // Set a global timeout for the entire loading process
      await _loadChatListInternal().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('Chat list loading timed out');
          if (mounted) setState(() => _loadingChats = false);
        },
      );
    } catch (e) {
      debugPrint('Error loading chat list: $e');
      if (mounted) setState(() => _loadingChats = false);
    }
  }

  Future<void> _loadChatListInternal() async {
    final items = <Map<String, dynamic>>[];

    // 1. Load admin IDs (Foundational)
    // 2. Load all components in parallel
    await Future.wait([
      _supabase
          .from('profiles')
          .select('id, role')
          .timeout(const Duration(seconds: 10))
          .then((res) {
            final list = res as List;
            _adminIds = list
                .where((a) => a['role'].toString() == 'admin' || a['role'].toString() == 'manager')
                .map((a) => a['id'].toString())
                .toList();
          }),
      if (widget.role == 'client')
        _loadClientChats(items).timeout(const Duration(seconds: 20))
      else
        _loadStaffChats(items).timeout(const Duration(seconds: 25)),
      _loadGroupChats(items).timeout(const Duration(seconds: 20)),
      _loadChannels(items).timeout(const Duration(seconds: 20)),
      SupaSettingsService.getAdminChatAvatar().then((url) => _adminAvatarUrl = url),
    ]);

    final unreadCounts = await SupaMessageService.getUnreadCounts(widget.role == 'admin' || widget.role == 'manager');
    if (_selectedChatId != null) {
      unreadCounts[_selectedChatId!] = 0;
    }
    final mutedIds = await SupaMessengerService.getMutedChatIds();
    final pinnedIds = await SupaMessengerService.getPinnedChatIds();

    if (mounted) {
      setState(() {
        _chatItems = items;
        _unreadCounts = unreadCounts;
        _mutedChatIds = mutedIds;
        _pinnedChatIds = pinnedIds;
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
      // TRIGGER DEEP LINK CHECK AFTER LOADING ITEMS
      _checkDeepLink();
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
      '_avatar_url': _adminAvatarUrl,
      '_icon': _adminAvatarUrl == null ? Icons.support_agent_rounded : null,
    });
  }

  Future<void> _loadStaffChats(List<Map<String, dynamic>> items) async {
    // Admin/Manager/Teacher sees individual client conversations
    final allProfiles = await _supabase
        .from('profiles')
        .select()
        .order('first_name')
        .timeout(const Duration(seconds: 15));

    // Filter clients in memory to avoid enum-to-text comparison issues in database
    final clientProfiles = (allProfiles as List)
        .where((p) => p['role'].toString() == 'client')
        .toList();

    // Run all profile message queries in parallel
    final List<Map<String, dynamic>> enrichedItems = await Future.wait(
      clientProfiles.map((client) async {
        final cid = client['id'] as String;
        
        // Staff see ALL communication with this specific client, regardless of which staff member sent it.
        // This ensures teamwork visibility (Admin A sees Admin B's replies).
        final orFilter = widget.role == 'teacher'
            ? 'and(sender_id.eq.$cid,receiver_id.eq.$_userId),and(sender_id.eq.$_userId,receiver_id.eq.$cid)'
            : 'sender_id.eq.$cid,receiver_id.eq.$cid';

        final lastMsg = await _supabase
            .from('messages')
            .select()
            .or(orFilter)
            .isFilter('group_chat_id', null)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (lastMsg != null) {
          final name = '${client['first_name'] ?? ''} ${client['last_name'] ?? ''}'.trim();
          return {
            'id': cid,
            '_item_type': 'direct',
            '_display_name': name.isEmpty ? 'Ученик' : name,
            '_partner_id': cid,
            '_last_message': lastMsg,
            '_last_message_time': lastMsg['created_at'],
            '_profile': client,
          };
        }
        return <String, dynamic>{};
      }),
    );

    // Add non-empty items to the list
    for (var item in enrichedItems) {
      if (item.isNotEmpty) {
        items.add(item);
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
          .select('*, first_responder:profiles!first_responder_id(first_name, last_name)')
          .inFilter('id', groupIds);

      // Parallelize last message fetching for groups
      final List<Map<String, dynamic>> enrichedGroups = await Future.wait(
        groups.map((group) async {
          final gid = group['id'] as String;
          final lastMsg = await _supabase
              .from('messages')
              .select()
              .eq('group_chat_id', gid)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

          return {
            'id': gid,
            '_item_type': 'group',
            '_display_name': group['name'] ?? 'Группа',
            '_last_message': lastMsg,
            '_last_message_time': lastMsg?['created_at'],
            '_group_data': group,
          };
        }),
      );

      items.addAll(enrichedGroups);
    } catch (e) {
      debugPrint('Error loading group chats: $e');
    }
  }

  Future<void> _loadChannels(List<Map<String, dynamic>> items) async {
    try {
      final channels = await _supabase.from('channels').select().timeout(const Duration(seconds: 10));
      
      final List<Map<String, dynamic>> enrichedChannels = await Future.wait(
        (channels as List).map((ch) async {
          final lastPost = await _supabase
              .from('channel_posts')
              .select()
              .eq('channel_id', ch['id'])
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle()
              .timeout(const Duration(seconds: 10));

          return {
            'id': ch['id'],
            '_item_type': 'channel',
            '_display_name': ch['name'] ?? 'Канал',
            '_last_message': lastPost != null
                ? {'content': lastPost['content'], 'created_at': lastPost['created_at']}
                : null,
            '_last_message_time': lastPost?['created_at'],
            '_channel_data': ch,
          };
        }),
      );

      items.addAll(enrichedChannels);
    } catch (e) {
      debugPrint('Error loading channels: $e');
    }
  }

  // ── Load messages for selected chat ────────────────────────────────────────

  Future<void> _loadMessages() async {
    if (_selectedChatId == null) return;
    
    _currentLoadId++;
    final loadId = _currentLoadId;
    
    debugPrint('💬 MESSENGER: _loadMessages started for $_selectedChatId (LoadId: $loadId)');
    
    setState(() {
      _loadingMessages = true;
      _messages = [];
    });

    try {
      if (_selectedChatType == 'channel') {
        final posts = await _supabase
            .from('channel_posts')
            .select('*, profiles:author_id(first_name, last_name)')
            .eq('channel_id', _selectedChatId!)
            .order('created_at', ascending: true)
            .limit(500)
            .timeout(const Duration(seconds: 20));

        if (loadId != _currentLoadId) return;

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(posts).map((p) => {
              ...p,
              'sender_id': p['author_id'],
              'message_type': p['message_type'] ?? 'text',
              'is_read': true,
            }).toList();
          });
        }
      } else if (_selectedChatType == 'group') {
        final msgs = await _supabase
            .from('messages')
            .select()
            .eq('group_chat_id', _selectedChatId!)
            .order('created_at', ascending: true)
            .limit(500)
            .timeout(const Duration(seconds: 20));

        if (loadId != _currentLoadId) return;

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(msgs);
          });
          _fetchReactionsForCurrentMessages();
          _markMessagesRead();
        }
      } else {
        // Direct chat
        final chatItemByPartnerId = _chatItems.where((c) => c['_partner_id'] == _selectedChatId).toList();
        final chatItemById = _chatItems.where((c) => c['id'] == _selectedChatId).toList();
        
        final chatItem = chatItemById.isNotEmpty 
            ? chatItemById.first 
            : (chatItemByPartnerId.isNotEmpty ? chatItemByPartnerId.first : {});
            
        final partnerId = chatItem['_partner_id'] as String? ?? (chatItem['id'] != 'admin_chat' ? chatItem['id'] : null);

        List<dynamic> msgs = [];
        if (widget.role == 'client') {
          msgs = await _supabase
              .from('messages')
              .select()
              .or('sender_id.eq.$_userId,receiver_id.eq.$_userId')
              .isFilter('group_chat_id', null)
              .order('created_at', ascending: true)
              .limit(500)
              .timeout(const Duration(seconds: 20));

          if (loadId != _currentLoadId) return;

          msgs = msgs.where((m) {
            final isFromMe = m['sender_id'] == _userId;
            final isToMe = m['receiver_id'] == _userId;
            if (isFromMe) return m['receiver_id'] == null || _adminIds.contains(m['receiver_id']);
            if (isToMe) return m['sender_id'] == null || _adminIds.contains(m['sender_id']);
            return false;
          }).toList();
        } else if (partnerId != null) {
          final orFilter = widget.role == 'teacher'
              ? 'and(sender_id.eq.$partnerId,receiver_id.eq.$_userId),and(sender_id.eq.$_userId,receiver_id.eq.$partnerId)'
              : 'and(sender_id.eq.$partnerId,or(receiver_id.eq.$_userId,receiver_id.is.null)),and(sender_id.eq.$_userId,receiver_id.eq.$partnerId),and(sender_id.eq.$partnerId,receiver_id.is.null)';

          msgs = await _supabase
              .from('messages')
              .select()
              .or(orFilter)
              .isFilter('group_chat_id', null)
              .order('created_at', ascending: true)
              .limit(500)
              .timeout(const Duration(seconds: 20));

          if (loadId != _currentLoadId) return;

          msgs = msgs.where((m) {
            final isFromPartner = m['sender_id'] == partnerId;
            final isFromMe = m['sender_id'] == _userId;
            if (isFromPartner) {
              if (widget.role == 'teacher') return m['receiver_id'] == _userId;
              return m['receiver_id'] == null || m['receiver_id'] == _userId || _adminIds.contains(m['receiver_id']);
            }
            if (isFromMe) return m['receiver_id'] == partnerId;
            return false;
          }).toList();
        }

        if (mounted && loadId == _currentLoadId) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(msgs);
            _loadingMessages = false;
          });
          _fetchReactionsForCurrentMessages();
          _markMessagesRead();
        }
      }
    } on Exception catch (e) {
      debugPrint('❌ MESSENGER ERROR [LoadId: $loadId]: $e');
      if (mounted && loadId == _currentLoadId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки сообщений: ${e.toString()}'),
            backgroundColor: TelegramColors.danger,
          ),
        );
      }
    } finally {
      if (mounted && loadId == _currentLoadId) {
        setState(() => _loadingMessages = false);
        debugPrint('💬 MESSENGER: _loadMessages finished (LoadId: $loadId)');
      }
    }
  }

  Future<void> _markMessagesRead() async {
    if (_selectedChatId == null) return;
    try {
      final List<String> unreadIds = [];

      // 1. Gather unread message IDs from the local list
      for (final m in _messages) {
        if (m['is_read'] == true) continue;

        bool isMyUnread = false;
        if (_selectedChatType == 'group') {
          // In a group, any message that isn't from me and is unread counts
          if (m['group_chat_id'] == _selectedChatId && m['sender_id'] != _userId) {
            isMyUnread = true;
          }
        } else {
          // Direct or Administration
          final receiverId = m['receiver_id']?.toString();
          final senderId = m['sender_id']?.toString();
          
          final isToMe = receiverId == _userId;
          final isToAdmin = receiverId == null && widget.role != 'client';
          
          final chatItem = _chatItems.firstWhere((c) => c['id'] == _selectedChatId, orElse: () => {});
          final partnerId = chatItem['_partner_id'] as String?;

          if (isToMe && _selectedChatId == 'admin_chat' && widget.role == 'client') {
            // ALL direct messages to client are considered "admin" messages in this view
            isMyUnread = true;
          } else if ((isToMe || isToAdmin) && senderId == partnerId) {
            isMyUnread = true;
          }
        }

        if (isMyUnread) {
          unreadIds.add(m['id'] as String);
        }
      }

      if (unreadIds.isNotEmpty) {
        await SupaMessageService.markIdsAsRead(unreadIds);
        
        if (mounted) {
          setState(() {
            for (final mid in unreadIds) {
              final idx = _messages.indexWhere((msg) => msg['id'] == mid);
              if (idx != -1) _messages[idx]['is_read'] = true;
            }
            _unreadCounts[_selectedChatId!] = 0;
          });
        }
      }
      
      // Also ensure DB is synced for any messages NOT in the current _messages view
      await SupaMessageService.markMessagesAsRead(
        currentUserId: _userId,
        chatId: _selectedChatId!,
        chatType: _selectedChatType!,
        isStaff: widget.role != 'client',
      );

    } catch (e) {
      debugPrint('MessengerScreen: Error marking messages as read: $e');
    }
  }

  // ── Realtime subscription ──────────────────────────────────────────────────

  void _subscribeToMessages() {
    _messagesChannel = _supabase.channel('messenger_$_userId');
    
    // Listen for direct and group messages
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
              
              // Trigger read status if this message is part of the currently open chat
              bool shouldMarkRead = false;
              if (_selectedChatType == 'group') {
                shouldMarkRead = groupChatId == _selectedChatId && senderId != _userId;
              } else {
                final isToMe = receiverId == _userId;
                final isToAdmin = receiverId == null && widget.role != 'client';
                final chatItem = _chatItems.firstWhere((c) => c['id'] == _selectedChatId, orElse: () => {});
                final partnerId = chatItem['_partner_id'] as String?;
                
                if ((isToMe || isToAdmin) && senderId == partnerId) {
                  shouldMarkRead = true;
                }
              }

              if (shouldMarkRead) {
                _markMessagesRead();
              }
            }
          }

          // Update unread counts
          final isUnread = m['is_read'] == false;
          if (isUnread && senderId != _userId) {
            bool isRelevantUnread = false;
            if (groupChatId != null) {
               // Group message unread count (if shared flag allows)
               isRelevantUnread = true;
            } else {
               final isToMe = receiverId == _userId;
               final isToAdmin = receiverId == null && widget.role != 'client';
               if (isToMe || isToAdmin) isRelevantUnread = true;
            }

            if (isRelevantUnread) {
              final key = groupChatId ?? senderId ?? '';
              if (key != _selectedChatId) {
                setState(() {
                  _unreadCounts[key] = (_unreadCounts[key] ?? 0) + 1;
                });
              }
            }
          }

          // Refresh chat list item's last message
          _updateChatItemLastMessage(m);

          // Trigger Desktop Notification if relevant and not current chat
          final isFromMe = senderId == _userId;
          if (!isFromMe) {
            final key = groupChatId ?? senderId ?? 'admin';
            if (key != _selectedChatId && !_mutedChatIds.contains(key)) {
              final senderName = _chatItems.where((c) => c['id'] == key).firstOrNull?['_display_name'] ?? 'Новое сообщение';
              NotificationService.showLocalNotification(
                title: senderName,
                body: m['content'] ?? (m['message_type'] == 'file' ? '📁 Файл' : 'Сообщение'),
                payload: {'type': 'chat', 'id': key},
              );
            }
          }
        }
      },
    );

    // Listen for channel posts
    _messagesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'channel_posts',
      callback: (payload) {
        final post = payload.newRecord;
        final channelId = post['channel_id']?.toString();

        if (mounted) {
          // If viewing this channel, add to messages
          if (_selectedChatId == channelId && _selectedChatType == 'channel') {
            setState(() {
              _messages.add({
                ...post,
                'sender_id': post['author_id'],
                'message_type': post['message_type'] ?? 'text',
                'is_read': true,
              });
            });
          }

          // Refresh chat list item's last message
          _updateChatItemLastMessage({
            ...post,
            'group_chat_id': null, // It's a channel, but we use this helper
            '_is_channel_post': true,
          });
        }
      },
    );

    _messagesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        final m = payload.newRecord;
        final mid = m['id']?.toString();
        
        if (mounted) {
          setState(() {
            // Update message in the list
            final idx = _messages.indexWhere((msg) => msg['id'] == mid);
            if (idx != -1) {
              _messages[idx] = m;
            }
            // Update unread count if it was marked read
            if (m['is_read'] == true) {
              final senderId = m['sender_id']?.toString();
              final groupChatId = m['group_chat_id']?.toString();
              final key = groupChatId ?? senderId ?? '';
              
              // If this message was why we had unread, maybe re-fetch or decrement
              // Simplest is to clear it if it's the current chat or just re-load counts eventually
              if (key == _selectedChatId) {
                _unreadCounts[key] = 0;
              }
            }
          });
        }
      },
    );

    _messagesChannel!.subscribe();
  }

  void _subscribeToReactions() {
    _reactionsChannel = _supabase.channel('message_reactions_realtime');
    _reactionsChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'message_reactions',
      callback: (payload) {
        if (mounted) {
          _fetchReactionsForCurrentMessages();
        }
      },
    ).subscribe();
  }

  void _subscribeToProfiles() {
    _profilesChannel = _supabase.channel('messenger_profiles');
    _profilesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'profiles',
      callback: (payload) {
        final profile = payload.newRecord;
        final pid = profile['id']?.toString();
        
        if (mounted) {
          setState(() {
            // Update _chatItems that contain this profile
            for (var i = 0; i < _chatItems.length; i++) {
              if (_chatItems[i]['id'] == pid && _chatItems[i]['_item_type'] == 'direct') {
                _chatItems[i]['_profile'] = profile;
                _chatItems[i]['_display_name'] = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
                
                // If it's the selected chat, update header info
                if (_selectedChatId == pid) {
                  _selectedChatName = _chatItems[i]['_display_name'];
                  _selectedChatAvatarUrl = _getAvatarUrl(_chatItems[i]);
                }
              }
            }
          });
        }
      },
    ).subscribe();
  }

  void _subscribeToGroups() {
    _groupsChannel = _supabase.channel('messenger_groups');
    _groupsChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'group_chats',
      callback: (payload) {
        final group = payload.newRecord;
        final gid = group['id']?.toString();
        
        if (mounted) {
          setState(() {
            for (var i = 0; i < _chatItems.length; i++) {
              if (_chatItems[i]['id'] == gid && _chatItems[i]['_item_type'] == 'group') {
                _chatItems[i]['_group_data'] = group;
                _chatItems[i]['_display_name'] = group['name'] ?? 'Группа';
                
                if (_selectedChatId == gid) {
                  _selectedChatName = _chatItems[i]['_display_name'];
                  _selectedChatAvatarUrl = _getAvatarUrl(_chatItems[i]);
                }
              }
            }
          });
        }
      },
    ).subscribe();
  }

  void _updateChatItemLastMessage(Map<String, dynamic> msg) {
    final groupChatId = msg['group_chat_id']?.toString();
    final channelId = msg['channel_id']?.toString();
    final isChannel = msg['_is_channel_post'] == true;

    setState(() {
      for (var i = 0; i < _chatItems.length; i++) {
        final item = _chatItems[i];
        
        if (isChannel && item['id'] == channelId && item['_item_type'] == 'channel') {
           _chatItems[i] = {
            ...item,
            '_last_message': msg,
            '_last_message_time': msg['created_at'],
          };
          break;
        }

        if (groupChatId != null && item['id'] == groupChatId) {
          _chatItems[i] = {
            ...item,
            '_last_message': msg,
            '_last_message_time': msg['created_at'],
          };
          break;
        } else if (groupChatId == null && !isChannel) {
          if (widget.role == 'client' && item['id'] == 'admin_chat') {
             // Admin chat for clients - check if sender is from adminIds or it's my own message to null receiver
             final senderId = msg['sender_id']?.toString();
             final receiverId = msg['receiver_id']?.toString();
             bool isRelevant = (senderId == _userId && receiverId == null) || 
                              _adminIds.contains(senderId) || 
                              _adminIds.contains(receiverId);
             
             if (isRelevant) {
                _chatItems[i] = {
                  ...item,
                  '_last_message': msg,
                  '_last_message_time': msg['created_at'],
                };
                break;
             }
          } else if (item['_partner_id'] == msg['sender_id'] ||
              item['_partner_id'] == msg['receiver_id']) {
            
            // For teachers, ignore messages to "Administration" (null receiver)
            if (widget.role == 'teacher' && msg['receiver_id'] == null) {
              continue;
            }

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

  // ── Typing Presence ────────────────────────────────────────────────────────

  Future<void> _joinTypingChannel(String chatId) async {
    _leaveTypingChannel();

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // Get my profile for name
    final profile = await _supabase.from('profiles').select('first_name, last_name').eq('id', user.id).maybeSingle();
    final myName = '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();

    _typingChannel = _supabase.channel('typing_$chatId');
    
    _typingChannel!.onPresenceSync((_) {
      final states = _typingChannel!.presenceState();
      final Map<String, String> newTypists = {};
      
      for (final state in states) {
        for (final presence in state.presences) {
          final Map<String, dynamic> data = Map<String, dynamic>.from(presence.payload);
          final typistId = data['id']?.toString();
          final isTyping = data['isTyping'] == true;
          
          if (typistId != null && typistId != _userId && isTyping) {
            final role = data['role']?.toString();
            final name = data['name']?.toString() ?? 'Пользователь';
            
            if (widget.role == 'client' && (role == 'admin' || role == 'manager')) {
              newTypists[typistId] = 'Администратор';
            } else {
              newTypists[typistId] = name;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          if (newTypists.isEmpty) {
            _typingText = '';
          } else if (newTypists.length == 1) {
            _typingText = '${newTypists.values.first} печатает...';
          } else {
            _typingText = '${newTypists.length} чел. печатают...';
          }
        });
      }
    }).subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _trackTyping(false, myName);
      }
    });
  }

  void _leaveTypingChannel() {
    _typingChannel?.unsubscribe();
    _typingChannel = null;
    if (mounted) {
      setState(() {
        _typingText = '';
      });
    }
  }

  Future<void> _trackTyping(bool isTyping, String name) async {
    if (_typingChannel == null) return;
    await _typingChannel!.track({
      'id': _userId,
      'name': name,
      'role': widget.role,
      'isTyping': isTyping,
    });
  }

  void _handleTyping(bool isTyping) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    
    // Get name from profile if not cached etc. 
    // For performance, we could cache this, but profile select is fast with RLS
    final profile = await _supabase.from('profiles').select('first_name').eq('id', user.id).maybeSingle();
    final name = profile?['first_name'] ?? 'Аноним';
    
    await _trackTyping(isTyping, name);
    
    // Auto-stop typing after 3 seconds
    if (isTyping) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _trackTyping(false, name);
      });
    }
  }

  // ── Send message ───────────────────────────────────────────────────────────

  Future<void> _sendTextMessage(String text, {String? replyToId, String? editingMessageId}) async {
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

    if (editingMessageId != null) {
      await SupaMessageService.editMessage(editingMessageId, text);
      setState(() => _editingMessage = null);
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

    await SupaMessageService.sendMessage(
      senderId: _userId,
      content: text,
      receiverId: receiverId,
      groupChatId: groupChatId,
      replyToId: replyToId,
    );
    
    if (replyToId != null) {
      setState(() => _replyingTo = null);
    }
  }

  void _deleteMessage(Map<String, dynamic> msg) async {
    final mid = msg['id'].toString();
    final isMe = msg['sender_id'] == _userId;
    
    if (!isMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы можете удалять только свои сообщения')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление сообщения'),
        content: const Text('Вы уверены, что хотите удалить это сообщение для всех?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: TelegramColors.danger)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SupaMessageService.deleteMessage(mid);
    }
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
    final id = (item['id'] ?? '').toString();
    if (id == _selectedChatId && _loadingMessages) return; // Already loading this chat
    
    final type = (item['_item_type'] ?? item['item_type'] ?? 'individual').toString();
    final avatarUrl = _getAvatarUrl(item);
            
    setState(() {
      _selectedChatId = id;
      _selectedChatType = type;
      _selectedChatName = (item['_display_name'] ?? item['display_name'] ?? 'Аноним').toString();
      _selectedChatAvatarUrl = avatarUrl;
      _messages = [];
    });
    _loadMessages();
    _joinTypingChannel(id);
    _joinPresenceChannel(id);
    _joinReactionsChannel(id);
    _loadPinnedMessage(id, type);
    SupaMessengerService.updateLastSeen(); // Update on chat selection
  }

  Future<void> _joinReactionsChannel(String chatId) async {
    // Note: This relies on message_reactions table having a message_id that belongs to this chat.
    // Realtime filter is limited, so we either listen to all or rely on specific message IDs.
    // For now, listen to all and filter locally if needed.
    _supabase.channel('reactions_$chatId').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'message_reactions',
      callback: (payload) {
        _fetchReactionsForCurrentMessages();
      },
    ).subscribe();
  }

  Future<void> _loadPinnedMessage(String chatId, String chatType) async {
    try {
      if (chatType == 'group') {
        final chat = await _supabase.from('group_chats').select('pinned_message_id').eq('id', chatId).single();
        final pinnedId = chat['pinned_message_id'];
        if (pinnedId != null) {
          final msg = await _supabase.from('messages').select().eq('id', pinnedId).single();
          if (mounted) setState(() => _pinnedMessages = [msg]);
        } else {
          if (mounted) setState(() => _pinnedMessages = []);
        }
      } else {
        // Individual chat: find latest pinned message
        final res = await _supabase.from('messages')
            .select()
            .eq('receiver_id', chatId)
            .not('pinned_at', 'is', null)
            .order('pinned_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (mounted) setState(() => _pinnedMessages = res != null ? [res] : []);
      }
    } catch (e) {
      debugPrint('Error loading pinned message: $e');
    }
  }

  void _onSearchInChat() {
    setState(() {
      _showProfilePanel = false;
      _isSearchingInChat = true;
      _searchResults = [];
      _chatSearchController.clear();
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    
    final results = await SupaMessageService.searchMessages(
      query: query,
      chatId: _selectedChatId!,
      chatType: _selectedChatType!,
    );
    
    if (mounted) {
      setState(() => _searchResults = results);
    }
  }

  Future<void> _joinPresenceChannel(String chatId) async {
    _presenceChannel?.unsubscribe();
    
    _presenceChannel = _supabase.channel('presence_$chatId');
    
    _presenceChannel!.onPresenceSync((_) {
      final states = _presenceChannel!.presenceState();
      final Set<String> online = {};
          
      for (final state in states) {
        for (final presence in state.presences) {
          final data = Map<String, dynamic>.from(presence.payload);
          final uid = data['id']?.toString();
          if (uid != null) {
            online.add(uid);
          }
        }
      }
      
      if (mounted) setState(() => _onlineUsers = online);
    }).subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _presenceChannel!.track({'id': _userId});
      }
    });
  }

  void _deselectChat() {
    _leaveTypingChannel();
    setState(() {
      _selectedChatId = null;
      _selectedChatType = null;
      _selectedChatName = null;
      _selectedChatAvatarUrl = null;
      _messages = [];
      _showProfilePanel = false;
    });
  }


  void _onMuteChat(bool isMuted) async {
    if (_selectedChatId == null || _selectedChatType == null) return;
    try {
      await SupaMessengerService.setChatMuteStatus(
        chatId: _selectedChatId!,
        chatType: _selectedChatType!,
        isMuted: isMuted,
      );
      setState(() {
        if (isMuted) {
          _mutedChatIds.add(_selectedChatId!);
        } else {
          _mutedChatIds.remove(_selectedChatId!);
        }
      });
    } catch (e) {
      debugPrint('Error muting chat: $e');
    }
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
    if (item.containsKey('_avatar_url')) return item['_avatar_url'] as String?;
    
    final type = (item['_item_type'] ?? item['item_type']) as String?;
    if (type == 'direct') {
      final profile = item['_profile'] ?? item['profile'];
      return profile is Map ? profile['avatar_url']?.toString() : null;
    } else if (type == 'group') {
      final groupData = item['_group_data'] ?? item['group_data'];
      return groupData is Map ? groupData['avatar_url']?.toString() : null;
    } else if (type == 'channel') {
      final channelData = item['_channel_data'] ?? item['channel_data'];
      return channelData is Map ? channelData['avatar_url']?.toString() : null;
    }
    return null;
  }

  Future<void> _fetchReactionsForCurrentMessages() async {
    if (_messages.isEmpty) return;
    try {
      final msgIds = _messages.map((m) => m['id'].toString()).toList();
      final reactions = await SupaMessageService.getReactionsForMessages(msgIds);
      if (mounted) {
        final Map<String, List<dynamic>> newMap = {};
        for (final r in reactions) {
          final mid = r['message_id'].toString();
          newMap[mid] = [...(newMap[mid] ?? []), r];
        }
        setState(() {
          _reactionsMap = newMap;
          // Also update messages list for backward compatibility with bubbles that use msg['reactions']
          for (var i = 0; i < _messages.length; i++) {
            final mid = _messages[i]['id'].toString();
            _messages[i]['reactions'] = newMap[mid];
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching reactions: $e');
    }
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    try {
      final existing = _reactionsMap[messageId]?.firstWhere(
        (r) => r['user_id'] == _userId && r['emoji'] == emoji,
        orElse: () => null,
      );

      if (existing != null) {
        await SupaMessageService.removeReaction(messageId: messageId, emoji: emoji);
      } else {
        await SupaMessageService.addReaction(messageId: messageId, emoji: emoji);
      }
      // Realtime listener will handle the update, but we can also trigger a manual fetch
      _fetchReactionsForCurrentMessages();
    } catch (e) {
      debugPrint('Error toggling reaction: $e');
    }
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
              onSearch: _onSearchInChat,
              onMute: _onMuteChat,
            )
          : const SizedBox.shrink(),
    );
  }

  void _onForwardMessage(Map<String, dynamic> msg) async {
    final targetChat = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переслать...'),
        content: SizedBox(
          width: 400,
          height: 500,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: _chatItems.length,
                  itemBuilder: (context, index) {
                    final item = _chatItems[index];
                    final name = item['name'] ?? 'Чат';
                    return ListTile(
                      leading: TelegramAvatar(
                        name: name,
                        avatarUrl: item['avatar_url'],
                        uniqueId: item['id'].toString(),
                        radius: 18,
                      ),
                      title: Text(name),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ],
      ),
    );

    if (targetChat != null) {
      final targetId = targetChat['id'].toString();
      final targetType = targetChat['_item_type'].toString();

      String? receiverId;
      String? groupChatId;

      if (targetType == 'group') {
        groupChatId = targetId;
      } else {
        receiverId = targetChat['_partner_id'];
      }

      await SupaMessageService.sendMessage(
        senderId: _userId,
        content: msg['content'] ?? '',
        receiverId: receiverId,
        groupChatId: groupChatId,
        messageType: msg['message_type'] ?? 'text',
        attachmentUrl: msg['attachment_url'],
        attachmentName: msg['attachment_name'],
        attachmentSize: msg['attachment_size'] as int?,
        forwardedFromId: msg['sender_id'],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сообщение переслано')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for notification navigation events
    ref.listen(messengerNavigationProvider, (previous, next) {
      if (next != null) {
        debugPrint('🎯 MESSENGER: Navigation provider changed, checking link...');
        _checkDeepLink();
      }
    });

    if (widget.role == 'client') {
      // Clients only see the chat shell directly, no CRM navigation
      return Scaffold(
        body: SafeArea(
          child: _buildMessengerShell(context),
        ),
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
        body: SafeArea(child: bodyContent),
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
            final name = (item['display_name'] as String? ?? '').toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    // Sorting: Pinned first, then by last message time
    final sortedItems = List<Map<String, dynamic>>.from(filteredItems)
      ..sort((a, b) {
        final idA = (a['id'] ?? '').toString();
        final idB = (b['id'] ?? '').toString();
        final isPinnedA = _pinnedChatIds.contains(idA);
        final isPinnedB = _pinnedChatIds.contains(idB);

        if (isPinnedA && !isPinnedB) return -1;
        if (!isPinnedA && isPinnedB) return 1;

        final timeA = a['_last_message_time'] as String? ?? '';
        final timeB = b['_last_message_time'] as String? ?? '';
        return timeB.compareTo(timeA);
      });

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
                      if (mounted) {
                        context.push('/profile');
                      }
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
              : sortedItems.isEmpty
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
                        itemCount: sortedItems.length,
                        itemBuilder: (context, index) {
                          final item = sortedItems[index];
                          final id = (item['id'] ?? '').toString();
                          final type = (item['_item_type'] ?? item['item_type'] ?? 'individual').toString();
                          final name = (item['_display_name'] ?? item['display_name'] ?? 'Аноним').toString();
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
                            isMuted: _mutedChatIds.contains(id),
                            statusIcon: _buildStatusIcon(item, isDark),
                            onStatusTap: () => _showStatusInfo(item),
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
        final messenger = ScaffoldMessenger.of(context);
        for (final file in details.files) {
          final bytes = await file.readAsBytes();
          final size = await file.length();
          if (size > ChatAttachmentService.maxFileSizeBytes) {
            if (mounted) {
              messenger.showSnackBar(
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
              subtitle: _selectedChatType == 'individual'
                  ? (_onlineUsers.contains(_chatItems.firstWhere((c) => c['id'] == _selectedChatId, orElse: () => {})['_partner_id'])
                      ? 'в сети'
                      : widget.role == 'client'
                          ? 'Поддержка'
                          : 'был(а) недавно')
                  : _selectedChatType == 'group'
                      ? '${_onlineUsers.where((u) => u != _userId).length + 1} в сети' // Rough estimate or fetch real count
                      : isChannel
                          ? 'Канал'
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
              // if (widget.role == 'client' && _selectedChatType == 'direct') return; // Do not show school admin profile
              
              if (MediaQuery.of(context).size.width >= 768) {
                setState(() => _showProfilePanel = !_showProfilePanel);
              } else {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatInfoDialog(
                    chatId: _selectedChatId!,
                    chatType: _selectedChatType!,
                    userRole: widget.role,
                    onUpdate: _loadChatList,
                    onSearch: _onSearchInChat,
                    onMute: _onMuteChat,
                  ),
                ));
              }
            },
            ),
              if (_pinnedMessages.isNotEmpty) _buildPinnedBar(),
              if (_isSearchingInChat)
                Container(
                  color: isDark ? TelegramColors.darkSurface : TelegramColors.lightSurface,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: ChatSearchBar(
                                controller: _chatSearchController,
                                hint: 'Поиск по сообщениям...',
                                onChanged: _performSearch,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _isSearchingInChat = false;
                                _searchResults = [];
                              }),
                              child: const Text('Отмена'),
                            ),
                          ],
                        ),
                      ),
                      if (_searchResults.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final res = _searchResults[index];
                              return ListTile(
                                leading: const Icon(Icons.history_rounded, size: 16),
                                title: Text(res['content'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  DateFormat('dd.MM HH:mm').format(DateTime.parse(res['created_at'])),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                dense: true,
                                onTap: () {
                                  // In a real app, we would jump to this message ID
                                  setState(() => _isSearchingInChat = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Переход к сообщению...')),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              _PresenceBanner(chatId: _selectedChatId),
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
                        onReply: (msg) => setState(() {
                          _replyingTo = msg;
                          _editingMessage = null;
                        }),
                        onEdit: (msg) => setState(() {
                          _editingMessage = msg;
                          _replyingTo = null;
                        }),
                        onDelete: _deleteMessage,
                        onForward: _onForwardMessage,
                        onPin: (msg) => _togglePin(msg['id'].toString(), msg['pinned_at'] == null),
                        onReact: _toggleReaction,
                        reactionsMap: _reactionsMap,
                      ),
          ),
          // Input (not for channels unless user has permission)
          if (!isChannel)
            Column(
              children: [
                if (_typingText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _typingText,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? TelegramColors.darkTextSecondary
                              : TelegramColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ),
                MessageInput(
                  replyingTo: _replyingTo,
                  editingMessage: _editingMessage,
                  onCancelMode: () => setState(() {
                    _replyingTo = null;
                    _editingMessage = null;
                  }),
                  onSendText: _sendTextMessage,
                  onSendVoice: _sendVoiceMessage,
                  onTyping: _handleTyping,
                  onSendFile: (bytes, name, size, {caption}) async {
                    _showSendFileDialog(bytes, name, size);
                  },
                ),
              ],
            )
          else
            FutureBuilder<bool>(
              future: _canPostToChannel(_selectedChatId!),
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return MessageInput(
                    onSendText: _sendTextMessage,
                    onTyping: _handleTyping,
                    onSendFile: (bytes, name, size, {caption}) async {
                      _sendFileMessage(bytes, name, size, caption: caption);
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



  Widget? _buildStatusIcon(Map<String, dynamic> item, bool isDark) {
    if (widget.role != 'admin' && widget.role != 'manager') return null;
    if (item['_item_type'] != 'group') return null;

    final respondedAt = item['_group_data']?['responded_at'];
    if (respondedAt == null) {
      return Icon(Icons.help_outline_rounded, size: 18, color: Colors.amber.shade700);
    } else {
      return const Icon(Icons.check_circle_rounded, size: 18, color: Colors.green);
    }
  }

  void _showStatusInfo(Map<String, dynamic> item) {
    final groupData = item['_group_data'];
    if (groupData == null) return;

    final respondedAt = groupData['responded_at'];
    if (respondedAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('На этот запрос еще никто не ответил')),
      );
      return;
    }

    final responder = groupData['first_responder'];
    final responderName = responder != null 
        ? '${responder['first_name'] ?? ''} ${responder['last_name'] ?? ''}'.trim()
        : 'Неизвестно';
    
    final time = DateFormat('dd.MM HH:mm').format(DateTime.parse(respondedAt));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Информация об ответе'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.person_rounded, color: TelegramColors.accentBlue),
              title: const Text('Ответил первым:'),
              subtitle: Text(responderName),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.access_time_rounded, color: TelegramColors.accentBlue),
              title: const Text('Время ответа:'),
              subtitle: Text(time),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  // ── Pinned Bar ────────────────────────────────────────────────────────────

  Widget _buildPinnedBar() {
    if (_pinnedMessages.isEmpty) return const SizedBox.shrink();
    
    final lastPinned = _pinnedMessages.last;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _jumpToMessage(lastPinned['id']),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.push_pin_rounded, size: 18, color: TelegramColors.accentBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Закрепленное сообщение',
                        style: TextStyle(
                          color: TelegramColors.accentBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        lastPinned['content'] ?? 'Вложение',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_pinnedMessages.length > 1)
                  Text(
                    '${_pinnedMessages.length}',
                    style: TextStyle(color: TelegramColors.accentBlue, fontSize: 12),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => _togglePin(lastPinned['id'], false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _fetchPinnedMessages() async {
    if (_selectedChatId == null) return;
    try {
      final res = await SupaMessageService.getPinnedMessages(
        _selectedChatId!,
        _selectedChatType == 'group' ? 'group' : 'direct',
      );
      if (mounted) {
        setState(() => _pinnedMessages = res);
      }
    } catch (e) {
      debugPrint('Error fetching pinned messages: $e');
    }
  }

  Future<void> _togglePin(String messageId, bool pin) async {
    try {
      await SupaMessageService.toggleMessagePin(messageId: messageId, isPinned: pin);
      _fetchPinnedMessages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при закреплении: $e')),
      );
    }
  }

  void _jumpToMessage(String messageId) {
    final msgIndex = _messages.indexWhere((m) => m['id'] == messageId);
    if (msgIndex != -1) {
      // TODO: Implement jump
    }
  }
} // End of _MessengerScreenState

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

  final Function(Map<String, dynamic>)? onReply;
  final Function(Map<String, dynamic>)? onEdit;
  final Function(Map<String, dynamic>)? onDelete;
  final Function(Map<String, dynamic>)? onForward;
  final Function(Map<String, dynamic>)? onPin;
  final Function(String, String)? onReact;
  final Map<String, List<dynamic>>? reactionsMap;

  const _MessageListView({
    required this.messages,
    required this.currentUserId,
    required this.isGroupChat,
    required this.isChannel,
    required this.chatItems,
    required this.adminIds,
    required this.role,
    this.selectedChatName,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onForward,
    this.onPin,
    this.onReact,
    this.reactionsMap,
  });

  @override
  State<_MessageListView> createState() => _MessageListViewState();
}

class _MessageListViewState extends State<_MessageListView> {
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  // Cache for sender names (profile lookups)
  final Map<String, String> _senderNameCache = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    
    // Show button if we are more than 200px from the bottom
    final isNearBottom = _scrollController.position.maxScrollExtent - _scrollController.offset < 200;
    
    if (isNearBottom && _showScrollToBottom) {
      if (mounted) setState(() => _showScrollToBottom = false);
    } else if (!isNearBottom && !_showScrollToBottom) {
      if (mounted) setState(() => _showScrollToBottom = true);
    }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: widget.messages.length,
          itemBuilder: (context, index) {
            final msg = widget.messages[index];
            final isMe = msg['sender_id'] == widget.currentUserId;
            
            // Resolve replied message from current list
            Map<String, dynamic>? repliedMsg;
            final replyId = msg['reply_to_id']?.toString();
            if (replyId != null) {
              try {
                repliedMsg = widget.messages.firstWhere((m) => m['id'].toString() == replyId);
              } catch (_) {
                // Not in current list (already deleted or too old)
              }
            }

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
                  repliedMessage: repliedMsg,
                  onReply: () => widget.onReply?.call(msg),
                  onEdit: () => widget.onEdit?.call(msg),
                  onDelete: () => widget.onDelete?.call(msg),
                  onForward: () => widget.onForward?.call(msg),
                  onPin: () => widget.onPin?.call(msg),
                  onReact: (emoji) => widget.onReact?.call(msg['id'], emoji),
                  reactions: widget.reactionsMap?[msg['id'].toString()],
                ),
              ],
            );
          },
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 16,
            bottom: 16,
            child: AnimatedOpacity(
              opacity: _showScrollToBottom ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton.small(
                onPressed: _scrollToBottom,
                backgroundColor: isDark ? TelegramColors.darkSidebar : Colors.white,
                foregroundColor: TelegramColors.brandPurple,
                elevation: 4,
                child: const Icon(Icons.arrow_downward_rounded),
              ),
            ),
          ),
      ],
    );
  }
}

class _PresenceBanner extends ConsumerWidget {
  final String? chatId;
  const _PresenceBanner({this.chatId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (chatId == null) return const SizedBox.shrink();
    
    final presenceAsync = ref.watch(chatPresenceProvider(chatId!));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return presenceAsync.when(
      data: (admins) {
        if (admins.isEmpty) return const SizedBox.shrink();
        
        final text = admins.length == 1 
            ? '${admins.first} ведет диалог' 
            : '${admins.length} админа в чате';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          color: Colors.amber.withAlpha(25),
          child: Row(
            children: [
              const Icon(Icons.remove_red_eye_rounded, size: 14, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
