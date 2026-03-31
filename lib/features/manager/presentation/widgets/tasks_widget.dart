import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class TasksWidget extends StatefulWidget {
  const TasksWidget({super.key});

  @override
  State<TasksWidget> createState() => _TasksWidgetState();
}

class _TasksWidgetState extends State<TasksWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);
    try {
      var query = _supabase
          .from('tasks')
          .select('*, profiles!tasks_assigned_to_fkey(first_name, last_name), branches(name), students(first_name, last_name, profiles(first_name, last_name)), leads(name), groups(name), teachers(first_name, last_name, profiles(first_name, last_name))');

      if (_filter != 'all') {
        query = query.eq('status', _filter);
      }

      final data = await query.order('created_at', ascending: false);
      setState(() {
        _tasks = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _createTask() async {
    final branches = await _supabase.from('branches').select('id, name');
    final employees = await _supabase.from('profiles').select('id, first_name, last_name');
    final students = await _supabase.from('students').select('id, first_name, last_name, profiles(first_name, last_name)');
    final leads = await _supabase.from('leads').select('id, name');
    final groups = await _supabase.from('groups').select('id, name');
    final teachers = await _supabase.from('teachers').select('id, first_name, last_name, profiles(first_name, last_name)');
    
    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _TaskDialog(
        branches: List<Map<String, dynamic>>.from(branches),
        employees: List<Map<String, dynamic>>.from(employees),
        students: List<Map<String, dynamic>>.from(students),
        leads: List<Map<String, dynamic>>.from(leads),
        groups: List<Map<String, dynamic>>.from(groups),
        teachers: List<Map<String, dynamic>>.from(teachers),
      ),
    );
    if (result != null) {
      await _supabase.from('tasks').insert({
        'title': result['title'],
        'description': result['description'],
        'priority': result['priority'],
        'branch_id': result['branch_id'],
        'assigned_to': result['assigned_to'],
        'student_id': result['student_id'],
        'lead_id': result['lead_id'],
        'group_id': result['group_id'],
        'teacher_id': result['teacher_id'],
        'due_date': result['due_date'],
        'status': 'todo',
        'created_by': _supabase.auth.currentUser?.id,
      });
      _loadTasks();
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    await _supabase.from('tasks').update({'status': status}).eq('id', id);
    _loadTasks();
  }

  Future<void> _deleteTask(String id) async {
    await _supabase.from('tasks').delete().eq('id', id);
    _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _createTask,
        child: Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(label: 'Все', value: 'all', selected: _filter == 'all', onTap: () { setState(() => _filter = 'all'); _loadTasks(); }),
                  SizedBox(width: 8),
                  _FilterChip(label: 'К выполнению', value: 'todo', selected: _filter == 'todo', onTap: () { setState(() => _filter = 'todo'); _loadTasks(); }),
                  SizedBox(width: 8),
                  _FilterChip(label: 'В работе', value: 'in_progress', selected: _filter == 'in_progress', onTap: () { setState(() => _filter = 'in_progress'); _loadTasks(); }),
                  SizedBox(width: 8),
                  _FilterChip(label: 'Завершены', value: 'done', selected: _filter == 'done', onTap: () { setState(() => _filter = 'done'); _loadTasks(); }),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple))
                : _tasks.isEmpty
                    ? Center(child: Text('Нет задач', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                    : RefreshIndicator(
                        color: AppTheme.primaryPurple,
                        onRefresh: _loadTasks,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _tasks.length,
                          itemBuilder: (ctx, i) => _TaskCard(
                            task: _tasks[i],
                            onStatusChange: _updateStatus,
                            onDelete: _deleteTask,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label, value;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryPurple : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final Function(String, String) onStatusChange;
  final Function(String) onDelete;
  const _TaskCard({required this.task, required this.onStatusChange, required this.onDelete});

  Color _priorityColor(String? p) {
    switch (p) {
      case 'high': return AppTheme.danger;
      case 'low': return AppTheme.success;
      default: return AppTheme.warning;
    }
  }

  String _priorityLabel(String? p) {
    switch (p) {
      case 'high': return 'Высокий';
      case 'low': return 'Низкий';
      default: return 'Средний';
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'in_progress': return 'В работе';
      case 'done': return 'Завершена';
      default: return 'К выполнению';
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = task['id'] as String;
    final status = task['status'] as String?;
    final priority = task['priority'] as String?;
    final dueDate = task['due_date'] != null
        ? DateFormat('d MMM yyyy', 'ru').format(DateTime.parse(task['due_date']))
        : null;
    final assignee = task['profiles'] as Map<String, dynamic>?;
    final assigneeText = assignee != null
        ? '${assignee['first_name'] ?? ''} ${assignee['last_name'] ?? ''}'.trim()
        : null;

    final student = task['students'];
    final lead = task['leads'];

    String? entityText;
    VoidCallback? onEntityTap;

    if (student != null) {
      final sfName = student['first_name']?.toString() ?? '';
      final slName = student['last_name']?.toString() ?? '';
      final sp = student['profiles'];
      var sName = '$sfName $slName'.trim();
      if (sName.isEmpty && sp != null) {
        sName = '${sp['first_name'] ?? ''} ${sp['last_name'] ?? ''}'.trim();
      }
      entityText = 'Ученик: ${sName.isEmpty ? 'Без имени' : sName}';
      onEntityTap = () => context.push('/student/${student['id']}');
    } else if (lead != null) {
      entityText = 'Лид: ${lead['name'] ?? ''}'.trim();
      // Add lead detail navigation when ready
    } else if (task['groups'] != null) {
      entityText = 'Группа: ${task['groups']['name']}';
      // onEntityTap = () => context.push('/group/${task['groups']['id']}');
    } else if (task['teachers'] != null) {
      final tfName = task['teachers']['first_name']?.toString() ?? '';
      final tlName = task['teachers']['last_name']?.toString() ?? '';
      final tp = task['teachers']['profiles'];
      var tName = '$tfName $tlName'.trim();
      if (tName.isEmpty && tp != null) {
        tName = '${tp['first_name'] ?? ''} ${tp['last_name'] ?? ''}'.trim();
      }
      entityText = 'Учитель: ${tName.isEmpty ? 'Без имени' : tName}';
      // onEntityTap = () => context.push('/teacher/${task['teachers']['id']}');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(task['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  color: Theme.of(context).colorScheme.surface,
                  onSelected: (v) {
                    if (v == 'delete') {
                      onDelete(id);
                    } else {
                      onStatusChange(id, v);
                    }
                  },
                  itemBuilder: (_) => [
                    if (status != 'in_progress') const PopupMenuItem(value: 'in_progress', child: Text('В работу')),
                    if (status != 'done') const PopupMenuItem(value: 'done', child: Text('Завершить')),
                    if (status != 'todo') const PopupMenuItem(value: 'todo', child: Text('Открыть снова')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'delete', child: Text('Удалить', style: TextStyle(color: AppTheme.danger))),
                  ],
                ),
              ],
            ),
            if (task['description'] != null && (task['description'] as String).isNotEmpty) ...[
              SizedBox(height: 4),
              Text(task['description'], style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            ],
            SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Tag(label: _priorityLabel(priority), color: _priorityColor(priority)),
                _Tag(label: _statusLabel(status), color: AppTheme.primaryPurple),
                if (task['branches'] != null)
                  _Tag(label: 'Филиал: ${task['branches']['name']}', color: AppTheme.success),
                if (dueDate != null) _Tag(label: 'До: $dueDate', color: Theme.of(context).colorScheme.onSurfaceVariant),
                if (assigneeText != null && assigneeText.isNotEmpty)
                  _Tag(label: assigneeText, color: AppTheme.secondaryGold),
                if (entityText != null)
                  _Tag(
                    label: entityText, 
                    color: AppTheme.primaryPurple, 
                    onTap: onEntityTap,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _Tag({required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(20),
          border: onTap != null ? Border.all(color: color.withAlpha(50)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            if (onTap != null) ...[
              SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 10, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskDialog extends StatefulWidget {
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> leads;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> teachers;
  const _TaskDialog({
    required this.branches, 
    required this.employees,
    required this.students,
    required this.leads,
    required this.groups,
    required this.teachers,
  });

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _priority = 'medium';
  String? _selectedBranchId;
  String? _selectedEmployeeId;
  String? _selectedStudentId;
  String? _selectedLeadId;
  String? _selectedGroupId;
  String? _selectedTeacherId;
  DateTime? _dueDate;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text('Новая задача'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Название')),
            SizedBox(height: 12),
            TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Описание (необязательно)'), maxLines: 3),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Приоритет'),
              items: [
                DropdownMenuItem(value: 'low', child: Text('Низкий')),
                DropdownMenuItem(value: 'medium', child: Text('Средний')),
                DropdownMenuItem(value: 'high', child: Text('Высокий')),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'medium'),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedBranchId,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Филиал'),
              items: widget.branches.map((b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['name'] ?? ''))).toList(),
              onChanged: (v) => setState(() => _selectedBranchId = v),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedEmployeeId,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Ответственный'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Не назначен')),
                ...widget.employees.map((e) => DropdownMenuItem(
                  value: e['id'].toString(), 
                  child: Text('${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.trim())
                )),
              ],
              onChanged: (v) => setState(() => _selectedEmployeeId = v),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedStudentId,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Привязать к ученику'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Не привязывать')),
                ...widget.students.map((s) {
                  final sfName = s['first_name']?.toString() ?? '';
                  final slName = s['last_name']?.toString() ?? '';
                  final p = s['profiles'];
                  var name = '$sfName $slName'.trim();
                  if (name.isEmpty && p != null) {
                    name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
                  }
                  return DropdownMenuItem(
                    value: s['id'].toString(), 
                    child: Text(name.isEmpty ? 'Без имени' : name)
                  );
                }),
              ],
              onChanged: (v) => setState(() {
                _selectedStudentId = v;
                if (v != null) _selectedLeadId = null;
              }),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedLeadId,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Привязать к лиду'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Не привязывать')),
                ...widget.leads.map((l) => DropdownMenuItem(
                  value: l['id'].toString(), 
                  child: Text(l['name'] ?? l['first_name'] ?? '')
                )),
              ],
              onChanged: (v) => setState(() {
                _selectedLeadId = v;
                if (v != null) {
                  _selectedStudentId = null;
                  _selectedGroupId = null;
                  _selectedTeacherId = null;
                }
              }),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedGroupId,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Привязать к группе'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Не привязывать')),
                ...widget.groups.map((g) => DropdownMenuItem(
                  value: g['id'].toString(), 
                  child: Text(g['name'] ?? '')
                )),
              ],
              onChanged: (v) => setState(() {
                _selectedGroupId = v;
                if (v != null) {
                  _selectedStudentId = null;
                  _selectedLeadId = null;
                  _selectedTeacherId = null;
                }
              }),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedTeacherId,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Привязать к учителю'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Не привязывать')),
                ...widget.teachers.map((t) {
                  final tfName = t['first_name']?.toString() ?? '';
                  final tlName = t['last_name']?.toString() ?? '';
                  final p = t['profiles'];
                  var name = '$tfName $tlName'.trim();
                  if (name.isEmpty && p != null) {
                    name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
                  }
                  return DropdownMenuItem(
                    value: t['id'].toString(), 
                    child: Text(name.isEmpty ? 'Без имени' : name)
                  );
                }),
              ],
              onChanged: (v) => setState(() {
                _selectedTeacherId = v;
                if (v != null) {
                  _selectedStudentId = null;
                  _selectedLeadId = null;
                  _selectedGroupId = null;
                }
              }),
            ),
            SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _dueDate = d);
              },
              icon: Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(_dueDate == null ? 'Установить срок' : DateFormat('dd.MM.yyyy').format(_dueDate!)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (_titleCtrl.text.trim().isNotEmpty) {
              Navigator.pop(context, {
                'title': _titleCtrl.text.trim(),
                'description': _descCtrl.text.trim(),
                'priority': _priority,
                'branch_id': _selectedBranchId,
                'assigned_to': _selectedEmployeeId,
                 'student_id': _selectedStudentId,
                 'lead_id': _selectedLeadId,
                 'group_id': _selectedGroupId,
                 'teacher_id': _selectedTeacherId,
                 'due_date': _dueDate?.toIso8601String(),
              });
            }
          },
          child: Text('Создать'),
        ),
      ],
    );
  }
}
