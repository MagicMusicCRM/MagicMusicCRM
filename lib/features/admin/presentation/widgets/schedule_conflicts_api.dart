import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';

/// Контракт 1/2 (правки №2, п.6): проверка занятости педагога и аудитории
/// перед сохранением занятия + пересоздание с `force: true` после
/// подтверждения «Всё равно назначить».
///
/// Живёт расширением на [MagicApiClient] рядом с расписанием, а не в общем
/// ядре сервисов: единственные потребители — диалог занятия и дневная сетка.

/// Роли, которым разрешено назначать занятие в занятый слот (admin+; сервер
/// гейтит то же самое, кнопка лишь не обещает лишнего).
const Set<String> kScheduleForceRoles = {
  'admin',
  'manager',
  'director',
  'system_admin',
};

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

class ScheduleConflictCheck {
  final bool teacherBusy;
  final bool roomBusy;
  final List<ScheduleConflictInfo> conflicts;

  const ScheduleConflictCheck({
    required this.teacherBusy,
    required this.roomBusy,
    required this.conflicts,
  });

  bool get hasConflicts => teacherBusy || roomBusy || conflicts.isNotEmpty;

  factory ScheduleConflictCheck.fromJson(Map<String, dynamic> json) {
    final raw = json['conflicts'];
    return ScheduleConflictCheck(
      teacherBusy: json['teacherBusy'] == true,
      roomBusy: json['roomBusy'] == true,
      conflicts: raw is! List
          ? const []
          : [
              for (final item in raw)
                if (item is Map)
                  ScheduleConflictInfo.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
            ],
    );
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

extension ScheduleConflictsApi on MagicApiClient {
  /// GET /crm/schedule/conflicts — занят ли педагог/аудитория в окне
  /// [startsAt, endsAt). Admin+ only на сервере; читающие ошибки здесь не
  /// глотаются — вызывающий сам решает, что fail-open (до ребилда сервера
  /// маршрута нет, и проверка не должна блокировать создание занятий).
  Future<ScheduleConflictCheck> checkScheduleConflicts({
    String? teacherId,
    String? roomId,
    required String startsAt,
    required String endsAt,
    String? excludeLessonId,
  }) async {
    final response = await get<Map<String, dynamic>>(
      '/crm/schedule/conflicts',
      queryParameters: {
        if (teacherId != null && teacherId.isNotEmpty) 'teacherId': teacherId,
        if (roomId != null && roomId.isNotEmpty) 'roomId': roomId,
        'startsAt': startsAt,
        'endsAt': endsAt,
        if (excludeLessonId != null && excludeLessonId.isNotEmpty)
          'excludeLessonId': excludeLessonId,
      },
    );
    return ScheduleConflictCheck.fromJson(response);
  }

  /// POST /crm/lessons c готовым DTO-телом; `force: true` — после
  /// подтверждения «Всё равно назначить» (admin+).
  Future<Map<String, dynamic>> createLessonRaw(
    Map<String, dynamic> data, {
    bool force = false,
  }) {
    return post<Map<String, dynamic>>(
      '/crm/lessons',
      data: {...data, if (force) 'force': true},
    );
  }

  /// PATCH /crm/lessons/:id c готовым DTO-телом (см. [createLessonRaw]).
  Future<Map<String, dynamic>> updateLessonRaw(
    String lessonId,
    Map<String, dynamic> data, {
    bool force = false,
  }) {
    return patch<Map<String, dynamic>>(
      '/crm/lessons/$lessonId',
      data: {...data, if (force) 'force': true},
    );
  }
}
