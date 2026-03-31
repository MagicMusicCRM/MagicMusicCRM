import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class UserRolesWidget extends StatefulWidget {
  const UserRolesWidget({super.key});

  @override
  State<UserRolesWidget> createState() => _UserRolesWidgetState();
}

class _UserRolesWidgetState extends State<UserRolesWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = false;
  String _searchQuery = '';

  static const _availableRoles = ['client', 'teacher', 'admin', 'manager'];

  static const _roleLabels = {
    'client': 'Ученик',
    'teacher': 'Преподаватель',
    'admin': 'Администратор',
    'manager': 'Управляющий',
  };

  static const _roleColors = {
    'client': Color(0xFF10B981),
    'teacher': Color(0xFF3B82F6),
    'admin': Color(0xFFF59E0B),
    'manager': Color(0xFF8B5CF6),
  };

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('profiles')
          .select('id, first_name, last_name, phone, email, role, dob, created_at')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _profiles = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateRole(String profileId, String newRole) async {
    try {
      await _supabase
          .from('profiles')
          .update({'role': newRole})
          .eq('id', profileId);
      setState(() {
        final idx = _profiles.indexWhere((p) => p['id'] == profileId);
        if (idx >= 0) _profiles[idx] = {..._profiles[idx], 'role': newRole};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Роль обновлена на «${_roleLabels[newRole]}»'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProfiles {
    if (_searchQuery.isEmpty) return _profiles;
    final q = _searchQuery.toLowerCase();
    return _profiles.where((p) {
      final name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.toLowerCase();
      final email = (p['email'] ?? '').toString().toLowerCase();
      final phone = (p['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q) || phone.contains(q);
    }).toList();
  }

  String _fullName(Map<String, dynamic> p) {
    final first = p['first_name'] ?? '';
    final last = p['last_name'] ?? '';
    if (first.isEmpty && last.isEmpty) return 'Без имени';
    return '$last $first'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProfiles;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Поиск по имени, email, телефону...',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                IconButton(
                  icon: Icon(Icons.refresh, color: Colors.white70),
                  tooltip: 'Обновить',
                  onPressed: _loadProfiles,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple))
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Пользователи не найдены',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          final role = p['role'] as String? ?? 'client';
                          final roleColor = _roleColors[role] ?? Theme.of(context).colorScheme.onSurfaceVariant;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withAlpha(10)),
                            ),
                            child: Row(
                              children: [
                                // Avatar
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: roleColor.withAlpha(40),
                                  child: Text(
                                    _fullName(p).isNotEmpty ? _fullName(p)[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: roleColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 14),
                                // Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _fullName(p),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if ((p['email'] ?? '').isNotEmpty)
                                        Text(
                                          p['email'],
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontSize: 13,
                                          ),
                                        ),
                                      if ((p['phone'] ?? '').isNotEmpty)
                                        Text(
                                          p['phone'],
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 8),
                                // Role Dropdown
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: roleColor.withAlpha(30),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: roleColor.withAlpha(80)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: role,
                                      onChanged: (newRole) {
                                        if (newRole != null && newRole != role) {
                                          _confirmRoleChange(p['id'], _fullName(p), role, newRole);
                                        }
                                      },
                                      dropdownColor: const Color(0xFF1E1A29),
                                      icon: Icon(Icons.arrow_drop_down, color: roleColor, size: 18),
                                      isDense: true,
                                      items: _availableRoles.map((r) {
                                        return DropdownMenuItem<String>(
                                          value: r,
                                          child: Text(
                                            _roleLabels[r] ?? r,
                                            style: TextStyle(
                                              color: _roleColors[r] ?? Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _confirmRoleChange(String profileId, String name, String oldRole, String newRole) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A29),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Изменить роль', style: TextStyle(color: Colors.white)),
        content: Text(
          'Вы уверены, что хотите изменить роль пользователя «$name» с «${_roleLabels[oldRole]}» на «${_roleLabels[newRole]}»?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryPurple),
            onPressed: () {
              Navigator.pop(context);
              _updateRole(profileId, newRole);
            },
            child: Text('Изменить'),
          ),
        ],
      ),
    );
  }
}
