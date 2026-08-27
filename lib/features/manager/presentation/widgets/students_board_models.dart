import 'package:flutter/foundation.dart';

@immutable
class StudentsBoardPageResult {
  final List<Map<String, dynamic>> items;
  final String? nextCursor;

  StudentsBoardPageResult({
    required List<Map<String, dynamic>> items,
    required this.nextCursor,
  }) : items = _freezeRecords(items);
}

@immutable
class StudentsBoardMoveResult {
  final bool succeeded;
  final Object? error;
  final bool reconciliationPending;

  const StudentsBoardMoveResult._({
    required this.succeeded,
    this.error,
    this.reconciliationPending = false,
  });

  const StudentsBoardMoveResult.success({bool reconciliationPending = false})
    : this._(succeeded: true, reconciliationPending: reconciliationPending);

  const StudentsBoardMoveResult.failure(Object error)
    : this._(succeeded: false, error: error);
}

@immutable
class StudentsBoardColumnData {
  final String? status;
  final String name;
  final String style;
  final Set<String> allowedTransitions;
  final List<Map<String, dynamic>> students;

  StudentsBoardColumnData({
    required this.status,
    required this.name,
    required this.style,
    required Set<String> allowedTransitions,
    required List<Map<String, dynamic>> students,
  }) : allowedTransitions = Set.unmodifiable(allowedTransitions),
       students = _freezeRecords(students);

  StudentsBoardColumnData copyWith({List<Map<String, dynamic>>? students}) {
    return StudentsBoardColumnData(
      status: status,
      name: name,
      style: style,
      allowedTransitions: allowedTransitions,
      students: students ?? this.students,
    );
  }
}

enum StudentsBoardContentState { idle, loading, error, data }

@immutable
class StudentsBoardState {
  final List<Map<String, dynamic>> branches;
  final String? selectedBranchId;
  final String query;
  final bool filtersOpen;
  final bool branchesLoaded;
  final String? branchLoadError;
  final List<Map<String, dynamic>> extraStudents;
  final String? nextStudentCursor;
  final bool loadingMoreStudents;
  final Map<String, String> optimisticStatuses;
  final Set<String> pendingStudentIds;

  StudentsBoardState({
    List<Map<String, dynamic>> branches = const [],
    this.selectedBranchId,
    this.query = '',
    this.filtersOpen = false,
    this.branchesLoaded = false,
    this.branchLoadError,
    List<Map<String, dynamic>> extraStudents = const [],
    this.nextStudentCursor,
    this.loadingMoreStudents = false,
    Map<String, String> optimisticStatuses = const {},
    Set<String> pendingStudentIds = const {},
  }) : branches = _freezeRecords(branches),
       extraStudents = _freezeRecords(extraStudents),
       optimisticStatuses = Map.unmodifiable(optimisticStatuses),
       pendingStudentIds = Set.unmodifiable(pendingStudentIds);

  const StudentsBoardState._({
    required this.branches,
    required this.selectedBranchId,
    required this.query,
    required this.filtersOpen,
    required this.branchesLoaded,
    required this.branchLoadError,
    required this.extraStudents,
    required this.nextStudentCursor,
    required this.loadingMoreStudents,
    required this.optimisticStatuses,
    required this.pendingStudentIds,
  });

  StudentsBoardState copyWith({
    List<Map<String, dynamic>>? branches,
    Object? selectedBranchId = _notSet,
    String? query,
    bool? filtersOpen,
    bool? branchesLoaded,
    Object? branchLoadError = _notSet,
    List<Map<String, dynamic>>? extraStudents,
    Object? nextStudentCursor = _notSet,
    bool? loadingMoreStudents,
    Map<String, String>? optimisticStatuses,
    Set<String>? pendingStudentIds,
  }) {
    return StudentsBoardState._(
      branches: branches == null ? this.branches : _freezeRecords(branches),
      selectedBranchId: identical(selectedBranchId, _notSet)
          ? this.selectedBranchId
          : selectedBranchId as String?,
      query: query ?? this.query,
      filtersOpen: filtersOpen ?? this.filtersOpen,
      branchesLoaded: branchesLoaded ?? this.branchesLoaded,
      branchLoadError: identical(branchLoadError, _notSet)
          ? this.branchLoadError
          : branchLoadError as String?,
      extraStudents: extraStudents == null
          ? this.extraStudents
          : _freezeRecords(extraStudents),
      nextStudentCursor: identical(nextStudentCursor, _notSet)
          ? this.nextStudentCursor
          : nextStudentCursor as String?,
      loadingMoreStudents: loadingMoreStudents ?? this.loadingMoreStudents,
      optimisticStatuses: optimisticStatuses == null
          ? this.optimisticStatuses
          : Map.unmodifiable(optimisticStatuses),
      pendingStudentIds: pendingStudentIds == null
          ? this.pendingStudentIds
          : Set.unmodifiable(pendingStudentIds),
    );
  }
}

const Object _notSet = Object();

List<Map<String, dynamic>> _freezeRecords(
  Iterable<Map<String, dynamic>> records,
) => List.unmodifiable(records.map(_freezeRecord));

Map<String, dynamic> _freezeRecord(Map<String, dynamic> record) =>
    Map.unmodifiable(
      record.map((key, value) => MapEntry(key, _deepFreeze(value))),
    );

Object? _deepFreeze(Object? value) {
  if (value is Map<String, dynamic>) return _freezeRecord(value);
  if (value is Map) {
    return Map.unmodifiable(
      value.map((key, item) => MapEntry(key, _deepFreeze(item))),
    );
  }
  if (value is List) return List.unmodifiable(value.map(_deepFreeze));
  if (value is Set) return Set.unmodifiable(value.map(_deepFreeze));
  return value;
}
