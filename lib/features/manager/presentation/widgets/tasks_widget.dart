import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
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
          .select('*, profiles!tasks_assigned_to_fkey(first_name, last_name)');

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
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => const _TaskDialog(),
    );
    if (result != null) {
      await _supabase.from('tasks').insert({
        'title': result['title'],
        'description': result['description'],
        'priority': result['priority'],
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
        child: const Icon(Icons.add),
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
                  const SizedBox(width: 8),
                  _FilterChip(label: 'К выполнению', value: 'todo', selected: _filter == 'todo', onTap: () { setState(() => _filter = 'todo'); _loadTasks(); }),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'В работе', value: 'in_progress', selected: _filter == 'in_progress', onTap: () { setState(() => _filter = 'in_progress'); _loadTasks(); }),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Завершены', value: 'done', selected: _filter == 'done', onTap: () { setState(() => _filter = 'done'); _loadTasks(); }),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple))
                : _tasks.isEmpty
                    ? const Center(child: Text('Нет задач', style: TextStyle(color: AppTheme.textSecondary)))
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
          color: selected ? AppTheme.primaryPurple : AppTheme.cardDark,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : AppTheme.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
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
                  icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
                  color: AppTheme.cardDark,
                  onSelected: (v) {
                    if (v == 'delete') onDelete(id);
                    else onStatusChange(id, v);
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
              const SizedBox(height: 4),
              Text(task['description'], style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                _Tag(label: _priorityLabel(priority), color: _priorityColor(priority)),
                _Tag(label: _statusLabel(status), color: AppTheme.primaryPurple),
                if (dueDate != null) _Tag(label: 'До: $dueDate', color: AppTheme.textSecondary),
                if (assigneeText != null && assigneeText.isNotEmpty)
                  _Tag(label: assigneeText, color: AppTheme.secondaryGold),
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
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog();

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _priority = 'medium';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      title: const Text('Новая задача'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 12),
            TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Описание (необязательно)'), maxLines: 3),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _priority,
              dropdownColor: AppTheme.cardDark,
              decoration: const InputDecoration(labelText: 'Приоритет'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Низкий')),
                DropdownMenuItem(value: 'medium', child: Text('Средний')),
                DropdownMenuItem(value: 'high', child: Text('Высокий')),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'medium'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (_titleCtrl.text.trim().isNotEmpty) {
              Navigator.pop(context, {
                'title': _titleCtrl.text.trim(),
                'description': _descCtrl.text.trim(),
                'priority': _priority,
              });
            }
          },
          child: const Text('Создать'),
        ),
      ],
    );
  }
}
