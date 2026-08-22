import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

export 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

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

class _SharedTaskCloseAttempt {
  const _SharedTaskCloseAttempt({
    required this.expectedVersion,
    required this.identity,
  });

  final int expectedVersion;
  final MagicMutationIdentity identity;
}

class SharedTasksController extends ChangeNotifier {
  SharedTasksController({
    required this.dataSource,
    Stream<void>? refreshes,
    SharedTasksQuery initialQuery = const SharedTasksQuery(),
    this.refreshDebounce = const Duration(milliseconds: 200),
  }) : state = SharedTasksState(
         query: initialQuery,
         appliedQuery: initialQuery,
       ) {
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
  final Map<String, _SharedTaskCloseAttempt> _closeAttempts = {};

  Future<void> refresh({bool showLoading = false}) =>
      setQuery(state.query, showLoading: showLoading);

  Future<void> retry({bool showLoading = true}) => setQuery(
    state.appliedQuery,
    showLoading: showLoading,
    preserveDraft: true,
  );

  void updateQuery(SharedTasksQuery query) {
    if (_disposed || query == state.query) return;
    state = state.copyWith(query: query);
    notifyListeners();
  }

  Future<void> setQuery(
    SharedTasksQuery query, {
    bool showLoading = true,
    bool preserveDraft = false,
  }) async {
    if (_disposed) return;
    final revision = ++_revision;
    state = state.copyWith(
      query: preserveDraft ? state.query : query,
      appliedQuery: query,
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
        successfulQuery: query,
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
    final previousAttempt = _closeAttempts[id];
    final attempt = previousAttempt?.expectedVersion == version
        ? previousAttempt!
        : _SharedTaskCloseAttempt(
            expectedVersion: version,
            identity: MagicMutationIdentity.create('shared-task-close'),
          );
    _closeAttempts[id] = attempt;
    state = state.copyWith(
      closing: Set.unmodifiable({...state.closing, id}),
      closeErrors: Map.unmodifiable({...state.closeErrors}..remove(id)),
    );
    notifyListeners();

    try {
      await dataSource.close(id, version, attempt.identity);
      _closeAttempts.remove(id);
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
