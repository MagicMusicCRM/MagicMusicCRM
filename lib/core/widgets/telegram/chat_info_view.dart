import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_view_components.dart';

class ChatInfoView extends StatelessWidget {
  const ChatInfoView({
    super.key,
    required this.model,
    required this.actions,
    required this.hasCloseAction,
    required this.tabBar,
    required this.tabBody,
  });

  final ChatInfoViewModel model;
  final ChatInfoActions actions;
  final bool hasCloseAction;
  final Widget tabBar;
  final Widget tabBody;

  @override
  Widget build(BuildContext context) {
    if (model.snapshot.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (model.snapshot.data == null) {
      return const Scaffold(body: Center(child: Text('Информация не найдена')));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? TelegramColors.darkBg : TelegramColors.lightBg,
      body: DefaultTabController(
        length: model.access.hasNotes ? 4 : 3,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            _buildAppBar(isDark, innerBoxIsScrolled),
            SliverToBoxAdapter(
              child: _ChatInfoSummary(model: model, actions: actions),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: ChatInfoTabHeaderDelegate(tabBar),
            ),
          ],
          body: tabBody,
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(bool isDark, bool innerBoxIsScrolled) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: isDark
          ? TelegramColors.darkSurface
          : TelegramColors.lightSurface,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: innerBoxIsScrolled
            ? Text(
                model.name,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
              )
            : null,
        background: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 50),
            Hero(
              tag: 'avatar_${model.request.chatId}',
              child: TelegramAvatar(
                name: model.name,
                avatarUrl: model.avatarUrl,
                uniqueId: model.request.chatId,
                radius: 50,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: model.access.canEditChannel ? actions.editChannel : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    model.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (model.access.canEditChannel) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: TelegramColors.accent,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              model.subtitle,
              style: TextStyle(
                color: isDark
                    ? TelegramColors.darkTextSecondary
                    : TelegramColors.lightTextSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      leading: hasCloseAction
          ? IconButton(
              tooltip: 'Закрыть',
              icon: const Icon(Icons.close),
              onPressed: actions.close,
            )
          : null,
    );
  }
}

class _ChatInfoSummary extends StatelessWidget {
  const _ChatInfoSummary({required this.model, required this.actions});

  final ChatInfoViewModel model;
  final ChatInfoActions actions;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? TelegramColors.darkBg : TelegramColors.lightBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: _ChatInfoActionsRow(
              model: model,
              actions: actions,
              isDark: isDark,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? TelegramColors.darkSurface
                  : TelegramColors.lightSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (model.request.chatType == 'direct') ...[
                  _DirectChatPhone(model: model, isDark: isDark),
                  const SizedBox(height: 16),
                ],
                _ChatDescription(
                  model: model,
                  actions: actions,
                  isDark: isDark,
                ),
                if (model.request.chatType == 'group' &&
                    model.snapshot.members.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ChatInfoMembersPreview(
                    model: model,
                    actions: actions,
                    isDark: isDark,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ChatInfoActionsRow extends StatelessWidget {
  const _ChatInfoActionsRow({
    required this.model,
    required this.actions,
    required this.isDark,
  });

  final ChatInfoViewModel model;
  final ChatInfoActions actions;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isMember = model.snapshot.members.any(
      (member) => member['is_current_user'] == true,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ChatInfoActionButton(
          icon: Icons.chat_bubble_outline,
          label: 'Чат',
          isDark: isDark,
          onTap: actions.openCurrentChat,
        ),
        if (model.request.chatType != 'channel' &&
            model.request.chatId != 'admin_chat') ...[
          const SizedBox(width: 32),
          ChatInfoActionButton(
            icon: model.snapshot.isMuted
                ? Icons.notifications_off_outlined
                : Icons.notifications_none,
            label: model.snapshot.isMuted ? 'Включить' : 'Заглушить',
            isDark: isDark,
            onTap: actions.toggleMute,
          ),
        ],
        if (model.request.chatType == 'group' && isMember) ...[
          const SizedBox(width: 32),
          ChatInfoActionButton(
            icon: Icons.exit_to_app_rounded,
            label: 'Выйти',
            isDark: isDark,
            color: Colors.red,
            onTap: actions.leaveGroup,
          ),
        ],
      ],
    );
  }
}

class _InfoCaption extends StatelessWidget {
  const _InfoCaption({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      color: isDark
          ? TelegramColors.darkTextSecondary
          : TelegramColors.lightTextSecondary,
    ),
  );
}

class _DirectChatPhone extends StatelessWidget {
  const _DirectChatPhone({required this.model, required this.isDark});

  final ChatInfoViewModel model;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final phone = model.conversationPartner?['phone']?.toString().trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          phone?.isNotEmpty == true ? phone! : 'Телефон не указан',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        _InfoCaption(text: 'Телефон', isDark: isDark),
      ],
    );
  }
}

class _ChatDescription extends StatelessWidget {
  const _ChatDescription({
    required this.model,
    required this.actions,
    required this.isDark,
  });

  final ChatInfoViewModel model;
  final ChatInfoActions actions;
  final bool isDark;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: model.access.canEditChannel ? actions.editChannel : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              model.description.isEmpty ? 'Нет описания' : model.description,
              style: const TextStyle(fontSize: 16),
            ),
            if (model.access.canEditChannel)
              Icon(Icons.edit_rounded, size: 14, color: TelegramColors.accent),
          ],
        ),
        const SizedBox(height: 4),
        _InfoCaption(
          text: model.request.chatType == 'direct'
              ? 'Статус / Роль'
              : 'Описание',
          isDark: isDark,
        ),
      ],
    ),
  );
}

class ChatInfoMembersPreview extends StatelessWidget {
  const ChatInfoMembersPreview({
    super.key,
    required this.model,
    required this.actions,
    required this.isDark,
  });

  final ChatInfoViewModel model;
  final ChatInfoActions actions;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final preview = model.snapshot.members.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Участники',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? TelegramColors.darkTextSecondary
                    : TelegramColors.lightTextSecondary,
              ),
            ),
            if (model.access.canManageGroup)
              GestureDetector(
                onTap: actions.addMembers,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_add_rounded,
                      size: 16,
                      color: TelegramColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Добавить',
                      style: TextStyle(
                        fontSize: 13,
                        color: TelegramColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...preview.map(
          (member) => _MemberRow(
            member: member,
            model: model,
            actions: actions,
            isDark: isDark,
          ),
        ),
        if (model.snapshot.members.length > preview.length)
          TextButton(
            onPressed: actions.showAllMembers,
            child: Text('Показать всех (${model.snapshot.members.length})'),
          ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.model,
    required this.actions,
    required this.isDark,
  });

  final Map<String, dynamic> member;
  final ChatInfoViewModel model;
  final ChatInfoActions actions;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final name = member['_display_name']?.toString() ?? 'Участник';
    final role = member['role']?.toString() == 'admin'
        ? 'Администратор группы'
        : chatInfoRoleLabel(member['user_role']?.toString() ?? 'client');
    final userId = member['user_id']?.toString();
    final canOpen = model.access.canOpenMember(userId);
    final canRemove = model.access.canRemoveMember(member);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          TelegramAvatar(name: name, uniqueId: userId ?? name, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? TelegramColors.darkTextSecondary
                        : TelegramColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (canOpen)
            IconButton(
              tooltip: 'Открыть чат',
              onPressed: () => actions.openMemberChat(userId),
              icon: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 18,
                color: TelegramColors.accent,
              ),
            ),
          if (canRemove)
            IconButton(
              tooltip: 'Удалить из группы',
              onPressed: () => actions.removeMember(member),
              icon: const Icon(
                Icons.person_remove_outlined,
                size: 18,
                color: Colors.redAccent,
              ),
            ),
        ],
      ),
    );
  }
}
