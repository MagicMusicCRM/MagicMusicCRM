import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_desktop_scrollbar.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/group_schedule_participants_editor.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';

class GroupDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> group;
  final bool canWrite;

  const GroupDetailDialog({
    super.key,
    required this.group,
    this.canWrite = true,
  });

  static Future<bool?> show(
    BuildContext context,
    Map<String, dynamic> group, {
    bool canWrite = true,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GroupDetailDialog(group: group, canWrite: canWrite),
    );
  }

  @override
  ConsumerState<GroupDetailDialog> createState() => _GroupDetailDialogState();
}

class _GroupDetailDialogState extends ConsumerState<GroupDetailDialog> {
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _error;
  List<Map<String, dynamic>> _groupStudents = [];
  List<Map<String, dynamic>> _allStudents = [];
  List<GroupScheduleMemberOption> _scheduleMembers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final results = await Future.wait([
        crm.listGroupStudents(widget.group['id'].toString(), limit: 100),
        crm.listStudents(limit: 100),
      ]);
      final groupStudents = results[0];
      final scheduleMembers = await Future.wait([
        for (final student in groupStudents)
          _scheduleMember(crm, student, loadSubscriptions: widget.canWrite),
      ]);

      if (!mounted) return;
      setState(() {
        _groupStudents = groupStudents;
        _allStudents = results[1];
        _scheduleMembers = scheduleMembers;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading group data: $e');
      if (mounted) {
        setState(() {
          _error = 'Не удалось загрузить данные группы';
          _loading = false;
        });
      }
    }
  }

  Future<GroupScheduleMemberOption> _scheduleMember(
    MagicCrmService crm,
    Map<String, dynamic> student, {
    required bool loadSubscriptions,
  }) async {
    final studentId = student['id']?.toString() ?? '';
    List<Map<String, dynamic>> subscriptions = const [];
    if (loadSubscriptions && studentId.isNotEmpty) {
      try {
        final rows = await crm.listSubscriptions(
          studentId: studentId,
          limit: 100,
        );
        subscriptions = rows
            .where((subscription) => subscription['status'] == 'active')
            .toList(growable: false);
      } catch (error) {
        debugPrint('Error loading group member subscriptions: $error');
      }
    }
    return GroupScheduleMemberOption(
      studentId: studentId,
      label: _studentName(student),
      subscriptions: subscriptions,
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить группу.'),
            ),
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить группу.'),
            ),
          ),
        );
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
          : _error != null
          ? SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: AppTheme.danger,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            )
          : SizedBox(
              width: double.maxFinite,
              child: MagicDesktopScrollbar(
                axis: Axis.vertical,
                builder: (context, controller) => SingleChildScrollView(
                  controller: controller,
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
                            trailing: widget.canWrite
                                ? IconButton(
                                    tooltip: 'Удалить $displayName из группы',
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
                                  )
                                : null,
                          );
                        }),
                      if (widget.canWrite) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _addStudent,
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text('Добавить ученика'),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),
                      RecurringSchedulePlanSection(
                        key: ValueKey(
                          'group-schedule-plans-${widget.group['id']}',
                        ),
                        groupId: widget.group['id']?.toString(),
                        subjectName: groupName.toString(),
                        fallbackLessons: const [],
                        branches: _groupBranches(),
                        defaultBranchId: _groupBranchId(),
                        subscriptions: const [],
                        groupMembers: _scheduleMembers,
                        canWrite: widget.canWrite,
                        onChanged: () => _changed = true,
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

  String? _groupBranchId() =>
      (widget.group['branch_id'] ?? (widget.group['branches'] as Map?)?['id'])
          ?.toString();

  List<Map<String, dynamic>> _groupBranches() {
    final id = _groupBranchId();
    if (id == null || id.isEmpty) return const [];
    final name =
        (widget.group['branch_name'] ??
                (widget.group['branches'] as Map?)?['name'] ??
                'Филиал')
            .toString();
    return [
      {'id': id, 'name': name},
    ];
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

    final crm = ref.read(magicCrmServiceProvider);
    SearchableSelectItem? selected;
    await SearchableSelect.show(
      context: context,
      title: 'Добавить ученика',
      hintText: 'Поиск по ФИО...',
      // Pre-loaded page (first 100) for the empty query; a real query hits
      // searchStudents server-side so student #101+ is still reachable.
      items: items,
      onSearch: (query) async {
        final response = await crm.searchStudents(q: query, limit: 50);
        final rows = response['items'];
        if (rows is! List) return const <SearchableSelectItem>[];
        return [
          for (final row in rows.whereType<Map<String, dynamic>>())
            if (!existingIds.contains(row['id']?.toString()))
              SearchableSelectItem(
                id: row['id'].toString(),
                label: _studentName(row),
              ),
        ];
      },
      onSelected: (item) => selected = item,
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
