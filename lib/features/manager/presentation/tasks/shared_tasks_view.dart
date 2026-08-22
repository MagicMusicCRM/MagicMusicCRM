import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_controller.dart';

typedef SharedTaskCallback = void Function(Map<String, dynamic> task);

class SharedTasksView extends StatefulWidget {
  const SharedTasksView({
    super.key,
    required this.state,
    required this.onQueryChanged,
    required this.onSearchDraftChanged,
    required this.onOpen,
    required this.onClose,
    required this.onEdit,
    required this.onCreate,
    required this.onRetry,
    required this.onRefresh,
    required this.canCreate,
    required this.canEdit,
    this.embedded = false,
    this.showViewToolbar = true,
    this.scrollController,
  });

  final SharedTasksState state;
  final ValueChanged<SharedTasksQuery> onQueryChanged;
  final ValueChanged<SharedTasksQuery> onSearchDraftChanged;
  final SharedTaskCallback onOpen;
  final SharedTaskCallback onClose;
  final SharedTaskCallback onEdit;
  final VoidCallback onCreate;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final bool canCreate;
  final bool canEdit;
  final bool embedded;
  final bool showViewToolbar;
  final ScrollController? scrollController;

  @override
  State<SharedTasksView> createState() => _SharedTasksViewState();
}

class _SharedTasksViewState extends State<SharedTasksView> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.state.query.search ?? '');
  }

  @override
  void didUpdateWidget(covariant SharedTasksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.state.query.search ?? '';
    if (_search.text != next) {
      _search.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 840;
        return Column(
          children: [
            if (widget.state.counters['overdue'] case final num overdue
                when overdue > 0)
              _ReminderBanner(overdue: overdue.toInt()),
            mobile
                ? _MobileTaskFilter(
                    value: widget.state.query.state,
                    onChanged: _setStateFilter,
                    onCreate: widget.embedded && widget.canCreate
                        ? widget.onCreate
                        : null,
                  )
                : _DesktopTaskFilter(
                    value: widget.state.query.state,
                    counters: widget.state.counters,
                    onChanged: _setStateFilter,
                    onCreate: widget.embedded && widget.canCreate
                        ? widget.onCreate
                        : null,
                  ),
            if (widget.showViewToolbar)
              _TaskViewToolbar(
                search: _search,
                query: widget.state.query,
                onSearchChanged: (value) => widget.onSearchDraftChanged(
                  widget.state.query.copyWith(search: value),
                ),
                onSearch: () => widget.onQueryChanged(
                  widget.state.query.copyWith(search: _search.text, day: null),
                ),
                onPriorityChanged: (value) => widget.onQueryChanged(
                  widget.state.query.copyWith(priority: value, day: null),
                ),
                onScopeChanged: (value) => widget.onQueryChanged(
                  widget.state.query.copyWith(scope: value, day: null),
                ),
                onDayChanged: (value) => widget.onQueryChanged(
                  widget.state.query.copyWith(day: value, calendarMode: false),
                ),
                onCalendarChanged: (value) => widget.onQueryChanged(
                  widget.state.query.copyWith(
                    calendarMode: value,
                    day: value ? null : widget.state.query.day,
                  ),
                ),
              ),
            Expanded(child: _body()),
          ],
        );
      },
    );
    if (widget.embedded) return content;
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Задачи'),
        actions: mobile || !widget.canCreate
            ? null
            : [
                FilledButton.icon(
                  onPressed: widget.onCreate,
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Новая задача'),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
      ),
      body: content,
      floatingActionButton: mobile && widget.canCreate
          ? FloatingActionButton.extended(
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Новая задача'),
            )
          : null,
    );
  }

  void _setStateFilter(String value) {
    final query = widget.state.query;
    if (value != query.state) {
      widget.onQueryChanged(query.copyWith(state: value));
    }
  }

  Widget _body() {
    final state = widget.state;
    if (state.loading && !state.hasLoaded) {
      return const MagicPageState.loading();
    }
    if (state.error != null && !state.hasLoaded) {
      return MagicPageState(
        kind: MagicPageStateKind.error,
        title: 'Не удалось загрузить задачи',
        actionLabel: 'Повторить',
        onAction: widget.onRetry,
      );
    }
    final contentQuery = state.contentQuery;
    late final Widget content;
    if (contentQuery.calendarMode) {
      final now = DateTime.now();
      content = _SharedTaskMonthGrid(
        month: contentQuery.calendarMonth ?? DateTime(now.year, now.month),
        counts: state.calendar,
        onMonthChanged: (month) =>
            widget.onQueryChanged(state.query.copyWith(calendarMonth: month)),
        onDaySelected: (day) => widget.onQueryChanged(
          state.query.copyWith(day: day, calendarMode: false),
        ),
      );
    } else if (state.items.isEmpty) {
      content = const MagicPageState(
        kind: MagicPageStateKind.empty,
        title: 'Нет задач',
        message: 'Создайте задачу, чтобы она появилась в этом списке.',
      );
    } else {
      content = RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView.separated(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (context, index) {
            final task = state.items[index];
            final id = task['id']?.toString() ?? '';
            return _SharedTaskCard(
              task: task,
              closing: state.closing.contains(id),
              closeError: state.closeErrors[id],
              onClose: () => widget.onClose(task),
              onEdit: () => widget.onEdit(task),
              onOpen: () => widget.onOpen(task),
              canEdit: widget.canEdit,
            );
          },
        ),
      );
    }
    if (!state.showContentNotice) return content;
    return Column(
      children: [
        _SharedTasksStaleNotice(
          queryChanged: state.contentQueryChanged,
          loading: state.contentReplacementPending,
          onRetry: widget.onRetry,
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _TaskViewToolbar extends StatelessWidget {
  const _TaskViewToolbar({
    required this.search,
    required this.query,
    required this.onSearchChanged,
    required this.onSearch,
    required this.onPriorityChanged,
    required this.onScopeChanged,
    required this.onDayChanged,
    required this.onCalendarChanged,
  });

  final TextEditingController search;
  final SharedTasksQuery query;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearch;
  final ValueChanged<String> onPriorityChanged;
  final ValueChanged<String> onScopeChanged;
  final ValueChanged<DateTime?> onDayChanged;
  final ValueChanged<bool> onCalendarChanged;

  @override
  Widget build(BuildContext context) {
    final searchWidth = (MediaQuery.sizeOf(context).width * .45)
        .clamp(180.0, 280.0)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                key: const Key('shared-task-search'),
                controller: search,
                textInputAction: TextInputAction.search,
                onChanged: onSearchChanged,
                onSubmitted: (_) => onSearch(),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Поиск',
                  suffixIcon: IconButton(
                    tooltip: 'Найти задачи',
                    onPressed: onSearch,
                    icon: const Icon(Icons.search_rounded),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            _FilterDropdown(
              filterKey: const Key('shared-task-priority-filter'),
              value: query.priority,
              entries: _priorityFilters,
              onChanged: onPriorityChanged,
            ),
            const SizedBox(width: AppSpace.sm),
            _FilterDropdown(
              filterKey: const Key('shared-task-scope-filter'),
              value: query.scope,
              entries: _scopeFilters,
              onChanged: onScopeChanged,
            ),
            const SizedBox(width: AppSpace.sm),
            ChoiceChip(
              key: const Key('shared-task-today-filter'),
              label: Text(
                query.day == null ||
                        _sameDay(query.day!, sharedTasksMoscowToday())
                    ? 'Сегодня'
                    : DateFormat('dd.MM.yyyy').format(query.day!),
              ),
              selected: query.day != null,
              onSelected: (selected) =>
                  onDayChanged(selected ? sharedTasksMoscowToday() : null),
            ),
            const SizedBox(width: AppSpace.sm),
            IconButton.filledTonal(
              key: const Key('shared-task-calendar-toggle'),
              tooltip: query.calendarMode
                  ? 'Показать список'
                  : 'Показать календарь',
              onPressed: () => onCalendarChanged(!query.calendarMode),
              icon: Icon(
                query.calendarMode
                    ? Icons.view_list_rounded
                    : Icons.calendar_month,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.filterKey,
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  final Key filterKey;
  final String value;
  final List<(String, String)> entries;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
    key: filterKey,
    value: value,
    items: [
      for (final entry in entries)
        DropdownMenuItem(value: entry.$1, child: Text(entry.$2)),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

class _SharedTaskMonthGrid extends StatelessWidget {
  const _SharedTaskMonthGrid({
    required this.month,
    required this.counts,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  final DateTime month;
  final Map<String, int> counts;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = (first.weekday - 1) + days;
    return Column(
      key: const Key('shared-task-month-grid'),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Предыдущий месяц',
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${_russianMonths[month.month - 1]} ${month.year}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              tooltip: 'Следующий месяц',
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final day in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
              Expanded(child: Center(child: Text(day))),
          ],
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.25,
            ),
            itemCount: ((cells + 6) ~/ 7) * 7,
            itemBuilder: (context, index) {
              final dayNumber = index - (first.weekday - 2);
              if (dayNumber < 1 || dayNumber > days) {
                return const SizedBox.shrink();
              }
              final date = DateTime(month.year, month.month, dayNumber);
              final dayKey =
                  '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              final count = counts[dayKey] ?? 0;
              return InkWell(
                key: Key('shared-task-day-$dayKey'),
                onTap: () => onDaySelected(date),
                child: Card(
                  margin: const EdgeInsets.all(2),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$dayNumber'),
                        if (count > 0)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              '$count',
                              key: Key('shared-task-count-$dayKey'),
                              style: const TextStyle(
                                color: AppColor.actionBlue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
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

class _ReminderBanner extends StatelessWidget {
  const _ReminderBanner({required this.overdue});
  final int overdue;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('shared-task-reminder-panel'),
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    padding: const EdgeInsets.all(AppSpace.md),
    decoration: BoxDecoration(
      color: AppColor.warning.withValues(alpha: .12),
      border: Border.all(color: AppColor.warning.withValues(alpha: .45)),
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.notifications_active_outlined,
          color: AppColor.warning,
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text('Просроченных задач: $overdue')),
      ],
    ),
  );
}

class _SharedTasksStaleNotice extends StatelessWidget {
  const _SharedTasksStaleNotice({
    required this.queryChanged,
    required this.loading,
    required this.onRetry,
  });
  final bool queryChanged;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('shared-tasks-stale-notice'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem_rounded, color: colors.onErrorContainer),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              queryChanged
                  ? loading
                        ? 'Загружаем выбранный фильтр. Пока показаны задачи предыдущего запроса.'
                        : 'Не удалось загрузить выбранный фильтр. Показаны задачи предыдущего запроса.'
                  : 'Не удалось обновить задачи. Показаны ранее загруженные данные.',
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: loading ? null : onRetry,
            child: Text(loading ? 'Загрузка…' : 'Повторить'),
          ),
        ],
      ),
    );
  }
}

const _stateFilters = [
  ('open', 'Открытые'),
  ('overdue', 'Просроченные'),
  ('closed', 'Закрытые'),
  ('all', 'Все'),
];
const _priorityFilters = [
  ('all', 'Все приоритеты'),
  ('high', 'Высокий'),
  ('medium', 'Обычный'),
  ('low', 'Низкий'),
];
const _scopeFilters = [
  ('mine', 'Мои задачи'),
  ('branch', 'Мой филиал'),
  ('school', 'Вся школа'),
  ('all', 'Все доступные'),
];
const _russianMonths = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

class _MobileTaskFilter extends StatelessWidget {
  const _MobileTaskFilter({
    required this.value,
    required this.onChanged,
    this.onCreate,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('shared-task-mobile-filter'),
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              initialValue: value,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Задачи',
              ),
              items: [
                for (final entry in _stateFilters)
                  DropdownMenuItem(value: entry.$1, child: Text(entry.$2)),
              ],
              onChanged: (next) {
                if (next != null) onChanged(next);
              },
            ),
          ),
          IconButton(
            tooltip: 'Расширенные фильтры',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) => Material(
                key: const ValueKey('magic-sheet-mobile'),
                child: _AdvancedFilters(
                  value: value,
                  onChanged: (next) {
                    Navigator.pop(context);
                    onChanged(next);
                  },
                ),
              ),
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
          if (onCreate != null)
            IconButton.filled(
              tooltip: 'Новая задача',
              onPressed: onCreate,
              icon: const Icon(Icons.add_task_rounded),
            ),
        ],
      ),
    ),
  );
}

class _DesktopTaskFilter extends StatelessWidget {
  const _DesktopTaskFilter({
    required this.value,
    required this.counters,
    required this.onChanged,
    this.onCreate,
  });
  final String value;
  final Map<String, dynamic> counters;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('shared-task-desktop-filter'),
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        for (final entry in _stateFilters)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.$2),
              selected: value == entry.$1,
              onSelected: (_) => onChanged(entry.$1),
            ),
          ),
        const Spacer(),
        Text(
          'Открыто: ${counters['open'] ?? 0}',
          style: const TextStyle(color: AppColor.text2),
        ),
        if (onCreate != null) ...[
          const SizedBox(width: AppSpace.md),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_task_rounded),
            label: const Text('Новая задача'),
          ),
        ],
      ],
    ),
  );
}

class _AdvancedFilters extends StatelessWidget {
  const _AdvancedFilters({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      key: const Key('shared-task-advanced-filter-scroll'),
      padding: AppSpace.sheetBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Фильтры', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.md),
          for (final entry in _stateFilters)
            ListTile(
              title: Text(entry.$1 == 'all' ? 'Все задачи' : entry.$2),
              trailing: value == entry.$1
                  ? const Icon(Icons.check_rounded, color: AppColor.gold)
                  : null,
              onTap: () => onChanged(entry.$1),
            ),
        ],
      ),
    ),
  );
}

class _SharedTaskCard extends StatelessWidget {
  const _SharedTaskCard({
    required this.task,
    required this.closing,
    required this.closeError,
    required this.onClose,
    required this.onEdit,
    required this.onOpen,
    required this.canEdit,
  });
  final Map<String, dynamic> task;
  final bool closing;
  final Object? closeError;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onOpen;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final closed = task['state'] == 'closed';
    final startsAt = DateTime.tryParse(task['startAt']?.toString() ?? '');
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task['title']?.toString() ?? 'Задача',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!closed && canEdit)
                    IconButton(
                      onPressed: closing ? null : onEdit,
                      tooltip: 'Изменить',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                ],
              ),
              if (task['body']?.toString().trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(task['body'].toString()),
                ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  SharedTaskMetaChip(
                    icon: task['allDay'] == true
                        ? Icons.event_outlined
                        : Icons.schedule_outlined,
                    label: startsAt == null
                        ? 'Без даты'
                        : DateFormat(
                            'dd.MM.yyyy HH:mm',
                          ).format(startsAt.toLocal()),
                  ),
                  SharedTaskMetaChip(
                    icon: Icons.flag_outlined,
                    label: sharedTaskPriorityLabel(task['priority']),
                  ),
                  SharedTaskMetaChip(
                    icon: closed
                        ? Icons.check_circle_outline
                        : Icons.groups_outlined,
                    label: closed ? 'Закрыта' : 'Открыта',
                  ),
                  if (task['hasReminder'] == true)
                    const SharedTaskMetaChip(
                      key: Key('shared-task-reminder-badge'),
                      icon: Icons.notifications_none,
                      label: 'Напоминание',
                    ),
                ],
              ),
              if (!closed) ...[
                const SizedBox(height: AppSpace.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: Key('close-shared-task-${task['id']}'),
                    onPressed: closing ? null : onClose,
                    icon: closing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.task_alt_rounded),
                    label: Text(
                      closeError == null
                          ? 'Закрыть задачу'
                          : 'Повторить закрытие',
                    ),
                  ),
                ),
                if (closeError != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Не удалось закрыть. Задача осталась открытой.',
                      style: TextStyle(color: AppColor.danger),
                    ),
                  ),
              ],
              const SizedBox(height: AppSpace.xs),
              Text(
                'Открыть детали и историю',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColor.actionBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SharedTaskMetaChip extends StatelessWidget {
  const SharedTaskMetaChip({
    super.key,
    required this.icon,
    required this.label,
  });
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppColor.goldSoft,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColor.gold),
        const SizedBox(width: 5),
        Text(label),
      ],
    ),
  );
}

String sharedTaskPriorityLabel(Object? value) => switch (value?.toString()) {
  'high' => 'Высокий',
  'low' => 'Низкий',
  _ => 'Обычный',
};

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
