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
  final Future<void> Function(Map<String, dynamic>) onRescheduleTap;
  final Future<void> Function(Map<String, dynamic>) onOpenEntity;
  final Future<void> Function(EntityLink) onOpenLink;
  final Future<void> Function(Map<String, dynamic>) onEditTap;
  final Future<void> Function(Map<String, dynamic>) onDeleteTap;

  const _TaskCard({
    required this.task,
    required this.isPending,
    required this.onStatusChange,
    required this.onTimelineTap,
    required this.onReassignTap,
    required this.onRescheduleTap,
    required this.onOpenEntity,
    required this.onOpenLink,
    required this.onEditTap,
    required this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    // Read defensively — a numeric/null id from the API would otherwise throw
    // a TypeError during build and render the card as a red error box.
    final id = task['id']?.toString() ?? '';
    final status = task['status']?.toString();
    final dueAllDay = task['due_all_day'] == true;
    final dueDate = task['due_date'] != null
        ? DateFormat(
            // With a time it drives the -1h/-10m reminders, so the time is
            // shown; an all-day deadline shows the date alone.
            dueAllDay ? 'd MMM' : 'd MMM, HH:mm',
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
    final isCancelled = status == 'cancelled';
    final priority = task['priority']?.toString() ?? 'medium';
    final assigneeText = task['assigned_name']?.toString();
    final creatorText = task['creator_name']?.toString();
    final assignedProfileId = task['assigned_profile_id']?.toString();
    final creatorProfileId = task['creator_profile_id']?.toString();
    final branchText = task['branch_name']?.toString();
    final entityText = _taskEntityLabel(task);
    final onEntityTap = _entityTap(context, task);

    return Opacity(
      // A cancelled task stays in the list but reads as retired — the whole
      // card dims, not just a hidden status. (Before, a cancelled task looked
      // identical to an open one, so «Отменить» seemed to do nothing.)
      opacity: isPending ? 0.65 : (isCancelled ? 0.55 : 1),
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
                  // Priority dot: red = high, amber = medium, grey = low.
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: _priorityColor(priority),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      task['title']?.toString() ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        decoration: isCancelled
                            ? TextDecoration.lineThrough
                            : null,
                        color: isCancelled
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
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
                    tooltip: 'История задачи',
                    // No longer gated on hasEntity: the task's own change log
                    // exists even when the related object does not.
                    onPressed: isPending ? null : () => onTimelineTap(task),
                    icon: const Icon(Icons.history_rounded),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Действия задачи',
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
                      if (value == 'reschedule') {
                        onRescheduleTap(task);
                        return;
                      }
                      if (value == 'edit') {
                        onEditTap(task);
                        return;
                      }
                      if (value == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Удалить задачу?'),
                            content: const Text(
                              'Задача будет удалена безвозвратно.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Отмена'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColor.danger,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Удалить'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) onDeleteTap(task);
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
                        value: 'edit',
                        child: Text('Редактировать'),
                      ),
                      const PopupMenuItem(
                        value: 'reassign',
                        child: Text('Назначить ответственного'),
                      ),
                      const PopupMenuItem(
                        value: 'reschedule',
                        child: Text('Перенести срок'),
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
                      const PopupMenuDivider(),
                      if (status != 'cancelled')
                        const PopupMenuItem(
                          value: 'cancelled',
                          child: Text('Отменить'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Удалить',
                          style: TextStyle(color: AppColor.danger),
                        ),
                      ),
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
                  _Tag(label: _taskStatusLabel(status), color: AppColor.gold),
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
                          ? () => onOpenLink(
                              EntityLink.typed(
                                entityType: EntityLinkType.user,
                                entityId: assignedProfileId,
                                optionalFocus: EntityLinkFocus(
                                  focus: 'assignee',
                                ),
                              ),
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
                          ? () => onOpenLink(
                              EntityLink.typed(
                                entityType: EntityLinkType.user,
                                entityId: creatorProfileId,
                                optionalFocus: EntityLinkFocus(
                                  focus: 'creator',
                                ),
                              ),
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

  static Color _priorityColor(String priority) {
    return switch (priority) {
      'high' => AppColor.danger,
      'low' => AppColor.text2,
      _ => AppColor.warning,
    };
  }
}

/// Год / Месяц / День switcher for the tasks calendar.
class _TaskViewSwitcher extends StatelessWidget {
  final String view; // 'year' | 'month' | 'day'
  final ValueChanged<String> onChanged;

  const _TaskViewSwitcher({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String value, String label) {
      final active = view == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColor.gold : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: active ? AppColor.gold : AppColor.goldLine,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? Colors.black
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 0, 9, 6),
      child: Row(
        children: [
          seg('year', 'Год'),
          seg('month', 'Месяц'),
          seg('day', 'День'),
        ],
      ),
    );
  }
}

String _taskDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Month calendar: a day-count per cell, tap a day to open its list.
class _TaskMonthGrid extends StatelessWidget {
  final DateTime month; // first day of the shown month
  final Map<String, int> counts; // 'yyyy-MM-dd' -> count
  final bool loading;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final void Function(DateTime day) onDayTap;

  const _TaskMonthGrid({
    required this.month,
    required this.counts,
    required this.loading,
    required this.onPrev,
    required this.onNext,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    // Monday-first grid. weekday: Mon=1..Sun=7.
    final leading = first.weekday - 1;
    final gridStart = first.subtract(Duration(days: leading));
    final today = DateTime.now();
    final todayKey = _taskDayKey(today);

    return Column(
      children: [
        _CalendarHeader(
          title: DateFormat('LLLL yyyy', 'ru').format(first),
          onPrev: onPrev,
          onNext: onNext,
          loading: loading,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final d in const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.85,
            ),
            itemCount: 42,
            itemBuilder: (ctx, i) {
              final day = gridStart.add(Duration(days: i));
              final inMonth = day.month == month.month;
              final key = _taskDayKey(day);
              final count = counts[key] ?? 0;
              final isToday = key == todayKey;
              return GestureDetector(
                onTap: () => onDayTap(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: isToday
                        ? AppColor.gold.withValues(alpha: 0.14)
                        : cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isToday ? AppColor.gold : cs.outlineVariant,
                      width: isToday ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          color: inMonth
                              ? cs.onSurface
                              : cs.onSurfaceVariant.withValues(alpha: 0.4),
                          fontSize: 13,
                          fontWeight: isToday
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColor.actionBlue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Year calendar: 12 months, each with a total task count.
class _TaskYearGrid extends StatelessWidget {
  final int year;
  final Map<String, int> counts; // 'yyyy-MM-dd' -> count
  final bool loading;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final void Function(int month) onMonthTap;

  const _TaskYearGrid({
    required this.year,
    required this.counts,
    required this.loading,
    required this.onPrev,
    required this.onNext,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Sum each month from the day-keyed counts.
    final monthTotals = List<int>.filled(13, 0);
    counts.forEach((key, value) {
      // key = 'yyyy-MM-dd'
      if (key.length >= 7 && key.startsWith('$year-')) {
        final mm = int.tryParse(key.substring(5, 7));
        if (mm != null && mm >= 1 && mm <= 12) monthTotals[mm] += value;
      }
    });
    final now = DateTime.now();

    return Column(
      children: [
        _CalendarHeader(
          title: '$year',
          onPrev: onPrev,
          onNext: onNext,
          loading: loading,
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.3,
            ),
            itemCount: 12,
            itemBuilder: (ctx, i) {
              final month = i + 1;
              final total = monthTotals[month];
              final isCurrent = year == now.year && month == now.month;
              return GestureDetector(
                onTap: () => onMonthTap(month),
                child: Container(
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppColor.gold.withValues(alpha: 0.14)
                        : cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent ? AppColor.gold : cs.outlineVariant,
                      width: isCurrent ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat(
                          'LLL',
                          'ru',
                        ).format(DateTime(year, month)).toUpperCase(),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        total == 0 ? '—' : '$total',
                        style: TextStyle(
                          color: total == 0
                              ? cs.onSurfaceVariant
                              : AppColor.actionBlue,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Prev/next header shared by the month and year grids.
class _CalendarHeader extends StatelessWidget {
  final String title;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool loading;

  const _CalendarHeader({
    required this.title,
    required this.onPrev,
    required this.onNext,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Предыдущий период',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.isNotEmpty
                        ? '${title[0].toUpperCase()}${title.substring(1)}'
                        : title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (loading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Следующий период',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
