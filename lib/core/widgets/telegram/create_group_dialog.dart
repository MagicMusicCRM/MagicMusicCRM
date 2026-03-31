import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';

/// Dialog for creating a new group chat.
/// Admins can add clients, other admins, managers, and teachers.
class CreateGroupChatDialog extends ConsumerStatefulWidget {
  const CreateGroupChatDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const CreateGroupChatDialog(),
    );
  }

  @override
  ConsumerState<CreateGroupChatDialog> createState() => _CreateGroupChatDialogState();
}

class _CreateGroupChatDialogState extends ConsumerState<CreateGroupChatDialog> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  final Set<String> _selectedUserIds = {};
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final res = await _supabase
          .from('profiles')
          .select()
          .neq('id', userId ?? '')
          .order('first_name');
      if (mounted) {
        setState(() {
          _allUsers = List<Map<String, dynamic>>.from(res);
          _filteredUsers = _allUsers;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filterUsers(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredUsers = _allUsers.where((u) {
        final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        return name.contains(q) || email.contains(q);
      }).toList();
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedUserIds.isEmpty) return;

    setState(() => _creating = true);
    try {
      final userId = _supabase.auth.currentUser!.id;

      // Create group
      final groupRes = await _supabase
          .from('group_chats')
          .insert({
            'name': name,
            'created_by': userId,
          })
          .select()
          .single();

      final groupId = groupRes['id'] as String;

      // Add creator as admin
      final members = <Map<String, dynamic>>[
        {
          'group_chat_id': groupId,
          'user_id': userId,
          'role': 'admin',
        },
      ];

      // Add selected users
      for (final uid in _selectedUserIds) {
        members.add({
          'group_chat_id': groupId,
          'user_id': uid,
          'role': 'member',
        });
      }

      await _supabase.from('group_chat_members').insert(members);

      if (mounted) Navigator.of(context).pop(groupId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка создания группы: $e'),
            backgroundColor: TelegramColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _getRoleLabel(String? role) {
    switch (role) {
      case 'admin': return 'Администратор';
      case 'manager': return 'Управляющий';
      case 'teacher': return 'Преподаватель';
      case 'client': return 'Ученик';
      default: return '';
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'admin': return TelegramColors.accentBlue;
      case 'manager': return TelegramColors.brandGold;
      case 'teacher': return TelegramColors.success;
      case 'client': return TelegramColors.brandPurple;
      default: return TelegramColors.darkTextSecondary;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      child: Container(
        width: 480,
        height: 600,
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Новая группа',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  // Group name field
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Название группы',
                      prefixIcon: const Icon(Icons.group_rounded),
                      filled: true,
                      fillColor: isDark
                          ? TelegramColors.darkInputBg
                          : TelegramColors.lightInputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  // Search users
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
            ),
            // Selected users chips
            if (_selectedUserIds.isNotEmpty)
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _selectedUserIds.map((uid) {
                    final user = _allUsers.firstWhere((u) => u['id'] == uid, orElse: () => {});
                    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Chip(
                        avatar: TelegramAvatar(name: name, uniqueId: uid, radius: 12),
                        label: Text(name, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(() => _selectedUserIds.remove(uid)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ),
            const Divider(height: 1),
            // User list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        final uid = user['id'] as String;
                        final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                        final role = user['role']?.toString();
                        final isSelected = _selectedUserIds.contains(uid);

                        return ListTile(
                          leading: TelegramAvatar(
                            name: name,
                            uniqueId: uid,
                            radius: 20,
                          ),
                          title: Text(
                            name.isEmpty ? 'Без имени' : name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            _getRoleLabel(role),
                            style: TextStyle(
                              fontSize: 12,
                              color: _getRoleColor(role),
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded,
                                  color: TelegramColors.accentBlue)
                              : Icon(Icons.circle_outlined,
                                  color: isDark
                                      ? TelegramColors.darkTextSecondary
                                      : TelegramColors.lightTextSecondary),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedUserIds.remove(uid);
                              } else {
                                _selectedUserIds.add(uid);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            // Action buttons
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _nameController.text.trim().isNotEmpty &&
                            _selectedUserIds.isNotEmpty &&
                            !_creating
                        ? _createGroup
                        : null,
                    icon: _creating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.group_add_rounded, size: 18),
                    label: Text(
                      'Создать (${_selectedUserIds.length})',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
