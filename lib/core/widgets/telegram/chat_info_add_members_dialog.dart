import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';

class ChatInfoAddMembersDialog extends StatefulWidget {
  const ChatInfoAddMembersDialog({
    super.key,
    required this.existingMemberUserIds,
    required this.loadProfiles,
  });

  final Set<String> existingMemberUserIds;
  final Future<List<Map<String, dynamic>>> Function() loadProfiles;

  static Future<Set<String>?> show(
    BuildContext context, {
    required Set<String> existingMemberUserIds,
    required Future<List<Map<String, dynamic>>> Function() loadProfiles,
  }) => showMagicDialog<Set<String>>(
    context: context,
    builder: (_) => ChatInfoAddMembersDialog(
      existingMemberUserIds: existingMemberUserIds,
      loadProfiles: loadProfiles,
    ),
  );

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
            .where(_canOfferProfile)
            .map((user) => {...user, 'id': user['user_id']})
            .toList();
        _filteredUsers = _allUsers;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  bool _canOfferProfile(Map<String, dynamic> user) {
    final userId = user['user_id']?.toString();
    return userId != null && !widget.existingMemberUserIds.contains(userId);
  }

  void _filterUsers(String query) {
    final normalized = query.toLowerCase();
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        final name = _profileName(user).toLowerCase();
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
        final name = _profileName(user);
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
    if (_loadError) return const _ProfileLoadFailure();
    if (_filteredUsers.isEmpty) return const _EmptyProfileResults();
    return ListView.builder(
      itemCount: _filteredUsers.length,
      itemBuilder: (_, index) =>
          _buildProfileTile(_filteredUsers[index], isDark: isDark),
    );
  }

  Widget _buildProfileTile(Map<String, dynamic> user, {required bool isDark}) {
    final userId = user['id']?.toString() ?? '';
    final name = _profileName(user);
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
          ? const Icon(Icons.check_circle_rounded, color: TelegramColors.accent)
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

class _ProfileLoadFailure extends StatelessWidget {
  const _ProfileLoadFailure();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Не удалось загрузить пользователей',
      style: TextStyle(color: Colors.grey),
    ),
  );
}

class _EmptyProfileResults extends StatelessWidget {
  const _EmptyProfileResults();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Нет пользователей для добавления',
      style: TextStyle(color: Colors.grey),
    ),
  );
}

String _profileName(Map<String, dynamic> user) =>
    '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
