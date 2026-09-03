import 'dart:collection';

const _unset = Object();

class PreferredScheduleEditorState {
  PreferredScheduleEditorState({
    required this.branchId,
    required Set<int> weekdays,
    required this.beginTime,
    required this.durationMinutes,
    required this.lessonsPerDay,
    required this.validFrom,
    required this.validUntil,
    required this.teacherId,
    required this.roomId,
    required this.subscriptionId,
    required this.settlementTypeKey,
    required this.teacherCompensationRuleKey,
    required this.teacherCreditedDurationInput,
    required this.teacherCompensationSource,
    required this.compensationTouched,
    required List<Map<String, dynamic>> clientDecisions,
    required this.openEnded,
    this.validationError,
  }) : weekdays = UnmodifiableSetView(Set<int>.of(weekdays)),
       clientDecisions = UnmodifiableListView([
         for (final item in clientDecisions)
           Map<String, dynamic>.unmodifiable(item),
       ]);

  final String branchId;
  final Set<int> weekdays;
  final String beginTime;
  final int durationMinutes;
  final int lessonsPerDay;
  final DateTime validFrom;
  final DateTime validUntil;
  final String? teacherId;
  final String? roomId;
  final String? subscriptionId;
  final String? settlementTypeKey;
  final String? teacherCompensationRuleKey;
  final String? teacherCreditedDurationInput;
  final String? teacherCompensationSource;
  final bool compensationTouched;
  final List<Map<String, dynamic>> clientDecisions;
  final bool openEnded;
  final String? validationError;

  PreferredScheduleEditorState copyWith({
    String? branchId,
    Set<int>? weekdays,
    String? beginTime,
    int? durationMinutes,
    int? lessonsPerDay,
    DateTime? validFrom,
    DateTime? validUntil,
    Object? teacherId = _unset,
    Object? roomId = _unset,
    Object? subscriptionId = _unset,
    Object? settlementTypeKey = _unset,
    Object? teacherCompensationRuleKey = _unset,
    Object? teacherCreditedDurationInput = _unset,
    Object? teacherCompensationSource = _unset,
    bool? compensationTouched,
    List<Map<String, dynamic>>? clientDecisions,
    bool? openEnded,
    Object? validationError = _unset,
  }) => PreferredScheduleEditorState(
    branchId: branchId ?? this.branchId,
    weekdays: weekdays ?? this.weekdays,
    beginTime: beginTime ?? this.beginTime,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    lessonsPerDay: lessonsPerDay ?? this.lessonsPerDay,
    validFrom: validFrom ?? this.validFrom,
    validUntil: validUntil ?? this.validUntil,
    teacherId: identical(teacherId, _unset)
        ? this.teacherId
        : teacherId as String?,
    roomId: identical(roomId, _unset) ? this.roomId : roomId as String?,
    subscriptionId: identical(subscriptionId, _unset)
        ? this.subscriptionId
        : subscriptionId as String?,
    settlementTypeKey: identical(settlementTypeKey, _unset)
        ? this.settlementTypeKey
        : settlementTypeKey as String?,
    teacherCompensationRuleKey: identical(teacherCompensationRuleKey, _unset)
        ? this.teacherCompensationRuleKey
        : teacherCompensationRuleKey as String?,
    teacherCreditedDurationInput:
        identical(teacherCreditedDurationInput, _unset)
        ? this.teacherCreditedDurationInput
        : teacherCreditedDurationInput as String?,
    teacherCompensationSource: identical(teacherCompensationSource, _unset)
        ? this.teacherCompensationSource
        : teacherCompensationSource as String?,
    compensationTouched: compensationTouched ?? this.compensationTouched,
    clientDecisions: clientDecisions ?? this.clientDecisions,
    openEnded: openEnded ?? this.openEnded,
    validationError: identical(validationError, _unset)
        ? this.validationError
        : validationError as String?,
  );
}
