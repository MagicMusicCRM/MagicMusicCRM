class PreferredScheduleDraft {
  const PreferredScheduleDraft({
    required this.branchId,
    required this.weekdays,
    required this.beginTime,
    required this.durationMinutes,
    required this.lessonsPerDay,
    required this.validFrom,
    required this.validUntil,
    required this.teacherId,
    required this.roomId,
    required this.notes,
    this.seriesId,
    this.title,
    this.subscriptionId,
    this.settlementTypeKey = '',
    this.teacherCompensationRuleKey = '',
    this.openEnded = false,
  });

  final String branchId;
  final Set<int> weekdays;
  final String beginTime;
  final int durationMinutes;
  final int lessonsPerDay;
  final DateTime validFrom;
  final DateTime validUntil;
  final String teacherId;
  final String roomId;
  final String notes;
  final String? seriesId;
  final String? title;
  final String? subscriptionId;
  final String settlementTypeKey;
  final String teacherCompensationRuleKey;
  final bool openEnded;

  PreferredScheduleDraft copyWith({
    String? branchId,
    Set<int>? weekdays,
    String? beginTime,
    int? durationMinutes,
    int? lessonsPerDay,
    DateTime? validFrom,
    DateTime? validUntil,
    String? teacherId,
    String? roomId,
    String? notes,
    String? seriesId,
    String? title,
    String? subscriptionId,
    String? settlementTypeKey,
    String? teacherCompensationRuleKey,
    bool? openEnded,
  }) => PreferredScheduleDraft(
    branchId: branchId ?? this.branchId,
    weekdays: weekdays ?? this.weekdays,
    beginTime: beginTime ?? this.beginTime,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    lessonsPerDay: lessonsPerDay ?? this.lessonsPerDay,
    validFrom: validFrom ?? this.validFrom,
    validUntil: validUntil ?? this.validUntil,
    teacherId: teacherId ?? this.teacherId,
    roomId: roomId ?? this.roomId,
    notes: notes ?? this.notes,
    seriesId: seriesId ?? this.seriesId,
    title: title ?? this.title,
    subscriptionId: subscriptionId ?? this.subscriptionId,
    settlementTypeKey: settlementTypeKey ?? this.settlementTypeKey,
    teacherCompensationRuleKey:
        teacherCompensationRuleKey ?? this.teacherCompensationRuleKey,
    openEnded: openEnded ?? this.openEnded,
  );
}
