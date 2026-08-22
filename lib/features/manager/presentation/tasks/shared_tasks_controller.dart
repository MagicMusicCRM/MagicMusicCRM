import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';

const _unchanged = Object();

@immutable
class SharedTasksQuery {
  const SharedTasksQuery({
    this.state = 'open',
    this.taskId,
    this.linkedEntityType,
    this.linkedEntityId,
    this.search,
    this.priority = 'all',
    this.scope = 'all',
    this.day,
    this.calendarMode = false,
    this.calendarMonth,
  });

  final String state;
  final String? taskId;
  final String? linkedEntityType;
  final String? linkedEntityId;
  final String? search;
  final String priority;
  final String scope;
  final DateTime? day;
  final bool calendarMode;
  final DateTime? calendarMonth;

  bool get isFocused => taskId != null;

  SharedTasksQuery copyWith({
    String? state,
    Object? taskId = _unchanged,
    Object? linkedEntityType = _unchanged,
    Object? linkedEntityId = _unchanged,
    Object? search = _unchanged,
    String? priority,
    String? scope,
    Object? day = _unchanged,
    bool? calendarMode,
    Object? calendarMonth = _unchanged,
  }) => SharedTasksQuery(
    state: state ?? this.state,
    taskId: identical(taskId, _unchanged) ? this.taskId : taskId as String?,
    linkedEntityType: identical(linkedEntityType, _unchanged)
        ? this.linkedEntityType
        : linkedEntityType as String?,
    linkedEntityId: identical(linkedEntityId, _unchanged)
        ? this.linkedEntityId
        : linkedEntityId as String?,
    search: identical(search, _unchanged) ? this.search : search as String?,
    priority: priority ?? this.priority,
    scope: scope ?? this.scope,
    day: identical(day, _unchanged) ? this.day : day as DateTime?,
    calendarMode: calendarMode ?? this.calendarMode,
    calendarMonth: identical(calendarMonth, _unchanged)
        ? this.calendarMonth
        : calendarMonth as DateTime?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SharedTasksQuery &&
          state == other.state &&
          taskId == other.taskId &&
          linkedEntityType == other.linkedEntityType &&
          linkedEntityId == other.linkedEntityId &&
          search == other.search &&
          priority == other.priority &&
          scope == other.scope &&
          day == other.day &&
          calendarMode == other.calendarMode &&
          calendarMonth == other.calendarMonth;

  @override
  int get hashCode => Object.hash(
    state,
    taskId,
    linkedEntityType,
    linkedEntityId,
    search,
    priority,
    scope,
    day,
    calendarMode,
    calendarMonth,
  );
}

@immutable
class SharedTasksState {
  const SharedTasksState({
    this.query = const SharedTasksQuery(),
    this.items = const [],
    this.counters = const {'open': 0, 'overdue': 0},
    this.calendar = const {},
    this.loading = false,
    this.hasLoaded = false,
    this.error,
    this.closing = const {},
    this.closeErrors = const {},
  });

  final SharedTasksQuery query;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> counters;
  final Map<String, int> calendar;
  final bool loading;
  final bool hasLoaded;
  final Object? error;
  final Set<String> closing;
  final Map<String, Object> closeErrors;

  SharedTasksState copyWith({
    SharedTasksQuery? query,
    List<Map<String, dynamic>>? items,
    Map<String, dynamic>? counters,
    Map<String, int>? calendar,
    bool? loading,
    bool? hasLoaded,
    Object? error = _unchanged,
    Set<String>? closing,
    Map<String, Object>? closeErrors,
  }) => SharedTasksState(
    query: query ?? this.query,
    items: items ?? this.items,
    counters: counters ?? this.counters,
    calendar: calendar ?? this.calendar,
    loading: loading ?? this.loading,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    error: identical(error, _unchanged) ? this.error : error,
    closing: closing ?? this.closing,
    closeErrors: closeErrors ?? this.closeErrors,
  );
}

@immutable
class SharedTaskCloseResult {
  const SharedTaskCloseResult._({required this.succeeded, this.error});

  const SharedTaskCloseResult.success() : this._(succeeded: true);

  const SharedTaskCloseResult.failure(Object error)
    : this._(succeeded: false, error: error);

  const SharedTaskCloseResult.ignored() : this._(succeeded: false);

  final bool succeeded;
  final Object? error;
}

class SharedTasksController extends ChangeNotifier {
  SharedTasksController({
    required this.dataSource,
    Stream<void>? refreshes,
    SharedTasksQuery initialQuery = const SharedTasksQuery(),
    this.refreshDebounce = const Duration(milliseconds: 200),
  }) : state = SharedTasksState(query: initialQuery) {
    _refreshSubscription = refreshes?.listen((_) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer(refreshDebounce, () => unawaited(refresh()));
    });
  }

  final SharedTasksDataSource dataSource;
  final Duration refreshDebounce;
  SharedTasksState state;

  StreamSubscription<void>? _refreshSubscription;
  Timer? _refreshTimer;
  int _revision = 0;
  bool _disposed = false;
  final Map<String, MagicMutationIdentity> _closeIdentities = {};

  Future<void> refresh({bool showLoading = false}) =>
      setQuery(state.query, showLoading: showLoading);

  void updateQuery(SharedTasksQuery query) {
    if (_disposed || query == state.query) return;
    _revision++;
    state = state.copyWith(query: query, loading: false);
    notifyListeners();
  }

  Future<void> setQuery(
    SharedTasksQuery query, {
    bool showLoading = true,
  }) async {
    if (_disposed) return;
    final revision = ++_revision;
    state = state.copyWith(
      query: query,
      loading: showLoading || !state.hasLoaded,
      error: null,
    );
    notifyListeners();

    try {
      final day = query.isFocused ? null : query.day;
      final dayFrom = day == null ? null : sharedTasksMoscowInstant(day);
      final dayTo = day == null
          ? null
          : sharedTasksMoscowInstant(day.add(const Duration(days: 1)));
      final result = await dataSource.listFiltered(
        state:
            query.isFocused || query.state == 'all' || query.state == 'overdue'
            ? null
            : query.state,
        taskId: query.taskId,
        linkedEntityType: query.linkedEntityType,
        linkedEntityId: query.linkedEntityId,
        q: _normalizedSearch(query.search),
        priority: query.priority == 'all' ? null : query.priority,
        scope: query.scope,
        from: dayFrom,
        to: dayTo,
      );
      if (!_isCurrent(revision)) return;

      var items = _normalizeItems(result['items']);
      if (query.state == 'overdue') {
        items = items.where(isOverdueSharedTask).toList(growable: false);
      }

      var calendar = state.calendar;
      if (query.calendarMode) {
        final month =
            query.calendarMonth ??
            DateTime(DateTime.now().year, DateTime.now().month);
        final nextMonth = DateTime(month.year, month.month + 1);
        calendar = await dataSource.calendar(
          from: sharedTasksMoscowInstant(month),
          to: sharedTasksMoscowInstant(nextMonth),
          state: query.state == 'all' || query.state == 'overdue'
              ? null
              : query.state,
          q: _normalizedSearch(query.search),
          priority: query.priority == 'all' ? null : query.priority,
          scope: query.scope,
          linkedEntityType: query.linkedEntityType,
          linkedEntityId: query.linkedEntityId,
        );
        if (!_isCurrent(revision)) return;
      }

      final counters = query.linkedEntityType != null
          ? <String, dynamic>{
              'open': items.where((task) => task['state'] == 'open').length,
              'overdue': items.where(isOverdueSharedTask).length,
            }
          : _normalizeCounters(result['counters']);
      state = state.copyWith(
        items: List.unmodifiable(items),
        counters: Map.unmodifiable(counters),
        calendar: Map.unmodifiable(calendar),
        loading: false,
        hasLoaded: true,
        error: null,
      );
    } catch (error) {
      if (!_isCurrent(revision)) return;
      state = state.copyWith(loading: false, error: error);
    }
    if (!_disposed) notifyListeners();
  }

  Future<SharedTaskCloseResult> close(Map<String, dynamic> task) async {
    final id = task['id']?.toString();
    final version = task['version'];
    if (_disposed ||
        id == null ||
        version is! int ||
        state.closing.contains(id)) {
      return const SharedTaskCloseResult.ignored();
    }
    final identity = _closeIdentities.putIfAbsent(
      id,
      () => MagicMutationIdentity.create('shared-task-close'),
    );
    state = state.copyWith(
      closing: Set.unmodifiable({...state.closing, id}),
      closeErrors: Map.unmodifiable({...state.closeErrors}..remove(id)),
    );
    notifyListeners();

    try {
      await dataSource.close(id, version, identity);
      _closeIdentities.remove(id);
      state = state.copyWith(
        closeErrors: Map.unmodifiable({...state.closeErrors}..remove(id)),
      );
      await refresh();
      return const SharedTaskCloseResult.success();
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          closeErrors: Map.unmodifiable({...state.closeErrors, id: error}),
        );
      }
      return SharedTaskCloseResult.failure(error);
    } finally {
      if (!_disposed) {
        state = state.copyWith(
          closing: Set.unmodifiable({...state.closing}..remove(id)),
        );
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int revision) => !_disposed && revision == _revision;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    _refreshTimer?.cancel();
    unawaited(_refreshSubscription?.cancel());
    super.dispose();
  }
}

String? _normalizedSearch(String? search) {
  final trimmed = search?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

List<Map<String, dynamic>> _normalizeItems(Object? value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map(
        (item) => Map<String, dynamic>.unmodifiable(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .toList(growable: false);
}

Map<String, dynamic> _normalizeCounters(Object? value) {
  if (value is! Map) return const {'open': 0, 'overdue': 0};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String sharedTasksMoscowInstant(DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).subtract(const Duration(hours: 3)).toIso8601String();

DateTime sharedTasksMoscowToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 3));
  return DateTime(now.year, now.month, now.day);
}

bool isOverdueSharedTask(Map<String, dynamic> task) {
  final start = DateTime.tryParse(task['startAt']?.toString() ?? '');
  if (task['state'] != 'open' || start == null) return false;
  if (task['allDay'] != true) return start.isBefore(DateTime.now());
  final moscowStart = start.toUtc().add(const Duration(hours: 3));
  return DateTime(
    moscowStart.year,
    moscowStart.month,
    moscowStart.day,
  ).isBefore(sharedTasksMoscowToday());
}
