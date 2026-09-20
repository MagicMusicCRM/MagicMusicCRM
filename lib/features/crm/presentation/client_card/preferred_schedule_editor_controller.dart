import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_financial_autofill.dart';

import 'preferred_schedule_draft.dart';
import 'preferred_schedule_editor_state.dart';

export 'preferred_schedule_editor_state.dart';

class PreferredScheduleEditorController extends ChangeNotifier {
  PreferredScheduleEditorController({
    required this.branches,
    required this.teachers,
    required this.rooms,
    required this.defaultBranchId,
    this.series,
    this.planMode = false,
    this.initialDraft,
    this.subscriptionOptions = const [],
    this.initialSubscriptionId,
    this.requireSubscription = false,
    this.allowOpenEnded = false,
    this.decisionCatalogs = const {},
    this.requireFinancialDecision = false,
    this.canManageTeacherCompensation = false,
    this.initialClientDecisions = const [],
  });

  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> rooms;
  final String? defaultBranchId;
  final Map<String, dynamic>? series;
  final bool planMode;
  final PreferredScheduleDraft? initialDraft;
  final List<Map<String, dynamic>> subscriptionOptions;
  final String? initialSubscriptionId;
  final bool requireSubscription;
  final bool allowOpenEnded;
  final Map<String, LessonDecisionCatalog> decisionCatalogs;
  final bool requireFinancialDecision;
  final bool canManageTeacherCompensation;
  final List<Map<String, dynamic>> initialClientDecisions;

  static const _autofill = LessonFinancialAutofill();

  late PreferredScheduleEditorState _state;

  PreferredScheduleEditorState get state => _state;
  bool get isEdit => series != null;
  LessonDecisionCatalog? get decisionCatalog =>
      decisionCatalogs[_state.branchId];

  List<Map<String, dynamic>> get teachersForBranch => teachers
      .where((teacher) => _teacherBelongsToBranch(teacher, _state.branchId))
      .toList(growable: false);

  List<Map<String, dynamic>> get roomsForBranch => rooms
      .where((room) => room['branch_id']?.toString() == _state.branchId)
      .toList(growable: false);

  void initialize({DateTime? now}) {
    final current = now ?? DateTime.now();
    final today = _dateOnly(current);
    final branchId = _initialBranchId();
    final requestedStart =
        _date(series?['valid_from']) ??
        initialDraft?.validFrom ??
        today.add(const Duration(days: 1));
    final validFrom = isEdit && !planMode && requestedStart.isBefore(today)
        ? today
        : requestedStart;
    var validUntil =
        _date(series?['valid_until']) ??
        initialDraft?.validUntil ??
        validFrom.add(const Duration(days: 90));
    if (validUntil.isBefore(validFrom)) {
      validUntil = validFrom.add(const Duration(days: 90));
    }
    final seriesDecision = Map<String, dynamic>.from(
      series?['financial_decision'] as Map? ?? const {},
    );
    _state = PreferredScheduleEditorState(
      branchId: branchId,
      weekdays: _initialWeekdays(current.weekday),
      beginTime:
          series?['begin_time']?.toString() ??
          initialDraft?.beginTime ??
          '15:00',
      durationMinutes:
          (series?['duration_minutes'] as num?)?.toInt() ??
          initialDraft?.durationMinutes ??
          60,
      lessonsPerDay: initialDraft?.lessonsPerDay ?? 1,
      validFrom: validFrom,
      validUntil: validUntil,
      teacherId: series?['teacher_id']?.toString() ?? initialDraft?.teacherId,
      roomId: series?['room_id']?.toString() ?? initialDraft?.roomId,
      subscriptionId: _initialSubscriptionId(),
      settlementTypeKey:
          seriesDecision['settlementTypeKey']?.toString() ??
          initialDraft?.settlementTypeKey,
      teacherCompensationRuleKey:
          seriesDecision['teacherCompensationRuleKey']?.toString() ??
          initialDraft?.teacherCompensationRuleKey,
      teacherCreditedDurationInput:
          seriesDecision['teacherCreditedDurationMinutes']?.toString() ??
          initialDraft?.teacherCreditedDurationMinutes?.toString(),
      teacherCompensationSource:
          seriesDecision['teacherCompensationSource']?.toString() ??
          initialDraft?.teacherCompensationSource,
      compensationTouched:
          (seriesDecision['teacherCompensationSource']?.toString() ??
              initialDraft?.teacherCompensationSource) ==
          'manual',
      clientDecisions: _initialClientDecisions(seriesDecision),
      openEnded:
          allowOpenEnded &&
          (series == null
              ? initialDraft?.openEnded ?? true
              : series?['valid_until'] == null),
    );
    if (seriesDecision.isEmpty) {
      _syncDecisionForBranch();
    }
    _clearInvalidResources();
  }

  List<Map<String, dynamic>> _initialClientDecisions(
    Map<String, dynamic> seriesDecision,
  ) => [
    for (final item
        in (seriesDecision['clientDecisions'] as List? ??
            initialDraft?.clientDecisions ??
            initialClientDecisions))
      if (item is Map) Map<String, dynamic>.from(item),
  ];

  String _initialBranchId() {
    final ids = branches
        .map((branch) => branch['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final preferred =
        series?['branch_id']?.toString() ??
        initialDraft?.branchId ??
        defaultBranchId;
    if (ids.contains(preferred)) return preferred!;
    return ids.isEmpty ? '' : ids.first;
  }

  Set<int> _initialWeekdays(int currentWeekday) => series == null
      ? Set<int>.of(initialDraft?.weekdays ?? {currentWeekday})
      : {(series?['weekday'] as num?)?.toInt() ?? currentWeekday};

  String? _initialSubscriptionId() {
    final preferred = initialSubscriptionId ?? initialDraft?.subscriptionId;
    if (subscriptionOptions.any(
      (option) => option['id']?.toString() == preferred,
    )) {
      return preferred;
    }
    return subscriptionOptions.isEmpty
        ? null
        : subscriptionOptions.first['id']?.toString();
  }

  void _clearInvalidResources() {
    final roomValid = roomsForBranch.any(
      (room) => room['id']?.toString() == _state.roomId,
    );
    final teacherValid = teachersForBranch.any(
      (teacher) => teacher['id']?.toString() == _state.teacherId,
    );
    _state = _state.copyWith(
      roomId: roomValid ? _state.roomId : null,
      teacherId: teacherValid ? _state.teacherId : null,
    );
  }

  bool _teacherBelongsToBranch(Map<String, dynamic> teacher, String branchId) {
    if (teacher['status']?.toString() != 'active') return false;
    final assignments = teacher['assigned_branches'];
    return assignments is List &&
        assignments.whereType<Map>().any(
          (branch) => branch['id']?.toString() == branchId,
        );
  }

  void _syncDecisionForBranch() {
    final catalog = decisionCatalog;
    if (catalog == null) return;
    final settlementValid = catalog.settlementTypes.any(
      (item) => item.key == _state.settlementTypeKey,
    );
    final compensationValid = catalog.compensationRules.any(
      (item) => item.key == _state.teacherCompensationRuleKey,
    );
    final settlementKey = settlementValid
        ? _state.settlementTypeKey
        : _firstKey(catalog.settlementTypes);
    final settlement = _settlement(settlementKey);
    final fallbackRule =
        catalog.compensationRules
            .where((item) => item.mode == 'standard')
            .firstOrNull
            ?.key ??
        _firstKey(catalog.compensationRules);
    if (settlement == null) {
      _state = _state.copyWith(
        settlementTypeKey: settlementKey,
        teacherCompensationRuleKey: compensationValid
            ? _state.teacherCompensationRuleKey
            : fallbackRule,
      );
      return;
    }
    final hasAutofillMetadata =
        settlement.defaultTeacherCompensationRuleKey != null ||
        settlement.teacherDurationMode != null;
    final shouldRecommend =
        hasAutofillMetadata && (!settlementValid || !compensationValid);
    final recommendation = shouldRecommend
        ? _autofill.apply(
            settlement: settlement,
            durationMinutes: _state.durationMinutes,
            compensationTouched: _state.compensationTouched,
            currentRuleKey: _state.teacherCompensationRuleKey,
            currentTeacherMinutes: int.tryParse(
              _state.teacherCreditedDurationInput ?? '',
            ),
          )
        : null;
    _state = _state.copyWith(
      settlementTypeKey: settlementKey,
      teacherCompensationRuleKey:
          recommendation?.compensationRuleKey ??
          (compensationValid
              ? _state.teacherCompensationRuleKey
              : fallbackRule),
      teacherCreditedDurationInput:
          recommendation?.teacherCreditedDurationMinutes?.toString() ??
          _state.teacherCreditedDurationInput,
      teacherCompensationSource:
          recommendation?.source ?? _state.teacherCompensationSource,
    );
  }

  LessonDecisionCatalogItem? _settlement(String? key) => decisionCatalog
      ?.settlementTypes
      .where((item) => item.key == key)
      .firstOrNull;

  String? _firstKey(List<LessonDecisionCatalogItem> items) =>
      items.isEmpty ? null : items.first.key;

  void selectBranch(String value) {
    _state = _state.copyWith(
      branchId: value,
      teacherId: null,
      roomId: null,
      validationError: null,
    );
    _syncDecisionForBranch();
    notifyListeners();
  }

  void toggleWeekday(int day, bool selected) {
    final weekdays = Set<int>.of(_state.weekdays);
    selected ? weekdays.add(day) : weekdays.remove(day);
    _update(_state.copyWith(weekdays: weekdays));
  }

  void setBeginTime(String value) => _update(_state.copyWith(beginTime: value));
  void selectDurationMinutes(int value) {
    var next = _state.copyWith(durationMinutes: value);
    final settlement = _settlement(next.settlementTypeKey);
    if (settlement != null && !next.compensationTouched) {
      final recommendation = _autofill.apply(
        settlement: settlement,
        durationMinutes: value,
        compensationTouched: false,
        currentRuleKey: next.teacherCompensationRuleKey,
        currentTeacherMinutes: int.tryParse(
          next.teacherCreditedDurationInput ?? '',
        ),
      );
      next = next.copyWith(
        teacherCompensationRuleKey: recommendation.compensationRuleKey,
        teacherCreditedDurationInput: recommendation
            .teacherCreditedDurationMinutes
            ?.toString(),
        teacherCompensationSource: recommendation.source,
      );
    }
    next = next.copyWith(
      clientDecisions: _recomputeInheritedClientMinutes(
        next.clientDecisions,
        settlement,
        value,
        clearManual: false,
      ),
    );
    _update(next);
  }

  void selectLessonsPerDay(int value) =>
      _update(_state.copyWith(lessonsPerDay: value));
  void selectTeacher(String? value) =>
      _update(_state.copyWith(teacherId: value));
  void selectRoom(String? value) => _update(_state.copyWith(roomId: value));
  void selectSubscription(String? value) =>
      _update(_state.copyWith(subscriptionId: value));
  void selectSettlementType(String? value) {
    final settlement = _settlement(value);
    var next = _state.copyWith(settlementTypeKey: value);
    if (settlement != null) {
      final recommendation = _autofill.apply(
        settlement: settlement,
        durationMinutes: next.durationMinutes,
        compensationTouched: next.compensationTouched,
        currentRuleKey: next.teacherCompensationRuleKey,
        currentTeacherMinutes: int.tryParse(
          next.teacherCreditedDurationInput ?? '',
        ),
      );
      next = next.copyWith(
        teacherCompensationRuleKey: recommendation.compensationRuleKey,
        teacherCreditedDurationInput: recommendation
            .teacherCreditedDurationMinutes
            ?.toString(),
        teacherCompensationSource: recommendation.source,
        clientDecisions: _recomputeInheritedClientMinutes(
          next.clientDecisions,
          settlement,
          next.durationMinutes,
        ),
      );
    }
    _update(next);
  }

  List<Map<String, dynamic>> _recomputeInheritedClientMinutes(
    List<Map<String, dynamic>> decisions,
    LessonDecisionCatalogItem? settlement,
    int durationMinutes, {
    bool clearManual = true,
  }) {
    if (settlement == null) return decisions;
    final minutes = _autofill.recommendedClientMinutes(
      settlement: settlement,
      durationMinutes: durationMinutes,
    );
    return [
      for (final decision in decisions)
        _recomputedClientDecision(decision, minutes, clearManual),
    ];
  }

  Map<String, dynamic> _recomputedClientDecision(
    Map<String, dynamic> decision,
    int? minutes,
    bool clearManual,
  ) {
    final copy = Map<String, dynamic>.from(decision);
    if (copy['settlementTypeKey'] != null) return copy;
    if (minutes != null) {
      copy['chargeDurationMinutes'] = minutes;
    } else if (clearManual) {
      copy.remove('chargeDurationMinutes');
    }
    return copy;
  }

  void selectTeacherCompensationRule(String? value) {
    if (!canManageTeacherCompensation) return;
    _update(
      _state.copyWith(
        teacherCompensationRuleKey: value,
        compensationTouched: true,
        teacherCompensationSource: 'manual',
      ),
    );
  }

  void setTeacherCreditedDurationInput(String value) {
    if (!canManageTeacherCompensation) return;
    _update(
      _state.copyWith(
        teacherCreditedDurationInput: value,
        compensationTouched: true,
        teacherCompensationSource: 'manual',
      ),
    );
  }

  void setClientChargeDurationInput(String clientId, String value) {
    _update(
      _state.copyWith(
        clientDecisions: [
          for (final decision in _state.clientDecisions)
            if (decision['clientId']?.toString() == clientId)
              {...decision, 'chargeDurationMinutes': value}
            else
              Map<String, dynamic>.from(decision),
        ],
      ),
    );
  }

  void applyRecommendedTeacherCompensation() {
    final settlement = _settlement(_state.settlementTypeKey);
    if (settlement == null) return;
    final recommendation = _autofill.restoreRecommendation(
      settlement: settlement,
      durationMinutes: _state.durationMinutes,
    );
    _update(
      _state.copyWith(
        teacherCompensationRuleKey: recommendation.compensationRuleKey,
        teacherCreditedDurationInput: recommendation
            .teacherCreditedDurationMinutes
            ?.toString(),
        teacherCompensationSource: recommendation.source,
        compensationTouched: false,
      ),
    );
  }

  void setOpenEnded(bool value) => _update(_state.copyWith(openEnded: value));

  void setValidFrom(DateTime value) {
    final validFrom = _dateOnly(value);
    final validUntil = _state.validUntil.isBefore(validFrom)
        ? validFrom
        : _state.validUntil;
    _update(_state.copyWith(validFrom: validFrom, validUntil: validUntil));
  }

  void setValidUntil(DateTime value) =>
      _update(_state.copyWith(validUntil: _dateOnly(value)));

  void clearValidationError() {
    if (_state.validationError == null) return;
    _update(_state);
  }

  void _update(PreferredScheduleEditorState next) {
    _state = next.copyWith(validationError: null);
    notifyListeners();
  }

  bool validate({required String title}) {
    final error =
        _identityValidationError(title) ??
        _resourceValidationError() ??
        _scheduleError();
    _state = _state.copyWith(validationError: error);
    notifyListeners();
    return error == null;
  }

  String? _identityValidationError(String title) {
    if (_state.branchId.isEmpty) return 'Выберите филиал.';
    if (planMode && title.trim().isEmpty) {
      return 'Укажите название расписания.';
    }
    if (requireSubscription && _state.subscriptionId == null) {
      return 'Выберите абонемент.';
    }
    if (_state.weekdays.isEmpty) {
      return 'Выберите хотя бы один день недели.';
    }
    return null;
  }

  String? _resourceValidationError() {
    if (_state.teacherId == null || _state.teacherId!.isEmpty) {
      return 'Выберите педагога.';
    }
    if (_state.roomId == null || _state.roomId!.isEmpty) {
      return 'Выберите аудиторию.';
    }
    return _financialDecisionError();
  }

  String? _financialDecisionError() {
    if (!planMode && !requireFinancialDecision) return null;
    if (_state.settlementTypeKey == null || _state.settlementTypeKey!.isEmpty) {
      return 'Выберите тип списания.';
    }
    if (canManageTeacherCompensation &&
        (_state.teacherCompensationRuleKey == null ||
            _state.teacherCompensationRuleKey!.isEmpty)) {
      return 'Выберите оплату преподавателю.';
    }
    final settlement = _settlement(_state.settlementTypeKey);
    if (canManageTeacherCompensation &&
        (settlement?.teacherDurationMode == 'manual' ||
            (_state.teacherCompensationSource == 'manual' &&
                (_state.teacherCreditedDurationInput?.isNotEmpty ?? false)))) {
      final error = partialDurationError(
        _state.teacherCreditedDurationInput,
        lessonDurationMinutes: _state.durationMinutes,
      );
      if (error != null) return error;
    }
    for (final decision in _state.clientDecisions) {
      final effective = _settlement(
        decision['settlementTypeKey']?.toString() ?? _state.settlementTypeKey,
      );
      if (effective?.clientDurationMode != 'manual') continue;
      final error = partialDurationError(
        decision['chargeDurationMinutes']?.toString(),
        lessonDurationMinutes: _state.durationMinutes,
      );
      if (error != null) return error;
    }
    return null;
  }

  String? _scheduleError() {
    if (!_state.openEnded && _state.validUntil.isBefore(_state.validFrom)) {
      return 'Дата окончания не может быть раньше даты начала.';
    }
    final parts = _state.beginTime.split(':');
    final minutes =
        (int.tryParse(parts.first) ?? 0) * 60 + (int.tryParse(parts.last) ?? 0);
    if (minutes + _state.durationMinutes * _state.lessonsPerDay > 24 * 60) {
      return 'Последнее занятие выходит за границы выбранного дня.';
    }
    return null;
  }

  PreferredScheduleDraft buildDraft({
    required String title,
    required String notes,
  }) => PreferredScheduleDraft(
    branchId: _state.branchId,
    weekdays: Set<int>.unmodifiable(_state.weekdays),
    beginTime: _state.beginTime,
    durationMinutes: _state.durationMinutes,
    lessonsPerDay: _state.lessonsPerDay,
    validFrom: _state.validFrom,
    validUntil: _state.validUntil,
    teacherId: _state.teacherId ?? '',
    roomId: _state.roomId ?? '',
    notes: notes.trim(),
    seriesId: initialDraft?.seriesId ?? series?['id']?.toString(),
    title: planMode ? title.trim() : null,
    subscriptionId: _state.subscriptionId,
    settlementTypeKey: _state.settlementTypeKey ?? '',
    teacherCompensationRuleKey: _state.teacherCompensationRuleKey ?? '',
    teacherCreditedDurationMinutes: int.tryParse(
      _state.teacherCreditedDurationInput ?? '',
    ),
    teacherCompensationSource: _state.teacherCompensationSource,
    clientDecisions: lessonClientDecisionsPayload(_state.clientDecisions),
    openEnded: _state.openEnded,
  );

  DateTime? _date(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null ? null : _dateOnly(parsed);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
