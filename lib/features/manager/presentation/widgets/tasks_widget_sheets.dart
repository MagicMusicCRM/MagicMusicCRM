part of 'tasks_widget.dart';

class _TaskTimelineSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> task;

  const _TaskTimelineSheet({required this.task});

  @override
  ConsumerState<_TaskTimelineSheet> createState() => _TaskTimelineSheetState();
}

class _TaskTimelineSheetState extends ConsumerState<_TaskTimelineSheet> {
  late Future<List<Map<String, dynamic>>> _timelineFuture;

  @override
  void initState() {
    super.initState();
    _timelineFuture = _fetchTimeline();
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
                        const Text(
                          'История объекта',
                          style: TextStyle(
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
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _timelineFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const ListSkeleton(count: 5);
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'История временно недоступна',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    final timeline =
                        snapshot.data ?? const <Map<String, dynamic>>[];
                    if (timeline.isEmpty) {
                      return Center(
                        child: Text(
                          'История по объекту пока пустая',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: timeline.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        return _TimelineTile(item: timeline[index]);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  const _TaskDialog({
    required this.employees,
    required this.students,
    required this.leads,
    required this.groups,
    required this.teachers,
    this.onSearchEntities,
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

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_onFormChanged);
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

  @override
  Widget build(BuildContext context) {
    final entityItems = _entityItems();
    final canSubmit =
        _titleCtrl.text.trim().isNotEmpty && _selectedEntityId != null;

    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('Новая задача'),
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
            DropdownButtonFormField<String>(
              initialValue: _selectedEmployeeUserId,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Ответственный'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Не назначен'),
                ),
                ...widget.employees
                    .where((profile) => profile['user_id'] != null)
                    .map(
                      (profile) => DropdownMenuItem<String>(
                        value: profile['user_id'].toString(),
                        child: Text(_profileName(profile)),
                      ),
                    ),
              ],
              onChanged: (value) =>
                  setState(() => _selectedEmployeeUserId = value),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) setState(() => _dueDate = date);
              },
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(
                _dueDate == null
                    ? 'Установить срок'
                    : DateFormat('dd.MM.yyyy').format(_dueDate!),
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
                    'due_at': _dueDate?.toIso8601String(),
                  });
                }
              : null,
          child: const Text('Создать'),
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
