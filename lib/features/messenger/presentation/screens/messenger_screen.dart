import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/app_back_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/services/alert_policy.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/adaptive_messenger_shell.dart';
import 'package:magic_music_crm/core/widgets/v7/dirty_form_exit.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_page_state.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_list_tile.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_header.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_search_bar.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_bubble.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_input.dart';
import 'package:magic_music_crm/core/widgets/telegram/date_separator.dart';
import 'package:magic_music_crm/core/widgets/telegram/create_group_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/channel_editor_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_dialog.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/services/notification_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:magic_music_crm/core/widgets/telegram/send_file_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:mime/mime.dart';
import 'package:magic_music_crm/features/messenger/data/chat_archive_api.dart';
import 'package:magic_music_crm/features/messenger/inbox_logic.dart';
import 'package:magic_music_crm/features/messenger/widgets/inbox_folder_bar.dart';
import 'messenger_dialogs.dart';

part 'messenger_screen_widgets.dart';
part 'messenger_screen_actions.dart';
part 'messenger_screen_realtime.dart';
part 'messenger_screen_messaging.dart';
part 'messenger_screen_builders_a.dart';
part 'messenger_screen_builders_b.dart';

void _logMessenger(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

/// Unified Telegram-style messenger screen used by all roles.
class MessengerScreen extends ConsumerStatefulWidget {
  final String role; // 'client', 'admin', 'system_admin', 'manager', 'teacher'
  final EntityLink? initialLink;
  final ContextViewState? initialViewState;
  final VoidCallback? onOpenSchool;
  const MessengerScreen({
    super.key,
    required this.role,
    this.initialLink,
    this.initialViewState,
    this.onOpenSchool,
    this.workspaceOwned = false,
  });

  final bool workspaceOwned;

  @override
  ConsumerState<MessengerScreen> createState() => _MessengerScreenState();
}

class _MessengerScreenState extends ConsumerState<MessengerScreen> {
  String? _selectedChatId;
  String? _selectedChatType; // 'direct', 'group', 'channel'
  String? _selectedChatRawType;
  String? _selectedChatSlug; // 'announcements' for the system Объявления chat
  bool _selectedChannelCanWrite = false;
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
  String? _chatListError;
  String? _messagesLoadError;
  String _searchQuery = '';
  bool _showProfilePanel = false;
  bool _showMyProfile = false;
  int _currentLoadId = 0;
  List<String> _adminIds = [];
  bool _isSearchingInChat = false;
  final _chatSearchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  int _currentMatchIndex = 0;

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
  // Broadcast channel rooms (e.g. Объявления) we keep subscribed so posts arrive
  // live even when the user is not viewing the channel. Re-joined on reconnect.
  final Set<String> _joinedChannelIds = {};
  Timer? _chatListReloadTimer;
  Timer? _realtimeFallbackTimer;
  DateTime _lastRealtimeEventAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFallbackChatListAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _currentUserId;

  // Folder bar state (staff / manager+admin only)
  InboxFolder _selectedFolder = InboxFolder.leads;

  /// #5 (дубли из чата): кэш «кто этот собеседник в CRM» по partnerId —
  /// {'leadId': …, 'studentId': …}. Заполняется при открытии личного чата,
  /// гейтит меню «Сохранить в CRM»: связанному контакту сохранение не
  /// предлагаем, только карточку.
  final Map<String, Map<String, String?>> _chatContactLinks = {};
  // Chat branch filter (staff only). null = «Все филиалы». A client with no
  // branch assigned is shown under every branch (server-side rule).
  String? _chatBranchFilter;
  List<Map<String, dynamic>> _chatBranches = const [];

  bool get _isAdminRole =>
      widget.role == 'admin' || widget.role == 'system_admin';

  bool get _isManagerOrAdminRole =>
      _isAdminRole || widget.role == 'manager' || widget.role == 'director';

  /// Manager-tier may clear assignment markers created by others. Claiming is
  /// advisory and available to every staff role.
  bool get _isManagerTier =>
      widget.role == 'manager' ||
      widget.role == 'director' ||
      widget.role == 'system_admin';

  bool get _isStaffRole => _isManagerOrAdminRole || widget.role == 'teacher';
  String _currentUserDisplayName = 'Пользователь';
  String? _openingNavigationPartnerId;

  @override
  void initState() {
    super.initState();
    _bootstrapMessenger();

    // Check for pending navigation from notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDeepLink();
    });
  }

  // setState guarded by mounted, so logic/builder methods can live in
  // extension part files (extensions cannot call the @protected setState).
  void _emitState(void Function() fn) {
    if (mounted) setState(fn);
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    _chatListReloadTimer?.cancel();
    _realtimeFallbackTimer?.cancel();
    _leaveTypingChannel(notify: false);
    _realtimeConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(messengerNavigationProvider, (previous, next) {
      if (next != null) {
        _logMessenger(
          'MessengerScreen: navigation provider changed, checking link.',
        );
        _checkDeepLink();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(activeViewProvider.notifier)
          .set(crmTab: CrmSection.chat, chatId: _selectedChatId);
    });
    return AppBackScope(
      hasLocalHistory: _hasInternalBackState(),
      onBack: _consumeBackNavigation,
      child: Scaffold(body: SafeArea(child: _buildMessengerShell(context))),
    );
  }

  final GlobalKey<_MessageListViewState> _messagesActionKey = GlobalKey();
} // End of _MessengerScreenState

// ── Message List with Date Separators ────────────────────────────────────────
