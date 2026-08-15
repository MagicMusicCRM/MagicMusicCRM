import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_page_state.dart';

abstract class SharedTasksDataSource {
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  });

  Future<Map<String, dynamic>> listFiltered({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
    String? q,
    String? priority,
    String? scope,
    String? from,
    String? to,
  }) => list(
    state: state,
    taskId: taskId,
    linkedEntityType: linkedEntityType,
    linkedEntityId: linkedEntityId,
  );

  Future<Map<String, int>> calendar({
    required String from,
    required String to,
    String? state,
    String? q,
    String? priority,
    String? scope,
    String? linkedEntityType,
    String? linkedEntityId,
  }) async {
    final result = await listFiltered(
      state: state,
      q: q,
      priority: priority,
      scope: scope,
      from: from,
      to: to,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
    );
    final counts = <String, int>{};
    for (final task in (result['items'] as List? ?? const [])) {
      if (task is! Map<String, dynamic>) continue;
      final start = DateTime.tryParse(task['startAt']?.toString() ?? '');
      if (start == null) continue;
      final local = start.toLocal();
      final day =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return counts;
  }

  Future<List<Map<String, dynamic>>> history(String taskId);

  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  );

  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );

  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );

  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  );

  Future<List<SharedTaskAudienceOption>> audienceOptions();
}

class SharedTaskAudienceOption {
  const SharedTaskAudienceOption({
    required this.type,
    required this.id,
    required this.label,
  });

  final String type;
  final String id;
  final String label;
}

typedef SharedTaskAudiencePreviewLoader =
    Future<Map<String, dynamic>> Function(List<Map<String, dynamic>> audiences);

class _ServiceSharedTasksDataSource implements SharedTasksDataSource {
  _ServiceSharedTasksDataSource(this.ref);

  final WidgetRef ref;

  @override
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  }) {
    return ref
        .read(magicCrmServiceProvider)
        .listSharedTasks(
          state: state,
          taskId: taskId,
          linkedEntityType: linkedEntityType,
          linkedEntityId: linkedEntityId,
        );
  }

  @override
  Future<Map<String, dynamic>> listFiltered({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
    String? q,
    String? priority,
    String? scope,
    String? from,
    String? to,
  }) {
    return ref
        .read(magicCrmServiceProvider)
        .listSharedTasks(
          state: state,
          taskId: taskId,
          linkedEntityType: linkedEntityType,
          linkedEntityId: linkedEntityId,
          q: q,
          priority: priority,
          scope: scope,
          from: from,
          to: to,
        );
  }

  @override
  Future<Map<String, int>> calendar({
    required String from,
    required String to,
    String? state,
    String? q,
    String? priority,
    String? scope,
    String? linkedEntityType,
    String? linkedEntityId,
  }) {
    return ref
        .read(magicCrmServiceProvider)
        .sharedTaskCalendar(
          from: from,
          to: to,
          state: state,
          q: q,
          priority: priority,
          scope: scope,
          linkedEntityType: linkedEntityType,
          linkedEntityId: linkedEntityId,
        );
  }

  @override
  Future<List<Map<String, dynamic>>> history(String taskId) {
    return ref.read(magicCrmServiceProvider).listSharedTaskHistory(taskId);
  }

  @override
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  ) {
    return ref
        .read(magicCrmServiceProvider)
        .previewSharedTaskAudience(audiences);
  }

  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    return ref
        .read(magicCrmServiceProvider)
        .createSharedTask(data: data, identity: identity);
  }

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    return ref
        .read(magicCrmServiceProvider)
        .updateSharedTask(taskId: taskId, data: data, identity: identity);
  }

  @override
  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  ) {
    return ref
        .read(magicCrmServiceProvider)
        .closeSharedTask(
          taskId: taskId,
          expectedVersion: expectedVersion,
          identity: identity,
        );
  }

  @override
  Future<List<SharedTaskAudienceOption>> audienceOptions() async {
    const taskRoles = {'admin', 'manager', 'director'};
    final profiles = ref.read(magicProfileAdminServiceProvider);
    final result = await Future.wait([
      ...taskRoles.map((role) => profiles.listProfiles(role: role, limit: 100)),
      ref.read(magicCrmServiceProvider).listBranches(limit: 100),
    ]);
    final branches = result.removeLast();
    return [
      ...result
          .expand((rows) => rows)
          .where((row) => row['user_id'] != null)
          .map(
            (row) => SharedTaskAudienceOption(
              type: 'user',
              id: row['user_id'].toString(),
              label: _profileLabel(row),
            ),
          ),
      ...branches.map(
        (row) => SharedTaskAudienceOption(
          type: 'branch',
          id: row['id'].toString(),
          label: row['name']?.toString() ?? 'Филиал',
        ),
      ),
    ];
  }
}

String _taskSavedMessage(Map<String, dynamic> result, {required bool created}) {
  final summary = result['recipientSummary'];
  final total = summary is Map<String, dynamic>
      ? summary['totalRecipients']
      : null;
  final action = created ? 'Задача создана.' : 'Задача сохранена.';
  return total is num
      ? '$action Получателей сейчас: ${total.toInt()}.'
      : action;
}

Future<void> showCreateSharedTask(
  BuildContext context,
  WidgetRef ref, {
  EntityLink? linkedEntity,
  VoidCallback? onSaved,
}) async {
  final source = _ServiceSharedTasksDataSource(ref);
  List<SharedTaskAudienceOption> options = const [];
  try {
    options = await source.audienceOptions();
  } catch (_) {
    // The all-branches audience remains usable without directory data.
  }
  if (!context.mounted) return;
  final payload = await showMagicAdaptiveSurface<Map<String, dynamic>>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Новая задача',
    subtitle: 'Срок, получатели и напоминание',
    icon: Icons.add_task_rounded,
    builder: (context) => SharedTaskEditor(
      audienceOptions: options,
      audiencePreview: source.previewAudience,
      linkedEntity: linkedEntity,
      embedded: true,
    ),
  );
  if (payload == null || !context.mounted) return;
  final identity = MagicMutationIdentity.create('shared-task-create');

  Future<void> persist() async {
    try {
      final result = await source.create(payload, identity);
      onSaved?.call();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_taskSavedMessage(result, created: true))),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Не удалось создать задачу.'),
          action: SnackBarAction(label: 'Повторить', onPressed: persist),
        ),
      );
    }
  }

  await persist();
}

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
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _counters = const {'open': 0, 'overdue': 0};
  bool _loading = true;
  Object? _error;
  String _filter = 'open';
  String _priority = 'all';
  late String _scope;
  final TextEditingController _search = TextEditingController();
  bool _calendarMode = false;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  Map<String, int> _calendarCounts = const {};
  Timer? _realtimeDebounce;
  final Set<String> _closing = {};
  final Map<String, Object> _closeErrors = {};
  final Map<String, MagicMutationIdentity> _closeIdentities = {};
  bool _focusConsumed = false;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? _ServiceSharedTasksDataSource(ref);
    _scope = widget.defaultToMineToday ? 'mine' : 'all';
    if (widget.defaultToMineToday) _selectedDay = _moscowToday();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final focusedTask =
          widget.initialLink?.entityType == EntityLinkType.task &&
          widget.initialLink?.entityId != '__section__';
      final day = focusedTask ? null : _selectedDay;
      final dayFrom = day == null ? null : _moscowInstant(day);
      final dayTo = day == null
          ? null
          : _moscowInstant(day.add(const Duration(days: 1)));
      final result = await _dataSource.listFiltered(
        state: focusedTask || _filter == 'all' || _filter == 'overdue'
            ? null
            : _filter,
        taskId: focusedTask ? widget.initialLink?.entityId : null,
        linkedEntityType: widget.linkedEntity?.rawEntityType,
        linkedEntityId: widget.linkedEntity?.entityId,
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        priority: _priority == 'all' ? null : _priority,
        scope: _scope,
        from: dayFrom,
        to: dayTo,
      );
      if (_calendarMode) {
        final nextMonth = DateTime(
          _calendarMonth.year,
          _calendarMonth.month + 1,
        );
        _calendarCounts = await _dataSource.calendar(
          from: _moscowInstant(_calendarMonth),
          to: _moscowInstant(nextMonth),
          state: _filter == 'all' || _filter == 'overdue' ? null : _filter,
          q: _search.text.trim().isEmpty ? null : _search.text.trim(),
          priority: _priority == 'all' ? null : _priority,
          scope: _scope,
          linkedEntityType: widget.linkedEntity?.rawEntityType,
          linkedEntityId: widget.linkedEntity?.entityId,
        );
      }
      final rawItems = result['items'];
      var items = rawItems is List
          ? rawItems.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      if (_filter == 'overdue') {
        items = items.where(_isOverdueSharedTask).toList();
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _counters = widget.linkedEntity != null
            ? {
                'open': items.where((task) => task['state'] == 'open').length,
                'overdue': items.where(_isOverdueSharedTask).length,
              }
            : result['counters'] is Map<String, dynamic>
            ? result['counters'] as Map<String, dynamic>
            : const {'open': 0, 'overdue': 0};
        _loading = false;
      });
      if (focusedTask && items.isNotEmpty) {
        final title = items.first['title']?.toString().trim() ?? '';
        if (title.isNotEmpty) {
          WorkspaceNavigationScope.maybeOf(
            context,
          )?.controller.updateEntityPresentation(
            widget.initialLink!,
            EntityPresentationReference(primary: title),
          );
        }
      }
      if (!_focusConsumed && focusedTask) {
        _focusConsumed = true;
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _close(Map<String, dynamic> task) async {
    final id = task['id']?.toString();
    final version = task['version'];
    if (id == null || version is! int || _closing.contains(id)) return;
    final identity = _closeIdentities.putIfAbsent(
      id,
      () => MagicMutationIdentity.create('shared-task-close'),
    );
    setState(() {
      _closing.add(id);
      _closeErrors.remove(id);
    });
    try {
      await _dataSource.close(id, version, identity);
      _closeIdentities.remove(id);
      await _load(showLoading: false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Задача закрыта.')));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _closeErrors[id] = error);
    } finally {
      if (mounted) setState(() => _closing.remove(id));
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? task]) async {
    if (task == null && widget.dataSource == null) {
      await showCreateSharedTask(
        context,
        ref,
        linkedEntity: widget.linkedEntity,
        onSaved: () => _load(showLoading: false),
      );
      return;
    }
    List<SharedTaskAudienceOption> options = const [];
    try {
      options = await _dataSource.audienceOptions();
    } catch (_) {
      // allBranches remains available even if directory loading failed.
    }
    if (!mounted) return;
    final payload = await showMagicAdaptiveSurface<Map<String, dynamic>>(
      context,
      kind: AppSurfaceKind.selection,
      title: task == null ? 'Новая задача' : 'Изменить задачу',
      subtitle: 'Срок, получатели и напоминание',
      icon: task == null ? Icons.add_task_rounded : Icons.edit_note_rounded,
      builder: (context) => SharedTaskEditor(
        task: task,
        audienceOptions: options,
        audiencePreview: _dataSource.previewAudience,
        linkedEntity: widget.linkedEntity,
        embedded: true,
      ),
    );
    if (payload == null || !mounted) return;
    final identity = MagicMutationIdentity.create(
      task == null ? 'shared-task-create' : 'shared-task-update',
    );
    try {
      final result = task == null
          ? await _dataSource.create(payload, identity)
          : await _dataSource.update(task['id'].toString(), payload, identity);
      await _load(showLoading: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_taskSavedMessage(result, created: task == null)),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Не удалось сохранить задачу. Повторите.'),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => _openEditor(task),
          ),
        ),
      );
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
    if (widget.dataSource == null) {
      ref.listen(crmRealtimeProvider, (previous, next) {
        final event = next.value;
        if (event?.entity != 'task') return;
        _realtimeDebounce?.cancel();
        _realtimeDebounce = Timer(
          const Duration(milliseconds: 200),
          () => mounted ? _load(showLoading: false) : null,
        );
      });
    }
    final canWrite = widget.canWrite ?? false;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 840;
        return Column(
          children: [
            if (_counters['overdue'] case final num overdue when overdue > 0)
              _ReminderBanner(overdue: overdue.toInt()),
            mobile
                ? _MobileTaskFilter(
                    value: _filter,
                    onChanged: _setFilter,
                    onCreate: widget.embedded && canWrite
                        ? () => _openEditor()
                        : null,
                  )
                : _DesktopTaskFilter(
                    value: _filter,
                    counters: _counters,
                    onChanged: _setFilter,
                    onCreate: widget.embedded && canWrite
                        ? () => _openEditor()
                        : null,
                  ),
            if (widget.linkedEntity == null)
              _TaskViewToolbar(
                search: _search,
                priority: _priority,
                scope: _scope,
                selectedDay: _selectedDay,
                calendarMode: _calendarMode,
                onSearch: () {
                  _selectedDay = null;
                  _load();
                },
                onPriorityChanged: (value) {
                  setState(() {
                    _priority = value;
                    _selectedDay = null;
                  });
                  _load();
                },
                onScopeChanged: (value) {
                  setState(() {
                    _scope = value;
                    _selectedDay = null;
                  });
                  _load();
                },
                onDayChanged: (value) {
                  setState(() {
                    _selectedDay = value;
                    _calendarMode = false;
                  });
                  _load();
                },
                onCalendarChanged: (value) {
                  setState(() {
                    _calendarMode = value;
                    if (value) _selectedDay = null;
                  });
                  _load();
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
    if (value == _filter) return;
    setState(() => _filter = value);
    _load();
  }

  Widget _body() {
    if (_loading) {
      return const MagicPageState.loading();
    }
    if (_error != null) {
      return MagicPageState(
        kind: MagicPageStateKind.error,
        title: 'Не удалось загрузить задачи',
        actionLabel: 'Повторить',
        onAction: _load,
      );
    }
    if (_calendarMode) {
      return _SharedTaskMonthGrid(
        month: _calendarMonth,
        counts: _calendarCounts,
        onMonthChanged: (month) {
          setState(() => _calendarMonth = month);
          _load();
        },
        onDaySelected: (day) {
          setState(() {
            _selectedDay = day;
            _calendarMode = false;
          });
          _load();
        },
      );
    }
    if (_items.isEmpty) {
      return const MagicPageState(
        kind: MagicPageStateKind.empty,
        title: 'Нет задач',
        message: 'Создайте задачу, чтобы она появилась в этом списке.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
        itemBuilder: (context, index) {
          final task = _items[index];
          final id = task['id']?.toString() ?? '';
          return _SharedTaskCard(
            task: task,
            closing: _closing.contains(id),
            closeError: _closeErrors[id],
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
}

String _moscowInstant(DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).subtract(const Duration(hours: 3)).toIso8601String();

DateTime _moscowToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 3));
  return DateTime(now.year, now.month, now.day);
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

bool _isOverdueSharedTask(Map<String, dynamic> task) {
  final start = DateTime.tryParse(task['startAt']?.toString() ?? '');
  if (task['state'] != 'open' || start == null) return false;
  if (task['allDay'] != true) return start.isBefore(DateTime.now());
  final moscowStart = start.toUtc().add(const Duration(hours: 3));
  return DateTime(
    moscowStart.year,
    moscowStart.month,
    moscowStart.day,
  ).isBefore(_moscowToday());
}

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
                selectedDay == null || _sameDay(selectedDay!, _moscowToday())
                    ? 'Сегодня'
                    : DateFormat('dd.MM.yyyy').format(selectedDay!),
              ),
              selected: selectedDay != null,
              onSelected: (selected) =>
                  onDayChanged(selected ? _moscowToday() : null),
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

class SharedTaskEditor extends StatefulWidget {
  const SharedTaskEditor({
    super.key,
    required this.audienceOptions,
    this.task,
    this.linkedEntity,
    this.audiencePreview,
    this.embedded = false,
  });

  final List<SharedTaskAudienceOption> audienceOptions;
  final Map<String, dynamic>? task;
  final EntityLink? linkedEntity;
  final SharedTaskAudiencePreviewLoader? audiencePreview;
  final bool embedded;

  @override
  State<SharedTaskEditor> createState() => _SharedTaskEditorState();
}

class _SharedTaskEditorState extends State<SharedTaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _allDay;
  late DateTime _start;
  late String _priority;
  DateTime? _end;
  String _audienceType = 'allBranches';
  String? _targetId;
  final List<Map<String, dynamic>> _audiences = [];
  List<Map<String, dynamic>> _existingReminders = const [];
  bool _reminder = false;
  DateTime? _reminderAt;
  bool _reminderCustomized = false;
  Map<String, dynamic>? _preview;
  Object? _previewError;
  bool _previewLoading = false;
  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?['title']?.toString() ?? '');
    _body = TextEditingController(text: task?['body']?.toString() ?? '');
    _allDay = task?['allDay'] != false;
    final parsedStart = DateTime.tryParse(
      task?['startAt']?.toString() ?? '',
    )?.toLocal();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _start = parsedStart == null
        ? DateTime(tomorrow.year, tomorrow.month, tomorrow.day)
        : (_allDay ? _dateOnly(parsedStart) : parsedStart);
    _priority = task?['priority']?.toString() ?? 'medium';
    _end = DateTime.tryParse(task?['endAt']?.toString() ?? '')?.toLocal();
    final existing = task?['audiences'];
    if (existing is List) {
      _audiences.addAll(existing.whereType<Map<String, dynamic>>());
    }
    if (_audiences.isEmpty) {
      _audiences.add({'type': 'allBranches'});
    }
    _reminder = task?['hasReminder'] == true;
    final existingReminders = task?['reminders'];
    if (existingReminders is List) {
      _existingReminders = existingReminders
          .whereType<Map<String, dynamic>>()
          .map((item) => {'dueAt': item['dueAt'], 'channel': item['channel']})
          .toList();
    }
    for (final reminder in _existingReminders) {
      if (reminder['channel'] != 'in_app') continue;
      _reminderAt = DateTime.tryParse(
        reminder['dueAt']?.toString() ?? '',
      )?.toLocal();
      if (_reminderAt != null) {
        _reminderCustomized = true;
        break;
      }
    }
    if (_reminder && _reminderAt == null) {
      _reminderAt = _defaultReminderAt();
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshAudiencePreview(),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.audienceOptions
        .where((option) => option.type == _audienceType)
        .toList();
    final content = SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('shared-task-title'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Название'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: const Key('shared-task-priority'),
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Приоритет'),
              items: const [
                DropdownMenuItem(value: 'high', child: Text('Высокий')),
                DropdownMenuItem(value: 'medium', child: Text('Обычный')),
                DropdownMenuItem(value: 'low', child: Text('Низкий')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _priority = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Описание'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('На весь день'),
              value: _allDay,
              onChanged: _setAllDay,
            ),
            _DateTimeButton(
              label: 'Начало',
              value: _start,
              dateOnly: _allDay,
              onChanged: _setStart,
            ),
            if (!_allDay)
              _DateTimeButton(
                label: 'Окончание',
                value: _end ?? _start.add(const Duration(hours: 1)),
                onChanged: (value) => setState(() => _end = value),
              ),
            if (!_hasValidInterval) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                'Окончание должно быть позже начала.',
                key: const Key('shared-task-interval-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Divider(height: 28),
            Text('Кому', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'user', label: Text('Сотрудники')),
                ButtonSegment(value: 'branch', label: Text('Один филиал')),
                ButtonSegment(value: 'allBranches', label: Text('Вся школа')),
              ],
              selected: {_audienceType},
              onSelectionChanged: (selection) => setState(() {
                _audienceType = selection.first;
                _targetId = null;
              }),
            ),
            if (_audienceType != 'allBranches') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                key: const Key('shared-task-audience-target'),
                initialValue: _targetId,
                decoration: InputDecoration(
                  labelText: _audienceType == 'user' ? 'Сотрудник' : 'Филиал',
                ),
                items: options
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _targetId = value),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _canAddAudience ? _addAudience : null,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Добавить получателя'),
            ),
            Wrap(
              spacing: 6,
              children: _audiences
                  .map(
                    (audience) => InputChip(
                      label: Text(_audienceLabel(audience)),
                      onDeleted: _audiences.length == 1
                          ? null
                          : () => _removeAudience(audience),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpace.sm),
            _buildAudiencePreview(context),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Напомнить в приложении'),
              subtitle: const Text('Можно выбрать точные дату и время'),
              value: _reminder,
              onChanged: _setReminder,
            ),
            if (_reminder)
              _DateTimeButton(
                key: const Key('shared-task-reminder-at'),
                label: 'Напомнить',
                value: _reminderAt ?? _defaultReminderAt(),
                onChanged: (value) => setState(() {
                  _reminderAt = value;
                  _reminderCustomized = true;
                }),
              ),
          ],
        ),
      ),
    );
    final actions = <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _canSubmit ? _submit : null,
        child: Text(widget.task == null ? 'Создать' : 'Сохранить'),
      ),
    ];
    if (widget.embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.sm),
                Expanded(child: actions[i]),
              ],
            ],
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(widget.task == null ? 'Новая задача' : 'Изменить задачу'),
      content: content,
      actions: actions,
    );
  }

  bool get _canAddAudience =>
      _audienceType == 'allBranches' || _targetId != null;

  bool get _canSubmit =>
      _title.text.trim().isNotEmpty &&
      _hasValidInterval &&
      (widget.audiencePreview == null ||
          (!_previewLoading && _previewError == null && _preview != null));

  bool get _hasValidInterval => _allDay || (_end?.isAfter(_start) ?? false);

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _defaultReminderAt() => _allDay
      ? DateTime(_start.year, _start.month, _start.day, 9)
      : _start.subtract(const Duration(hours: 1));

  void _setAllDay(bool value) {
    setState(() {
      if (_allDay == value) return;
      _allDay = value;
      if (value) {
        _start = _dateOnly(_start);
        _end = null;
      } else {
        _start = DateTime(_start.year, _start.month, _start.day, 9);
        _end = _start.add(const Duration(hours: 1));
      }
      if (_reminder && !_reminderCustomized) {
        _reminderAt = _defaultReminderAt();
      }
    });
  }

  void _setStart(DateTime value) {
    setState(() {
      _start = _allDay ? _dateOnly(value) : value;
      if (_reminder && !_reminderCustomized) {
        _reminderAt = _defaultReminderAt();
      }
    });
  }

  void _setReminder(bool value) {
    setState(() {
      _reminder = value;
      if (value) {
        _reminderAt ??= _defaultReminderAt();
      } else {
        _existingReminders = const [];
        _reminderAt = null;
        _reminderCustomized = false;
      }
    });
  }

  void _addAudience() {
    final audience = {
      'type': _audienceType,
      if (_audienceType != 'allBranches') 'targetId': _targetId,
    };
    final key = '${audience['type']}:${audience['targetId'] ?? ''}';
    if (_audiences.any(
      (item) => '${item['type']}:${item['targetId'] ?? ''}' == key,
    )) {
      return;
    }
    setState(() {
      if (_audienceType == 'allBranches') {
        _audiences
          ..clear()
          ..add(audience);
      } else {
        _audiences.removeWhere((item) => item['type'] == 'allBranches');
        _audiences.add(audience);
      }
    });
    _refreshAudiencePreview();
  }

  void _removeAudience(Map<String, dynamic> audience) {
    setState(() => _audiences.remove(audience));
    _refreshAudiencePreview();
  }

  String _audienceLabel(Map<String, dynamic> audience) {
    if (audience['type'] == 'allBranches') return 'Вся школа';
    final id = audience['targetId']?.toString();
    for (final option in widget.audienceOptions) {
      if (option.id == id) return option.label;
    }
    return audience['type'] == 'user' ? 'Сотрудник' : 'Филиал';
  }

  void _refreshAudiencePreview() {
    final loader = widget.audiencePreview;
    if (loader == null || !mounted) return;
    final generation = ++_previewGeneration;
    setState(() {
      _previewLoading = true;
      _previewError = null;
      _preview = null;
    });
    loader(_audiences.map(Map<String, dynamic>.from).toList()).then(
      (preview) {
        if (!mounted || generation != _previewGeneration) return;
        setState(() {
          _preview = preview;
          _previewLoading = false;
        });
      },
      onError: (Object error) {
        if (!mounted || generation != _previewGeneration) return;
        setState(() {
          _previewError = error;
          _previewLoading = false;
        });
      },
    );
  }

  Widget _buildAudiencePreview(BuildContext context) {
    if (widget.audiencePreview == null) {
      return const Text(
        'Сотрудники назначаются лично. Филиал и вся школа используют '
        'актуальный состав на момент показа задачи.',
      );
    }
    return Container(
      key: const Key('shared-task-audience-preview'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Кто получит задачу',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpace.xs),
          if (_previewLoading)
            const LinearProgressIndicator(
              key: Key('shared-task-audience-preview-loading'),
            )
          else if (_previewError != null) ...[
            const Text(
              'Не удалось проверить получателей. Задача не будет отправлена '
              'без точного расчёта.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _refreshAudiencePreview,
                child: const Text('Повторить расчёт'),
              ),
            ),
          ] else if (_preview case final preview?) ...[
            Text(
              'Сейчас получат: ${preview['totalRecipients'] ?? 0}',
              key: const Key('shared-task-recipient-total'),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpace.xs),
            for (final selector in _previewSelectors(preview))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      selector['mode'] == 'fixed'
                          ? Icons.person_outline_rounded
                          : Icons.account_tree_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        '${selector['label'] ?? 'Получатель'}: '
                        '${selector['mode'] == 'fixed' ? 'лично' : 'динамический состав'}; '
                        'сейчас ${selector['currentRecipientCount'] ?? 0}',
                      ),
                    ),
                  ],
                ),
              ),
            if (preview['hasDynamicMembership'] == true) ...[
              const SizedBox(height: AppSpace.sm),
              const Text(
                'Для филиала и всей школы состав обновляется автоматически: '
                'задачу увидят сотрудники, которые входят туда на момент работы.',
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _previewSelectors(Map<String, dynamic> preview) {
    final selectors = preview['selectors'];
    return selectors is List
        ? selectors.whereType<Map<String, dynamic>>().toList()
        : const [];
  }

  void _submit() {
    final end = _allDay ? null : (_end ?? _start.add(const Duration(hours: 1)));
    final existingLink = widget.task?['linkedEntity'];
    final linkedEntity = widget.linkedEntity == null
        ? existingLink
        : {
            'type': widget.linkedEntity!.rawEntityType,
            'id': widget.linkedEntity!.entityId,
          };
    Navigator.pop(context, {
      'title': _title.text.trim(),
      if (_body.text.trim().isNotEmpty) 'body': _body.text.trim(),
      'allDay': _allDay,
      'priority': _priority,
      'startAt': _start.toUtc().toIso8601String(),
      if (end != null) 'endAt': end.toUtc().toIso8601String(),
      'audiences': _audiences,
      'linkedEntity': ?linkedEntity,
      if (_reminder) 'reminders': _reminderPayload(),
      if (widget.task != null) 'expectedVersion': widget.task!['version'],
    });
  }

  List<Map<String, dynamic>> _reminderPayload() {
    final dueAt = (_reminderAt ?? _defaultReminderAt())
        .toUtc()
        .toIso8601String();
    var replacedInApp = false;
    final result = <Map<String, dynamic>>[];
    for (final reminder in _existingReminders) {
      final channel = reminder['channel']?.toString();
      if (channel == null || channel.isEmpty) continue;
      if (channel == 'in_app' && !replacedInApp) {
        result.add({'dueAt': dueAt, 'channel': channel});
        replacedInApp = true;
      } else {
        result.add({'dueAt': reminder['dueAt'], 'channel': channel});
      }
    }
    if (!replacedInApp) {
      result.add({'dueAt': dueAt, 'channel': 'in_app'});
    }
    return result;
  }
}

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.dateOnly = false,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        DateFormat(dateOnly ? 'dd.MM.yyyy' : 'dd.MM.yyyy HH:mm').format(value),
      ),
      trailing: const Icon(Icons.calendar_month_outlined),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (date == null || !context.mounted) return;
        if (dateOnly) {
          onChanged(DateTime(date.year, date.month, date.day));
          return;
        }
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (time == null) return;
        onChanged(
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        );
      },
    );
  }
}

String _profileLabel(Map<String, dynamic> profile) {
  final first = profile['first_name']?.toString().trim() ?? '';
  final last = profile['last_name']?.toString().trim() ?? '';
  final name = '$first $last'.trim();
  return name.isEmpty ? 'Сотрудник' : name;
}
