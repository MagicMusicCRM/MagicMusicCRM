import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/channel_editor_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_controller.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_member_dialogs.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_tabs.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_view.dart';

class ChatInfoDialog extends ConsumerStatefulWidget {
  final String chatType; // 'direct', 'group', 'channel'
  final String chatId; // target user ID, group ID, or channel ID
  final String userRole; // current user role
  final VoidCallback? onClose;
  final VoidCallback? onUpdate;
  final VoidCallback? onSearch;
  final Future<void> Function(bool isMuted)? onMute;
  final Function(Map<String, dynamic> chat)? onNavigateToChat;
  final bool initialIsMuted;

  /// Called after the current user successfully leaves a group chat.
  /// The screen should remove the chat from its list and deselect it.
  final VoidCallback? onLeftGroup;

  const ChatInfoDialog({
    super.key,
    required this.chatType,
    required this.chatId,
    required this.userRole,
    this.onClose,
    this.onUpdate,
    this.onSearch,
    this.onMute,
    this.onNavigateToChat,
    this.initialIsMuted = false,
    this.onLeftGroup,
  });

  @override
  ConsumerState<ChatInfoDialog> createState() => _ChatInfoDialogState();
}

class _ChatInfoDialogState extends ConsumerState<ChatInfoDialog>
    with SingleTickerProviderStateMixin
    implements ChatInfoActions {
  late TabController _tabController;
  late final ChatInfoController _controller;

  ChatInfoRequest get _request => ChatInfoRequest(
    chatType: widget.chatType,
    chatId: widget.chatId,
    userRole: widget.userRole,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _controller = ChatInfoController(
      request: _request,
      initialIsMuted: widget.initialIsMuted,
      messenger: ref.read(magicMessengerServiceProvider),
      profiles: ref.read(magicProfileAdminServiceProvider),
      settings: ref.read(magicSettingsServiceProvider),
    )..addListener(_onControllerChanged);
    _controller.load();
  }

  @override
  void didUpdateWidget(covariant ChatInfoDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabController.length != _tabCount) {
      _tabController.dispose();
      _tabController = TabController(length: _tabCount, vsync: this);
    }
    if (oldWidget.chatId != widget.chatId ||
        oldWidget.chatType != widget.chatType ||
        oldWidget.userRole != widget.userRole) {
      _controller.updateRequest(
        _request,
        initialIsMuted: widget.initialIsMuted,
      );
    } else if (oldWidget.initialIsMuted != widget.initialIsMuted) {
      _controller.replaceInitialMuted(widget.initialIsMuted);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _tabController.dispose();
    super.dispose();
  }

  int get _tabCount => chatInfoTabCount(widget.chatType, widget.userRole);

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final model = _controller.viewModel;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ChatInfoView(
      model: model,
      actions: this,
      hasCloseAction: widget.onClose != null,
      tabBar: ChatInfoTabBar(
        tabController: _tabController,
        isDark: isDark,
        hasNotes: model.access.hasNotes,
      ),
      tabBody: ChatInfoTabBody(
        model: model,
        tabController: _tabController,
        actions: this,
      ),
    );
  }

  @override
  void close() => _closePanel();

  @override
  void openCurrentChat() {
    final data = _controller.snapshot.data;
    if (widget.onNavigateToChat != null && data != null) {
      final partner = _controller.conversationPartner;
      widget.onNavigateToChat!({
        'id': widget.chatId == 'admin_chat' ? 'admin_chat' : widget.chatId,
        '_item_type': widget.chatType,
        'display_name': _controller.viewModel.name,
        '_display_name': _controller.viewModel.name,
        'avatar_url': _controller.viewModel.avatarUrl,
        '_avatar_url': _controller.viewModel.avatarUrl,
        '_partner_id': widget.chatType == 'direct'
            ? (partner?['user_id'])
            : null,
      });
      if (Navigator.canPop(context)) Navigator.pop(context);
    } else {
      _closePanel();
    }
  }

  @override
  Future<void> toggleMute() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await _controller.setMuted(!_controller.snapshot.isMuted, widget.onMute);
    } catch (_) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Не удалось изменить уведомления чата')),
      );
    }
  }

  @override
  Future<void> editChannel() async {
    if (!_controller.access.canEditChannel) return;
    final data = _controller.snapshot.data;
    final updated = await ChannelEditorDialog.show(
      context,
      channelId: widget.chatId,
      initialTitle: (data?['name'] ?? data?['title'] ?? '').toString(),
      initialDescription: data?['description']?.toString() ?? '',
    );
    if (updated == null || !mounted) return;
    _controller.replaceChannel(updated);
    widget.onUpdate?.call();
  }

  @override
  Future<void> leaveGroup() async {
    if (!await showChatInfoLeaveConfirmation(context)) return;
    try {
      await _controller.leaveGroup();
      if (!mounted) return;
      _closePanel();
      widget.onLeftGroup?.call();
    } catch (error) {
      _showError(
        userErrorMessage(error, fallback: 'Не удалось выйти из группы.'),
      );
    }
  }

  @override
  Future<void> addMembers() async {
    if (!_controller.access.canManageGroup) return;
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => ChatInfoAddMembersDialog(
        existingMemberUserIds: _controller.snapshot.members
            .map((member) => member['user_id']?.toString() ?? '')
            .where((userId) => userId.isNotEmpty)
            .toSet(),
        loadProfiles: _controller.listProfilesForMembership,
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    try {
      await _controller.addMembers(selected);
    } catch (error) {
      _showError(
        userErrorMessage(error, fallback: 'Не удалось добавить участников.'),
      );
    }
  }

  @override
  Future<void> removeMember(Map<String, dynamic> member) async {
    if (!_controller.access.canManageGroup ||
        member['is_current_user'] == true) {
      return;
    }
    final userId = member['user_id']?.toString();
    if (userId == null || userId.isEmpty) return;
    final name = member['_display_name']?.toString() ?? 'участника';
    if (!await showChatInfoRemoveConfirmation(context, name) || !mounted) {
      return;
    }
    try {
      await _controller.removeMember(userId);
      widget.onUpdate?.call();
    } catch (error) {
      _showError(
        userErrorMessage(error, fallback: 'Не удалось удалить участника.'),
      );
    }
  }

  @override
  Future<void> showAllMembers() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ChatInfoMembersDialog(
        members: _controller.snapshot.members,
        canManageGroup: _controller.access.canManageGroup,
      ),
    );
    if (selected != null && mounted) await removeMember(selected);
  }

  @override
  Future<void> openMemberChat(String? userId) async {
    if (!_controller.access.isManagerTier || userId == null || userId.isEmpty) {
      return;
    }
    try {
      final chat = await _controller.ensureDirectChat(userId);
      if (!mounted) return;
      _closePanel();
      widget.onNavigateToChat?.call(chat);
    } catch (error) {
      _showError(userErrorMessage(error, fallback: 'Не удалось открыть чат.'));
    }
  }

  @override
  Future<void> addNote() async {
    if (_controller.notesProfileId == null) {
      _showError('Не удалось определить профиль для заметки');
      return;
    }
    final body = await showChatInfoNoteEditor(context);
    if (body == null || body.isEmpty) return;
    try {
      await _controller.createNote(body);
    } catch (_) {
      _showError('Не удалось сохранить заметку');
    }
  }

  void _closePanel() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
