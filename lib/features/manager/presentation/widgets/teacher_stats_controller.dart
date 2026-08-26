import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_models.dart';

class TeacherStatsController extends ChangeNotifier {
  TeacherStatsController({
    required MagicCrmService crm,
    required MagicSettingsService settings,
    required ReportFileOpener reportFileOpener,
    required DateTimeRange? filterRange,
    required String? branchId,
    required bool canCorrectSettledPayroll,
    DateTime Function()? clock,
  }) : _crm = crm,
       _settings = settings,
       _reportFileOpener = reportFileOpener {
    final now = (clock ?? DateTime.now)();
    final from = filterRange?.start ?? DateTime(now.year, now.month);
    final to = filterRange == null
        ? DateTime(now.year, now.month + 1)
        : filterRange.end.add(const Duration(days: 1));
    _state = TeacherStatsState(
      query: TeacherStatsQuery(from: from, to: to, branchId: branchId),
      usesExternalRange: filterRange != null,
      canCorrectSettledPayroll: canCorrectSettledPayroll,
    );
  }

  final MagicCrmService _crm;
  final MagicSettingsService _settings;
  final ReportFileOpener _reportFileOpener;
  final NumberFormat _money = NumberFormat('#,##0', 'ru');
  final DateFormat _dayFormat = DateFormat('dd.MM');
  late TeacherStatsState _state;

  TeacherStatsState get state => _state;

  Future<void> initialize() async {
    await Future.wait([loadReferences(), loadReport()]);
  }

  Future<void> loadReferences() async {
    try {
      final results = await Future.wait([
        if (!_state.usesExternalRange) _crm.listBranches(limit: 100),
        _crm.listTeachers(limit: 100),
        _crm.listDisciplines(),
      ]);
      final offset = _state.usesExternalRange ? 0 : 1;
      _state = _state.copyWith(
        branches: offset == 1 ? results[0] : const [],
        teachers: results[offset],
        disciplines: results[offset + 1],
      );
      notifyListeners();
      try {
        final fields = await _settings.getCrmCustomFields();
        final categories =
            fields
                .where(
                  (field) =>
                      field.entity == 'teachers' && field.key == 'categories',
                )
                .expand((field) => field.options)
                .toSet()
                .toList()
              ..sort();
        _state = _state.copyWith(categoryOptions: categories);
        notifyListeners();
      } catch (_) {
        // Optional custom-field settings do not block the report.
      }
    } catch (_) {
      // Reference filters are optional; the report remains usable without them.
    }
  }

  Future<void> updateSharedFilter(
    DateTimeRange? filterRange,
    String? branchId,
  ) async {
    final now = DateTime.now();
    _state = _state.copyWith(
      usesExternalRange: filterRange != null,
      query: _state.query.copyWith(
        from: filterRange?.start ?? DateTime(now.year, now.month),
        to: filterRange == null
            ? DateTime(now.year, now.month + 1)
            : filterRange.end.add(const Duration(days: 1)),
        branchId: branchId,
      ),
    );
    await loadReferences();
    await loadReport();
  }

  void updateCorrectionPolicy(bool canCorrectSettledPayroll) {
    if (_state.canCorrectSettledPayroll == canCorrectSettledPayroll) return;
    _state = _state.copyWith(
      canCorrectSettledPayroll: canCorrectSettledPayroll,
    );
  }

  Future<void> setQuery(TeacherStatsQuery query) async {
    _state = _state.copyWith(query: query);
    await loadReport();
  }

  Future<void> loadReport() async {
    _state = _state.copyWith(
      loading: true,
      error: null,
      selectedUnits: const {},
    );
    notifyListeners();
    try {
      final query = _state.query;
      final report = await _crm.getTeacherStatsReport(
        from: query.from.toUtc().toIso8601String(),
        to: query.to.toUtc().toIso8601String(),
        branchId: query.branchId,
        teacherId: query.teacherId,
        unitType: query.unitType,
        status: query.status,
        discipline: query.discipline,
        category: query.category,
      );
      _state = _state.copyWith(report: report, loading: false, error: null);
    } catch (error) {
      _state = _state.copyWith(loading: false, error: error);
    }
    notifyListeners();
  }

  Future<void> applyRate(TeacherStatsRateChange change) async {
    if (change.lessonIds.isEmpty || _state.applyingRate) return;
    _state = _state.copyWith(applyingRate: true);
    notifyListeners();
    try {
      final updated = await _crm.setLessonsTeacherRate(
        lessonIds: change.lessonIds,
        teacherRate: change.teacherRate,
        reasonText: change.reasonText,
      );
      _state = _state.copyWith(lastUpdatedCount: updated);
      await loadReport();
    } finally {
      _state = _state.copyWith(applyingRate: false);
      notifyListeners();
    }
  }

  Future<void> updateGroupRate(String groupId, num? rate) async {
    await _crm.updateGroup(groupId, teacherRate: rate, setTeacherRate: true);
    await loadReport();
  }

  Future<ReportFileOpenResult> export() async {
    _state = _state.copyWith(exporting: true);
    notifyListeners();
    try {
      final query = _state.query;
      final csv = await _crm.exportTeacherStatsReport(
        from: query.from.toUtc().toIso8601String(),
        to: query.to.toUtc().toIso8601String(),
        branchId: query.branchId,
        teacherId: query.teacherId,
        unitType: query.unitType,
        status: query.status,
        discipline: query.discipline,
        category: query.category,
      );
      final bytes = utf8.encode(csv);
      validateReportExportBytes(bytes, 'csv');
      final stamp = DateFormat('yyyy-MM-dd').format(query.from);
      return _reportFileOpener(bytes, 'teacher-stats-$stamp.csv');
    } finally {
      _state = _state.copyWith(exporting: false);
      notifyListeners();
    }
  }

  void toggleUnit(String unitKey, List<String> lessonIds) {
    final selected = {
      for (final entry in _state.selectedUnits.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    };
    if (selected.containsKey(unitKey)) {
      selected.remove(unitKey);
    } else {
      selected[unitKey] = List<String>.unmodifiable(lessonIds);
    }
    _state = _state.copyWith(selectedUnits: Map.unmodifiable(selected));
    notifyListeners();
  }

  void clearSelection() {
    if (_state.selectedUnits.isEmpty) return;
    _state = _state.copyWith(selectedUnits: const {});
    notifyListeners();
  }

  List<String> editableLessonIdsFor(Map<String, dynamic> unit) {
    final source = _state.canCorrectSettledPayroll
        ? unit['lessonIds']
        : unit['editableLessonIds'];
    return [
      for (final id in (source as List? ?? const []))
        if (id != null) id.toString(),
    ];
  }

  List<String> selectableLessonIdsFor(Map<String, dynamic> unit) {
    final lessonIds = editableLessonIdsFor(unit);
    final isGroup =
        unit['unitType'] == 'group' || unit['unitType'] == 'group_trial';
    if (lessonIds.isEmpty || (!_state.canCorrectSettledPayroll && isGroup)) {
      return const [];
    }
    return lessonIds;
  }

  String rub(dynamic value) => '${_money.format(number(value))} ₽';

  String hours(dynamic value) {
    final hours = number(value);
    final text = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(2);
    return '$text астр.ч.';
  }

  String rateLabel(dynamic value) {
    final rate = number(value);
    return rate == 0 ? 'оклад' : '${_money.format(rate)} ₽';
  }

  String dayLabel(DateTime value) => _dayFormat.format(value);

  num number(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  int integer(dynamic value) => number(value).toInt();
}
