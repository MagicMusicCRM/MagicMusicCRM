import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'schedule_reference_draft_operations.dart';
import 'schedule_reference_models.dart';

class ScheduleReferenceController extends ChangeNotifier {
  ScheduleReferenceController({
    required MagicCrmService crm,
    required this.section,
    required this.canEdit,
    DateTime Function()? clock,
  }) : _crm = crm,
       _clock = clock ?? DateTime.now;

  final MagicCrmService _crm;
  final DateTime Function() _clock;
  final ScheduleReferenceSection section;
  final bool canEdit;

  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _teachers = const [];
  String? _branchId;
  String? _teacherId;
  BranchHoursDraft? _branchDraft;
  TeacherScheduleDraft? _teacherDraft;
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  int _catalogGeneration = 0;
  int _referenceGeneration = 0;
  bool _disposed = false;

  ScheduleReferenceSnapshot get state => ScheduleReferenceSnapshot(
    branches: _branches,
    teachers: _teachers,
    branchId: _branchId,
    teacherId: _teacherId,
    branchDraft: _branchDraft,
    teacherDraft: _teacherDraft,
    loading: _loading,
    saving: _saving,
    error: _error,
  );
  bool get availabilityLocked =>
      _teacherDraft?.extraRecurring.isNotEmpty == true;

  bool get canLoadReference => switch (section) {
    ScheduleReferenceSection.branchHours => _branchId != null,
    ScheduleReferenceSection.teacherSchedule =>
      _branchId != null && _teacherId != null,
  };

  Future<void> loadCatalogs() async {
    final generation = ++_catalogGeneration;
    _referenceGeneration++;
    _startLoading();
    try {
      final result = await Future.wait([
        _crm.listBranches(limit: 100),
        if (section == ScheduleReferenceSection.teacherSchedule)
          _crm.listTeachers(limit: 100),
      ]);
      if (!_catalogIsCurrent(generation)) return;
      _branches = result.first;
      _teachers = result.length > 1 ? result[1] : const [];
      _branchId = validScheduleReferenceSelection(_branchId, _branches);
      _teacherId = validScheduleReferenceSelection(_teacherId, _teachers);
      if (canLoadReference) {
        await _loadReference();
      } else {
        _finishLoading();
      }
    } catch (caught) {
      if (_catalogIsCurrent(generation)) _failLoading(caught);
    }
  }

  Future<void> selectBranch(String branchId) async {
    if (branchId == _branchId ||
        !containsScheduleReferenceId(_branches, branchId)) {
      return;
    }
    _branchId = branchId;
    _notify();
    await _loadReference();
  }

  Future<void> selectTeacher(String teacherId) async {
    if (teacherId == _teacherId ||
        !containsScheduleReferenceId(_teachers, teacherId)) {
      return;
    }
    _teacherId = teacherId;
    _notify();
    await _loadReference();
  }

  Future<void> _loadReference() async {
    final branchId = _branchId;
    final teacherId = _teacherId;
    if (!canLoadReference || branchId == null) return;
    final generation = ++_referenceGeneration;
    _startLoading();
    try {
      final data = section == ScheduleReferenceSection.branchHours
          ? await _crm.getBranchScheduleHours(branchId)
          : await _crm.getScheduleReference(
              branchId: branchId,
              teacherId: teacherId!,
            );
      if (!_referenceIsCurrent(generation, branchId, teacherId)) return;
      _applyReference(data);
      _finishLoading();
    } catch (caught) {
      if (_referenceIsCurrent(generation, branchId, teacherId)) {
        _failLoading(caught);
      }
    }
  }

  void _applyReference(Map<String, dynamic> data) {
    if (section == ScheduleReferenceSection.branchHours) {
      _branchDraft = BranchHoursDraft.fromJson(data);
      return;
    }
    _branchDraft = BranchHoursDraft.fromJson(
      data['branch'] as Map<String, dynamic>? ?? const {},
    );
    _teacherDraft = TeacherScheduleDraft.fromJson(
      data['teacher'] as Map<String, dynamic>? ?? const {},
    );
  }

  void setBranchDayEnabled(int weekday, bool enabled) {
    final draft = _branchDraft;
    if (!_canEditDraft || draft == null) return;
    _branchDraft = withBranchDayEnabled(draft, weekday, enabled: enabled);
    _notify();
  }

  void setBranchTime(int weekday, String field, String value) {
    final draft = _branchDraft;
    if (!_canEditDraft || draft?.weekly[weekday] == null) return;
    _branchDraft = withBranchTime(draft!, weekday, field, value);
    _notify();
  }

  void replaceBranchException(Map<String, dynamic> exception) {
    final draft = _branchDraft;
    final date = exception['date']?.toString();
    if (!_canEditDraft || draft == null || date == null) return;
    _branchDraft = withBranchException(draft, exception);
    _notify();
  }

  void removeBranchException(String date) {
    final draft = _branchDraft;
    if (!_canEditDraft || draft == null) return;
    _branchDraft = withoutBranchException(draft, date);
    _notify();
  }

  Future<void> saveBranchHours() async {
    final target = _branchSaveTarget;
    if (target == null) return;
    await _runSave(() async {
      final result = await _crm.replaceBranchHours(
        branchId: target.branchId,
        expectedVersion: target.draft.version,
        timezone: target.draft.timezone,
        weekly: branchWeeklyPayload(target.draft),
        exceptions: branchExceptionsPayload(target.draft),
      );
      _applyReturnedBranchVersion(target, result);
    });
  }

  Future<void> saveAssignments() async {
    final target = _teacherSaveTarget;
    if (target == null) return;
    await _runSave(() async {
      final result = await _crm.replaceTeacherBranches(
        teacherId: target.teacherId,
        expectedVersion: target.draft.version,
        assignments: teacherAssignmentsPayload(target.draft),
      );
      _applyReturnedTeacherVersion(target, result);
    });
  }

  Future<void> saveAvailability() async {
    final target = _teacherSaveTarget;
    if (target == null) return;
    await _runSave(() async {
      final result = await _crm.replaceTeacherAvailability(
        teacherId: target.teacherId,
        expectedVersion: target.draft.version,
        rules: teacherAvailabilityPayload(target.draft),
      );
      _applyReturnedTeacherVersion(target, result);
    });
  }

  ({String branchId, BranchHoursDraft draft})? get _branchSaveTarget {
    final branchId = _branchId;
    final draft = _branchDraft;
    if (!_canEditDraft || branchId == null || draft == null) return null;
    return (branchId: branchId, draft: draft);
  }

  ({String teacherId, TeacherScheduleDraft draft})? get _teacherSaveTarget {
    final teacherId = _teacherId;
    final draft = _teacherDraft;
    if (!_canEditDraft || teacherId == null || draft == null) return null;
    return (teacherId: teacherId, draft: draft);
  }

  void _applyReturnedBranchVersion(
    ({String branchId, BranchHoursDraft draft}) target,
    Map<String, dynamic> result,
  ) {
    if (_branchId != target.branchId ||
        !identical(_branchDraft, target.draft)) {
      return;
    }
    _branchDraft = target.draft.copyWith(
      version: returnedScheduleVersion(result, target.draft.version),
    );
  }

  void _applyReturnedTeacherVersion(
    ({String teacherId, TeacherScheduleDraft draft}) target,
    Map<String, dynamic> result,
  ) {
    if (_teacherId != target.teacherId ||
        !identical(_teacherDraft, target.draft)) {
      return;
    }
    _teacherDraft = target.draft.copyWith(
      version: returnedScheduleVersion(result, target.draft.version),
    );
  }

  Future<void> _runSave(Future<void> Function() action) async {
    _saving = true;
    _notify();
    try {
      await action();
    } finally {
      _saving = false;
      _notify();
    }
  }

  bool get _canEditDraft => canEdit && !_saving;
  bool get _canEditAvailability => _canEditDraft && !availabilityLocked;

  void _startLoading() {
    _loading = true;
    _error = null;
    _notify();
  }

  void _finishLoading() {
    _loading = false;
    _notify();
  }

  void _failLoading(Object caught) {
    _loading = false;
    _error = caught;
    _notify();
  }

  bool _catalogIsCurrent(int generation) =>
      !_disposed && generation == _catalogGeneration;

  bool _referenceIsCurrent(
    int generation,
    String branchId,
    String? teacherId,
  ) =>
      !_disposed &&
      generation == _referenceGeneration &&
      branchId == _branchId &&
      teacherId == _teacherId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _catalogGeneration++;
    _referenceGeneration++;
    super.dispose();
  }
}

extension ScheduleReferenceTeacherDraftCommands on ScheduleReferenceController {
  void setAssignment(String branchId, bool selected) {
    final draft = _teacherDraft;
    if (!_canEditDraft || draft == null) return;
    _teacherDraft = withTeacherAssignment(draft, branchId, selected: selected);
    _notify();
  }

  void setRecurringEnabled(int weekday, bool enabled) {
    final draft = _teacherDraft;
    if (!_canEditAvailability || draft == null) return;
    _teacherDraft = withRecurringDay(
      draft,
      weekday,
      enabled: enabled,
      timezone: _branchDraft?.timezone ?? 'Europe/Moscow',
      validFrom: DateFormat('yyyy-MM-dd').format(_clock()),
    );
    _notify();
  }

  void setRecurringTime(int weekday, String field, String value) {
    final draft = _teacherDraft;
    if (!_canEditAvailability || draft?.recurring[weekday] == null) return;
    _teacherDraft = withRecurringTime(draft!, weekday, field, value);
    _notify();
  }

  void addUnavailableInterval(Map<String, dynamic> interval) {
    final draft = _teacherDraft;
    if (!_canEditAvailability || draft == null) return;
    _teacherDraft = withUnavailableInterval(draft, interval);
    _notify();
  }

  void removeUnavailableInterval(Map<String, dynamic> interval) {
    final draft = _teacherDraft;
    if (!_canEditAvailability || draft == null) return;
    _teacherDraft = withoutUnavailableInterval(draft, interval);
    _notify();
  }
}
