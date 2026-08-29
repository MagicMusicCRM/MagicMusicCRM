import 'package:flutter/foundation.dart';

const _unsetTeacherStatsFilter = Object();

@immutable
class TeacherStatsQuery {
  const TeacherStatsQuery({
    required this.from,
    required this.to,
    this.branchId,
    this.teacherId,
    this.unitType,
    this.status,
    this.discipline,
    this.category,
  });

  final DateTime from;
  final DateTime to;
  final String? branchId;
  final String? teacherId;
  final String? unitType;
  final String? status;
  final String? discipline;
  final String? category;

  TeacherStatsQuery copyWith({
    DateTime? from,
    DateTime? to,
    Object? branchId = _unsetTeacherStatsFilter,
    Object? teacherId = _unsetTeacherStatsFilter,
    Object? unitType = _unsetTeacherStatsFilter,
    Object? status = _unsetTeacherStatsFilter,
    Object? discipline = _unsetTeacherStatsFilter,
    Object? category = _unsetTeacherStatsFilter,
  }) {
    return TeacherStatsQuery(
      from: from ?? this.from,
      to: to ?? this.to,
      branchId: identical(branchId, _unsetTeacherStatsFilter)
          ? this.branchId
          : branchId as String?,
      teacherId: identical(teacherId, _unsetTeacherStatsFilter)
          ? this.teacherId
          : teacherId as String?,
      unitType: identical(unitType, _unsetTeacherStatsFilter)
          ? this.unitType
          : unitType as String?,
      status: identical(status, _unsetTeacherStatsFilter)
          ? this.status
          : status as String?,
      discipline: identical(discipline, _unsetTeacherStatsFilter)
          ? this.discipline
          : discipline as String?,
      category: identical(category, _unsetTeacherStatsFilter)
          ? this.category
          : category as String?,
    );
  }
}

@immutable
class TeacherStatsRateChange {
  const TeacherStatsRateChange({
    required this.lessonIds,
    required this.teacherRate,
    required this.reasonText,
  });

  final List<String> lessonIds;
  final num? teacherRate;
  final String reasonText;
}

@immutable
class TeacherStatsGroupRateChange {
  const TeacherStatsGroupRateChange(this.teacherRate);

  final num? teacherRate;
}

@immutable
class TeacherStatsState {
  const TeacherStatsState({
    required this.query,
    required this.usesExternalRange,
    required this.canManageTeacherRates,
    this.loading = true,
    this.error,
    this.report = const {},
    this.branches = const [],
    this.teachers = const [],
    this.disciplines = const [],
    this.categoryOptions = const [],
    this.selectedUnits = const {},
    this.exporting = false,
    this.applyingRate = false,
    this.lastUpdatedCount = 0,
  });

  final TeacherStatsQuery query;
  final bool usesExternalRange;
  final bool canManageTeacherRates;
  final bool loading;
  final Object? error;
  final Map<String, dynamic> report;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> disciplines;
  final List<String> categoryOptions;
  final Map<String, List<String>> selectedUnits;
  final bool exporting;
  final bool applyingRate;
  final int lastUpdatedCount;

  TeacherStatsState copyWith({
    TeacherStatsQuery? query,
    bool? usesExternalRange,
    bool? canManageTeacherRates,
    bool? loading,
    Object? error = _unsetTeacherStatsFilter,
    Map<String, dynamic>? report,
    List<Map<String, dynamic>>? branches,
    List<Map<String, dynamic>>? teachers,
    List<Map<String, dynamic>>? disciplines,
    List<String>? categoryOptions,
    Map<String, List<String>>? selectedUnits,
    bool? exporting,
    bool? applyingRate,
    int? lastUpdatedCount,
  }) {
    return TeacherStatsState(
      query: query ?? this.query,
      usesExternalRange: usesExternalRange ?? this.usesExternalRange,
      canManageTeacherRates:
          canManageTeacherRates ?? this.canManageTeacherRates,
      loading: loading ?? this.loading,
      error: identical(error, _unsetTeacherStatsFilter) ? this.error : error,
      report: report ?? this.report,
      branches: branches ?? this.branches,
      teachers: teachers ?? this.teachers,
      disciplines: disciplines ?? this.disciplines,
      categoryOptions: categoryOptions ?? this.categoryOptions,
      selectedUnits: selectedUnits ?? this.selectedUnits,
      exporting: exporting ?? this.exporting,
      applyingRate: applyingRate ?? this.applyingRate,
      lastUpdatedCount: lastUpdatedCount ?? this.lastUpdatedCount,
    );
  }
}
