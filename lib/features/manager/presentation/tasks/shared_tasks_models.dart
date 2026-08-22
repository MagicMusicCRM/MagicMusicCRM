import 'package:flutter/foundation.dart';

const _unchanged = Object();

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
    this.appliedQuery = const SharedTasksQuery(),
    this.successfulQuery,
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
  final SharedTasksQuery appliedQuery;
  final SharedTasksQuery? successfulQuery;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> counters;
  final Map<String, int> calendar;
  final bool loading;
  final bool hasLoaded;
  final Object? error;
  final Set<String> closing;
  final Map<String, Object> closeErrors;

  bool get contentQueryChanged =>
      successfulQuery != null && successfulQuery != appliedQuery;

  bool get contentReplacementPending =>
      loading && hasLoaded && contentQueryChanged;

  bool get showContentNotice =>
      hasLoaded && (error != null || contentReplacementPending);

  SharedTasksQuery get contentQuery => successfulQuery ?? appliedQuery;

  SharedTasksState copyWith({
    SharedTasksQuery? query,
    SharedTasksQuery? appliedQuery,
    Object? successfulQuery = _unchanged,
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
    appliedQuery: appliedQuery ?? this.appliedQuery,
    successfulQuery: identical(successfulQuery, _unchanged)
        ? this.successfulQuery
        : successfulQuery as SharedTasksQuery?,
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

DateTime sharedTasksMoscowToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 3));
  return DateTime(now.year, now.month, now.day);
}
