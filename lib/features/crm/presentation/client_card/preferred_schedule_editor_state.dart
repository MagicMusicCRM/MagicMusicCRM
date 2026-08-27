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
    required this.openEnded,
    this.validationError,
  }) : weekdays = UnmodifiableSetView(Set<int>.of(weekdays));

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
    openEnded: openEnded ?? this.openEnded,
    validationError: identical(validationError, _unset)
        ? this.validationError
        : validationError as String?,
  );
}
