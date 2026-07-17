import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/group_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';

part 'tasks_widget_cards.dart';
part 'tasks_widget_sheets.dart';

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
  Timer? _realtimeDebounce;
  bool _loading = true;
  bool _filtersLoading = true;
  bool _creatingTask = false;
  Object? _loadError;
  String _statusFilter = 'all';
  String _entityTypeFilter = 'all';
  String _priorityFilter = 'all';
  String _branchFilter = 'all';
  String _assigneeFilter = 'all';
  // Day-by-day to-do is the default view: staff work today's list, not the
  // whole backlog. 'all'/'overdue'/'week' stay available in the Срок filter.
  String _dueFilter = 'day';
  DateTime _selectedDay = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _loadFilterData();
    _loadTasks();
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
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
      // The picked day, not necessarily today — the day view pages back and
      // forward.
      'day' => (
        _selectedDay.toUtc().toIso8601String(),
        _selectedDay.add(const Duration(days: 1)).toUtc().toIso8601String(),
      ),
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
            backgroundColor: AppColor.danger,
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
        // Server search so tasks can reference students/leads beyond the
        // 100-row pre-loaded page.
        onSearchEntities: (entityType, query) async {
          final crmService = ref.read(magicCrmServiceProvider);
          if (entityType == 'lead') {
            return crmService.listLeads(limit: 30, q: query);
          }
          final response = await crmService.searchStudents(
            q: query,
            limit: 30,
          );
          final items = response['items'];
          return items is List
              ? items.whereType<Map<String, dynamic>>().toList()
              : <Map<String, dynamic>>[];
        },
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
            backgroundColor: AppColor.danger,
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
          backgroundColor: AppColor.danger,
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
          backgroundColor: AppColor.danger,
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

  /// Opens the object a task points at. Lives here rather than in _TaskCard
  /// because groups and teachers have no route: their cards are dialogs that
  /// want a whole record, so the row has to be fetched by id first — and that
  /// needs `ref`, which a StatelessWidget card does not have.
  Future<void> _openTaskEntity(Map<String, dynamic> task) async {
    final entityType = task['entity_type']?.toString();
    final entityId = task['entity_id']?.toString();
    if (entityId == null || entityId.trim().isEmpty) return;

    try {
      switch (entityType) {
        case 'student':
          showClientCard(context, entityType: 'student', entityId: entityId);
        case 'lead':
          showClientCard(context, entityType: 'lead', entityId: entityId);
        case 'lesson':
          context.push('/lessons/$entityId');
        case 'profile':
          context.push('/admin/profiles/$entityId');
        case 'group':
          final group = await ref
              .read(magicCrmServiceProvider)
              .getGroup(entityId);
          if (!mounted) return;
          await GroupDetailDialog.show(context, group);
        case 'teacher':
          final teacher = await ref
              .read(magicCrmServiceProvider)
              .getTeacher(entityId);
          if (!mounted) return;
          await TeacherDetailDialog.show(context, teacher);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось открыть: $e')));
    }
  }

  /// Moves a task's deadline. A plain PATCH — the server logs who moved it from
  /// what to what into task_history, which is what makes the change auditable
  /// for the director rather than just silently applied.
  Future<void> _rescheduleTask(Map<String, dynamic> task) async {
    final id = task['id']?.toString();
    if (id == null || id.isEmpty || _pendingTaskIds.contains(id)) return;

    final current = task['due_at'] != null
        ? DateTime.tryParse(task['due_at'].toString())?.toLocal()
        : null;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      // Unlike task creation, a reschedule may legitimately move a deadline
      // into the past (logging when it was actually meant to be done).
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: 'Перенести срок',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 12, minute: 0)
          : TimeOfDay.fromDateTime(current),
      helpText: 'Время выполнения',
    );
    if (!mounted) return;
    final picked =
        time ??
        (current == null
            ? const TimeOfDay(hour: 12, minute: 0)
            : TimeOfDay.fromDateTime(current));
    final dueAt = DateTime(
      date.year,
      date.month,
      date.day,
      picked.hour,
      picked.minute,
    );

    setState(() => _pendingTaskIds.add(id));
    try {
      await ref
          .read(magicCrmServiceProvider)
          // toUtc(): a local ISO string without an offset gets read in the
          // server's zone and the deadline drifts.
          .updateTask(id, dueAt: dueAt.toUtc().toIso8601String());
      await _loadTasks(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Срок перенесён на ${DateFormat('dd.MM.yyyy HH:mm').format(dueAt)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось перенести срок: $e'),
          backgroundColor: AppColor.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _pendingTaskIds.remove(id));
    }
  }

  /// Supervisor view: every due-date move across tasks, newest first.
  /// Spec §2.2 — «чтобы директор и управляющий могли видеть, кто какие задачи
  /// когда переносит и тд».
  Future<void> _showRescheduleControl() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => const _TaskHistoryFeedSheet(),
    );
  }

  Future<void> _showTaskTimeline(Map<String, dynamic> task) async {
    // Deliberately not gated on the related object: the sheet's first tab is
    // the task's own change log, which exists even for an orphaned task.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _TaskTimelineSheet(task: task),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: refresh the task list when another staff member changes a task.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || event.entity != 'task' || !mounted) return;
      // Skip while loading or while an optimistic status/assignee update is in
      // flight — those refetch themselves on completion.
      if (_loading || _pendingTaskIds.isNotEmpty) return;
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _loading || _pendingTaskIds.isNotEmpty) return;
        _loadTasks(showLoading: false);
      });
    });
    // Mirrors the server's assertManagerOnly on the history feed: showing the
    // button to a teacher would just hand them a 403.
    final role = ref.watch(releaseGateStatusProvider).asData?.value.role;
    final canControl = role != null && crmHasManagerAccess(role);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _creatingTask ? null : _createTask,
        tooltip: _creatingTask ? 'Подготовка…' : 'Новая задача',
        child: _creatingTask
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add),
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
          if (canControl)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _showRescheduleControl,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Контроль переносов'),
                ),
              ),
            ),
          if (_dueFilter == 'day')
            _DayNavigator(
              day: _selectedDay,
              onShift: (days) => _setDropdownFilter(
                () => _selectedDay = _selectedDay.add(Duration(days: days)),
              ),
              onPick: _pickDay,
              onToday: () {
                final now = DateTime.now();
                _setDropdownFilter(
                  () => _selectedDay = DateTime(now.year, now.month, now.day),
                );
              },
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
                    color: AppColor.gold,
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
                        onRescheduleTap: _rescheduleTask,
                        onReassignTap: _reassignTask,
                        onOpenEntity: _openTaskEntity,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    _setDropdownFilter(
      () => _selectedDay = DateTime(picked.year, picked.month, picked.day),
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
      // Back to the default view (today's list), not to the whole backlog.
      _dueFilter = 'day';
      final now = DateTime.now();
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
    _loadTasks();
  }
}
