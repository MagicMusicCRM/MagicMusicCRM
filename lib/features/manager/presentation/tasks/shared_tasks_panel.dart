import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/providers/crm_section_focus_provider.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/section_unseen_service.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_details.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_close_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_results_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_view.dart';

class SharedTasksPanel extends ConsumerStatefulWidget {
  const SharedTasksPanel({
    super.key,
    this.dataSource,
    this.embedded = false,
    this.compactEmpty = false,
    this.initialLink,
    this.linkedEntity,
    this.scrollController,
    this.canWrite,
    this.defaultToMineToday = false,
    this.now,
    this.canViewResults,
    this.onOpenResultEntity,
  });

  final SharedTasksDataSource? dataSource;
  final bool embedded;
  final bool compactEmpty;
  final EntityLink? initialLink;
  final EntityLink? linkedEntity;
  final ScrollController? scrollController;
  final bool? canWrite;
  final bool defaultToMineToday;
  final DateTime Function()? now;
  final bool? canViewResults;
  final ValueChanged<EntityLink>? onOpenResultEntity;

  @override
  ConsumerState<SharedTasksPanel> createState() => _SharedTasksPanelState();
}

class _SharedTasksPanelState extends ConsumerState<SharedTasksPanel> {
  late SharedTasksDataSource _dataSource;
  late SharedTasksController _controller;
  StreamController<void>? _realtimeRefreshes;
  ProviderSubscription<AsyncValue<CrmChangedEvent>>? _realtimeSubscription;
  ProviderSubscription<CrmSectionFocus?>? _sectionFocusSubscription;
  Timer? _todayRolloverTimer;
  DateTime? _followedToday;
  bool _focusConsumed = false;
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _dataSource =
        widget.dataSource ?? MagicCrmSharedTasksDataSource.fromWidgetRef(ref);
    _realtimeRefreshes = widget.dataSource == null
        ? StreamController<void>.broadcast()
        : null;
    final now = DateTime.now();
    _followedToday = _moscowToday();
    final sectionFocus = ref.read(crmSectionFocusProvider);
    final focusedOverdue =
        (sectionFocus?.section == 'tasks' &&
            sectionFocus?.filters['due'] == 'overdue') ||
        widget.initialLink?.optionalFocus?.filter['due'] == 'overdue';
    _controller = SharedTasksController(
      dataSource: _dataSource,
      refreshes: _realtimeRefreshes?.stream,
      initialQuery: SharedTasksQuery(
        taskId: _focusedTaskId,
        linkedEntityType: widget.linkedEntity?.rawEntityType,
        linkedEntityId: widget.linkedEntity?.entityId,
        scope: widget.defaultToMineToday ? 'mine' : 'all',
        day: widget.defaultToMineToday ? _followedToday : null,
        calendarMonth: DateTime(now.year, now.month),
        state: focusedOverdue ? 'overdue' : 'open',
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
    _sectionFocusSubscription = ref.listenManual<CrmSectionFocus?>(
      crmSectionFocusProvider,
      (_, next) {
        if (next?.section != 'tasks') return;
        final nextState = next!.filters['due'] == 'overdue'
            ? 'overdue'
            : 'open';
        if (_controller.state.query.state != nextState) {
          unawaited(
            _controller.setQuery(
              _controller.state.query.copyWith(state: nextState),
            ),
          );
        }
        ref.read(crmSectionFocusProvider.notifier).consume('tasks');
      },
    );
    Future<void>.microtask(_load);
    _scheduleTodayRollover();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(crmSectionFocusProvider.notifier).consume('tasks');
      }
    });
  }

  @override
  void didUpdateWidget(covariant SharedTasksPanel oldWidget) {
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
    if (defaultsChanged || oldWidget.now != widget.now) {
      _followedToday = _moscowToday();
      _scheduleTodayRollover();
    }
    final oldRouteState = _routeTaskState(oldWidget.initialLink);
    final nextRouteState = _routeTaskState(widget.initialLink);
    final routeStateChanged = oldRouteState != nextRouteState;
    if (!focusChanged &&
        !linkedChanged &&
        !defaultsChanged &&
        !routeStateChanged) {
      return;
    }
    if (focusChanged) _focusConsumed = false;

    final query = _controller.state.query;
    unawaited(
      _controller.setQuery(
        query.copyWith(
          taskId: nextFocusedTaskId,
          linkedEntityType: widget.linkedEntity?.rawEntityType,
          linkedEntityId: widget.linkedEntity?.entityId,
          scope: defaultsChanged
              ? (widget.defaultToMineToday ? 'mine' : 'all')
              : query.scope,
          day: defaultsChanged
              ? (widget.defaultToMineToday ? _followedToday : null)
              : query.day,
          state: routeStateChanged ? nextRouteState : query.state,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _todayRolloverTimer?.cancel();
    _sectionFocusSubscription?.close();
    _realtimeSubscription?.close();
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    final refreshes = _realtimeRefreshes;
    if (refreshes != null) unawaited(refreshes.close());
    super.dispose();
  }

  String? get _focusedTaskId => _focusedTaskIdFor(widget.initialLink);

  DateTime _moscowToday() {
    final now =
        (widget.now ?? ref.read<DateTime Function()>(crmDayClockProvider))()
            .toUtc()
            .add(const Duration(hours: 3));
    return DateTime(now.year, now.month, now.day);
  }

  void _scheduleTodayRollover() {
    _todayRolloverTimer?.cancel();
    if (!widget.defaultToMineToday) return;
    final now =
        (widget.now ?? ref.read<DateTime Function()>(crmDayClockProvider))()
            .toUtc()
            .add(const Duration(hours: 3));
    final nextDay = DateTime.utc(now.year, now.month, now.day + 1);
    _todayRolloverTimer = Timer(
      nextDay.difference(now) + const Duration(milliseconds: 1),
      () {
        if (!mounted) return;
        final previous = _followedToday;
        final today = _moscowToday();
        _followedToday = today;
        final query = _controller.state.query;
        if (today != previous &&
            query.scope == 'mine' &&
            query.day == previous) {
          unawaited(_controller.setQuery(query.copyWith(day: today)));
        }
        _scheduleTodayRollover();
      },
    );
  }

  String _routeTaskState(EntityLink? link) =>
      link?.optionalFocus?.filter['due'] == 'overdue' ? 'overdue' : 'open';

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
    final closed = await showSharedTaskCloseDialog(
      context,
      onSubmit: (input) async {
        final result = await _controller.close(task, input);
        if (result.succeeded && mounted) ref.invalidate(sectionUnseenProvider);
        return result;
      },
    );
    if (closed == true && mounted) {
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
    if (saved == true && mounted) await _load(showLoading: false);
  }

  Future<void> _openDetails(Map<String, dynamic> task) async {
    await showMagicAdaptiveSurface<void>(
      context,
      kind: AppSurfaceKind.quickView,
      title: task['title']?.toString() ?? 'Задача',
      icon: Icons.task_alt_rounded,
      builder: (surfaceContext) => SharedTaskDetails(
        task: task,
        history: _dataSource.history(task['id'].toString()),
        onOpenEntity: (link) =>
            _openLinkedEntity(task, link, surfaceContext: surfaceContext),
      ),
    );
  }

  Future<void> _openAdvancedFilters() async {
    final selected = await showMagicAdaptiveSurface<String>(
      context,
      kind: AppSurfaceKind.selection,
      title: 'Фильтры задач',
      icon: Icons.tune_rounded,
      builder: (surfaceContext) => SharedTaskAdvancedFilters(
        value: _controller.state.query.state,
        onChanged: (value) => Navigator.pop(surfaceContext, value),
      ),
    );
    if (!mounted || selected == null) return;
    final query = _controller.state.query;
    if (selected != query.state) {
      await _controller.setQuery(query.copyWith(state: selected));
    }
  }

  Future<void> _openLinkedEntity(
    Map<String, dynamic> task,
    EntityLink link, {
    required BuildContext surfaceContext,
  }) async {
    final scoped = widget.linkedEntity;
    final destination =
        scoped?.rawEntityType == link.rawEntityType &&
            scoped?.entityId == link.entityId
        ? scoped!
        : link;
    if (!destination.isSupported) return;
    Navigator.of(surfaceContext).pop();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await openEntityLink(
      context,
      ref,
      destination,
      sourceViewState: ContextViewState(
        filters: {'taskId': task['id']?.toString()},
      ),
    );
  }

  Future<void> _openResultEntity(EntityLink link) async {
    if (!link.isSupported) return;
    await openEntityLink(context, ref, link);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.read(capabilitySnapshotProvider).value;
    final canCreate = widget.canWrite ?? false;
    final canEdit =
        widget.canWrite ??
        ref
                .read(capabilitySnapshotProvider)
                .value
                ?.allows('workflow.task.write') ==
            true;
    final canViewResults =
        widget.canViewResults ??
        (snapshot?.allows('report.status.read') == true &&
            const {
              'admin',
              'manager',
              'director',
              'system_admin',
            }.contains(snapshot?.role));
    if (_showResults && canViewResults && !widget.embedded) {
      return SharedTaskResultsPanel(
        dataSource: _dataSource,
        onBack: () => setState(() => _showResults = false),
        onOpenEntity: (link) {
          final callback = widget.onOpenResultEntity;
          if (callback != null) {
            callback(link);
          } else {
            unawaited(_openResultEntity(link));
          }
        },
      );
    }
    return SharedTasksView(
      state: _controller.state,
      onQueryChanged: (query) => unawaited(_controller.setQuery(query)),
      onSearchDraftChanged: _controller.updateQuery,
      onOpen: (task) => unawaited(_openDetails(task)),
      onClose: (task) => unawaited(_close(task)),
      onEdit: (task) => unawaited(_openEditor(task)),
      onCreate: () => unawaited(_openEditor()),
      onAdvancedFilters: () => unawaited(_openAdvancedFilters()),
      onRetry: () => unawaited(_controller.retry()),
      onRefresh: _load,
      canCreate: canCreate,
      canEdit: canEdit,
      onOpenResults: canViewResults && !widget.embedded
          ? () => setState(() => _showResults = true)
          : null,
      embedded: widget.embedded,
      compactEmpty: widget.compactEmpty,
      showViewToolbar: widget.linkedEntity == null,
      scrollController: widget.scrollController,
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
