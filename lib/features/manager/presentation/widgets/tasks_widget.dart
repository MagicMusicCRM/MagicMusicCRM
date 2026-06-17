import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';

class TasksWidget extends ConsumerStatefulWidget {
  const TasksWidget({super.key});

  @override
  ConsumerState<TasksWidget> createState() => _TasksWidgetState();
}

class _TasksWidgetState extends ConsumerState<TasksWidget> {
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employees = [];
  final _searchCtrl = TextEditingController();
  final Set<String> _pendingTaskIds = {};
  Timer? _searchDebounce;
  bool _loading = true;
  bool _filtersLoading = true;
  bool _creatingTask = false;
  Object? _loadError;
  String _statusFilter = 'all';
  String _entityTypeFilter = 'all';
  String _priorityFilter = 'all';
  String _branchFilter = 'all';
  String _assigneeFilter = 'all';
  String _dueFilter = 'all';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _loadFilterData();
    _loadTasks();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFilterData() async {
    try {
      final results = await Future.wait([
        ref.read(magicCrmServiceProvider).listBranches(limit: 100),
        ref.read(magicProfileAdminServiceProvider).listProfiles(limit: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(results[0]);
        _employees = List<Map<String, dynamic>>.from(
          results[1],
        ).where((profile) => profile['user_id'] != null).toList();
        _filtersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _filtersLoading = false);
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadTasks();
    });
  }

  Future<void> _loadTasks({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final dueBounds = _dueBounds();
      final data = await ref
          .read(magicCrmServiceProvider)
          .listTasks(
            q: _searchCtrl.text,
            status: _statusFilter == 'all' ? null : _statusFilter,
            entityType: _entityTypeFilter == 'all' ? null : _entityTypeFilter,
            assignedTo: _assigneeFilter == 'all' ? null : _assigneeFilter,
            branchId: _branchFilter == 'all' ? null : _branchFilter,
            priority: _priorityFilter == 'all' ? null : _priorityFilter,
            from: dueBounds?.$1,
            to: dueBounds?.$2,
            limit: 100,
          );
      if (!mounted) return;
      setState(() {
        _tasks = data;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  (String?, String?)? _dueBounds() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrow = todayStart.add(const Duration(days: 1));
    final weekEnd = todayStart.add(const Duration(days: 8));

    return switch (_dueFilter) {
      'overdue' => (null, now.toUtc().toIso8601String()),
      'today' => (
        todayStart.toUtc().toIso8601String(),
        tomorrow.toUtc().toIso8601String(),
      ),
      'week' => (
        todayStart.toUtc().toIso8601String(),
        weekEnd.toUtc().toIso8601String(),
      ),
      _ => null,
    };
  }

  Future<void> _createTask() async {
    if (_creatingTask) return;
    final messenger = ScaffoldMessenger.of(context);
    final crm = ref.read(magicCrmServiceProvider);
    final profiles = ref.read(magicProfileAdminServiceProvider);

    // Prefetch select options with a visible pending state so the FAB never
    // looks dead while the requests are in flight, and surface failures.
    setState(() => _creatingTask = true);
    List<List<Map<String, dynamic>>> results;
    try {
      results = await Future.wait([
        profiles.listProfiles(limit: 100),
        crm.listStudents(limit: 100),
        crm.listLeads(limit: 100),
        crm.listGroups(limit: 100),
        crm.listTeachers(limit: 100),
      ]);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Не удалось подготовить форму задачи: $e'),
            backgroundColor: AppTheme.danger,
            action: SnackBarAction(
              label: 'Повторить',
              textColor: Colors.white,
              onPressed: _createTask,
            ),
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _creatingTask = false);
    }

    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _TaskDialog(
        employees: results[0],
        students: results[1],
        leads: results[2],
        groups: results[3],
        teachers: results[4],
      ),
    );

    if (result == null) return;

    try {
      await crm.createTask(
        entityType: result['entity_type'].toString(),
        entityId: result['entity_id'].toString(),
        title: result['title'].toString(),
        description: result['description']?.toString(),
        assignedTo: result['assigned_to']?.toString(),
        dueAt: result['due_at']?.toString(),
        status: 'open',
      );
      await _loadTasks();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Задача создана')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Не удалось создать задачу: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    if (_pendingTaskIds.contains(id)) return;
    final index = _tasks.indexWhere((task) => task['id']?.toString() == id);
    if (index < 0) return;
    final previous = Map<String, dynamic>.from(_tasks[index]);
    setState(() {
      _tasks[index] = {..._tasks[index], 'status': status};
      _pendingTaskIds.add(id);
    });
    try {
      await ref.read(magicCrmServiceProvider).updateTaskStatus(id, status);
      await _loadTasks(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final rollbackIndex = _tasks.indexWhere(
          (task) => task['id']?.toString() == id,
        );
        if (rollbackIndex >= 0) _tasks[rollbackIndex] = previous;
        _pendingTaskIds.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось обновить задачу: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingTaskIds.remove(id));
      }
    }
  }

  Future<void> _reassignTask(Map<String, dynamic> task) async {
    if (_employees.isEmpty) {
      await _loadFilterData();
    }
    if (!mounted) return;
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступных сотрудников')),
      );
      return;
    }

    final selectedUserId = await showDialog<String>(
      context: context,
      builder: (ctx) => _TaskAssigneeDialog(
        employees: _employees,
        initialUserId: task['assigned_to']?.toString(),
      ),
    );
    if (selectedUserId == null || selectedUserId.trim().isEmpty) return;
    if (selectedUserId == task['assigned_to']?.toString()) return;
    await _updateAssignee(task, selectedUserId);
  }

  Future<void> _updateAssignee(
    Map<String, dynamic> task,
    String assignedTo,
  ) async {
    final id = task['id']?.toString();
    if (id == null || id.isEmpty || _pendingTaskIds.contains(id)) return;
    final index = _tasks.indexWhere((item) => item['id']?.toString() == id);
    if (index < 0) return;
    final previous = Map<String, dynamic>.from(_tasks[index]);
    final assignedName = _employeeNameByUserId(assignedTo);
    setState(() {
      _tasks[index] = {
        ..._tasks[index],
        'assigned_to': assignedTo,
        'assigned_name': assignedName,
      };
      _pendingTaskIds.add(id);
    });
    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateTask(id, assignedTo: assignedTo);
      await _loadTasks(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final rollbackIndex = _tasks.indexWhere(
          (item) => item['id']?.toString() == id,
        );
        if (rollbackIndex >= 0) _tasks[rollbackIndex] = previous;
        _pendingTaskIds.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось назначить ответственного: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingTaskIds.remove(id));
      }
    }
  }

  String _employeeNameByUserId(String userId) {
    final profile = _employees.where(
      (item) => item['user_id']?.toString() == userId,
    );
    if (profile.isEmpty) return 'Ответственный';
    return _taskFilterProfileName(profile.first);
  }

  Future<void> _showTaskTimeline(Map<String, dynamic> task) async {
    final entityType = task['entity_type']?.toString();
    final entityId = task['entity_id']?.toString();
    if (entityType == null ||
        entityType.trim().isEmpty ||
        entityId == null ||
        entityId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У задачи нет связанного объекта.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _TaskTimelineSheet(task: task),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creatingTask ? null : _createTask,
        icon: _creatingTask
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add),
        label: Text(_creatingTask ? 'Подготовка…' : 'Новая задача'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _TaskFilters(
              searchCtrl: _searchCtrl,
              status: _statusFilter,
              entityType: _entityTypeFilter,
              priority: _priorityFilter,
              branchId: _branchFilter,
              assigneeId: _assigneeFilter,
              due: _dueFilter,
              branches: _branches,
              employees: _employees,
              loading: _filtersLoading,
              onStatusChanged: _setStatusFilter,
              onEntityTypeChanged: (value) =>
                  _setDropdownFilter(() => _entityTypeFilter = value),
              onPriorityChanged: (value) =>
                  _setDropdownFilter(() => _priorityFilter = value),
              onBranchChanged: (value) =>
                  _setDropdownFilter(() => _branchFilter = value),
              onAssigneeChanged: (value) =>
                  _setDropdownFilter(() => _assigneeFilter = value),
              onDueChanged: (value) =>
                  _setDropdownFilter(() => _dueFilter = value),
              onClear: _clearFilters,
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: ListSkeleton(count: 6),
                  )
                : _loadError != null
                ? _TasksError(error: _loadError, onRetry: _loadTasks)
                : _tasks.isEmpty
                ? Center(
                    child: Text(
                      'Нет задач',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: AppTheme.primaryPurple,
                    onRefresh: _loadTasks,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _tasks.length,
                      itemBuilder: (ctx, i) => _TaskCard(
                        task: _tasks[i],
                        isPending: _pendingTaskIds.contains(
                          _tasks[i]['id']?.toString(),
                        ),
                        onStatusChange: _updateStatus,
                        onTimelineTap: _showTaskTimeline,
                        onReassignTap: _reassignTask,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _setStatusFilter(String value) {
    if (_statusFilter == value) return;
    setState(() => _statusFilter = value);
    _loadTasks();
  }

  void _setDropdownFilter(void Function() update) {
    setState(update);
    _loadTasks();
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    setState(() {
      _searchCtrl.clear();
      _searchDebounce?.cancel();
      _statusFilter = 'all';
      _entityTypeFilter = 'all';
      _priorityFilter = 'all';
      _branchFilter = 'all';
      _assigneeFilter = 'all';
      _dueFilter = 'all';
    });
    _loadTasks();
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
              color: AppTheme.danger,
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
              ? AppTheme.primaryPurple
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
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

  const _TaskCard({
    required this.task,
    required this.isPending,
    required this.onStatusChange,
    required this.onTimelineTap,
    required this.onReassignTap,
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
    final id = task['id'] as String;
    final status = task['status'] as String?;
    final dueDate = task['due_date'] != null
        ? DateFormat(
            'd MMM yyyy',
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
                    onSelected: (value) {
                      if (value == 'reassign') {
                        onReassignTap(task);
                        return;
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
                            style: TextStyle(color: AppTheme.danger),
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
                  _Tag(
                    label: _statusLabel(status),
                    color: AppTheme.primaryPurple,
                  ),
                  if (dueDate != null)
                    _Tag(
                      label: 'До: $dueDate',
                      color: isOverdue
                          ? AppTheme.danger
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  if (assigneeText != null && assigneeText.trim().isNotEmpty)
                    _Tag(label: assigneeText, color: AppTheme.secondaryGold),
                  if (creatorText != null && creatorText.trim().isNotEmpty)
                    _Tag(
                      label: 'Создал: $creatorText',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  if (branchText != null && branchText.trim().isNotEmpty)
                    _Tag(label: branchText, color: AppTheme.success),
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
      ),
    );
  }

  VoidCallback? _entityTap(BuildContext context, Map<String, dynamic> task) {
    if (task['entity_type'] == 'student' && task['entity_id'] != null) {
      return () => context.push('/student/${task['entity_id']}');
    }
    return null;
  }
}

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
          backgroundColor: AppTheme.danger,
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
                    borderRadius: BorderRadius.circular(99),
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
        backgroundColor: AppTheme.primaryGold.withAlpha(30),
        child: Icon(
          _timelineIcon(item['type']?.toString()),
          size: 18,
          color: AppTheme.primaryGold,
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
                      color: AppTheme.success,
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
          borderRadius: BorderRadius.circular(20),
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
        child: DropdownButtonFormField<String>(
          initialValue: _selectedUserId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Ответственный',
            prefixIcon: Icon(Icons.person_search_rounded),
          ),
          items: employees
              .map(
                (profile) => DropdownMenuItem<String>(
                  value: profile['user_id']?.toString() ?? '',
                  child: Text(
                    _taskFilterProfileName(profile),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _selectedUserId = value),
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

  const _TaskDialog({
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
  String _entityType = 'student';
  String? _selectedEntityId;
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
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedEntityId,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(labelText: 'Объект'),
              items: entityItems
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedEntityId = value),
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
