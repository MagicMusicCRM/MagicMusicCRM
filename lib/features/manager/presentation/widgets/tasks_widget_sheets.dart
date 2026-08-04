part of 'tasks_widget.dart';

class _TaskTimelineSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> task;

  const _TaskTimelineSheet({required this.task});

  @override
  ConsumerState<_TaskTimelineSheet> createState() => _TaskTimelineSheetState();
}

class _TaskTimelineSheetState extends ConsumerState<_TaskTimelineSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<List<Map<String, dynamic>>> _timelineFuture;
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _timelineFuture = _fetchTimeline();
    _historyFuture = _fetchHistory();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchTimeline() {
    return ref
        .read(magicCrmServiceProvider)
        .listTimeline(
          entityType: widget.task['entity_type'].toString(),
          entityId: widget.task['entity_id'].toString(),
          includeAudit: true,
          limit: 40,
        );
  }

  Future<List<Map<String, dynamic>>> _fetchHistory() {
    return ref
        .read(magicCrmServiceProvider)
        .listTaskHistory(widget.task['id'].toString());
  }

  Future<void> _addHistory() async {
    final entityType = widget.task['entity_type']?.toString();
    final entityId = widget.task['entity_id']?.toString();
    if (entityType == null ||
        entityType.trim().isEmpty ||
        entityId == null ||
        entityId.trim().isEmpty) {
      return;
    }

    final controller = TextEditingController();
    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить запись'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Комментарий к истории',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, controller.text),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmed = body?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    try {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: entityType,
            entityId: entityId,
            body: trimmed,
          );
      if (!mounted) return;
      setState(() => _timelineFuture = _fetchTimeline());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запись добавлена в историю')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось добавить запись: $e'),
          backgroundColor: AppColor.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entityLabel = _taskEntityLabel(widget.task) ?? 'Связанный объект';
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.76,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withAlpha(70),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.task['title']?.toString().trim().isNotEmpty ==
                                  true
                              ? widget.task['title'].toString()
                              : 'История',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entityLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Добавить запись',
                    onPressed: _addHistory,
                    icon: const Icon(Icons.add_comment_rounded),
                  ),
                  IconButton(
                    tooltip: 'Закрыть задачу',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Задача'),
                  Tab(text: 'Объект'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    // The task's own change log — what the customer means by
                    // «история задач как в AmoCRM».
                    _HistoryList<Map<String, dynamic>>(
                      future: _historyFuture,
                      emptyLabel: 'Изменений по задаче пока нет',
                      itemBuilder: (item) => _TaskHistoryTile(entry: item),
                    ),
                    // The related client/lead's timeline: what this sheet
                    // showed before the task log existed. Kept — it answers a
                    // different question («что вообще происходило с клиентом»).
                    _HistoryList<Map<String, dynamic>>(
                      future: _timelineFuture,
                      emptyLabel: 'История по объекту пока пустая',
                      itemBuilder: (item) => _TimelineTile(item: item),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Supervisor control feed: who moved which deadline, and when. Read-only by
/// design — this answers «кто перенёс», it is not another place to edit tasks.
class _TaskHistoryFeedSheet extends ConsumerStatefulWidget {
  const _TaskHistoryFeedSheet();

  @override
  ConsumerState<_TaskHistoryFeedSheet> createState() =>
      _TaskHistoryFeedSheetState();
}

class _TaskHistoryFeedSheetState extends ConsumerState<_TaskHistoryFeedSheet> {
  static const _fields = <String, String>{
    'due_at': 'Переносы срока',
    'assigned_to': 'Смена исполнителя',
    'status': 'Смена статуса',
  };

  String _field = 'due_at';
  late Future<List<Map<String, dynamic>>> _future = _fetch();

  Future<List<Map<String, dynamic>>> _fetch() {
    return ref
        .read(magicCrmServiceProvider)
        .listTaskHistoryFeed(field: _field, limit: 100);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.76,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withAlpha(70),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Контроль изменений задач',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть фильтры',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _fields.entries
                    .map(
                      (entry) => ChoiceChip(
                        label: Text(entry.value),
                        selected: _field == entry.key,
                        onSelected: (_) => setState(() {
                          _field = entry.key;
                          _future = _fetch();
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _HistoryList<Map<String, dynamic>>(
                  future: _future,
                  emptyLabel: 'Изменений за этот период нет',
                  itemBuilder: (item) => _TaskHistoryTile(
                    entry: item,
                    // Cross-task feed: without the task name a line reading
                    // «Срок перенесён: 12.06 → 20.06» names no task at all.
                    showTaskTitle: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared skeleton/error/empty/list plumbing for both tabs of the history sheet.
class _HistoryList<T> extends StatelessWidget {
  final Future<List<T>> future;
  final String emptyLabel;
  final Widget Function(T item) itemBuilder;

  const _HistoryList({
    required this.future,
    required this.emptyLabel,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListSkeleton(count: 5);
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'История временно недоступна',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return Center(
            child: Text(
              emptyLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => itemBuilder(items[index]),
        );
      },
    );
  }
}

/// One field change, rendered as «Срок: было → стало», with author and time.
class _TaskHistoryTile extends StatelessWidget {
  final Map<String, dynamic> entry;

  /// Cross-task feeds need the task name; the per-task feed already has it in
  /// the sheet header and would just repeat it on every row.
  final bool showTaskTitle;

  const _TaskHistoryTile({required this.entry, this.showTaskTitle = false});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final field = entry['field']?.toString() ?? '';
    final author = entry['author_name']?.toString().trim();
    final when = _formatTaskHistoryDate(entry['changed_at']);
    // Backfilled HolliHop rows carry the ORIGINAL date, so without this badge a
    // 2023 import event is indistinguishable from something a colleague just did.
    final imported = entry['source']?.toString() == 'hollihop';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_taskHistoryIcon(field), size: 18, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showTaskTitle) ...[
                  Text(
                    entry['task_title']?.toString() ?? 'Задача',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  _taskHistoryHeadline(entry),
                  style: TextStyle(
                    fontWeight: showTaskTitle
                        ? FontWeight.w500
                        : FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (author != null && author.isNotEmpty) author,
                    ?when,
                    if (imported) 'из HolliHop',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _taskHistoryIcon(String field) {
  return switch (field) {
    'created' => Icons.add_circle_outline_rounded,
    'due_at' => Icons.event_repeat_rounded,
    'assigned_to' => Icons.person_outline_rounded,
    'status' => Icons.flag_outlined,
    'entity' => Icons.link_rounded,
    _ => Icons.edit_outlined,
  };
}

/// Renders one change as a sentence. Values are formatted per field: a raw
/// timestamp or a bare `done` would be readable to us and to nobody else.
String _taskHistoryHeadline(Map<String, dynamic> entry) {
  final field = entry['field']?.toString() ?? '';
  String value(Object? raw) {
    final text = raw?.toString().trim();
    return (text == null || text.isEmpty) ? '—' : text;
  }

  switch (field) {
    case 'created':
      return 'Задача создана';
    case 'status':
      return 'Статус: ${_taskStatusLabel(entry['old_value']?.toString())} → '
          '${_taskStatusLabel(entry['new_value']?.toString())}';
    case 'due_at':
      final from = _formatTaskHistoryDate(entry['old_value']) ?? '—';
      final to = _formatTaskHistoryDate(entry['new_value']) ?? '—';
      return 'Срок перенесён: $from → $to';
    case 'assigned_to':
      return 'Исполнитель: ${value(entry['old_user_name'])} → '
          '${value(entry['new_user_name'])}';
    case 'title':
      return 'Название: ${value(entry['old_value'])} → ${value(entry['new_value'])}';
    case 'description':
      return 'Описание изменено';
    case 'entity':
      return 'Связанный объект изменён';
    default:
      return 'Изменение: $field';
  }
}

String? _formatTaskHistoryDate(Object? raw) {
  final text = raw?.toString();
  if (text == null || text.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return DateFormat('dd.MM.yyyy HH:mm').format(parsed.toLocal());
}

String _taskStatusLabel(String? status) {
  switch (status) {
    case 'in_progress':
      return 'В работе';
    case 'done':
      return 'Завершена';
    case 'cancelled':
      return 'Отменена';
    default:
      return 'К выполнению';
  }
}

class _TimelineTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _TimelineTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final amount = _formatTimelineAmount(item['amount']);
    final status = item['status']?.toString().trim();
    final subtitle = [
      if ((item['body']?.toString().trim() ?? '').isNotEmpty)
        item['body'].toString().trim(),
      _formatTimelineDate(item['occurred_at']),
      if ((item['actor_name']?.toString().trim() ?? '').isNotEmpty)
        item['actor_name'].toString().trim(),
    ].where((value) => value != null && value.isNotEmpty).join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: AppColor.gold.withAlpha(30),
        child: Icon(
          _timelineIcon(item['type']?.toString()),
          size: 18,
          color: AppColor.gold,
        ),
      ),
      title: Text(
        item['title']?.toString() ??
            _timelineTypeLabel(item['type']?.toString()),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: amount == null && (status == null || status.isEmpty)
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (amount != null)
                  Text(
                    amount,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColor.success,
                    ),
                  ),
                if (status != null && status.isNotEmpty)
                  Text(
                    _timelineStatusLabel(status),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
    );
  }
}

String? _taskEntityLabel(Map<String, dynamic> task) {
  final name = task['entity_name']?.toString();
  final label = name == null || name.trim().isEmpty ? 'Без имени' : name;
  switch (task['entity_type']) {
    case 'student':
      return 'Ученик: $label';
    case 'teacher':
      return 'Учитель: $label';
    case 'lead':
      return 'Лид: $label';
    case 'group':
      return 'Группа: $label';
    case 'profile':
      return 'Профиль: $label';
    case 'lesson':
      return 'Занятие: $label';
    default:
      return null;
  }
}

IconData _timelineIcon(String? type) {
  return switch (type) {
    'payment' => Icons.payments_rounded,
    'task' => Icons.task_alt_rounded,
    'comment' => Icons.chat_bubble_outline_rounded,
    'lesson' => Icons.event_available_rounded,
    'audit' => Icons.verified_user_rounded,
    _ => Icons.history_rounded,
  };
}

String _timelineTypeLabel(String? type) {
  return switch (type) {
    'payment' => 'Оплата',
    'task' => 'Задача',
    'comment' => 'Комментарий',
    'lesson' => 'Занятие',
    'audit' => 'Аудит',
    _ => 'Событие',
  };
}

String _timelineStatusLabel(String status) {
  return switch (status) {
    'open' => 'к выполнению',
    'in_progress' => 'в работе',
    'done' => 'завершено',
    'cancelled' => 'отменено',
    'cash' => 'наличные',
    'card' => 'карта',
    'transfer' => 'перевод',
    _ => status,
  };
}

String? _formatTimelineDate(Object? raw) {
  final value = raw?.toString();
  if (value == null || value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('d MMM yyyy, HH:mm', 'ru').format(parsed.toLocal());
}

String? _formatTimelineAmount(Object? raw) {
  if (raw == null) return null;
  final amount = raw is num ? raw : num.tryParse(raw.toString());
  if (amount == null) return null;
  return '${NumberFormat.decimalPattern('ru').format(amount)} ₽';
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
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: onTap != null ? Border.all(color: color.withAlpha(50)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 10, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

String _taskFilterProfileName(Map<String, dynamic> profile) {
  final firstName = profile['first_name']?.toString().trim() ?? '';
  final lastName = profile['last_name']?.toString().trim() ?? '';
  final name = '$firstName $lastName'.trim();
  final role = profile['role']?.toString();
  final displayName = name.isEmpty
      ? profile['email']?.toString() ?? 'Без имени'
      : name;
  if (role == null || role.isEmpty) return displayName;
  return '$displayName (${_taskFilterRoleLabel(role)})';
}

String _taskFilterRoleLabel(String role) {
  return switch (role) {
    'admin' => 'Администратор',
    'system_admin' => 'Администратор системы',
    'manager' => 'Управляющий',
    'director' => 'Директор',
    'teacher' => 'Учитель',
    'client' => 'Клиент',
    _ => role,
  };
}

class _TaskAssigneeDialog extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final String? initialUserId;

  const _TaskAssigneeDialog({
    required this.employees,
    required this.initialUserId,
  });

  @override
  State<_TaskAssigneeDialog> createState() => _TaskAssigneeDialogState();
}

class _TaskAssigneeDialogState extends State<_TaskAssigneeDialog> {
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    final userIds = widget.employees
        .map((profile) => profile['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    _selectedUserId = userIds.contains(widget.initialUserId)
        ? widget.initialUserId
        : (userIds.isEmpty ? null : userIds.first);
  }

  String? _selectedEmployeeName(List<Map<String, dynamic>> employees) {
    if (_selectedUserId == null) return null;
    for (final profile in employees) {
      if (profile['user_id']?.toString() == _selectedUserId) {
        return _taskFilterProfileName(profile);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final employees = widget.employees.where((profile) {
      final userId = profile['user_id']?.toString();
      return userId != null && userId.isNotEmpty;
    }).toList();

    return AlertDialog(
      title: const Text('Назначить ответственного'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => SearchableSelect.show(
            context: context,
            title: 'Ответственный',
            hintText: 'Поиск по имени…',
            selectedId: _selectedUserId,
            isNullable: false,
            items: [
              for (final profile in employees)
                SearchableSelectItem(
                  id: profile['user_id']?.toString() ?? '',
                  label: _taskFilterProfileName(profile),
                ),
            ],
            onSelected: (item) {
              if (item == null) return;
              setState(() => _selectedUserId = item.id);
            },
          ),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Ответственный',
              prefixIcon: Icon(Icons.person_search_rounded),
            ),
            child: Text(
              _selectedEmployeeName(employees) ?? 'Выберите сотрудника',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _selectedUserId == null
              ? null
              : () => Navigator.pop(context, _selectedUserId),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Назначить'),
        ),
      ],
    );
  }
}

class _TaskDialog extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> leads;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> teachers;

  /// Server search for the «Объект» picker (students/leads): the pre-loaded
  /// lists are capped at 100, so without this a task simply can't reference
  /// record #101+.
  final Future<List<Map<String, dynamic>>> Function(
    String entityType,
    String query,
  )?
  onSearchEntities;

  /// When set the dialog EDITS this task instead of creating one: fields are
  /// prefilled and the button says «Сохранить».
  final Map<String, dynamic>? task;

  const _TaskDialog({
    required this.employees,
    required this.students,
    required this.leads,
    required this.groups,
    required this.teachers,
    this.onSearchEntities,
    this.task,
  });

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _entityType = 'student';
  String? _selectedEntityId;
  String? _selectedEntityLabel;
  String? _selectedEmployeeUserId;
  DateTime? _dueDate;
  String _priority = 'medium';
  // false → the deadline is «all-day» (a date with no meaningful time).
  bool _dueHasTime = true;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_onFormChanged);
    final task = widget.task;
    if (task != null) {
      _titleCtrl.text = task['title']?.toString() ?? '';
      _descCtrl.text = task['description']?.toString() ?? '';
      _entityType = task['entity_type']?.toString() ?? 'student';
      _selectedEntityId = task['entity_id']?.toString();
      _selectedEntityLabel = task['entity_name']?.toString();
      _selectedEmployeeUserId = task['assigned_to']?.toString();
      _priority = task['priority']?.toString() ?? 'medium';
      _dueHasTime = task['due_all_day'] != true;
      final due = task['due_at'];
      if (due != null) {
        _dueDate = DateTime.tryParse(due.toString())?.toLocal();
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onFormChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  /// Date, then time only when «со временем» is on. With a time the deadline
  /// drives the -1h/-10m/overdue reminders; «без времени» stores an all-day
  /// deadline (kept at noon so a reminder never lands in the small hours).
  Future<void> _pickDueAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    if (!_dueHasTime) {
      setState(() {
        _dueDate = DateTime(date.year, date.month, date.day, 12, 0);
      });
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: _dueDate == null
          ? const TimeOfDay(hour: 12, minute: 0)
          : TimeOfDay.fromDateTime(_dueDate!),
    );
    if (!mounted) return;
    setState(() {
      final fallback = _dueDate == null
          ? const TimeOfDay(hour: 12, minute: 0)
          : TimeOfDay.fromDateTime(_dueDate!);
      final picked = time ?? fallback;
      _dueDate = DateTime(
        date.year,
        date.month,
        date.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final entityItems = _entityItems();
    // Owner rule: a task must carry a deadline, so «Создать» is disabled until
    // one is set (title and object were already required).
    final canSubmit =
        _titleCtrl.text.trim().isNotEmpty &&
        _selectedEntityId != null &&
        _dueDate != null;

    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(_isEdit ? 'Редактировать задачу' : 'Новая задача'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Описание (необязательно)',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _entityType,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Тип объекта'),
              items: const [
                DropdownMenuItem(value: 'student', child: Text('Ученик')),
                DropdownMenuItem(value: 'lead', child: Text('Лид')),
                DropdownMenuItem(value: 'group', child: Text('Группа')),
                DropdownMenuItem(value: 'teacher', child: Text('Учитель')),
                DropdownMenuItem(value: 'profile', child: Text('Профиль')),
              ],
              onChanged: (value) => setState(() {
                _entityType = value ?? 'student';
                _selectedEntityId = null;
                _selectedEntityLabel = null;
              }),
            ),
            const SizedBox(height: 12),
            // Searchable picker instead of a plain dropdown: a school has
            // hundreds of students/leads and the dropdown was capped at the
            // first 100 with no way to type a name.
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickEntity(entityItems),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Объект',
                  suffixIcon: Icon(Icons.search_rounded, size: 20),
                ),
                child: Text(
                  _selectedEntityLabel ?? 'Выбрать…',
                  overflow: TextOverflow.ellipsis,
                  style: _selectedEntityId == null
                      ? TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SearchablePickerField(
              label: 'Ответственный',
              placeholder: 'Не назначен',
              selectedId: _selectedEmployeeUserId,
              items: [
                for (final profile in widget.employees)
                  if (profile['user_id'] != null)
                    SearchableSelectItem(
                      id: profile['user_id'].toString(),
                      label: _profileName(profile),
                    ),
              ],
              onSelected: (item) =>
                  setState(() => _selectedEmployeeUserId = item?.id),
            ),
            const SizedBox(height: 12),
            // Priority (real, stored — was a dead filter before).
            DropdownButtonFormField<String>(
              initialValue: _priority,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Приоритет'),
              items: const [
                DropdownMenuItem(value: 'high', child: Text('Высокий')),
                DropdownMenuItem(value: 'medium', child: Text('Средний')),
                DropdownMenuItem(value: 'low', child: Text('Низкий')),
              ],
              onChanged: (value) =>
                  setState(() => _priority = value ?? 'medium'),
            ),
            const SizedBox(height: 4),
            // With-time / all-day toggle for the deadline.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Указать время'),
              subtitle: Text(
                _dueHasTime ? 'Срок со временем' : 'Срок без времени (весь день)',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              value: _dueHasTime,
              onChanged: (value) => setState(() {
                _dueHasTime = value;
                // Re-normalise an already-picked date to the new mode: an
                // all-day deadline sits at noon.
                if (!value && _dueDate != null) {
                  _dueDate = DateTime(
                    _dueDate!.year,
                    _dueDate!.month,
                    _dueDate!.day,
                    12,
                  );
                }
              }),
            ),
            OutlinedButton.icon(
              onPressed: _pickDueAt,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(
                _dueDate == null
                    ? 'Установить срок *'
                    : DateFormat(
                        _dueHasTime ? 'dd.MM.yyyy HH:mm' : 'dd.MM.yyyy',
                      ).format(_dueDate!),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () {
                  Navigator.pop(context, {
                    'title': _titleCtrl.text.trim(),
                    'description': _descCtrl.text.trim(),
                    'entity_type': _entityType,
                    'entity_id': _selectedEntityId,
                    'assigned_to': _selectedEmployeeUserId,
                    'priority': _priority,
                    'due_all_day': !_dueHasTime,
                    // toUtc() matters: a bare local ISO string carries no
                    // offset, so the timestamptz column would read it in the
                    // server's zone and shift the deadline.
                    'due_at': _dueDate?.toUtc().toIso8601String(),
                  });
                }
              : null,
          child: Text(_isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }

  void _pickEntity(List<(String, String)> entityItems) {
    final items = [
      for (final (id, label) in entityItems)
        SearchableSelectItem(id: id, label: label),
    ];
    // Server search only where the dataset is unbounded; groups/teachers/
    // profiles fit in the pre-loaded page and filter locally.
    final serverSearch =
        widget.onSearchEntities != null &&
        (_entityType == 'student' || _entityType == 'lead');
    SearchableSelect.show(
      context: context,
      title: _entityTypeLabel(_entityType),
      hintText: 'Поиск по имени…',
      items: items,
      selectedId: _selectedEntityId,
      isNullable: false,
      onSearch: !serverSearch
          ? null
          : (query) async {
              final rows = await widget.onSearchEntities!(_entityType, query);
              return [
                for (final row in rows)
                  SearchableSelectItem(
                    id: row['id'].toString(),
                    label: _entityType == 'lead'
                        ? _leadName(row)
                        : _personName(row),
                    subtitle: row['phone']?.toString(),
                  ),
              ];
            },
      onSelected: (item) {
        if (item == null) return;
        setState(() {
          _selectedEntityId = item.id;
          _selectedEntityLabel = item.label;
        });
      },
    );
  }

  String _entityTypeLabel(String type) {
    return switch (type) {
      'lead' => 'Лид',
      'group' => 'Группа',
      'teacher' => 'Учитель',
      'profile' => 'Профиль',
      _ => 'Ученик',
    };
  }

  List<(String, String)> _entityItems() {
    switch (_entityType) {
      case 'lead':
        return widget.leads
            .map((lead) => (lead['id'].toString(), _leadName(lead)))
            .toList();
      case 'group':
        return widget.groups
            .map((group) => (group['id'].toString(), _safeName(group)))
            .toList();
      case 'teacher':
        return widget.teachers
            .map((teacher) => (teacher['id'].toString(), _personName(teacher)))
            .toList();
      case 'profile':
        return widget.employees
            .map((profile) => (profile['id'].toString(), _profileName(profile)))
            .toList();
      default:
        return widget.students
            .map((student) => (student['id'].toString(), _personName(student)))
            .toList();
    }
  }

  String _personName(Map<String, dynamic> item) {
    final name = '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'
        .trim();
    return name.isEmpty ? 'Без имени' : name;
  }

  String _profileName(Map<String, dynamic> item) {
    final name = _personName(item);
    final role = item['role']?.toString();
    if (role == null || role.isEmpty) return name;
    return '$name (${_roleLabel(role)})';
  }

  String _roleLabel(String role) {
    return switch (role) {
      'admin' => 'Администратор',
      'system_admin' => 'Администратор системы',
      'manager' => 'Управляющий',
      'director' => 'Директор',
      'teacher' => 'Учитель',
      'client' => 'Клиент',
      _ => role,
    };
  }

  String _leadName(Map<String, dynamic> lead) {
    final name = '${lead['first_name'] ?? ''} ${lead['last_name'] ?? ''}'
        .trim();
    if (name.isNotEmpty) return name;
    return lead['name']?.toString().trim().isNotEmpty == true
        ? lead['name'].toString()
        : 'Без имени';
  }

  String _safeName(Map<String, dynamic> item) {
    final name = item['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Без имени' : name;
  }
}
