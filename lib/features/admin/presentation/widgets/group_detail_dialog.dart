import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';

class GroupDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> group;

  const GroupDetailDialog({super.key, required this.group});

  static Future<bool?> show(BuildContext context, Map<String, dynamic> group) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GroupDetailDialog(group: group),
    );
  }

  @override
  ConsumerState<GroupDetailDialog> createState() => _GroupDetailDialogState();
}

class _GroupDetailDialogState extends ConsumerState<GroupDetailDialog> {
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
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
      final crm = ref.read(magicCrmServiceProvider);
      final results = await Future.wait([
        crm.listGroupStudents(widget.group['id'].toString(), limit: 100),
        crm.listStudents(limit: 100),
      ]);

      if (!mounted) return;
      setState(() {
        _groupStudents = results[0];
        _allStudents = results[1];
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading group data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addStudent() async {
    final selectedStudent = await _showStudentPicker();
    if (selectedStudent == null) return;

    final selectedStudentId = selectedStudent.id;
    if (_groupStudents.any((student) => student['id'] == selectedStudentId)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ученик уже в группе')));
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .addGroupStudent(
            groupId: widget.group['id'].toString(),
            studentId: selectedStudentId,
          );
      _changed = true;
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeStudent(String studentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить из группы?'),
        content: const Text(
          'Вы уверены, что хотите удалить ученика из этой группы?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .removeGroupStudent(
            groupId: widget.group['id'].toString(),
            studentId: studentId,
          );
      _changed = true;
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupName = widget.group['name'] ?? 'Без названия';

    return AlertDialog(
      title: Text('Группа: $groupName'),
      content: _loading
          ? SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryGold),
              ),
            )
          : SizedBox(
              width: double.maxFinite,
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Состав группы:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_groupStudents.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Нет учеников',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._groupStudents.map((student) {
                          final displayName = _studentName(student);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.primaryGold.withAlpha(
                                50,
                              ),
                              child: Text(
                                displayName.isNotEmpty ? displayName[0] : '?',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.primaryGold,
                                ),
                              ),
                            ),
                            title: Text(
                              displayName,
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: AppTheme.danger,
                                size: 20,
                              ),
                              onPressed: _saving
                                  ? null
                                  : () => _removeStudent(
                                      student['id'].toString(),
                                    ),
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
          onPressed: () => Navigator.pop(context, _changed),
          child: Text(
            'Закрыть',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Future<SearchableSelectItem?> _showStudentPicker() async {
    final existingIds = _groupStudents
        .map((student) => student['id']?.toString())
        .whereType<String>()
        .toSet();
    final items = _allStudents
        .where((student) => !existingIds.contains(student['id']?.toString()))
        .map(
          (student) => SearchableSelectItem(
            id: student['id'].toString(),
            label: _studentName(student),
          ),
        )
        .toList();

    SearchableSelectItem? selected;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SearchableSelect(
        title: 'Добавить ученика',
        hintText: 'Поиск по ФИО...',
        items: items,
        onSelected: (item) => selected = item,
      ),
    );
    return selected;
  }

  String _studentName(Map<String, dynamic> student) {
    final first = student['first_name']?.toString() ?? '';
    final last = student['last_name']?.toString() ?? '';
    final email = student['email']?.toString() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? (email.isEmpty ? 'Без имени' : email) : name;
  }
}
