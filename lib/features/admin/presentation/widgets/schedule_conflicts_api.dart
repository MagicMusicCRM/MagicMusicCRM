import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';

/// Legacy busy-slot preview plus the v4 structured constraint contract.
///
/// Живёт расширением на [MagicApiClient] рядом с расписанием, а не в общем
/// ядре сервисов: единственные потребители — диалог занятия и дневная сетка.

class ScheduleConflictInfo {
  final String? lessonId;
  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? roomName;
  final String? teacherName;

  const ScheduleConflictInfo({
    required this.title,
    this.lessonId,
    this.startsAt,
    this.endsAt,
    this.roomName,
    this.teacherName,
  });

  factory ScheduleConflictInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString());
    final title = json['title']?.toString().trim();
    String? text(Object? value) {
      final s = value?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return ScheduleConflictInfo(
      lessonId: text(json['lessonId']),
      title: (title == null || title.isEmpty) ? 'Занятие' : title,
      startsAt: parseTime(json['startsAt']),
      endsAt: parseTime(json['endsAt']),
      roomName: text(json['roomName']),
      teacherName: text(json['teacherName']),
    );
  }

  /// «Кто · когда · где» одной строкой для диалога конфликтов. Время — в поясе
  /// Москвы (UTC+3), как и остальные времена расписания.
  String label({int utcOffsetMinutes = 180}) {
    String two(int v) => v.toString().padLeft(2, '0');
    String? hhmm(DateTime? t) {
      if (t == null) return null;
      final local = t.toUtc().add(Duration(minutes: utcOffsetMinutes));
      return '${two(local.hour)}:${two(local.minute)}';
    }

    final from = hhmm(startsAt);
    final to = hhmm(endsAt);
    return [
      title,
      if (from != null) to == null ? from : '$from–$to',
      ?teacherName,
      ?roomName,
    ].join(' · ');
  }
}

/// Разбирает `conflicts` из тела 409 (контракт 2: занятый педагог/аудитория).
/// Возвращает null, если это не «наш» 409 — тогда ошибка идёт обычным путём.
List<ScheduleConflictInfo>? scheduleConflictsFrom409(MagicApiException error) {
  if (error.statusCode != 409) return null;
  final details = error.details;
  if (details is! Map) return null;
  final raw = details['conflicts'];
  if (raw is! List) return null;
  return [
    for (final item in raw)
      if (item is Map)
        ScheduleConflictInfo.fromJson(Map<String, dynamic>.from(item)),
  ];
}

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
    'TEACHER_OVERLAP' => 'У преподавателя уже есть занятие',
    'CLIENT_OVERLAP' => 'У клиента уже есть занятие',
    'ROOM_OVERLAP' => 'Аудитория уже занята',
    _ => 'Ограничение расписания: $code',
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

/// Parses the authoritative v4 create/edit/drag response. Unlike the old
/// `conflicts` payload, all violations can arrive together and every overlap
/// contains stable lesson ids suitable for a UI link.
List<LessonConstraintViolation>? lessonConstraintViolations(
  MagicApiException error,
) {
  final details = error.details;
  if (details is! Map) return null;
  final raw = details['violations'];
  if (raw is! List) return null;
  return [
    for (final item in raw)
      if (item is Map)
        LessonConstraintViolation.fromJson(Map<String, dynamic>.from(item)),
  ];
}

extension ScheduleConflictsApi on MagicApiClient {
  Future<List<LessonConstraintViolation>> previewLessonConstraints({
    required String clientType,
    required String clientId,
    required String teacherId,
    required String branchId,
    required String roomId,
    required String scheduledAt,
    required int durationMinutes,
    String? excludeLessonId,
  }) async {
    final response = await post<Map<String, dynamic>>(
      '/crm/lessons/constraints/preview',
      data: {
        'clientRef': {'type': clientType, 'id': clientId},
        'teacherId': teacherId,
        'branchId': branchId,
        'roomId': roomId,
        'scheduledAt': scheduledAt,
        'durationMinutes': durationMinutes,
        'excludeLessonId': ?excludeLessonId,
      },
    );
    final raw = response['violations'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          LessonConstraintViolation.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  /// POST /crm/lessons with a complete v4 draft. Mutation metadata is attached
  /// centrally by [MagicApiClient] and no business role can bypass violations.
  Future<Map<String, dynamic>> createLessonRaw(Map<String, dynamic> data) {
    return post<Map<String, dynamic>>('/crm/lessons', data: data);
  }

  /// PATCH /crm/lessons/:id c готовым DTO-телом (см. [createLessonRaw]).
  Future<Map<String, dynamic>> updateLessonRaw(
    String lessonId,
    Map<String, dynamic> data,
  ) {
    return patch<Map<String, dynamic>>('/crm/lessons/$lessonId', data: data);
  }
}
