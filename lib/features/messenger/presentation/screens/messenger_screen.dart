import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/widgets/adaptive_messenger_shell.dart';
import 'package:magic_music_crm/core/widgets/v7/v7_nav_shell.dart';
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
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/providers/theme_provider.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:magic_music_crm/core/widgets/telegram/send_file_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/user_roles_widget.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_portal_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/admin_overview_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manager_overview_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/students_board_providers.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/tasks_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_students_widget.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/lead_detail_dialog.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:mime/mime.dart';

void _logMessenger(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

/// Unified Telegram-style messenger screen used by all roles.
class MessengerScreen extends ConsumerStatefulWidget {
  final String role; // 'client', 'admin', 'system_admin', 'manager', 'teacher'
  const MessengerScreen({super.key, required this.role});

  @override
  ConsumerState<MessengerScreen> createState() => _MessengerScreenState();
}

class _MessengerScreenState extends ConsumerState<MessengerScreen> {
  String? _selectedChatId;
  String? _selectedChatType; // 'direct', 'group', 'channel'
  String? _selectedChatName;
  String? _selectedChatAvatarUrl;
  String? _selectedPartnerId;
  String? _adminAvatarUrl;

  // Data
  List<Map<String, dynamic>> _chatItems = [];
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _pinnedMessages = [];
  final Set<String> _hiddenPinnedBars = {};
  Map<String, List<dynamic>> _reactionsMap = {};
  Map<String, int> _unreadCounts = {};
  Set<String> _mutedChatIds = {};
  Set<String> _pinnedChatIds = {};
  bool _loadingChats = true;
  bool _loadingMessages = false;
  String _searchQuery = '';
  int _selectedCrmTab = 0;
  int _selectedReportsTab = 0;
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
  String _typingText = '';
  Timer? _typingStopTimer;
  final Set<String> _onlineUsers = {};
  StateSetter? _pinnedDialogSetState;
  MagicRealtimeConnection? _realtimeConnection;
  String? _joinedRealtimeChatId;
  String? _currentUserId;

  bool get _isAdminRole =>
      widget.role == 'admin' || widget.role == 'system_admin';

  bool get _isManagerOrAdminRole => _isAdminRole || widget.role == 'manager';

  /// A1: manager-tier access for the manager-only CRM destinations and role
  /// editing. Администратор (`admin`) is EXCLUDED (Управляющий > Администратор);
  /// superuser `system_admin` is included. See [crmHasManagerAccess].
  bool get _hasManagerAccess => crmHasManagerAccess(widget.role);

  bool get _isStaffRole => _isManagerOrAdminRole || widget.role == 'teacher';
  String _currentUserDisplayName = 'Пользователь';
  String? _openingNavigationPartnerId;
  String? _userRolesInitialSearch;

  @override
  void initState() {
    super.initState();
    _bootstrapMessenger();

    // Check for pending navigation from notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDeepLink();
    });
  }

  Future<void> _bootstrapMessenger() async {
    // Profile and chat list are independent — load in parallel.
    // Realtime needs _currentUserId from profile, so it waits for both.
    await Future.wait([_loadCurrentProfile(), _loadChatList()]);
    if (!mounted) return;
    await _connectRealtime();
  }

  Future<void> _loadCurrentProfile() async {
    try {
      final profile = await ref.read(magicAuthServiceProvider).currentProfile();
      final name = '${profile.firstName ?? ''} ${profile.lastName ?? ''}'
          .trim();
      if (mounted) {
        setState(() {
          _currentUserId = profile.userId;
          _currentUserDisplayName = name.isEmpty ? profile.email : name;
        });
      }
    } catch (e) {
      _logMessenger('MessengerScreen: Error loading v3 profile: $e');
    }
  }

  void _checkDeepLink() {
    final nav = ref.read(messengerNavigationProvider);
    if (nav != null) {
      if (mounted) {
        _logMessenger(
          'MessengerScreen: processing deep link. Partner: ${nav.partnerId}, Group: ${nav.groupChatId}',
        );
        _logMessenger(
          'MessengerScreen: chat items count: ${_chatItems.length}',
        );

        // Don't attempt matching if chat list hasn't loaded yet
        if (_chatItems.isEmpty) {
          _logMessenger(
            'MessengerScreen: chat list not loaded yet, deferring deep link',
          );
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
          // Special case: null partnerId with no groupChatId = administration chat.
          return c['id'] == 'admin_chat';
        }).firstOrNull;

        if (item != null) {
          _logMessenger('MessengerScreen: found target chat, selecting.');
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
          _logMessenger(
            'MessengerScreen: target chat not found in items, keeping state for retry',
          );
          if (nav.partnerId != null) {
            unawaited(_openDirectChatFromNavigation(nav.partnerId!));
          }
          // DON'T clear — _loadChatList will call _checkDeepLink again after loading
        }
      }
    }
  }

  Future<void> _openDirectChatFromNavigation(String partnerId) async {
    if (_openingNavigationPartnerId == partnerId) return;
    _openingNavigationPartnerId = partnerId;
    try {
      final chat = await ref
          .read(magicMessengerServiceProvider)
          .ensureDirectChat(partnerId);
      if (!mounted) return;
      final item = {
        ...chat,
        '_item_type': 'direct',
        '_partner_id': partnerId,
        '_display_name': chat['_display_name'] ?? chat['title'] ?? 'Личный чат',
      };
      setState(() {
        _chatItems = [
          if (!_chatItems.any((chatItem) => chatItem['id'] == item['id'])) item,
          ..._chatItems.where((chatItem) => chatItem['id'] != item['id']),
        ];
        _selectedCrmTab = 0;
      });
      _selectChat(item);
      Future.microtask(() {
        ref.read(messengerNavigationProvider.notifier).clear();
      });
    } catch (e) {
      _logMessenger('MessengerScreen: Error opening direct chat from CRM: $e');
    } finally {
      if (_openingNavigationPartnerId == partnerId) {
        _openingNavigationPartnerId = null;
      }
    }
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    _leaveTypingChannel();
    _realtimeConnection?.dispose();
    super.dispose();
  }

  // ── CRM actions from a chat (staff only) ───────────────────────────────────

  // KVA-173/174/175 helper — floating above the input bar.
  void _showChatSnack(
    String text, {
    Color? bg,
    Duration? duration,
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 72, left: 12, right: 12),
        duration: duration ?? const Duration(seconds: 4),
        action: action,
      ),
    );
  }

  Future<void> _saveContactFromChat(String as) async {
    final partnerId = _selectedPartnerId;
    if (partnerId == null || partnerId.isEmpty) return;
    final label = as == 'lead' ? 'лид' : 'ученик';
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .saveContactFromChat(userId: partnerId, as: as);
      if (!mounted) return;
      final created = result['created'] == true;
      final leadId = result['leadId']?.toString() ?? '';
      // KVA-175: offer to open the lead card straight from the snackbar.
      final leadStub = <String, dynamic>{'id': leadId};
      _showChatSnack(
        created
            ? 'Контакт сохранён как $label'
            : 'Контакт уже был сохранён как $label',
        bg: Colors.green,
        action: (as == 'lead' && leadId.isNotEmpty)
            ? SnackBarAction(
                label: 'Открыть карточку',
                textColor: Colors.white,
                onPressed: () => _openLeadCard(leadStub),
              )
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      _showChatSnack('Не удалось сохранить: $e', bg: AppColor.danger);
    }
  }

  // KVA-175: open LeadDetailDialog for a given lead stub/map.
  Future<void> _openLeadCard(Map<String, dynamic> lead) async {
    if (!mounted) return;
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

  Future<void> _openContactCard() async {
    final partnerId = _selectedPartnerId;
    if (partnerId == null || partnerId.isEmpty) return;
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final contact = await crm.resolveContactForUser(partnerId);
      final studentId = contact['studentId']?.toString();
      final leadId = contact['leadId']?.toString();
      if (studentId != null && studentId.isNotEmpty) {
        if (!mounted) return;
        // Open the canonical (rich, tabbed) student screen.
        context.push('/student/$studentId');
      } else if (leadId != null && leadId.isNotEmpty) {
        if (!mounted) return;
        // KVA-175: open lead card directly in a dialog instead of redirecting.
        await _openLeadCard({'id': leadId});
      } else {
        if (!mounted) return;
        _showChatSnack(
          'Этот контакт ещё не сохранён в CRM. '
          'Сохраните его как лид или ученик.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showChatSnack(
        'Не удалось открыть карточку: $e',
        bg: AppColor.danger,
      );
    }
  }

  String get _userId => _currentUserId ?? '';

  // ── Load chat list ─────────────────────────────────────────────────────────

  Future<void> _loadChatList() async {
    try {
      // Set a global timeout for the entire loading process
      await _loadChatListInternal().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _logMessenger('Chat list loading timed out');
          if (mounted) setState(() => _loadingChats = false);
        },
      );
    } catch (e) {
      _logMessenger('Error loading chat list: $e');
      if (mounted) setState(() => _loadingChats = false);
    }
  }

  Future<void> _loadChatListInternal() async {
    final isStaff = _isStaffRole;
    final messenger = ref.read(magicMessengerServiceProvider);

    final rawItemsFuture = messenger.listChats(limit: 100);
    final channelsFuture = messenger.listChannels();
    final adminAvatarFuture = ref
        .read(magicSettingsServiceProvider)
        .getAdminChatAvatar();
    final Future<Map<String, dynamic>?> adminChatFuture = isStaff
        ? Future<Map<String, dynamic>?>.value(null)
        : messenger.ensureAdministrationChat();
    final Future<List<Map<String, dynamic>>> adminProfilesFuture = isStaff
        ? ref
              .read(magicProfileAdminServiceProvider)
              .listProfiles(limit: 100)
              .catchError((Object e) {
                _logMessenger(
                  'MessengerScreen: Error loading admin profiles: $e',
                );
                return <Map<String, dynamic>>[];
              })
        : Future<List<Map<String, dynamic>>>.value(
            const <Map<String, dynamic>>[],
          );

    final rawItems = await rawItemsFuture;
    final adminChat = await adminChatFuture;
    if (adminChat != null) {
      if (!rawItems.any((item) => item['id'] == adminChat['id'])) {
        rawItems.insert(0, adminChat);
      }
    }

    final channels = await channelsFuture;
    rawItems.addAll(channels);

    _adminAvatarUrl = await adminAvatarFuture;
    if (isStaff) {
      final adminProfiles = await adminProfilesFuture;
      _adminIds = adminProfiles
          .where(
            (profile) =>
                profile['role'] == 'admin' ||
                profile['role'] == 'manager' ||
                profile['role'] == 'system_admin',
          )
          .map((profile) => profile['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } else {
      _adminIds = const [];
    }

    // 3. Map raw items to internal state
    final items = <Map<String, dynamic>>[];
    final unreadCounts = <String, int>{};
    final mutedIds = <String>{};
    final pinnedIds = <String>{};

    for (final raw in rawItems) {
      final id = raw['id'].toString();
      final itemType = raw['_item_type'] ?? raw['item_type'] ?? raw['type'];
      final lastMessage = raw['_last_message'];

      // Construct item for _chatItems list
      final item = {
        'id': id,
        '_item_type': itemType,
        '_display_name': raw['_display_name'] ?? raw['display_name'],
        '_partner_id': raw['_partner_id'] ?? raw['partner_id'],
        '_partner_data': raw['_partner_data'] ?? raw['partner'],
        '_last_message': lastMessage,
        '_last_message_time':
            raw['_last_message_time'] ?? raw['last_message_created_at'],
        '_avatar_url':
            raw['_avatar_url'] ??
            raw['avatar_url'] ??
            (raw['raw_type'] == 'administration' ? _adminAvatarUrl : null),
        '_group_data': itemType == 'group' ? raw : null,
        '_channel_data': itemType == 'channel' ? raw : null,
      };
      items.add(item);

      // Update auxiliary states
      unreadCounts[id] = raw['unread_count'] ?? 0;
      if (raw['is_muted'] == true) mutedIds.add(id);
      if (raw['is_pinned'] == true) pinnedIds.add(id);
    }

    if (_selectedChatId != null) {
      unreadCounts[_selectedChatId!] = 0;
    }

    if (mounted) {
      setState(() {
        _chatItems = items;
        _unreadCounts = unreadCounts;
        _mutedChatIds = mutedIds;
        _pinnedChatIds = pinnedIds;
        _loadingChats = false;

        // Update selected chat info from list
        if (_selectedChatId != null) {
          try {
            final selectedItem = items.firstWhere(
              (i) => i['id'] == _selectedChatId,
            );
            _selectedChatName = selectedItem['_display_name'];
            _selectedChatAvatarUrl = _getAvatarUrl(selectedItem);
            _selectedPartnerId = selectedItem['_partner_id']?.toString();
          } catch (_) {}
        }
      });
      _checkDeepLink();
    }
  }

  // Legacy loading methods removed in favor of RPC get_recent_chats_v3

  // Legacy loading methods removed in favor of RPC get_recent_chats_v3

  // ── Load messages for selected chat ────────────────────────────────────────

  Future<void> _loadMessages() async {
    if (_selectedChatId == null) return;

    _currentLoadId++;
    final loadId = _currentLoadId;

    _logMessenger(
      'MessengerScreen: _loadMessages started for $_selectedChatId (LoadId: $loadId)',
    );

    setState(() {
      _loadingMessages = true;
      _messages = [];
    });

    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      if (_selectedChatType == 'channel') {
        final posts = await messenger
            .listChannelPosts(_selectedChatId!, limit: 100)
            .timeout(const Duration(seconds: 20));

        if (loadId != _currentLoadId) return;

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(posts);
            _sortMessagesChronologically();
          });
        }
      } else {
        final msgs = await messenger
            .listMessages(_selectedChatId!, limit: 100)
            .timeout(const Duration(seconds: 20));

        if (loadId != _currentLoadId) return;

        if (mounted) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(msgs);
            _sortMessagesChronologically();
          });
          _fetchReactionsForCurrentMessages();
          _markMessagesRead();
        }
      }
    } on Exception catch (e) {
      _logMessenger('MessengerScreen error [LoadId: $loadId]: $e');
      if (mounted && loadId == _currentLoadId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки сообщений: ${e.toString()}'),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted && loadId == _currentLoadId) {
        setState(() => _loadingMessages = false);
        _logMessenger(
          'MessengerScreen: _loadMessages finished (LoadId: $loadId)',
        );
      }
    }
  }

  Future<void> _markMessagesRead() async {
    if (_selectedChatId == null) return;
    final chatId = _selectedChatId!;
    final previous = _unreadCounts[chatId] ?? 0;
    setState(() => _unreadCounts[chatId] = 0);
    // Pass the latest message ID so the server can skip the resolve query.
    final lastMsgId = _messages.isNotEmpty
        ? _messages.last['id']?.toString()
        : null;
    try {
      await ref
          .read(magicMessengerServiceProvider)
          .markRead(chatId, lastReadMessageId: lastMsgId);
    } catch (e) {
      if (mounted) setState(() => _unreadCounts[chatId] = previous);
      _logMessenger('MessengerScreen: Error marking messages as read: $e');
    }
  }

  // ── Realtime subscription ──────────────────────────────────────────────────

  Future<void> _connectRealtime() async {
    try {
      _realtimeConnection?.dispose();
      final connection = await ref.read(magicRealtimeServiceProvider).connect();
      _realtimeConnection = connection;
      if (_userId.isNotEmpty) connection.joinUserRoom(_userId);

      connection.onMessageCreated(_handleRealtimeMessageCreated);
      connection.onMessageUpdated(_handleRealtimeMessageUpdated);
      connection.onChannelPostCreated(_handleRealtimeChannelPostCreated);
      connection.onChatUpdated(_handleRealtimeChatUpdated);
      connection.onTypingStart(_handleRealtimeTypingStart);
      connection.onTypingStop(_handleRealtimeTypingStop);
      connection.onPresenceUpdated(_handleRealtimePresenceUpdated);
    } catch (e) {
      _logMessenger('MessengerScreen: Error connecting v3 realtime: $e');
    }
  }

  void _handleRealtimeMessageCreated(Map<String, dynamic> payload) {
    if (!mounted) return;
    final message = _normalizeRealtimeMessage(payload);
    final chatId = message['chat_id']?.toString();
    final senderId = message['sender_id']?.toString();
    if (chatId == null) return;

    if (_selectedChatId == chatId) {
      setState(() {
        _upsertMessage(message);
      });
      if (senderId != _userId) _markMessagesRead();
    } else if (senderId != _userId) {
      setState(() => _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1);
    }

    _updateChatItemLastMessage(message);
    if (senderId != _userId &&
        chatId != _selectedChatId &&
        !_mutedChatIds.contains(chatId)) {
      final senderName =
          _chatItems
              .where((c) => c['id'] == chatId)
              .firstOrNull?['_display_name'] ??
          'Новое сообщение';
      NotificationService.showLocalNotification(
        title: senderName,
        body: message['content'] ?? 'Сообщение',
        payload: {'type': 'chat', 'id': chatId},
      );
    }
  }

  void _handleRealtimeMessageUpdated(Map<String, dynamic> payload) {
    if (!mounted) return;
    final message = _normalizeRealtimeMessage(payload);
    final messageId = message['id']?.toString();
    if (messageId == null) return;

    setState(() {
      final idx = _messages.indexWhere((msg) => msg['id'] == messageId);
      if (idx != -1) {
        _messages[idx] = {..._messages[idx], ...message};
      }
      if (payload['reactions'] is List) {
        _reactionsMap[messageId] = payload['reactions'] as List<dynamic>;
      }
    });
    _fetchPinnedMessages();
  }

  void _handleRealtimeChannelPostCreated(Map<String, dynamic> payload) {
    if (!mounted) return;
    final post = _normalizeRealtimeChannelPost(payload);
    final channelId = post['channel_id']?.toString();
    if (channelId == null) return;

    if (_selectedChatId == channelId && _selectedChatType == 'channel') {
      setState(() {
        _upsertMessage(post);
      });
    }
    _updateChatItemLastMessage({...post, '_is_channel_post': true});
  }

  void _handleRealtimeChatUpdated(Map<String, dynamic> payload) {
    if (!mounted) return;
    final chatId = (payload['id'] ?? payload['chatId'])?.toString();
    final readerId = payload['readerId']?.toString();
    if (chatId != null && readerId != null) {
      if (readerId == _userId) {
        setState(() => _unreadCounts[chatId] = 0);
      }
      return;
    }

    final userId = payload['userId']?.toString();
    if (chatId != null && userId == _userId && payload.containsKey('isMuted')) {
      final isMuted = payload['isMuted'] == true;
      setState(() {
        if (isMuted) {
          _mutedChatIds.add(chatId);
        } else {
          _mutedChatIds.remove(chatId);
        }
      });
      return;
    }

    _loadChatList();
  }

  void _handleRealtimeTypingStart(Map<String, dynamic> payload) {
    if (!mounted || payload['chatId'] != _selectedChatId) return;
    final userId = payload['userId']?.toString();
    if (userId == null || userId == _userId) return;
    setState(() => _typingText = 'Пользователь печатает...');
  }

  void _handleRealtimeTypingStop(Map<String, dynamic> payload) {
    if (!mounted || payload['chatId'] != _selectedChatId) return;
    setState(() => _typingText = '');
  }

  void _handleRealtimePresenceUpdated(Map<String, dynamic> payload) {
    if (!mounted) return;
    final userId = payload['userId']?.toString();
    if (userId == null || userId == _userId) return;
    final status = payload['status']?.toString();
    setState(() {
      if (status == 'offline') {
        _onlineUsers.remove(userId);
      } else {
        _onlineUsers.add(userId);
      }
    });
  }

  Map<String, dynamic> _normalizeRealtimeMessage(Map<String, dynamic> payload) {
    final sender = payload['sender'];
    final senderMap = sender is Map
        ? sender.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    return {
      'id': payload['id'],
      'chat_id': payload['chatId'] ?? payload['chat_id'],
      'sender_id': payload['senderId'] ?? payload['sender_id'],
      'content': payload['content'],
      'message_type': payload['messageType'] ?? payload['message_type'],
      'attachment_file_id':
          payload['attachmentFileId'] ?? payload['attachment_file_id'],
      'attachment_name':
          payload['attachmentName'] ??
          payload['attachmentFileName'] ??
          payload['attachment_name'],
      'attachment_size':
          payload['attachmentSize'] ??
          payload['attachmentFileSize'] ??
          payload['attachment_size'],
      'attachment_mime_type':
          payload['attachmentMimeType'] ??
          payload['attachmentContentType'] ??
          payload['attachment_mime_type'],
      'reply_to_id': payload['replyToId'] ?? payload['reply_to_id'],
      'forwarded_from_id':
          payload['forwardedFromId'] ?? payload['forwarded_from_id'],
      'pinned_by': payload['pinnedBy'] ?? payload['pinned_by'],
      'pinned_at': payload['pinnedAt'] ?? payload['pinned_at'],
      'created_at': payload['createdAt'] ?? payload['created_at'],
      'updated_at': payload['updatedAt'] ?? payload['updated_at'],
      'deleted_at': payload['deletedAt'] ?? payload['deleted_at'],
      'is_read':
          payload['isRead'] == true ||
          payload['is_read'] == true ||
          payload['read'] == true,
      if (payload['reactions'] is List) 'reactions': payload['reactions'],
      'profiles': {
        'id': senderMap['id'],
        'first_name': senderMap['firstName'] ?? senderMap['first_name'],
        'last_name': senderMap['lastName'] ?? senderMap['last_name'],
      },
    };
  }

  Map<String, dynamic> _normalizeRealtimeChannelPost(
    Map<String, dynamic> payload,
  ) {
    return {
      'id': payload['id'],
      'channel_id': payload['channelId'] ?? payload['channel_id'],
      'author_id': payload['authorId'] ?? payload['author_id'],
      'sender_id': payload['authorId'] ?? payload['author_id'],
      'content': payload['content'],
      'attachment_file_id':
          payload['attachmentFileId'] ?? payload['attachment_file_id'],
      'message_type':
          (payload['attachmentFileId'] ?? payload['attachment_file_id']) == null
          ? 'text'
          : 'file',
      'published_at': payload['publishedAt'] ?? payload['published_at'],
      'created_at': payload['publishedAt'] ?? payload['published_at'],
      'updated_at': payload['updatedAt'] ?? payload['updated_at'],
      'is_read': true,
    };
  }

  void _updateChatItemLastMessage(Map<String, dynamic> msg) {
    final chatId = msg['chat_id']?.toString();
    final groupChatId = msg['group_chat_id']?.toString();
    final channelId = msg['channel_id']?.toString();
    final isChannel = msg['_is_channel_post'] == true;

    setState(() {
      for (var i = 0; i < _chatItems.length; i++) {
        final item = _chatItems[i];

        if (isChannel &&
            item['id'] == channelId &&
            item['_item_type'] == 'channel') {
          _chatItems[i] = {
            ...item,
            '_last_message': msg,
            '_last_message_time': msg['created_at'],
          };
          break;
        }

        if (chatId != null && item['id'] == chatId) {
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
            bool isRelevant =
                (senderId == _userId && receiverId == null) ||
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
            // For teachers, ignore messages to the administration queue.
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
    if (_joinedRealtimeChatId != chatId) {
      if (_joinedRealtimeChatId != null) {
        _realtimeConnection?.leaveRoom(_joinedRealtimeChatId!);
      }
      _joinedRealtimeChatId = chatId;
      _realtimeConnection?.joinChat(chatId);
      if (mounted) {
        setState(() {
          _typingText = '';
          _onlineUsers.clear();
        });
      }
    }
    _realtimeConnection?.updatePresence();
  }

  void _leaveTypingChannel() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    if (_joinedRealtimeChatId != null) {
      _realtimeConnection?.leaveRoom(_joinedRealtimeChatId!);
      _joinedRealtimeChatId = null;
    }
    if (mounted) {
      setState(() {
        _typingText = '';
        _onlineUsers.clear();
      });
    }
  }

  Future<void> _trackTyping(bool isTyping, String name) async {
    final chatId = _selectedChatId;
    if (chatId == null) return;
    if (isTyping) {
      _realtimeConnection?.startTyping(chatId);
    } else {
      _realtimeConnection?.stopTyping(chatId);
    }
  }

  void _handleTyping(bool isTyping) {
    _typingStopTimer?.cancel();
    unawaited(_trackTyping(isTyping, _currentUserDisplayName));

    if (isTyping) {
      final chatId = _selectedChatId;
      _typingStopTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted || _selectedChatId != chatId) return;
        unawaited(_trackTyping(false, _currentUserDisplayName));
      });
    } else {
      _typingStopTimer = null;
    }
  }

  // ── Send message ───────────────────────────────────────────────────────────

  void _upsertMessage(Map<String, dynamic> message) {
    final id = message['id']?.toString();
    if (id == null || id.isEmpty) return;
    final index = _messages.indexWhere((item) => item['id']?.toString() == id);
    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] = {..._messages[index], ...message};
    }
    _sortMessagesChronologically();
  }

  void _sortMessagesChronologically() {
    _messages.sort((a, b) {
      final aCreated = DateTime.tryParse(a['created_at']?.toString() ?? '');
      final bCreated = DateTime.tryParse(b['created_at']?.toString() ?? '');
      if (aCreated == null && bCreated == null) {
        return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
      }
      if (aCreated == null) return 1;
      if (bCreated == null) return -1;
      final byDate = aCreated.compareTo(bCreated);
      if (byDate != 0) return byDate;
      return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });
  }

  void _applySentMessage(Map<String, dynamic> message, {bool channel = false}) {
    if (!mounted) return;
    setState(() {
      _upsertMessage(message);
      if (message['id'] != null) _hiddenPinnedBars.remove(message['id']);
    });
    _updateChatItemLastMessage(
      channel ? {...message, '_is_channel_post': true} : message,
    );
  }

  void _removeMessageById(String messageId) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((item) => item['id']?.toString() == messageId);
    });
  }

  Map<String, dynamic> _optimisticTextMessage(
    String text, {
    String? replyToId,
  }) {
    final now = DateTime.now().toIso8601String();
    return {
      'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
      'chat_id': _selectedChatId,
      'sender_id': _userId,
      'sender_name': _currentUserDisplayName,
      'content': text,
      'message_type': 'text',
      'created_at': now,
      'reply_to_id': replyToId,
      'is_read': false,
      '_pending': true,
    };
  }

  Future<void> _sendTextMessage(
    String text, {
    String? replyToId,
    String? editingMessageId,
  }) async {
    if (_selectedChatId == null) return;
    final messenger = ref.read(magicMessengerServiceProvider);

    if (_selectedChatType == 'channel') {
      final optimistic = _optimisticTextMessage(text);
      _applySentMessage(optimistic, channel: true);
      try {
        final post = await messenger.createChannelPost(
          _selectedChatId!,
          content: text,
        );
        _removeMessageById(optimistic['id'].toString());
        _applySentMessage(post, channel: true);
      } catch (e) {
        _removeMessageById(optimistic['id'].toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось опубликовать сообщение: $e')),
          );
        }
      }
      return;
    }

    if (editingMessageId != null) {
      try {
        final updated = await messenger.updateMessage(
          editingMessageId,
          content: text,
        );
        if (!mounted) return;
        setState(() {
          final index = _messages.indexWhere(
            (message) => message['id']?.toString() == editingMessageId,
          );
          if (index != -1) {
            _messages[index] = {..._messages[index], ...updated};
          }
          _editingMessage = null;
        });
      } catch (e) {
        if (mounted) {
          setState(() => _editingMessage = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось изменить сообщение: $e')),
          );
        }
      }
      return;
    }

    final optimistic = _optimisticTextMessage(text, replyToId: replyToId);
    _applySentMessage(optimistic);
    try {
      final message = await messenger.sendMessage(
        _selectedChatId!,
        content: text,
        replyToId: replyToId,
      );

      if (!mounted) return;
      setState(() => _replyingTo = null);
      _removeMessageById(optimistic['id'].toString());
      _applySentMessage(message);
    } catch (e) {
      _removeMessageById(optimistic['id'].toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить сообщение: $e')),
        );
      }
    }
  }

  void _deleteMessage(Map<String, dynamic> msg) async {
    final mid = msg['id'].toString();
    final isMe = msg['sender_id'] == _userId;

    if (!isMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Вы можете удалять только свои сообщения'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление сообщения'),
        content: const Text(
          'Вы уверены, что хотите удалить это сообщение для всех?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: AppColor.danger),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final updated = await ref
            .read(magicMessengerServiceProvider)
            .deleteMessage(mid, mode: isMe ? 'own' : 'moderated');
        // Apply the server response locally so the message shows as deleted
        // immediately, independent of realtime delivery.
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m['id'] == mid);
            if (idx != -1) _messages[idx] = {..._messages[idx], ...updated};
          });
        }
      } catch (e) {
        _logMessenger('Error deleting message: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось удалить сообщение: $e')),
          );
        }
      }
    }
  }

  Future<void> _sendVoiceMessage(
    Uint8List bytes,
    int durationMs,
    String ext,
  ) async {
    if (_selectedChatId == null) return;
    final fileId = await ref
        .read(chatAttachmentServiceProvider)
        .uploadVoice(
          bytes: bytes,
          senderId: _userId,
          extension: ext,
          chatId: _selectedChatId!,
        );

    final message = await ref
        .read(magicMessengerServiceProvider)
        .sendMessage(
          _selectedChatId!,
          content: '🎤 Голосовое сообщение',
          messageType: 'voice',
          attachmentFileId: fileId,
        );
    _applySentMessage({...message, 'voice_duration_ms': durationMs});
  }

  Future<void> _sendFileMessage(
    Uint8List bytes,
    String fileName,
    int fileSize, {
    String? caption,
  }) async {
    if (_selectedChatId == null) return;
    final mimeType = lookupMimeType(fileName, headerBytes: bytes);
    final messageType = mimeType?.startsWith('image/') == true
        ? 'image'
        : 'file';
    final fileId = await ref
        .read(chatAttachmentServiceProvider)
        .uploadFile(
          bytes: bytes,
          originalFileName: fileName,
          senderId: _userId,
          chatId: _selectedChatId!,
        );

    final content = caption?.isNotEmpty == true ? caption!.trim() : fileName;
    final message = await ref
        .read(magicMessengerServiceProvider)
        .sendMessage(
          _selectedChatId!,
          content: content,
          messageType: messageType,
          attachmentFileId: fileId,
        );
    _applySentMessage({
      ...message,
      'message_type': messageType,
      'attachment_file_id': fileId,
      'attachment_name': fileName,
      'attachment_size': fileSize,
      'attachment_mime_type': mimeType,
    });
  }

  void _showSendFileDialog(Uint8List bytes, String fileName, int fileSize) {
    showDialog(
      context: context,
      builder: (context) => SendFileDialog(
        fileName: fileName,
        fileSize: fileSize,
        fileBytes: bytes,
        onSend: (caption) =>
            _sendFileMessage(bytes, fileName, fileSize, caption: caption),
      ),
    );
  }

  // ── Chat selection ─────────────────────────────────────────────────────────

  void _selectChat(Map<String, dynamic> item) {
    String id = (item['id'] ?? '').toString();
    final type = (item['_item_type'] ?? item['item_type'] ?? 'direct')
        .toString();

    // Robust ID resolution:
    // If the ID looks like a user ID (e.g. from profile), try to find an existing chat session first
    if (type == 'direct' && id.isNotEmpty) {
      final existingChat = _chatItems
          .where((c) => c['id'] == id || c['_partner_id'] == id)
          .toList();

      if (existingChat.isNotEmpty) {
        // Use the existing chat's ID (the UUID for the conversation)
        id = existingChat.first['id'].toString();
      }
    }

    if (id == _selectedChatId && _loadingMessages) return;

    final avatarUrl = _getAvatarUrl(item);
    final partnerId =
        item['_partner_id']?.toString() ?? item['partner_id']?.toString();
    final name =
        (item['_display_name'] ??
                item['display_name'] ??
                item['name'] ??
                'Аноним')
            .toString();

    setState(() {
      _selectedChatId = id;
      _selectedChatType = type;
      _selectedChatName = name;
      _selectedChatAvatarUrl = avatarUrl;
      _selectedPartnerId = partnerId;
      _messages = [];
      _onlineUsers.clear();
    });

    _loadMessages();
    _joinTypingChannel(id);
    _joinPresenceChannel(id);
    _joinReactionsChannel(id);
    _fetchPinnedMessages();
  }

  Future<void> _joinReactionsChannel(String chatId) async {
    _realtimeConnection?.joinChat(chatId);
  }

  Future<void> _joinPresenceChannel(String chatId) async {
    _realtimeConnection?.joinChat(chatId);
    _realtimeConnection?.updatePresence();
  }

  void _deselectChat() {
    _leaveTypingChannel();
    setState(() {
      _selectedChatId = null;
      _selectedChatType = null;
      _selectedChatName = null;
      _selectedChatAvatarUrl = null;
      _selectedPartnerId = null;
      _messages = [];
      _showProfilePanel = false;
    });
  }

  bool _hasInternalBackState({required bool includeCrmTabs}) {
    return _showMyProfile ||
        _showProfilePanel ||
        _isSearchingInChat ||
        _selectedChatId != null ||
        (includeCrmTabs && _selectedCrmTab != 0);
  }

  void _consumeBackNavigation({required bool includeCrmTabs}) {
    if (_showMyProfile) {
      setState(() => _showMyProfile = false);
      return;
    }

    if (_showProfilePanel) {
      setState(() => _showProfilePanel = false);
      return;
    }

    if (_isSearchingInChat) {
      setState(() {
        _isSearchingInChat = false;
        _chatSearchController.clear();
        _searchResults.clear();
        _currentMatchIndex = 0;
      });
      return;
    }

    if (_selectedChatId != null) {
      _deselectChat();
      return;
    }

    if (includeCrmTabs && _selectedCrmTab != 0) {
      setState(() => _selectedCrmTab = 0);
    }
  }

  Future<void> _onMuteChat(bool isMuted) async {
    if (_selectedChatId == null || _selectedChatType == null) return;
    final chatId = _selectedChatId!;
    final wasMuted = _mutedChatIds.contains(chatId);
    try {
      setState(() {
        if (isMuted) {
          _mutedChatIds.add(chatId);
        } else {
          _mutedChatIds.remove(chatId);
        }
        _chatItems = _chatItems
            .map(
              (item) =>
                  item['id'] == chatId ? {...item, 'is_muted': isMuted} : item,
            )
            .toList();
      });
      await ref
          .read(magicMessengerServiceProvider)
          .setChatMute(chatId, isMuted: isMuted);
    } catch (e) {
      _logMessenger('Error muting chat: $e');
      if (mounted) {
        setState(() {
          if (wasMuted) {
            _mutedChatIds.add(chatId);
          } else {
            _mutedChatIds.remove(chatId);
          }
          _chatItems = _chatItems
              .map(
                (item) => item['id'] == chatId
                    ? {...item, 'is_muted': wasMuted}
                    : item,
              )
              .toList();
        });
      }
      rethrow;
    }
  }

  // ── Check channel post permission ──────────────────────────────────────────

  bool _canPostToChannel() {
    return _isManagerOrAdminRole;
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
    final nextMap = <String, List<dynamic>>{};
    for (final message in _messages) {
      final reactions = message['reactions'];
      if (reactions is List) {
        nextMap[message['id'].toString()] = reactions;
      }
    }
    if (mounted) setState(() => _reactionsMap = nextMap);
  }

  void _applyReactionsToMessage(String messageId, List<dynamic> reactions) {
    final idx = _messages.indexWhere((m) => m['id'] == messageId);
    if (idx != -1) {
      _messages[idx] = {..._messages[idx], 'reactions': reactions};
    }
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    final messenger = ref.read(magicMessengerServiceProvider);
    final previous = List<dynamic>.from(_reactionsMap[messageId] ?? const []);
    final hasMine = previous.any(
      (r) => r is Map && r['user_id'] == _userId && r['emoji'] == emoji,
    );

    // Optimistic update so the reaction reflects instantly, independent of
    // realtime delivery (top-tier messenger behaviour). The server response is
    // then applied as the authoritative state below.
    final optimistic = List<dynamic>.from(previous);
    if (hasMine) {
      optimistic.removeWhere(
        (r) => r is Map && r['user_id'] == _userId && r['emoji'] == emoji,
      );
    } else {
      optimistic.add({'user_id': _userId, 'emoji': emoji});
    }
    setState(() {
      _reactionsMap = {..._reactionsMap, messageId: optimistic};
      _applyReactionsToMessage(messageId, optimistic);
    });

    try {
      final result = hasMine
          ? await messenger.removeReaction(messageId: messageId, emoji: emoji)
          : await messenger.setReaction(messageId: messageId, emoji: emoji);
      final reactions = result['reactions'];
      if (reactions is List && mounted) {
        setState(() {
          _reactionsMap = {..._reactionsMap, messageId: reactions};
          _applyReactionsToMessage(messageId, reactions);
        });
      }
    } catch (e) {
      _logMessenger('Error toggling reaction: $e');
      // Revert the optimistic change on failure.
      if (mounted) {
        setState(() {
          _reactionsMap = {..._reactionsMap, messageId: previous};
          _applyReactionsToMessage(messageId, previous);
        });
      }
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
    if (today.difference(msgDate).inDays < 7) {
      return DateFormat('EE', 'ru').format(local);
    }
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
      chatViewBuilder: (context, isMobile, selectedId) =>
          _buildChatView(context, isMobile),
      profilePanelBuilder: (context) =>
          _selectedChatId != null && _selectedChatType != null
          ? ChatInfoDialog(
              key: ValueKey('$_selectedChatType:$_selectedChatId'),
              chatId: _selectedChatId!,
              chatType: _selectedChatType!,
              userRole: widget.role,
              onClose: () => setState(() => _showProfilePanel = false),
              onUpdate: _loadChatList,
              onSearch: _onSearchInChat,
              onMute: _onMuteChat,
              initialIsMuted:
                  _selectedChatId != null &&
                  _mutedChatIds.contains(_selectedChatId),
              onNavigateToChat: (chat) {
                setState(() {
                  _showProfilePanel = false;
                });
                _selectChat(chat);
              },
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
                    // Robust name resolution
                    String name = 'Чат';
                    if (item['_display_name'] != null &&
                        item['_display_name'].toString().isNotEmpty) {
                      name = item['_display_name'].toString();
                    } else if (item['display_name'] != null &&
                        item['display_name'].toString().isNotEmpty) {
                      name = item['display_name'].toString();
                    } else if (item['profiles'] != null) {
                      final p = item['profiles'];
                      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
                          .trim();
                    } else if (item['_partner_data'] != null) {
                      final p = item['_partner_data'];
                      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
                          .trim();
                    } else if (item['name'] != null) {
                      name = item['name'].toString();
                    }
                    if (name.trim().isEmpty) name = 'Без имени';

                    return ListTile(
                      leading: TelegramAvatar(
                        name: name,
                        avatarUrl: item['_avatar_url'] ?? item['avatar_url'],
                        uniqueId: item['id'].toString(),
                        radius: 18,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, {
                        ...item,
                        'resolved_name': name,
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (targetChat != null) {
      if (!mounted) return;
      final targetName = targetChat['resolved_name'] ?? 'Чат';

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Переслать сообщение?'),
          content: Text('Переслать сообщение в чат "$targetName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.gold,
                foregroundColor: AppColor.onGold,
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              child: const Text(
                'Переслать',
                style: TextStyle(color: AppColor.onGold),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      final targetId = targetChat['id'].toString();
      await ref
          .read(magicMessengerServiceProvider)
          .sendMessage(
            targetId,
            content: msg['content'] ?? '',
            messageType: msg['message_type'] ?? 'text',
            forwardedFromId: msg['sender_id'],
          );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Сообщение переслано')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for notification navigation events
    ref.listen(messengerNavigationProvider, (previous, next) {
      if (next != null) {
        _logMessenger(
          'MessengerScreen: navigation provider changed, checking link.',
        );
        _checkDeepLink();
      }
    });

    if (widget.role == 'client') {
      // Clients only see the chat shell directly, no CRM navigation
      return PopScope(
        canPop: !_hasInternalBackState(includeCrmTabs: false),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _consumeBackNavigation(includeCrmTabs: false);
        },
        child: Scaffold(body: SafeArea(child: _buildMessengerShell(context))),
      );
    }

    // Staff view with CRM navigation
    final isDesktopPlatform =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    final isDesktop =
        isDesktopPlatform || MediaQuery.of(context).size.width >= 768;

    ref.listen<CrmNavigationRequest?>(crmNavigationRequestProvider, (
      previous,
      next,
    ) {
      if (next == null || !mounted) return;
      final requested = next.tabIndex.toInt();
      setState(() {
        // A1: only honour deep-links to a destination this role can see, so a
        // notification can't drop Администратор onto a manager-only tab.
        if (_visibleCrmTabs(isDesktop).contains(requested)) {
          _selectedCrmTab = requested;
        }
        _userRolesInitialSearch = next.userSearch;
      });
      Future.microtask(() {
        ref.read(crmNavigationRequestProvider.notifier).clear();
      });
    });

    final visibleCrmTabs = _visibleCrmTabs(isDesktop);
    // Normalise to a tab the current role can actually see, so a stale or
    // hidden index never renders a manager-only body for Администратор (A1).
    final selectedCrmTab = visibleCrmTabs.contains(_selectedCrmTab)
        ? _selectedCrmTab
        : visibleCrmTabs.first;
    final bodyContent = _buildCrmBody(
      context,
      isDesktop: isDesktop,
      selectedTab: selectedCrmTab,
    );

    if (isDesktop) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            V7NavShell(
              isDesktop: true,
              destinations: [
                for (final tab in visibleCrmTabs) _v7DestinationForTab(tab),
              ],
              selectedIndex: visibleCrmTabs.indexOf(selectedCrmTab),
              onSelected: (pos) {
                if (!mounted) return; // «Ещё» menu resolves async
                final canonical = visibleCrmTabs[pos];
                setState(() {
                  _selectedCrmTab = canonical;
                  if (canonical == 7) _selectedReportsTab = 0;
                });
              },
            ),
            Expanded(child: bodyContent),
          ],
        ),
      );
    } else {
      return PopScope(
        canPop: !_hasInternalBackState(includeCrmTabs: true),
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _consumeBackNavigation(includeCrmTabs: true);
        },
        child: Scaffold(
          body: SafeArea(child: bodyContent),
          bottomNavigationBar: selectedCrmTab == 0 && _selectedChatId != null
              ? null // Hide bar in chat view
              : V7NavShell(
                  isDesktop: false,
                  destinations: [
                    for (final tab in visibleCrmTabs) _v7DestinationForTab(tab),
                  ],
                  selectedIndex: visibleCrmTabs.indexOf(selectedCrmTab),
                  onSelected: (pos) {
                    if (!mounted) return; // «Ещё» menu resolves async
                    setState(() => _selectedCrmTab = visibleCrmTabs[pos]);
                  },
                ),
        ),
      );
    }
  }

  /// Canonical CRM tab indices visible to the current role (see
  /// [crmVisibleTabs] for the index legend + A1 hierarchy rules).
  List<int> _visibleCrmTabs(bool isDesktop) =>
      crmVisibleTabs(widget.role, isDesktop: isDesktop);

  int _maxCrmTab(bool isDesktop) => _visibleCrmTabs(isDesktop).last;

  void _handleOverviewTabChange(
    int index,
    int? subIndex, {
    required bool isDesktop,
  }) {
    final targetTab = _overviewTargetTab(index, subIndex, isDesktop: isDesktop);
    setState(() {
      _selectedCrmTab = targetTab.clamp(0, _maxCrmTab(isDesktop));
      if (isDesktop && targetTab == 7 && subIndex != null) {
        _selectedReportsTab = subIndex.clamp(0, 2);
      }
    });
  }

  int _overviewTargetTab(int index, int? subIndex, {required bool isDesktop}) {
    if (index == 1 && subIndex != null) {
      if (subIndex == 3 || subIndex == 4) return 2;
      return 4;
    }
    if (!isDesktop) {
      if (index == 5 || index == 7) return 4;
      if (index == 6) return 3;
    }
    return index;
  }

  Widget _buildCrmBody(
    BuildContext context, {
    required bool isDesktop,
    required int selectedTab,
  }) {
    if (selectedTab == 0) return _buildMessengerShell(context);

    if (widget.role == 'teacher') {
      return switch (selectedTab) {
        1 => const TeacherScheduleWidget(),
        2 => const TeacherStudentsWidget(),
        _ => _buildMessengerShell(context),
      };
    }

    // A1: every manager-only destination is gated on `_hasManagerAccess`, so
    // Администратор can only ever render Чат/Расписание/Клиенты even if a stale
    // index slips through.
    return switch (selectedTab) {
      1 when _hasManagerAccess =>
        _isAdminRole
            ? AdminOverviewWidget(
                onTabChange: (index, subIndex) => _handleOverviewTabChange(
                  index,
                  subIndex,
                  isDesktop: isDesktop,
                ),
              )
            : ManagerOverviewWidget(
                onTabChange: (index, subIndex) => _handleOverviewTabChange(
                  index,
                  subIndex,
                  isDesktop: isDesktop,
                ),
              ),
      2 => const ScheduleWidget(),
      3 => const ClientsWidget(),
      4 when _hasManagerAccess => UserRolesWidget(
        currentRole: widget.role,
        initialSearch: _userRolesInitialSearch,
      ),
      5 when isDesktop && _hasManagerAccess => const FinanceWidget(),
      6 when isDesktop && _hasManagerAccess => const TasksWidget(),
      7 when isDesktop && _hasManagerAccess => ReportsWidget(
        initialTab: _selectedReportsTab,
      ),
      _ => _buildMessengerShell(context),
    };
  }

  /// Builds the v7 nav destination for a canonical CRM tab index (see
  /// [_visibleCrmTabs]). Teacher reuses 1/2 for Расписание/Ученики.
  V7NavDestination _v7DestinationForTab(int tab) {
    if (widget.role == 'teacher') {
      switch (tab) {
        case 1:
          return const V7NavDestination(
            icon: Icons.calendar_today_outlined,
            selectedIcon: Icons.calendar_today_rounded,
            label: 'Расписание',
          );
        case 2:
          return const V7NavDestination(
            icon: Icons.school_outlined,
            selectedIcon: Icons.school_rounded,
            label: 'Ученики',
          );
      }
    }
    switch (tab) {
      case 1:
        return const V7NavDestination(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          label: 'Обзор',
        );
      case 2:
        return const V7NavDestination(
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
          label: 'Расписание',
        );
      case 3:
        return V7NavDestination(
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
          label: 'Клиенты',
          badgeCount: ref.watch(appLeadsCountProvider).asData?.value ?? 0,
        );
      case 4:
        return const V7NavDestination(
          icon: Icons.manage_accounts_outlined,
          selectedIcon: Icons.manage_accounts_rounded,
          label: 'Пользователи',
        );
      case 5:
        return const V7NavDestination(
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
          label: 'Финансы',
        );
      case 6:
        return const V7NavDestination(
          icon: Icons.task_alt_outlined,
          selectedIcon: Icons.task_alt_rounded,
          label: 'Задачи',
        );
      case 7:
        return const V7NavDestination(
          icon: Icons.insert_chart_outlined_rounded,
          selectedIcon: Icons.insert_chart_rounded,
          label: 'Отчёты',
        );
      default:
        return const V7NavDestination(
          icon: Icons.chat_bubble_outline_rounded,
          selectedIcon: Icons.chat_bubble_rounded,
          label: 'Чат',
        );
    }
  }

  // ── Chat List Panel ────────────────────────────────────────────────────────

  Widget _buildChatList(BuildContext context, bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? AppColor.divider : TelegramColors.lightDivider;
    final secondaryText = isDark
        ? AppColor.text2
        : TelegramColors.lightTextSecondary;
    final canCreateGroups = _isManagerOrAdminRole;

    final filteredItems = _searchQuery.isEmpty
        ? _chatItems
        : _chatItems.where((item) {
            final name = (item['_display_name'] ?? item['display_name'] ?? '')
                .toString()
                .toLowerCase();
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(
            color: isDark ? AppColor.surface : TelegramColors.lightBg,
            border: Border(
              bottom: BorderSide(color: dividerColor, width: 0.5),
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
                        isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
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
                      leading: Icon(
                        Icons.logout_rounded,
                        color: AppColor.danger,
                      ),
                      title: Text(
                        'Выйти',
                        style: TextStyle(color: AppColor.danger),
                      ),
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
                    await ref.read(magicAuthServiceProvider).signOut();
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
              if (widget.role == 'client')
                IconButton(
                  icon: const Icon(Icons.school_rounded),
                  tooltip: 'Моя школа',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ClientPortalScreen(),
                      ),
                    );
                  },
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
        ChatSearchBar(onChanged: (q) => setState(() => _searchQuery = q)),
        // Chat list
        Expanded(
          child: _loadingChats
              ? const Center(
                  child: CircularProgressIndicator(color: AppColor.gold),
                )
              : sortedItems.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isNotEmpty ? 'Ничего не найдено' : 'Нет чатов',
                    style: TextStyle(color: secondaryText),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChatList,
                  color: AppColor.gold,
                  child: ListView.builder(
                    itemCount: sortedItems.length,
                    itemBuilder: (context, index) {
                      final item = sortedItems[index];
                      final id = (item['id'] ?? '').toString();
                      final type =
                          (item['_item_type'] ??
                                  item['item_type'] ??
                                  'individual')
                              .toString();
                      final name =
                          (item['_display_name'] ??
                                  item['display_name'] ??
                                  'Аноним')
                              .toString();
                      final lastMsg =
                          item['_last_message'] as Map<String, dynamic>?;
                      final unread = _unreadCounts[id] ?? 0;
                      final avatarUrl = _getAvatarUrl(item);

                      return ChatListTile(
                        title: name,
                        subtitle: _messagePreview(lastMsg),
                        time: _formatTime(
                          item['_last_message_time'] as String?,
                        ),
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
    final secondaryText = isDark
        ? AppColor.text2
        : TelegramColors.lightTextSecondary;
    final isChannel = _selectedChatType == 'channel';
    final isGroup = _selectedChatType == 'group';

    return DropTarget(
      onDragDone: (details) async {
        if (details.files.isEmpty) return;
        final messenger = ScaffoldMessenger.of(context);
        if (isChannel) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Вложения в каналах пока недоступны'),
              backgroundColor: AppColor.danger,
            ),
          );
          return;
        }
        for (final file in details.files) {
          final size = await file.length();
          if (size > ChatAttachmentService.maxFileSizeBytes) {
            if (mounted) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Файл слишком большой (макс. 25 МБ)'),
                  backgroundColor: AppColor.danger,
                ),
              );
            }
            continue;
          }
          final bytes = await file.readAsBytes();
          _showSendFileDialog(bytes, file.name, size);
        }
      },
      child: Container(
        color: isDark ? TelegramColors.darkChatBg : TelegramColors.lightChatBg,
        child: Column(
          children: [
            ChatHeader(
              title: _selectedChatName ?? '',
              subtitle: _selectedChatType == 'direct'
                  ? (_selectedPartnerId != null &&
                            _onlineUsers.contains(_selectedPartnerId)
                        ? 'в сети'
                        : widget.role == 'client'
                        ? 'Поддержка'
                        : 'не в сети')
                  : _selectedChatType == 'group'
                  // Neutral label — the previous "{tracked}+1 в сети" was a
                  // fabricated estimate (a 30-member group could show "1 в сети").
                  ? 'Групповой чат'
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
              actions: [
                if (_pinnedMessages.isNotEmpty &&
                    _hiddenPinnedBars.contains(_selectedChatId))
                  IconButton(
                    icon: const Icon(
                      Icons.push_pin_rounded,
                      size: 20,
                      color: AppColor.gold,
                    ),
                    tooltip: 'Показать закрепленные',
                    onPressed: () => setState(
                      () => _hiddenPinnedBars.remove(_selectedChatId),
                    ),
                  ),
                // Staff CRM actions for a 1:1 client chat: save the contact as a
                // lead/student or jump to their existing card.
                if (_isManagerOrAdminRole &&
                    _selectedChatType == 'direct' &&
                    (_selectedPartnerId?.isNotEmpty ?? false))
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 20,
                      color: AppColor.gold,
                    ),
                    tooltip: 'Сохранить в CRM',
                    onSelected: (value) {
                      if (value == 'open_card') {
                        _openContactCard();
                      } else if (value == 'save_lead') {
                        _saveContactFromChat('lead');
                      } else if (value == 'save_student') {
                        _saveContactFromChat('student');
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'open_card',
                        child: Row(
                          children: [
                            Icon(Icons.badge_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Открыть карточку клиента'),
                          ],
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'save_lead',
                        child: Row(
                          children: [
                            Icon(Icons.assignment_ind_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Сохранить как лид'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save_student',
                        child: Row(
                          children: [
                            Icon(Icons.school_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Сохранить как ученик'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
              onTitleTap: () {
                if (_selectedChatId == null || _selectedChatType == null) {
                  return;
                }

                if (MediaQuery.of(context).size.width >= 768) {
                  setState(() => _showProfilePanel = !_showProfilePanel);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatInfoDialog(
                        key: ValueKey('$_selectedChatType:$_selectedChatId'),
                        chatId: _selectedChatId!,
                        chatType: _selectedChatType!,
                        userRole: widget.role,
                        onUpdate: _loadChatList,
                        onSearch: _onSearchInChat,
                        onMute: _onMuteChat,
                        initialIsMuted:
                            _selectedChatId != null &&
                            _mutedChatIds.contains(_selectedChatId),
                        onNavigateToChat: (chat) {
                          _selectChat(chat);
                        },
                      ),
                    ),
                  );
                }
              },
              isSearchActive: _isSearchingInChat,
              searchController: _chatSearchController,
              onSearchToggle: _onSearchInChat,
              onSearchChanged: (val) => _performSearch(val),
              onSearchSubmitted: (val) => _performSearch(val, jump: true),
              matchCount: _searchResults.length,
              currentMatchIndex: _currentMatchIndex + 1,
              onNextMatch: _nextSearchMatch,
              onPrevMatch: _prevSearchMatch,
            ),
            if (_pinnedMessages.isNotEmpty) _buildPinnedBar(),
            _PresenceBanner(
              chatId: _selectedChatId,
              chatType: _selectedChatType,
              partnerId: _selectedPartnerId,
              onlineUserIds: _onlineUsers,
              currentUserId: _userId,
            ),
            Expanded(
              child: _loadingMessages
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColor.gold),
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
                            color: secondaryText.withAlpha(60),
                          ),
                          const SizedBox(height: AppSpace.md),
                          Text(
                            isChannel
                                ? 'Пока нет публикаций'
                                : 'Начните общение!',
                            style: TextStyle(color: secondaryText),
                          ),
                        ],
                      ),
                    )
                  : _MessageListView(
                      key: _messagesActionKey,
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
                      onPin: (msg) => _togglePin(
                        msg['id'].toString(),
                        msg['pinned_at'] == null,
                      ),
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
                      padding: const EdgeInsets.only(
                        left: AppSpace.lg,
                        bottom: AppSpace.xs,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _typingText,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: secondaryText,
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
            else if (_canPostToChannel())
              MessageInput(
                onSendText: _sendTextMessage,
                onTyping: _handleTyping,
              ),
          ],
        ),
      ),
    );
  }

  Widget? _buildStatusIcon(Map<String, dynamic> item, bool isDark) {
    if (!_isManagerOrAdminRole) return null;
    if (item['_item_type'] != 'group') return null;

    final respondedAt = item['_group_data']?['responded_at'];
    if (respondedAt == null) {
      return Icon(
        Icons.help_outline_rounded,
        size: 18,
        color: Colors.amber.shade700,
      );
    } else {
      return const Icon(
        Icons.check_circle_rounded,
        size: 18,
        color: Colors.green,
      );
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
        ? '${responder['first_name'] ?? ''} ${responder['last_name'] ?? ''}'
              .trim()
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
              leading: const Icon(
                Icons.person_rounded,
                color: AppColor.gold,
              ),
              title: const Text('Ответил первым:'),
              subtitle: Text(responderName),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(
                Icons.access_time_rounded,
                color: AppColor.gold,
              ),
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
    if (_pinnedMessages.isEmpty ||
        _hiddenPinnedBars.contains(_selectedChatId)) {
      return const SizedBox.shrink();
    }

    final lastPinned = _pinnedMessages.first;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content =
        lastPinned['content']?.toString() ??
        (lastPinned['message_type'] == 'file' ? '📁 Файл' : 'Вложение');

    return Container(
      width: double.infinity,
      color: cs.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_pinnedMessages.length == 1) {
              _jumpToMessage(_pinnedMessages.first['id'].toString());
            } else {
              _showPinnedMessagesDialog();
            }
          },
          child: Row(
            children: [
              Container(
                width: 2,
                height: 35,
                decoration: BoxDecoration(
                  color: AppColor.gold,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _pinnedMessages.length > 1
                          ? 'Закрепленные сообщения'
                          : 'Закрепленное сообщение',
                      style: const TextStyle(
                        color: AppColor.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface.withAlpha(isDark ? 178 : 222),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (_pinnedMessages.length > 1)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.xs + 2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.goldSoft,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      '${_pinnedMessages.length}',
                      style: const TextStyle(
                        color: AppColor.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Скрыть панель',
                onPressed: () {
                  if (_selectedChatId != null) {
                    setState(() => _hiddenPinnedBars.add(_selectedChatId!));
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPinnedMessagesDialog() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          _pinnedDialogSetState = setDialogState;

          return AlertDialog(
            backgroundColor: cs.surface,
            title: const Row(
              children: [
                Icon(Icons.pin_drop_rounded, color: AppColor.gold),
                SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'Закрепленные сообщения',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: _pinnedMessages.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('Пусто', textAlign: TextAlign.center),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _pinnedMessages.length,
                      separatorBuilder: (_, _) => Divider(
                        color: isDark
                            ? AppColor.divider
                            : TelegramColors.lightDivider,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final msg = _pinnedMessages[index];
                        final content =
                            msg['content']?.toString() ??
                            (msg['message_type'] == 'file'
                                ? '📁 Файл'
                                : 'Сообщение');

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          title: Text(
                            content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Открепить',
                            onPressed: () async {
                              await _togglePin(msg['id'].toString(), false);
                              if (_pinnedMessages.isEmpty) {
                                if (context.mounted) Navigator.pop(context);
                              } else {
                                setDialogState(() {});
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _jumpToMessage(msg['id'].toString());
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _pinnedDialogSetState = null;
                  Navigator.pop(context);
                },
                child: const Text('Закрыть'),
              ),
            ],
          );
        },
      ),
    ).then((_) => _pinnedDialogSetState = null);
  }

  Future<void> _fetchPinnedMessages() async {
    if (_selectedChatId == null) return;
    final pinned = _messages
        .where((message) => message['pinned_at'] != null)
        .toList()
        .reversed
        .toList();
    if (mounted) {
      setState(() => _pinnedMessages = pinned);
      if (_pinnedDialogSetState != null) {
        _pinnedDialogSetState!(() {});
      }
    }
  }

  void _onSearchInChat() {
    setState(() {
      _isSearchingInChat = !_isSearchingInChat;
      if (!_isSearchingInChat) {
        _chatSearchController.clear();
        _searchResults.clear();
        _currentMatchIndex = 0;
      }
    });
  }

  int _currentMatchIndex = 0;

  void _performSearch(String query, {bool jump = false}) {
    if (query.isEmpty) {
      setState(() {
        _searchResults.clear();
        _currentMatchIndex = 0;
      });
      return;
    }

    final results = _messages
        .where(
          (m) => (m['content']?.toString() ?? '').toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();

    setState(() {
      _searchResults = results;
      if (results.isNotEmpty) {
        if (jump) {
          _currentMatchIndex = 0;
          _jumpToMessage(results.first['id']);
        }
      } else {
        _currentMatchIndex = 0;
      }
    });
  }

  void _nextSearchMatch() {
    if (_searchResults.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _searchResults.length;
      _jumpToMessage(_searchResults[_currentMatchIndex]['id']);
    });
  }

  void _prevSearchMatch() {
    if (_searchResults.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _searchResults.length) %
          _searchResults.length;
      _jumpToMessage(_searchResults[_currentMatchIndex]['id']);
    });
  }

  Future<void> _togglePin(String messageId, bool pin) async {
    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      final updated = pin
          ? await messenger.pinMessage(messageId)
          : await messenger.unpinMessage(messageId);
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m['id'] == messageId);
          if (index != -1) _messages[index] = updated;
        });
      }
      await _fetchPinnedMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка при закреплении: $e')));
      }
    }
  }

  void _jumpToMessage(String messageId) {
    if (_messagesActionKey.currentState != null) {
      _messagesActionKey.currentState!._jumpToMessage(messageId);
    }
  }

  final GlobalKey<_MessageListViewState> _messagesActionKey = GlobalKey();
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
    super.key,
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
  final ScrollController _scrollController = ScrollController();
  // KVA-174: replaced _showScrollToBottom with _isAtBottom + _unreadCount.
  bool _isAtBottom = true;
  int _unreadCount = 0;
  String? _highlightedMessageId;
  bool _isJumping = false;

  // Cache for sender names (profile lookups)
  final Map<String, String> _senderNameCache = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // KVA-174: track whether the list is scrolled to (near) the bottom.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom =
        _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 80;
    if (atBottom && !_isAtBottom) {
      setState(() {
        _isAtBottom = true;
        _unreadCount = 0;
      });
    } else if (!atBottom && _isAtBottom) {
      setState(() => _isAtBottom = false);
    }
  }

  void _jumpToMessage(String messageId) {
    if (!mounted) return;

    final index = widget.messages.indexWhere(
      (m) => m['id'].toString() == messageId,
    );
    if (index == -1) return;

    setState(() {
      _isJumping = true;
      _highlightedMessageId = null; // Reset highlight before new jump
    });

    final targetKey = GlobalObjectKey(messageId);
    final context = targetKey.currentContext;

    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      _startHighlight(messageId);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _isJumping = false);
      });
    } else {
      // Heuristic jump to general area
      final estimate = index * 120.0;
      _scrollController
          .animateTo(
            estimate,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          )
          .then((_) {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final newContext = targetKey.currentContext;
              if (newContext != null) {
                Scrollable.ensureVisible(
                  newContext,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: 0.5,
                );
              }
              _startHighlight(messageId);
              Future.delayed(const Duration(milliseconds: 600), () {
                if (mounted) setState(() => _isJumping = false);
              });
            });
          });
    }
  }

  void _startHighlight(String messageId) {
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  @override
  void didUpdateWidget(_MessageListView old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length) {
      if (!_isJumping) {
        if (_isAtBottom) {
          // KVA-174: auto-scroll only when already at the bottom.
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        } else {
          // KVA-174: count unseen messages while scrolled up — by the actual
          // number added so a burst/batch delivery isn't undercounted.
          final added = widget.messages.length - old.messages.length;
          if (added > 0) setState(() => _unreadCount += added);
        }
      }
    }
  }

  void _scrollToBottom() {
    if (_isJumping || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
      final name =
          '${profiles['first_name'] ?? ''} ${profiles['last_name'] ?? ''}'
              .trim();
      if (name.isNotEmpty) {
        _senderNameCache[senderId] = name;
        return name;
      }
    }

    if (widget.adminIds.contains(senderId)) return 'Администрация';
    return 'Пользователь';
  }

  String? _getForwardedName(Map<String, dynamic> msg) {
    if (msg['forwarded_from_id'] == null) return null;

    final forwardedId = msg['forwarded_from_id'].toString();

    // Check embedded forwarded_profiles from our enriched query
    final fProfiles = msg['forwarded_profiles'];
    if (fProfiles != null && fProfiles is Map) {
      final name =
          '${fProfiles['first_name'] ?? ''} ${fProfiles['last_name'] ?? ''}'
              .trim();
      if (name.isNotEmpty) return name;
    }

    if (widget.adminIds.contains(forwardedId)) return 'Администрация';
    return 'Пользователь';
  }

  bool _shouldShowDate(int index) {
    if (index == 0) return true;
    final curr = DateTime.tryParse(widget.messages[index]['created_at'] ?? '');
    final prev = DateTime.tryParse(
      widget.messages[index - 1]['created_at'] ?? '',
    );
    if (curr == null || prev == null) return false;
    return curr.toLocal().day != prev.toLocal().day ||
        curr.toLocal().month != prev.toLocal().month ||
        curr.toLocal().year != prev.toLocal().year;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canAdminDelete =
        widget.role == 'admin' ||
        widget.role == 'manager' ||
        widget.role == 'system_admin';

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          itemCount: widget.messages.length,
          itemBuilder: (context, index) {
            final msg = widget.messages[index];
            final isMe = msg['sender_id'] == widget.currentUserId;

            // Resolve replied message from current list
            Map<String, dynamic>? repliedMsg;
            final replyId = msg['reply_to_id']?.toString();
            if (replyId != null) {
              try {
                repliedMsg = widget.messages.firstWhere(
                  (m) => m['id'].toString() == replyId,
                );
              } catch (_) {
                // Not in current list (already deleted or too old)
              }
            }

            return Column(
              key: GlobalObjectKey(msg['id'].toString()),
              children: [
                if (_shouldShowDate(index))
                  DateSeparator(
                    date:
                        DateTime.tryParse(msg['created_at'] ?? '')?.toLocal() ??
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
                  isHighlighted: _highlightedMessageId == msg['id'].toString(),
                  forwardedFromName: _getForwardedName(msg),
                  onJumpToReplied: () {
                    if (repliedMsg != null) {
                      _jumpToMessage(repliedMsg['id'].toString());
                    }
                  },
                  canDeleteOthers: canAdminDelete,
                ),
              ],
            );
          },
        ),
        // KVA-174: scroll-to-bottom button with unread badge.
        if (!_isAtBottom)
          Positioned(
            bottom: AppSpace.md,
            right: AppSpace.md,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                FloatingActionButton.small(
                  heroTag: 'scroll_to_bottom',
                  onPressed: () {
                    setState(() => _unreadCount = 0);
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  backgroundColor: cs.surface,
                  foregroundColor: AppColor.gold,
                  elevation: 4,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
                if (_unreadCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpace.xs),
                      decoration: const BoxDecoration(
                        color: AppColor.danger,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PresenceBanner extends StatelessWidget {
  final String? chatId;
  final String? chatType;
  final String? partnerId;
  final Set<String> onlineUserIds;
  final String currentUserId;

  const _PresenceBanner({
    this.chatId,
    this.chatType,
    this.partnerId,
    required this.onlineUserIds,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (chatId == null) return const SizedBox.shrink();
    if (chatType != 'direct') return const SizedBox.shrink();

    final peerId = partnerId;
    if (peerId == null || peerId.isEmpty || peerId == currentUserId) {
      return const SizedBox.shrink();
    }
    if (!onlineUserIds.contains(peerId)) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const text = 'Собеседник в сети';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      color: Colors.amber.withAlpha(25),
      child: Row(
        children: [
          const Icon(
            Icons.remove_red_eye_rounded,
            size: 14,
            color: Colors.amber,
          ),
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
  }
}
