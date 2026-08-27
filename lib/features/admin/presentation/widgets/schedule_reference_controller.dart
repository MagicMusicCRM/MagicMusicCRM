import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

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
    if (!canEdit || draft == null) return;
    final weekly = copyIndexedScheduleRows(draft.weekly);
    if (enabled) {
      weekly[weekday] = {'weekday': weekday, 'open': '09:00', 'close': '21:00'};
    } else {
      weekly.remove(weekday);
    }
    _branchDraft = draft.copyWith(weekly: weekly);
    _notify();
  }

  void setBranchTime(int weekday, String field, String value) {
    final draft = _branchDraft;
    final row = draft?.weekly[weekday];
    if (!canEdit || draft == null || row == null) return;
    final weekly = copyIndexedScheduleRows(draft.weekly);
    weekly[weekday] = {...row, field: value};
    _branchDraft = draft.copyWith(weekly: weekly);
    _notify();
  }

  void replaceBranchException(Map<String, dynamic> exception) {
    final draft = _branchDraft;
    final date = exception['date']?.toString();
    if (!canEdit || draft == null || date == null) return;
    final exceptions =
        [
          for (final row in draft.exceptions)
            if (row['date']?.toString() != date) {...row},
          {...exception},
        ]..sort(
          (left, right) =>
              left['date'].toString().compareTo(right['date'].toString()),
        );
    _branchDraft = draft.copyWith(exceptions: exceptions);
    _notify();
  }

  void removeBranchException(String date) {
    final draft = _branchDraft;
    if (!canEdit || draft == null) return;
    _branchDraft = draft.copyWith(
      exceptions: [
        for (final row in draft.exceptions)
          if (row['date']?.toString() != date) {...row},
      ],
    );
    _notify();
  }

  void setAssignment(String branchId, bool selected) {
    final draft = _teacherDraft;
    if (!canEdit || draft == null) return;
    final assignments = copyNamedScheduleRows(draft.assignments);
    if (selected) {
      assignments[branchId] = {
        'branchId': branchId,
        'activeFrom': '1970-01-01',
      };
    } else {
      assignments.remove(branchId);
    }
    _teacherDraft = draft.copyWith(assignments: assignments);
    _notify();
  }

  void setRecurringEnabled(int weekday, bool enabled) {
    final draft = _teacherDraft;
    if (!_canEditAvailability || draft == null) return;
    final recurring = copyIndexedScheduleRows(draft.recurring);
    if (enabled) {
      recurring[weekday] = {
        'kind': 'recurring',
        'available': true,
        'timezone': _branchDraft?.timezone ?? 'Europe/Moscow',
        'weekday': weekday,
        'localStart': '09:00',
        'localEnd': '21:00',
        'validFrom': DateFormat('yyyy-MM-dd').format(_clock()),
      };
    } else {
      recurring.remove(weekday);
    }
    _teacherDraft = draft.copyWith(recurring: recurring);
    _notify();
  }

  void setRecurringTime(int weekday, String field, String value) {
    final draft = _teacherDraft;
    final row = draft?.recurring[weekday];
    if (!_canEditAvailability || draft == null || row == null) return;
    final recurring = copyIndexedScheduleRows(draft.recurring);
    recurring[weekday] = {...row, field: value};
    _teacherDraft = draft.copyWith(recurring: recurring);
    _notify();
  }

  void addUnavailableInterval(Map<String, dynamic> interval) {
    final draft = _teacherDraft;
    if (!_canEditAvailability || draft == null) return;
    final reason = interval['reason']?.toString().trim() ?? '';
    final startsAt = DateTime.tryParse(interval['startsAt']?.toString() ?? '');
    final endsAt = DateTime.tryParse(interval['endsAt']?.toString() ?? '');
    if (reason.isEmpty || startsAt == null || endsAt == null) {
      throw ArgumentError('Interval requires UTC bounds and a reason.');
    }
    _teacherDraft = draft.copyWith(
      intervals: [
        for (final row in draft.intervals) {...row},
        {
          ...interval,
          'kind': 'interval',
          'available': false,
          'startsAt': startsAt.toUtc().toIso8601String(),
          'endsAt': endsAt.toUtc().toIso8601String(),
          'reason': reason,
        },
      ],
    );
    _notify();
  }

  void removeUnavailableInterval(Map<String, dynamic> interval) {
    final draft = _teacherDraft;
    if (!_canEditAvailability || draft == null) return;
    _teacherDraft = draft.copyWith(
      intervals: [
        for (final row in draft.intervals)
          if (!sameScheduleInterval(row, interval)) {...row},
      ],
    );
    _notify();
  }

  Future<void> saveBranchHours() async {
    final branchId = _branchId;
    final draft = _branchDraft;
    if (!canEdit || _saving || branchId == null || draft == null) return;
    await _runSave(() async {
      final result = await _crm.replaceBranchHours(
        branchId: branchId,
        expectedVersion: draft.version,
        timezone: draft.timezone,
        weekly: [
          for (final entry
              in (draft.weekly.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
            cleanScheduleReferenceMap({...entry.value, 'weekday': entry.key}),
        ],
        exceptions: [
          for (final row in draft.exceptions) cleanScheduleReferenceMap(row),
        ],
      );
      if (_branchId == branchId && identical(_branchDraft, draft)) {
        _branchDraft = draft.copyWith(
          version: returnedScheduleVersion(result, draft.version),
        );
      }
    });
  }

  Future<void> saveAssignments() async {
    final teacherId = _teacherId;
    final draft = _teacherDraft;
    if (!canEdit || _saving || teacherId == null || draft == null) return;
    await _runSave(() async {
      final result = await _crm.replaceTeacherBranches(
        teacherId: teacherId,
        expectedVersion: draft.version,
        assignments: [
          for (final row in draft.assignments.values)
            cleanScheduleReferenceMap({
              ...row,
              'activeFrom': row['activeFrom'] ?? '1970-01-01',
            }),
        ],
      );
      if (_teacherId == teacherId && identical(_teacherDraft, draft)) {
        _teacherDraft = draft.copyWith(
          version: returnedScheduleVersion(result, draft.version),
        );
      }
    });
  }

  Future<void> saveAvailability() async {
    final teacherId = _teacherId;
    final draft = _teacherDraft;
    if (!canEdit || _saving || teacherId == null || draft == null) return;
    await _runSave(() async {
      final result = await _crm.replaceTeacherAvailability(
        teacherId: teacherId,
        expectedVersion: draft.version,
        rules: [
          for (final row in draft.recurring.values)
            cleanScheduleReferenceMap(row),
          for (final row in draft.extraRecurring)
            cleanScheduleReferenceMap(row),
          for (final row in draft.intervals) cleanScheduleReferenceMap(row),
        ],
      );
      if (_teacherId == teacherId && identical(_teacherDraft, draft)) {
        _teacherDraft = draft.copyWith(
          version: returnedScheduleVersion(result, draft.version),
        );
      }
    });
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

  bool get _canEditAvailability => canEdit && !availabilityLocked;

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
