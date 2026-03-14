import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class GroupDetailDialog extends StatefulWidget {
  final Map<String, dynamic> group;
  
  const GroupDetailDialog({super.key, required this.group});

  static Future<bool?> show(BuildContext context, Map<String, dynamic> group) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GroupDetailDialog(group: group),
    );
  }

  @override
  State<GroupDetailDialog> createState() => _GroupDetailDialogState();
}

class _GroupDetailDialogState extends State<GroupDetailDialog> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _groupStudents = [];
  List<Map<String, dynamic>> _allStudents = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final groupId = widget.group['id'];
      
      // 1. Load group students
      final gsRes = await _supabase
          .from('group_students')
          .select('student_id, students(id, profiles(first_name, last_name))')
          .eq('group_id', groupId);
      
      _groupStudents = List<Map<String, dynamic>>.from(gsRes);

      // 2. Load all students for the picker
      final sRes = await _supabase
          .from('students')
          .select('id, profiles(first_name, last_name)');
      _allStudents = List<Map<String, dynamic>>.from(sRes);

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading group data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addStudent() async {
    final selectedStudentId = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? current;
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Добавить ученика'),
            content: SizedBox(
              width: double.maxFinite,
              child: DropdownButtonFormField<String>(
                initialValue: current,
                isExpanded: true,
                dropdownColor: AppTheme.cardDark,
                items: _allStudents.map((s) {
                  final p = s['profiles'];
                  final name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
                  return DropdownMenuItem(value: s['id'].toString(), child: Text(name));
                }).toList(),
                onChanged: (v) => setDialogState(() => current = v),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(ctx, current), child: const Text('Добавить')),
            ],
          );
        });
      },
    );

    if (selectedStudentId != null) {
      // Check if already in group
      if (_groupStudents.any((s) => s['student_id'] == selectedStudentId)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ученик уже в группе')));
        return;
      }

      setState(() => _saving = true);
      try {
        await _supabase.from('group_students').insert({
          'group_id': widget.group['id'],
          'student_id': selectedStudentId,
        });
        await _loadData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  Future<void> _removeStudent(String studentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить из группы?'),
        content: const Text('Вы уверены, что хотите удалить ученика из этой группы?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _saving = true);
      try {
        await _supabase.from('group_students')
            .delete()
            .eq('group_id', widget.group['id'])
            .eq('student_id', studentId);
        await _loadData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupName = widget.group['name'] ?? 'Без названия';

    return AlertDialog(
      title: Text('Группа: $groupName'),
      content: _loading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)))
          : SizedBox(
              width: double.maxFinite,
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Состав группы:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),
                      if (_groupStudents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: Text('Нет учеников', style: TextStyle(color: AppTheme.textSecondary))),
                        )
                      else
                        ..._groupStudents.map((item) {
                          final s = item['students'];
                          final p = s?['profiles'];
                          final name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.primaryPurple.withAlpha(50),
                              child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(fontSize: 10, color: AppTheme.primaryPurple)),
                            ),
                            title: Text(name, style: const TextStyle(fontSize: 13)),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: AppTheme.danger, size: 20),
                              onPressed: () => _removeStudent(s['id']),
                            ),
                          );
                        }),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _addStudent,
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: const Text('Добавить ученика'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть', style: TextStyle(color: AppTheme.textSecondary)),
        ),
      ],
    );
  }
}
