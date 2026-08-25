/// v4 structured constraint contract for lesson creation.
class LessonConstraintViolation {
  final String code;
  final String resourceType;
  final String resourceId;
  final List<String> conflictingLessonIds;
  final List<String> ruleIds;

  const LessonConstraintViolation({
    required this.code,
    required this.resourceType,
    required this.resourceId,
    required this.conflictingLessonIds,
    required this.ruleIds,
  });

  factory LessonConstraintViolation.fromJson(Map<String, dynamic> json) {
    final resource = json['resource'];
    final resourceMap = resource is Map
        ? Map<String, dynamic>.from(resource)
        : const <String, dynamic>{};
    return LessonConstraintViolation(
      code: json['code']?.toString() ?? 'UNKNOWN_CONSTRAINT',
      resourceType: resourceMap['type']?.toString() ?? 'resource',
      resourceId: resourceMap['id']?.toString() ?? '',
      conflictingLessonIds: [
        for (final id in (json['conflictingLessonIds'] as List? ?? const []))
          id.toString(),
      ],
      ruleIds: [
        for (final id in (json['ruleIds'] as List? ?? const [])) id.toString(),
      ],
    );
  }

  String get title => switch (code) {
    'INVALID_INTERVAL' => 'Некорректное время занятия',
    'OUTSIDE_BRANCH_HOURS' => 'Филиал закрыт в это время',
    'TEACHER_UNAVAILABLE' => 'Преподаватель недоступен',
    'TEACHER_BRANCH_MISMATCH' => 'Преподаватель не назначен в филиал',
    'ROOM_BRANCH_MISMATCH' => 'Аудитория относится к другому филиалу',
    'TEACHER_OVERLAP' => 'У преподавателя уже есть занятие',
    'CLIENT_OVERLAP' => 'У клиента уже есть занятие',
    'ROOM_OVERLAP' => 'Аудитория уже занята',
    _ => 'Не удалось проверить одно из ограничений расписания',
  };

  String get resourceLabel => switch (resourceType) {
    'branch' => 'Филиал',
    'teacher' => 'Преподаватель',
    'client' => 'Клиент',
    'room' => 'Аудитория',
    'interval' => 'Интервал',
    _ => 'Ресурс',
  };
}

class ScheduleSuggestion {
  final String kind;
  final int rank;
  final int score;
  final String? roomId;
  final String? roomName;
  final String? teacherId;
  final String? teacherName;
  final DateTime? startAt;
  final int? startOffsetMinutes;

  const ScheduleSuggestion({
    required this.kind,
    required this.rank,
    required this.score,
    this.roomId,
    this.roomName,
    this.teacherId,
    this.teacherName,
    this.startAt,
    this.startOffsetMinutes,
  });

  factory ScheduleSuggestion.fromJson(Map<String, dynamic> json) {
    final changes = json['changes'];
    final map = changes is Map
        ? Map<String, dynamic>.from(changes)
        : const <String, dynamic>{};
    return ScheduleSuggestion(
      kind: json['kind']?.toString() ?? 'COMBINED',
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toInt() ?? 0,
      roomId: map['roomId']?.toString(),
      roomName: map['roomName']?.toString(),
      teacherId: map['teacherId']?.toString(),
      teacherName: map['teacherName']?.toString(),
      startAt: DateTime.tryParse(map['startAt']?.toString() ?? '')?.toLocal(),
      startOffsetMinutes: (map['startOffsetMinutes'] as num?)?.toInt(),
    );
  }

  String get title => switch (kind) {
    'SAME_TIME_ROOM' => 'Свободная аудитория в то же время',
    'NEAREST_TIME' => 'Ближайшее свободное время',
    'SAME_SPECIALIZATION_TEACHER' =>
      'Свободный преподаватель по этому предмету',
    _ => 'Комбинированный вариант',
  };
}

class LessonScheduleAnalysis {
  final bool valid;
  final List<LessonConstraintViolation> violations;
  final List<ScheduleSuggestion> suggestions;

  const LessonScheduleAnalysis({
    required this.valid,
    required this.violations,
    required this.suggestions,
  });

  const LessonScheduleAnalysis.fromViolations(this.violations)
    : valid = false,
      suggestions = const [];

  factory LessonScheduleAnalysis.fromJson(Map<String, dynamic> json) {
    final violations = [
      for (final item in (json['violations'] as List? ?? const []))
        if (item is Map)
          LessonConstraintViolation.fromJson(Map<String, dynamic>.from(item)),
    ];
    final suggestions = [
      for (final item in (json['suggestions'] as List? ?? const []))
        if (item is Map)
          ScheduleSuggestion.fromJson(Map<String, dynamic>.from(item)),
    ];
    return LessonScheduleAnalysis(
      valid: json['valid'] == true,
      violations: violations,
      suggestions: suggestions,
    );
  }
}

List<LessonConstraintViolation>? lessonConstraintViolationsFromDetails(
  Object? details,
) {
  if (details is! Map) return null;
  final raw = details['violations'];
  if (raw is! List) return null;
  return [
    for (final item in raw)
      if (item is Map)
        LessonConstraintViolation.fromJson(Map<String, dynamic>.from(item)),
  ];
}
