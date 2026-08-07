import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';

/// v4 structured constraint contract for lesson creation.
///
/// Живёт расширением на [MagicApiClient] рядом с расписанием, а не в общем
/// ядре сервисов: единственные потребители — диалог занятия и дневная сетка.

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
}
