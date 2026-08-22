import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';

class SharedTasksV4Panel extends ConsumerStatefulWidget {
  const SharedTasksV4Panel({
    super.key,
    this.dataSource,
    this.embedded = false,
    this.initialLink,
    this.linkedEntity,
    this.scrollController,
    this.canWrite,
    this.defaultToMineToday = false,
  });

  final SharedTasksDataSource? dataSource;
  final bool embedded;
  final EntityLink? initialLink;
  final EntityLink? linkedEntity;
  final ScrollController? scrollController;
  final bool? canWrite;
  final bool defaultToMineToday;

  @override
  ConsumerState<SharedTasksV4Panel> createState() => _SharedTasksV4PanelState();
}

class _SharedTasksV4PanelState extends ConsumerState<SharedTasksV4Panel> {
  late SharedTasksDataSource _dataSource;
  late SharedTasksController _controller;
  StreamController<void>? _realtimeRefreshes;
  ProviderSubscription<AsyncValue<CrmChangedEvent>>? _realtimeSubscription;
  final TextEditingController _search = TextEditingController();
  bool _focusConsumed = false;

  @override
  void initState() {
    super.initState();
    _dataSource =
        widget.dataSource ?? MagicCrmSharedTasksDataSource.fromWidgetRef(ref);
    _realtimeRefreshes = widget.dataSource == null
        ? StreamController<void>.broadcast()
        : null;
    final now = DateTime.now();
    _controller = SharedTasksController(
      dataSource: _dataSource,
      refreshes: _realtimeRefreshes?.stream,
      initialQuery: SharedTasksQuery(
        taskId: _focusedTaskId,
        linkedEntityType: widget.linkedEntity?.rawEntityType,
        linkedEntityId: widget.linkedEntity?.entityId,
        scope: widget.defaultToMineToday ? 'mine' : 'all',
        day: widget.defaultToMineToday ? sharedTasksMoscowToday() : null,
        calendarMonth: DateTime(now.year, now.month),
      ),
    )..addListener(_onControllerChanged);
    if (_realtimeRefreshes case final refreshes?) {
      _realtimeSubscription = ref.listenManual(crmRealtimeProvider, (
        previous,
        next,
      ) {
        if (next.value?.entity == 'task' && !refreshes.isClosed) {
          refreshes.add(null);
        }
      });
    }
    Future<void>.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant SharedTasksV4Panel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFocusedTaskId = _focusedTaskIdFor(oldWidget.initialLink);
    final nextFocusedTaskId = _focusedTaskId;
    final focusChanged = oldFocusedTaskId != nextFocusedTaskId;
    final linkedChanged = !_sameEntityScope(
      oldWidget.linkedEntity,
      widget.linkedEntity,
    );
    final defaultsChanged =
        oldWidget.defaultToMineToday != widget.defaultToMineToday;
    if (!focusChanged && !linkedChanged && !defaultsChanged) return;
    if (focusChanged) _focusConsumed = false;

    final query = _controller.state.query;
    _controller.setQuery(
      query.copyWith(
        taskId: nextFocusedTaskId,
        linkedEntityType: widget.linkedEntity?.rawEntityType,
        linkedEntityId: widget.linkedEntity?.entityId,
        scope: defaultsChanged
            ? (widget.defaultToMineToday ? 'mine' : 'all')
            : query.scope,
        day: defaultsChanged
            ? (widget.defaultToMineToday ? sharedTasksMoscowToday() : null)
            : query.day,
      ),
    );
  }

  @override
  void dispose() {
    _realtimeSubscription?.close();
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    final refreshes = _realtimeRefreshes;
    if (refreshes != null) unawaited(refreshes.close());
    _search.dispose();
    super.dispose();
  }

  String? get _focusedTaskId => _focusedTaskIdFor(widget.initialLink);

  Future<void> _load({bool showLoading = true}) =>
      _controller.refresh(showLoading: showLoading);

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final state = _controller.state;
    if (!state.hasLoaded || state.loading || state.error != null) return;
    final focusedTask = _focusedTaskId != null;
    final successfulQuery = state.successfulQuery;
    if (focusedTask &&
        (successfulQuery?.taskId != _focusedTaskId ||
            successfulQuery?.linkedEntityType !=
                widget.linkedEntity?.rawEntityType ||
            successfulQuery?.linkedEntityId != widget.linkedEntity?.entityId)) {
      return;
    }
    if (focusedTask && state.items.isNotEmpty) {
      final title = state.items.first['title']?.toString().trim() ?? '';
      if (title.isNotEmpty) {
        WorkspaceNavigationScope.maybeOf(
          context,
        )?.controller.updateEntityPresentation(
          widget.initialLink!,
          EntityPresentationReference(primary: title),
        );
      }
    }
    if (_focusConsumed || !focusedTask) return;
    _focusConsumed = true;
    final items = state.items;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Связанная запись недоступна.')),
        );
        return;
      }
      unawaited(_openDetails(items.first));
    });
  }

  Future<void> _close(Map<String, dynamic> task) async {
    final result = await _controller.close(task);
    if (result.succeeded && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Задача закрыта.')));
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? task]) async {
    final saved = await showSharedTaskEditor(
      context,
      dataSource: _dataSource,
      task: task,
      linkedEntity: widget.linkedEntity,
    );
    if (saved == true && mounted) {
      await _load(showLoading: false);
    }
  }

  Future<void> _openDetails(Map<String, dynamic> task) async {
    await showMagicAdaptiveSurface<void>(
      context,
      kind: AppSurfaceKind.quickView,
      title: task['title']?.toString() ?? 'Задача',
      icon: Icons.task_alt_rounded,
      builder: (context) => _SharedTaskDetails(
        task: task,
        history: _dataSource.history(task['id'].toString()),
        onOpenEntity: () => _openLinkedEntity(task),
      ),
    );
  }

  Future<void> _openLinkedEntity(Map<String, dynamic> task) async {
    final raw = task['linkedEntity'];
    if (raw is! Map) return;
    final scoped = widget.linkedEntity;
    final link =
        scoped?.rawEntityType == raw['type']?.toString() &&
            scoped?.entityId == raw['id']?.toString()
        ? scoped!
        : EntityLink.fromJson({
            'entityType': raw['type'],
            'entityId': raw['id'],
          });
    if (!link.isSupported) return;
    await openEntityLink(
      context,
      ref,
      link,
      sourceViewState: ContextViewState(
        filters: {'taskId': task['id']?.toString()},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final query = state.query;
    final canWrite = widget.canWrite ?? false;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 840;
        return Column(
          children: [
            if (state.counters['overdue'] case final num overdue
                when overdue > 0)
              _ReminderBanner(overdue: overdue.toInt()),
            mobile
                ? _MobileTaskFilter(
                    value: query.state,
                    onChanged: _setFilter,
                    onCreate: widget.embedded && canWrite
                        ? () => _openEditor()
                        : null,
                  )
                : _DesktopTaskFilter(
                    value: query.state,
                    counters: state.counters,
                    onChanged: _setFilter,
                    onCreate: widget.embedded && canWrite
                        ? () => _openEditor()
                        : null,
                  ),
            if (widget.linkedEntity == null)
              _TaskViewToolbar(
                search: _search,
                priority: query.priority,
                scope: query.scope,
                selectedDay: query.day,
                calendarMode: query.calendarMode,
                onSearchChanged: (value) {
                  _controller.updateQuery(query.copyWith(search: value));
                },
                onSearch: () {
                  _controller.setQuery(
                    query.copyWith(search: _search.text, day: null),
                  );
                },
                onPriorityChanged: (value) {
                  _controller.setQuery(
                    query.copyWith(priority: value, day: null),
                  );
                },
                onScopeChanged: (value) {
                  _controller.setQuery(query.copyWith(scope: value, day: null));
                },
                onDayChanged: (value) {
                  _controller.setQuery(
                    query.copyWith(day: value, calendarMode: false),
                  );
                },
                onCalendarChanged: (value) {
                  _controller.setQuery(
                    query.copyWith(
                      calendarMode: value,
                      day: value ? null : query.day,
                    ),
                  );
                },
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
        actions: mobile || !canWrite
            ? null
            : [
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Новая задача'),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
      ),
      body: content,
      floatingActionButton: mobile && canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Новая задача'),
            )
          : null,
    );
  }

  void _setFilter(String value) {
    final query = _controller.state.query;
    if (value == query.state) return;
    _controller.setQuery(query.copyWith(state: value));
  }

  Widget _body() {
    final state = _controller.state;
    final query = state.query;
    final contentQuery = state.contentQuery;
    if (state.loading && !state.hasLoaded) {
      return const MagicPageState.loading();
    }
    if (state.error != null && !state.hasLoaded) {
      return MagicPageState(
        kind: MagicPageStateKind.error,
        title: 'Не удалось загрузить задачи',
        actionLabel: 'Повторить',
        onAction: _load,
      );
    }
    late final Widget content;
    if (contentQuery.calendarMode) {
      final now = DateTime.now();
      content = _SharedTaskMonthGrid(
        month: contentQuery.calendarMonth ?? DateTime(now.year, now.month),
        counts: state.calendar,
        onMonthChanged: (month) {
          _controller.setQuery(query.copyWith(calendarMonth: month));
        },
        onDaySelected: (day) {
          _controller.setQuery(query.copyWith(day: day, calendarMode: false));
        },
      );
    } else if (state.items.isEmpty) {
      content = const MagicPageState(
        kind: MagicPageStateKind.empty,
        title: 'Нет задач',
        message: 'Создайте задачу, чтобы она появилась в этом списке.',
      );
    } else {
      content = RefreshIndicator(
        onRefresh: _load,
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
              onClose: () => _close(task),
              onEdit: () => _openEditor(task),
              onOpen: () => _openDetails(task),
              canEdit:
                  widget.canWrite ??
                  ref
                          .read(capabilitySnapshotProvider)
                          .value
                          ?.allows('workflow.task.write') ==
                      true,
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
          onRetry: () => unawaited(_controller.retry()),
        ),
        Expanded(child: content),
      ],
    );
  }
}

String? _focusedTaskIdFor(EntityLink? link) =>
    link?.entityType == EntityLinkType.task && link?.entityId != '__section__'
    ? link?.entityId
    : null;

bool _sameEntityScope(EntityLink? left, EntityLink? right) =>
    left?.rawEntityType == right?.rawEntityType &&
    left?.entityId == right?.entityId;

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _taskPriorityLabel(Object? value) => switch (value?.toString()) {
  'high' => 'Высокий',
  'low' => 'Низкий',
  _ => 'Обычный',
};

class _TaskViewToolbar extends StatelessWidget {
  const _TaskViewToolbar({
    required this.search,
    required this.priority,
    required this.scope,
    required this.selectedDay,
    required this.calendarMode,
    required this.onSearchChanged,
    required this.onSearch,
    required this.onPriorityChanged,
    required this.onScopeChanged,
    required this.onDayChanged,
    required this.onCalendarChanged,
  });

  final TextEditingController search;
  final String priority;
  final String scope;
  final DateTime? selectedDay;
  final bool calendarMode;
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
            DropdownButton<String>(
              key: const Key('shared-task-priority-filter'),
              value: priority,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Все приоритеты')),
                DropdownMenuItem(value: 'high', child: Text('Высокий')),
                DropdownMenuItem(value: 'medium', child: Text('Обычный')),
                DropdownMenuItem(value: 'low', child: Text('Низкий')),
              ],
              onChanged: (value) {
                if (value != null) onPriorityChanged(value);
              },
            ),
            const SizedBox(width: AppSpace.sm),
            DropdownButton<String>(
              key: const Key('shared-task-scope-filter'),
              value: scope,
              items: const [
                DropdownMenuItem(value: 'mine', child: Text('Мои задачи')),
                DropdownMenuItem(value: 'branch', child: Text('Мой филиал')),
                DropdownMenuItem(value: 'school', child: Text('Вся школа')),
                DropdownMenuItem(value: 'all', child: Text('Все доступные')),
              ],
              onChanged: (value) {
                if (value != null) onScopeChanged(value);
              },
            ),
            const SizedBox(width: AppSpace.sm),
            ChoiceChip(
              key: const Key('shared-task-today-filter'),
              label: Text(
                selectedDay == null ||
                        _sameDay(selectedDay!, sharedTasksMoscowToday())
                    ? 'Сегодня'
                    : DateFormat('dd.MM.yyyy').format(selectedDay!),
              ),
              selected: selectedDay != null,
              onSelected: (selected) =>
                  onDayChanged(selected ? sharedTasksMoscowToday() : null),
            ),
            const SizedBox(width: AppSpace.sm),
            IconButton.filledTonal(
              key: const Key('shared-task-calendar-toggle'),
              tooltip: calendarMode ? 'Показать список' : 'Показать календарь',
              onPressed: () => onCalendarChanged(!calendarMode),
              icon: Icon(
                calendarMode ? Icons.view_list_rounded : Icons.calendar_month,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
              final key =
                  '${date.year.toString().padLeft(4, '0')}-'
                  '${date.month.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')}';
              final count = counts[key] ?? 0;
              return InkWell(
                key: Key('shared-task-day-$key'),
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
                              key: Key('shared-task-count-$key'),
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

class _ReminderBanner extends StatelessWidget {
  const _ReminderBanner({required this.overdue});

  final int overdue;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                        ? 'Загружаем выбранный фильтр. '
                              'Пока показаны задачи предыдущего запроса.'
                        : 'Не удалось загрузить выбранный фильтр. '
                              'Показаны задачи предыдущего запроса.'
                  : 'Не удалось обновить задачи. '
                        'Показаны ранее загруженные данные.',
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
  Widget build(BuildContext context) {
    return SizedBox(
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
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Открытые')),
                  DropdownMenuItem(
                    value: 'overdue',
                    child: Text('Просроченные'),
                  ),
                  DropdownMenuItem(value: 'closed', child: Text('Закрытые')),
                  DropdownMenuItem(value: 'all', child: Text('Все')),
                ],
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
            ),
            IconButton(
              tooltip: 'Расширенные фильтры',
              onPressed: () => showMagicAdaptiveSurface<void>(
                context,
                kind: AppSurfaceKind.selection,
                title: 'Фильтры задач',
                icon: Icons.tune_rounded,
                builder: (context) => _AdvancedFilters(
                  value: value,
                  onChanged: (next) {
                    Navigator.pop(context);
                    onChanged(next);
                  },
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (final entry in const [
            ('open', 'Открытые'),
            ('overdue', 'Просроченные'),
            ('closed', 'Закрытые'),
            ('all', 'Все'),
          ])
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
}

class _AdvancedFilters extends StatelessWidget {
  const _AdvancedFilters({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('shared-task-advanced-filter-scroll'),
        padding: AppSpace.sheetBody,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Фильтры', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.md),
            for (final entry in const [
              ('open', 'Открытые'),
              ('overdue', 'Просроченные'),
              ('closed', 'Закрытые'),
              ('all', 'Все задачи'),
            ])
              ListTile(
                title: Text(entry.$2),
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
}

class _SharedTaskDetails extends StatelessWidget {
  const _SharedTaskDetails({
    required this.task,
    required this.history,
    required this.onOpenEntity,
  });

  final Map<String, dynamic> task;
  final Future<List<Map<String, dynamic>>> history;
  final VoidCallback onOpenEntity;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(
      task['startAt']?.toString() ?? '',
    )?.toLocal();
    final rawLinked = task['linkedEntity'];
    final linked = rawLinked is Map
        ? EntityLink.fromJson({
            'entityType': rawLinked['type'],
            'entityId': rawLinked['id'],
          })
        : null;
    return SingleChildScrollView(
      padding: AppSpace.sheetBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (task['body']?.toString().trim().isNotEmpty == true) ...[
            Text(task['body'].toString()),
            const SizedBox(height: AppSpace.lg),
          ],
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              _MetaChip(
                icon: task['state'] == 'closed'
                    ? Icons.check_circle_outline
                    : Icons.pending_actions_outlined,
                label: task['state'] == 'closed' ? 'Закрыта' : 'Открыта',
              ),
              _MetaChip(
                icon: Icons.schedule_outlined,
                label: start == null
                    ? 'Без даты'
                    : DateFormat('dd.MM.yyyy HH:mm').format(start),
              ),
            ],
          ),
          if (linked?.isSupported == true) ...[
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                const Text('Связанная запись: '),
                Flexible(
                  child: EntityLinkText(
                    key: const Key('shared-task-linked-entity'),
                    text: const EntityPresentationResolver()
                        .resolve(linked!)
                        .primary,
                    onPressed: onOpenEntity,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          Text('История', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpace.sm),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return const Text('Не удалось загрузить историю задачи.');
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return const Text('Изменений пока нет.');
              }
              return Column(
                children: [
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history_rounded),
                      title: Text(_taskHistoryAction(item['action'])),
                      subtitle: Text(
                        [
                          if (item['actorName']?.toString().trim().isNotEmpty ==
                              true)
                            item['actorName'].toString(),
                          if (DateTime.tryParse(
                                item['occurredAt']?.toString() ?? '',
                              )?.toLocal()
                              case final occurred?)
                            DateFormat('dd.MM.yyyy HH:mm').format(occurred),
                        ].join(' · '),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _taskHistoryAction(Object? action) => switch (action?.toString()) {
  'workflow.shared_task_created' => 'Задача создана',
  'workflow.shared_task_updated' => 'Задача изменена',
  'workflow.shared_task_closed' => 'Задача закрыта',
  final String value when value.startsWith('workflow.shared_task_legacy_') =>
    'Историческое изменение',
  _ => 'Задача обновлена',
};

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
                      onPressed: closing
                          ? null
                          : () {
                              onEdit();
                            },
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
                  _MetaChip(
                    icon: task['allDay'] == true
                        ? Icons.event_outlined
                        : Icons.schedule_outlined,
                    label: startsAt == null
                        ? 'Без даты'
                        : DateFormat(
                            'dd.MM.yyyy HH:mm',
                          ).format(startsAt.toLocal()),
                  ),
                  _MetaChip(
                    icon: Icons.flag_outlined,
                    label: _taskPriorityLabel(task['priority']),
                  ),
                  _MetaChip(
                    icon: closed
                        ? Icons.check_circle_outline
                        : Icons.groups_outlined,
                    label: closed ? 'Закрыта' : 'Открыта',
                  ),
                  if (task['hasReminder'] == true)
                    const _MetaChip(
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
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
}
