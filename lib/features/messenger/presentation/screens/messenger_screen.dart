import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/app_back_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/alert_policy.dart';
import 'package:magic_music_crm/core/services/section_unseen_service.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/widgets/adaptive_messenger_shell.dart';
import 'package:magic_music_crm/core/widgets/v7/v7_nav_shell.dart';
import 'package:magic_music_crm/core/widgets/v7/dirty_form_exit.dart';
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
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/shared_tasks_v4_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_students_widget.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/crm_configuration_workspace.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
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
  const MessengerScreen({
    super.key,
    required this.role,
    this.initialLink,
    this.initialViewState,
  });

  @override
  ConsumerState<MessengerScreen> createState() => _MessengerScreenState();
}

class _MessengerScreenState extends ConsumerState<MessengerScreen> {
  String? _selectedChatId;
  String? _selectedChatType; // 'direct', 'group', 'channel'
  String? _selectedChatRawType;
  String? _selectedChatSlug; // 'announcements' for the system Объявления chat
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

  /// Какой раздел уже отмечен просмотренным — чтобы не слать запрос на
  /// каждый кадр build().
  String? _lastMarkedSection;
  int _selectedReportsTab = 0;
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

  /// Счётчик непросмотренного для вкладки. 0 — бейдж не рисуется.
  ///
  /// ✔ Заказчик 17.07: «счётчик непрочитанных или непросмотренных изменений»
  /// по разделам. Считает сервер (см. section-views.service.ts): счётчик обязан
  /// пережить перезапуск и совпадать на телефоне и на компьютере.
  int _unseenFor(int tab) {
    final key = sectionKeyForTab(tab);
    if (key == null) return 0;
    return ref.watch(sectionUnseenProvider).asData?.value[key] ?? 0;
  }

  /// «Я открыл раздел» — обнуляет его счётчик.
  ///
  /// Зовётся при КАЖДОЙ отрисовке открытой вкладки, а не только по нажатию:
  /// вкладку открывают и переходом из задачи, и глубокой ссылкой, и после
  /// перезапуска — по нажатию отметилась бы только часть случаев. Сервер это
  /// терпит: запрос идемпотентный (`on conflict do update`).
  void _markSectionSeen(int tab) {
    final key = sectionKeyForTab(tab);
    if (key == null) return;
    if (_lastMarkedSection == key) return;
    _lastMarkedSection = key;
    unawaited(
      ref
          .read(sectionUnseenServiceProvider)
          .markSeen(key)
          .then((_) => ref.invalidate(sectionUnseenProvider))
          // Счётчик — не то, ради чего стоит показывать человеку ошибку: не
          // обнулился, обнулится при следующем открытии.
          .catchError((_) {}),
    );
  }

  /// Manager-tier may clear assignment markers created by others. Claiming is
  /// advisory and available to every staff role.
  bool get _isManagerTier =>
      widget.role == 'manager' ||
      widget.role == 'director' ||
      widget.role == 'system_admin';

  CapabilitySnapshot? get _accessSnapshot =>
      ref.read(capabilitySnapshotProvider).asData?.value;

  bool get _isStaffRole => _isManagerOrAdminRole || widget.role == 'teacher';
  String _currentUserDisplayName = 'Пользователь';
  String? _openingNavigationPartnerId;
  String? _userRolesInitialSearch;

  @override
  void initState() {
    super.initState();
    final initialLink = widget.initialLink;
    if (initialLink != null) {
      _selectedCrmTab = crmTabForEntityLink(initialLink, widget.role) ?? 0;
      _userRolesInitialSearch = initialLink.optionalFocus?.filter['query']
          ?.toString();
    }
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

  void _selectCrmTab(int tab, {bool resetReports = false}) {
    _emitState(() {
      _selectedCrmTab = tab;
      if (resetReports && tab == 7) _selectedReportsTab = 0;
    });
    final section = switch ((widget.role, tab)) {
      ('teacher', 1) => 'schedule',
      ('teacher', 2) => 'clients',
      (_, 0) => 'chat',
      (_, 1) => 'overview',
      (_, 2) => 'schedule',
      (_, 3) => 'clients',
      (_, 4) => 'users',
      (_, 5) => 'finance',
      (_, 6) => 'tasks',
      (_, 7) => 'reports',
      (_, 8) => 'configuration',
      _ => null,
    };
    final workspace = WorkspaceNavigationScope.maybeOf(context);
    if (section == null || workspace == null) return;
    final controller = workspace.controller;
    final link = EntityRouteRegistry.sectionRootLink(section);
    final current = controller.state.activeTab.currentRoute.link;
    if (current.rawEntityType == link.rawEntityType &&
        current.entityId == link.entityId &&
        current.optionalFocus?.focus == link.optionalFocus?.focus) {
      return;
    }
    controller.replaceCurrentLink(controller.state.activeTabId, link);
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
    // Rebuild immediately when the account/accessVersion-keyed snapshot is
    // dropped or replaced after access.invalidated.
    ref.watch(capabilitySnapshotProvider);
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
      return AppBackScope(
        hasLocalHistory: _hasInternalBackState(includeCrmTabs: false),
        onBack: () => _consumeBackNavigation(includeCrmTabs: false),
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

    // Счётчики непросмотренного пересчитываются, когда что-то появилось.
    //
    // Раскладка «сущность → раздел» берётся из sectionForEntity — та же, по
    // которой решается, звучать ли. Заведи здесь вторую, и бейдж со звуком
    // разошлись бы: звук молчит про открытый раздел, а бейдж на нём капает.
    //
    // Опрос-фолбэк (isFallbackPoll) пропускаем: он приходит по таймеру, а не
    // потому, что что-то случилось, и дёргал бы сервер вхолостую.
    ref.listen(crmRealtimeProvider, (previous, next) {
      final event = next.value;
      if (event == null || !mounted || event.isFallbackPoll) return;
      if (sectionForEntity(event.entity) == null) return;
      ref.invalidate(sectionUnseenProvider);
    });

    ref.listen<CrmNavigationRequest?>(crmNavigationRequestProvider, (
      previous,
      next,
    ) {
      if (next == null || !mounted) return;
      final snapshot = _accessSnapshot;
      unawaited(
        snapshot == null
            ? openEntityLink(
                context,
                ref,
                next.link,
                target: next.openInNewTab
                    ? EntityOpenTarget.newTab
                    : EntityOpenTarget.current,
                sourceViewState: next.sourceState,
              )
            : navigateEntityLink(
                context,
                snapshot,
                next.link,
                target: next.openInNewTab
                    ? EntityOpenTarget.newTab
                    : EntityOpenTarget.current,
                sourceViewState: next.sourceState,
              ),
      );
      Future.microtask(
        () => ref.read(crmNavigationRequestProvider.notifier).clear(),
      );
    });

    final visibleCrmTabs = _visibleCrmTabs(isDesktop);
    // Normalise to a tab the current role can actually see, so a stale or
    // hidden index never renders a destination unavailable to the role.
    final selectedCrmTab = visibleCrmTabs.contains(_selectedCrmTab)
        ? _selectedCrmTab
        : visibleCrmTabs.first;

    // Сообщаем «где сейчас пользователь» — по этому решается, звучать ли
    // (✔ заказчик 17.07: молчим про то, на что человек смотрит). Берётся
    // нормализованная вкладка, а не сырое поле: у роли без доступа к разделу
    // сырое значение врёт. Чат считается открытым только на своей вкладке.
    //
    // После кадра, а не в build(): менять провайдер во время построения нельзя.
    final openChatId = selectedCrmTab == CrmSection.chat
        ? _selectedChatId
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(activeViewProvider.notifier)
          .set(crmTab: selectedCrmTab, chatId: openChatId);
      _markSectionSeen(selectedCrmTab);
    });
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
                _selectCrmTab(canonical, resetReports: true);
              },
            ),
            Expanded(child: bodyContent),
          ],
        ),
      );
    } else {
      return AppBackScope(
        hasLocalHistory: _hasInternalBackState(includeCrmTabs: true),
        onBack: () => _consumeBackNavigation(includeCrmTabs: true),
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
                    _selectCrmTab(visibleCrmTabs[pos]);
                  },
                ),
        ),
      );
    }
  }

  final GlobalKey<_MessageListViewState> _messagesActionKey = GlobalKey();
} // End of _MessengerScreenState

// ── Message List with Date Separators ────────────────────────────────────────
