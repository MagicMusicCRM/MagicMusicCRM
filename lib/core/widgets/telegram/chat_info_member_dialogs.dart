import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';

Future<bool> showChatInfoLeaveConfirmation(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Выйти из группы'),
          content: const Text('Вы уверены, что хотите выйти из этой группы?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Выйти', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> showChatInfoRemoveConfirmation(
  BuildContext context,
  String name,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Удалить из группы'),
          content: Text(
            'Удалить $name из группы? История сообщений сохранится.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Удалить', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ) ??
      false;
}

Future<String?> showChatInfoNoteEditor(BuildContext context) async {
  final textController = TextEditingController();
  final body = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Добавить заметку'),
      content: TextField(
        controller: textController,
        autofocus: true,
        maxLines: 5,
        minLines: 3,
        decoration: const InputDecoration(hintText: 'Введите текст заметки'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.pop(dialogContext, textController.text.trim()),
          child: const Text('Добавить'),
        ),
      ],
    ),
  );
  textController.dispose();
  return body;
}

class ChatInfoAddMembersDialog extends StatefulWidget {
  const ChatInfoAddMembersDialog({
    super.key,
    required this.existingMemberUserIds,
    required this.loadProfiles,
  });

  final Set<String> existingMemberUserIds;
  final Future<List<Map<String, dynamic>>> Function() loadProfiles;

  @override
  State<ChatInfoAddMembersDialog> createState() =>
      _ChatInfoAddMembersDialogState();
}

class _ChatInfoAddMembersDialogState extends State<ChatInfoAddMembersDialog> {
  final _searchController = TextEditingController();
  final _selectedUserIds = <String>{};
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final profiles = await widget.loadProfiles();
      if (!mounted) return;
      setState(() {
        _allUsers = profiles
            .where(
              (user) =>
                  user['user_id'] != null &&
                  !widget.existingMemberUserIds.contains(
                    user['user_id']?.toString(),
                  ),
            )
            .map((user) => {...user, 'id': user['user_id']})
            .toList();
        _filteredUsers = _allUsers;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  void _filterUsers(String query) {
    final normalized = query.toLowerCase();
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
            .toLowerCase();
        final email = (user['email'] ?? '').toString().toLowerCase();
        return name.contains(normalized) || email.contains(normalized);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      child: SizedBox(
        width: 480,
        height: 520,
        child: Column(
          children: [
            _buildHeader(isDark),
            if (_selectedUserIds.isNotEmpty) _buildSelectedUsers(),
            const Divider(height: 1),
            Expanded(child: _buildUserList(isDark)),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Добавить участников',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Поиск пользователей...',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: isDark
                ? TelegramColors.darkInputBg
                : TelegramColors.lightInputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: _filterUsers,
        ),
      ],
    ),
  );

  Widget _buildSelectedUsers() => SizedBox(
    height: 40,
    child: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      scrollDirection: Axis.horizontal,
      children: _selectedUserIds.map((userId) {
        final user = _allUsers.firstWhere(
          (item) => item['id'] == userId,
          orElse: () => const {},
        );
        final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
            .trim();
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Chip(
            avatar: TelegramAvatar(name: name, uniqueId: userId, radius: 12),
            label: Text(name, style: const TextStyle(fontSize: 12)),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () => setState(() => _selectedUserIds.remove(userId)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        );
      }).toList(),
    ),
  );

  Widget _buildUserList(bool isDark) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError) {
      return const Center(
        child: Text(
          'Не удалось загрузить пользователей',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_filteredUsers.isEmpty) {
      return const Center(
        child: Text(
          'Нет пользователей для добавления',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      itemCount: _filteredUsers.length,
      itemBuilder: (_, index) {
        final user = _filteredUsers[index];
        final userId = user['id']?.toString() ?? '';
        final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
            .trim();
        final selected = _selectedUserIds.contains(userId);
        return ListTile(
          leading: TelegramAvatar(name: name, uniqueId: userId, radius: 20),
          title: Text(
            name.isEmpty ? 'Без имени' : name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            chatInfoRoleLabel(user['role']?.toString() ?? 'client'),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: selected
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: TelegramColors.accent,
                )
              : Icon(
                  Icons.circle_outlined,
                  color: isDark
                      ? TelegramColors.darkTextSecondary
                      : TelegramColors.lightTextSecondary,
                ),
          onTap: () => setState(() {
            selected
                ? _selectedUserIds.remove(userId)
                : _selectedUserIds.add(userId);
          }),
        );
      },
    );
  }

  Widget _buildFooter() => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _selectedUserIds.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedUserIds),
          style: ElevatedButton.styleFrom(
            backgroundColor: TelegramColors.accent,
            foregroundColor: Colors.white,
          ),
          child: Text('Добавить (${_selectedUserIds.length})'),
        ),
      ],
    ),
  );
}

class ChatInfoMembersDialog extends StatelessWidget {
  const ChatInfoMembersDialog({
    super.key,
    required this.members,
    required this.canManageGroup,
  });

  final List<Map<String, dynamic>> members;
  final bool canManageGroup;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Участники (${members.length})'),
    content: SizedBox(
      width: 480,
      height: 480,
      child: ListView.builder(
        itemCount: members.length,
        itemBuilder: (_, index) {
          final member = members[index];
          final name = member['_display_name']?.toString() ?? 'Участник';
          final canRemove = canManageGroup && member['is_current_user'] != true;
          return ListTile(
            leading: TelegramAvatar(
              name: name,
              uniqueId: member['user_id']?.toString() ?? name,
              radius: 18,
            ),
            title: Text(name),
            subtitle: Text(
              member['role'] == 'admin'
                  ? 'Администратор группы'
                  : chatInfoRoleLabel(
                      member['user_role']?.toString() ?? 'client',
                    ),
            ),
            trailing: canRemove
                ? IconButton(
                    tooltip: 'Удалить из группы',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => Navigator.pop(context, member),
                  )
                : null,
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
    ],
  );
}
