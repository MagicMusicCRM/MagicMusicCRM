part of 'tasks_widget.dart';

/// Day pager for the to-do view: ‹ day › plus a jump back to today.
class _DayNavigator extends StatelessWidget {
  final DateTime day;
  final void Function(int days) onShift;
  final VoidCallback onPick;
  final VoidCallback onToday;

  const _DayNavigator({
    required this.day,
    required this.onShift,
    required this.onPick,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    // Relative names read faster than a date when you are working the list.
    final label = switch (diff) {
      0 => 'Сегодня',
      1 => 'Завтра',
      -1 => 'Вчера',
      _ => DateFormat('EEEE, d MMMM', 'ru').format(day),
    };
    final sub = diff.abs() <= 1
        ? DateFormat('EEEE, d MMMM', 'ru').format(day)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Предыдущий день',
            onPressed: () => onShift(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Следующий день',
            onPressed: () => onShift(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          if (diff != 0)
            TextButton(onPressed: onToday, child: const Text('Сегодня')),
        ],
      ),
    );
  }
}

class _TasksError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _TasksError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColor.danger,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'Не удалось загрузить задачи',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _TaskFilters extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String status;
  final String entityType;
  final String priority;
  final String branchId;
  final String assigneeId;
  final String due;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> employees;
  final bool loading;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onEntityTypeChanged;
  final ValueChanged<String> onPriorityChanged;
  final ValueChanged<String> onBranchChanged;
  final ValueChanged<String> onAssigneeChanged;
  final ValueChanged<String> onDueChanged;
  final VoidCallback onClear;

  const _TaskFilters({
    required this.searchCtrl,
    required this.status,
    required this.entityType,
    required this.priority,
    required this.branchId,
    required this.assigneeId,
    required this.due,
    required this.branches,
    required this.employees,
    required this.loading,
    required this.onStatusChanged,
    required this.onEntityTypeChanged,
    required this.onPriorityChanged,
    required this.onBranchChanged,
    required this.onAssigneeChanged,
    required this.onDueChanged,
    required this.onClear,
  });

  bool get _hasFilters {
    return searchCtrl.text.trim().isNotEmpty ||
        status != 'all' ||
        entityType != 'all' ||
        priority != 'all' ||
        branchId != 'all' ||
        assigneeId != 'all' ||
        due != 'all';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340, minWidth: 240),
              child: TextField(
                controller: searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Поиск задач',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            _FilterDropdown(
              label: 'Объект',
              value: entityType,
              icon: Icons.link_rounded,
              options: const [
                ('all', 'Все объекты'),
                ('student', 'Ученики'),
                ('lead', 'Лиды'),
                ('group', 'Группы'),
                ('teacher', 'Учителя'),
                ('profile', 'Профили'),
                ('lesson', 'Занятия'),
              ],
              onChanged: onEntityTypeChanged,
            ),
            _FilterDropdown(
              label: 'Срок',
              value: due,
              icon: Icons.event_rounded,
              options: const [
                // 'day' is the day-by-day to-do (with the pager below);
                // 'today' is the same range but pinned, without paging.
                ('day', 'По дням'),
                ('all', 'Любой срок'),
                ('overdue', 'Просрочено'),
                ('today', 'Сегодня'),
                ('week', '7 дней'),
              ],
              onChanged: onDueChanged,
            ),
            _FilterDropdown(
              label: 'Приоритет',
              value: priority,
              icon: Icons.flag_outlined,
              options: const [
                ('all', 'Любой'),
                ('high', 'Высокий'),
                ('medium', 'Средний'),
                ('low', 'Низкий'),
              ],
              onChanged: onPriorityChanged,
            ),
            _FilterDropdown(
              label: 'Филиал',
              value: branchId,
              icon: Icons.location_on_outlined,
              options: [
                const ('all', 'Все филиалы'),
                ...branches.map(
                  (branch) => (
                    branch['id']?.toString() ?? '',
                    branch['name']?.toString() ?? 'Без названия',
                  ),
                ),
              ],
              enabled: !loading,
              onChanged: onBranchChanged,
            ),
            _FilterDropdown(
              label: 'Ответственный',
              value: assigneeId,
              icon: Icons.person_search_rounded,
              options: [
                const ('all', 'Все сотрудники'),
                ...employees.map(
                  (profile) => (
                    profile['user_id']?.toString() ?? '',
                    _taskFilterProfileName(profile),
                  ),
                ),
              ],
              enabled: !loading,
              onChanged: onAssigneeChanged,
            ),
            if (_hasFilters)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Сбросить'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'Все',
                value: 'all',
                selected: status == 'all',
                onTap: () => onStatusChanged('all'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'К выполнению',
                value: 'open',
                selected: status == 'open',
                onTap: () => onStatusChanged('open'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'В работе',
                value: 'in_progress',
                selected: status == 'in_progress',
                onTap: () => onStatusChanged('in_progress'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Завершены',
                value: 'done',
                selected: status == 'done',
                onTap: () => onStatusChanged('done'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Отменены',
                value: 'cancelled',
                selected: status == 'cancelled',
                onTap: () => onStatusChanged('cancelled'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<(String, String)> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.icon,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = options.any((option) => option.$1 == value)
        ? value
        : options.first.$1;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240, minWidth: 180),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$normalized-${options.length}'),
        initialValue: normalized,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        items: options
            .where((option) => option.$1.isNotEmpty)
            .map(
              (option) => DropdownMenuItem<String>(
                value: option.$1,
                child: Text(option.$2, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: enabled
            ? (value) {
                if (value != null) onChanged(value);
              }
            : null,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColor.gold
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected
                ? AppColor.gold
                : Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? AppColor.onGold
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final bool isPending;
  final Future<void> Function(String, String) onStatusChange;
  final Future<void> Function(Map<String, dynamic>) onTimelineTap;
  final Future<void> Function(Map<String, dynamic>) onReassignTap;
  final Future<void> Function(Map<String, dynamic>) onOpenEntity;

  const _TaskCard({
    required this.task,
    required this.isPending,
    required this.onStatusChange,
    required this.onTimelineTap,
    required this.onReassignTap,
    required this.onOpenEntity,
  });

  String _statusLabel(String? status) {
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

  @override
  Widget build(BuildContext context) {
    // Read defensively — a numeric/null id from the API would otherwise throw
    // a TypeError during build and render the card as a red error box.
    final id = task['id']?.toString() ?? '';
    final status = task['status']?.toString();
    final dueDate = task['due_date'] != null
        ? DateFormat(
            // Deadlines carry a time of day now, and it drives the -1h/-10m
            // reminders — showing the date alone hides why one just fired.
            'd MMM, HH:mm',
            'ru',
          ).format(DateTime.parse(task['due_date'].toString()).toLocal())
        : null;
    final dueAt = task['due_date'] != null
        ? DateTime.tryParse(task['due_date'].toString())?.toLocal()
        : null;
    final isOverdue =
        dueAt != null &&
        dueAt.isBefore(DateTime.now()) &&
        status != 'done' &&
        status != 'cancelled';
    final assigneeText = task['assigned_name']?.toString();
    final creatorText = task['creator_name']?.toString();
    final assignedProfileId = task['assigned_profile_id']?.toString();
    final creatorProfileId = task['creator_profile_id']?.toString();
    final branchText = task['branch_name']?.toString();
    final entityText = _taskEntityLabel(task);
    final onEntityTap = _entityTap(context, task);
    final hasEntity =
        task['entity_type']?.toString().trim().isNotEmpty == true &&
        task['entity_id']?.toString().trim().isNotEmpty == true;

    return Opacity(
      opacity: isPending ? 0.65 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        // An overdue task has to be findable at a glance in a long list, so
        // the whole card burns red rather than just the due-date tag.
        color: isOverdue
            ? Color.alphaBlend(
                AppColor.danger.withValues(alpha: 0.06),
                Theme.of(context).colorScheme.surface,
              )
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: isOverdue
                ? AppColor.danger
                : Theme.of(context).colorScheme.outlineVariant,
            width: isOverdue ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task['title']?.toString() ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  // One tap straight to the object, without hunting for the
                  // small entity tag at the bottom of the card.
                  IconButton(
                    tooltip: entityText == null
                        ? 'Перейти к объекту'
                        : 'Перейти: $entityText',
                    onPressed: (onEntityTap == null || isPending)
                        ? null
                        : onEntityTap,
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  IconButton(
                    tooltip: 'История объекта',
                    onPressed: hasEntity && !isPending
                        ? () => onTimelineTap(task)
                        : null,
                    icon: const Icon(Icons.history_rounded),
                  ),
                  PopupMenuButton<String>(
                    enabled: !isPending,
                    icon: isPending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.more_vert_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                    color: Theme.of(context).colorScheme.surface,
                    onSelected: (value) async {
                      if (value == 'reassign') {
                        onReassignTap(task);
                        return;
                      }
                      // Cancelling drops the task out of the active workflow —
                      // confirm to avoid an accidental mis-click in the menu.
                      if (value == 'cancelled') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Отменить задачу?'),
                            content: const Text(
                              'Задача будет отменена и скрыта из активного '
                              'списка.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Нет'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColor.danger,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Отменить задачу'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                      }
                      onStatusChange(id, value);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'reassign',
                        child: Text('Назначить ответственного'),
                      ),
                      const PopupMenuDivider(),
                      if (status != 'in_progress')
                        const PopupMenuItem(
                          value: 'in_progress',
                          child: Text('В работу'),
                        ),
                      if (status != 'done')
                        const PopupMenuItem(
                          value: 'done',
                          child: Text('Завершить'),
                        ),
                      if (status != 'open')
                        const PopupMenuItem(
                          value: 'open',
                          child: Text('Открыть снова'),
                        ),
                      if (status != 'cancelled') ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'cancelled',
                          child: Text(
                            'Отменить',
                            style: TextStyle(color: AppColor.danger),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (task['description'] != null &&
                  task['description'].toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task['description'].toString(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Tag(label: _statusLabel(status), color: AppColor.gold),
                  if (dueDate != null)
                    _Tag(
                      label: 'До: $dueDate',
                      color: isOverdue
                          ? AppColor.danger
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  if (assigneeText != null && assigneeText.trim().isNotEmpty)
                    _Tag(
                      label: assigneeText,
                      color: AppColor.gold2,
                      onTap:
                          (assignedProfileId != null &&
                              assignedProfileId.isNotEmpty)
                          ? () => context.push(
                              '/admin/profiles/$assignedProfileId',
                            )
                          : null,
                    ),
                  if (creatorText != null && creatorText.trim().isNotEmpty)
                    _Tag(
                      label: 'Создал: $creatorText',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      onTap:
                          (creatorProfileId != null &&
                              creatorProfileId.isNotEmpty)
                          ? () => context.push(
                              '/admin/profiles/$creatorProfileId',
                            )
                          : null,
                    ),
                  if (branchText != null && branchText.trim().isNotEmpty)
                    _Tag(label: branchText, color: AppColor.success),
                  if (entityText != null)
                    _Tag(
                      label: entityText,
                      color: AppColor.gold,
                      onTap: onEntityTap,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Every entity type a task can point at is now reachable; the parent does
  // the opening (groups/teachers need a fetch by id). Previously group,
  // teacher and profile fell through to null and the tap was simply dead.
  static const _openableEntityTypes = {
    'student',
    'lead',
    'lesson',
    'profile',
    'group',
    'teacher',
  };

  VoidCallback? _entityTap(BuildContext context, Map<String, dynamic> task) {
    final entityId = task['entity_id']?.toString();
    if (entityId == null || entityId.trim().isEmpty) return null;
    if (!_openableEntityTypes.contains(task['entity_type']?.toString())) {
      return null;
    }
    return () => onOpenEntity(task);
  }
}
