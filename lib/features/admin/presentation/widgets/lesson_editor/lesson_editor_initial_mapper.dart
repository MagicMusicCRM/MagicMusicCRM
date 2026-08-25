import 'lesson_editor_models.dart';

class LessonEditorInitialMapper {
  const LessonEditorInitialMapper();

  LessonEditorSession map(LessonEditorInitialInput input) {
    final lesson = input.lesson;
    final constructorClient = _constructorClient(input);
    final client = lesson == null
        ? constructorClient
        : _editClient(lesson) ?? constructorClient;
    final localStart = _localStart(input, lesson);
    final durationMinutes = _durationMinutes(input, lesson);
    final compensationRuleKey = _text(
      lesson,
      'teacher_compensation_rule_key',
      'teacherCompensationRuleKey',
    );
    final compensationValueMinor = _text(
      lesson,
      'teacher_compensation_value_minor',
      'teacherCompensationValueMinor',
    );
    final draft = LessonEditorDraft(
      localStart: localStart,
      durationMinutes: durationMinutes,
      isTrial: lesson == null
          ? input.initialIsTrial
          : lesson['snapshot_trial'] == true || lesson['is_trial'] == true,
      completionType: _text(lesson, 'completion_type') ?? 'standard.success',
      clientChargeType: _text(lesson, 'client_charge_type') ?? 'none',
      client: client,
      teacherId: _text(lesson, 'teacher_id'),
      branchId: _text(lesson, 'branch_id') ?? input.initialBranchId,
      roomId: _text(lesson, 'room_id') ?? input.initialRoomId,
      subscriptionId: _text(lesson, 'subscription_id'),
      settlementTypeKey: _text(
        lesson,
        'settlement_type_key',
        'settlementTypeKey',
      ),
      compensationRuleKey: compensationRuleKey,
      compensationValueMinor: compensationValueMinor,
    );
    final snapshot = lesson == null
        ? null
        : LessonEditorSnapshot(
            lessonId: _text(lesson, 'id') ?? '',
            expectedVersion: _version(lesson['version']),
            rawLesson: Map.unmodifiable(Map<String, dynamic>.from(lesson)),
            clientLocked: true,
            initialSchedulePayload: Map.unmodifiable({
              'teacherId': draft.teacherId,
              'branchId': draft.branchId,
              'roomId': draft.roomId,
              'scheduledAt': lesson['scheduled_at'],
              'durationMinutes': draft.durationMinutes,
            }),
            initialCompensationRuleKey: compensationRuleKey,
            initialCompensationValueMinor: compensationValueMinor,
          );

    return LessonEditorSession(
      draft: draft,
      snapshot: snapshot,
      seededClient: client,
      leadNoteSource: _nonEmpty(input.leadName),
    );
  }

  LessonClientRef? _constructorClient(LessonEditorInitialInput input) {
    final clientId = _nonEmpty(input.clientId);
    if (clientId != null) {
      return LessonClientRef(
        type: input.clientType == 'lead' ? 'lead' : 'student',
        id: clientId,
        label: _nonEmpty(input.clientName) ?? 'Клиент без имени',
      );
    }
    final leadId = _nonEmpty(input.leadId);
    if (leadId == null) return null;
    return LessonClientRef(
      type: 'lead',
      id: leadId,
      label: _nonEmpty(input.leadName) ?? 'Лид без имени',
    );
  }

  LessonClientRef? _editClient(Map<String, dynamic> lesson) {
    final groupId = _text(lesson, 'group_id', 'groupId');
    if (groupId != null) {
      return LessonClientRef(
        type: 'group',
        id: groupId,
        label: _text(lesson, 'group_name', 'groupName') ?? 'Группа',
      );
    }
    final leadId = _text(lesson, 'lead_id');
    if (leadId != null) {
      return LessonClientRef(
        type: 'lead',
        id: leadId,
        label: _text(lesson, 'lead_name') ?? 'Лид без имени',
      );
    }
    final studentId = _text(lesson, 'student_id');
    if (studentId == null) return null;
    return LessonClientRef(
      type: 'student',
      id: studentId,
      label: _text(lesson, 'student_name') ?? 'Ученик без имени',
    );
  }

  DateTime _localStart(
    LessonEditorInitialInput input,
    Map<String, dynamic>? lesson,
  ) {
    final parsed = DateTime.tryParse(_text(lesson, 'scheduled_at') ?? '');
    if (parsed != null) {
      final moscow = parsed.toUtc().add(const Duration(hours: 3));
      return DateTime(
        moscow.year,
        moscow.month,
        moscow.day,
        moscow.hour,
        moscow.minute,
        moscow.second,
        moscow.millisecond,
        moscow.microsecond,
      );
    }
    final initialDate = input.initialDate;
    if (initialDate == null) return DateTime.now();
    if (!input.initialIsTrial) return initialDate;
    return DateTime(initialDate.year, initialDate.month, initialDate.day, 10);
  }

  int _durationMinutes(
    LessonEditorInitialInput input,
    Map<String, dynamic>? lesson,
  ) {
    final value = lesson?['duration_minutes'];
    if (value is num && value > 0) return value.toInt();
    final initial = input.initialDurationMinutes;
    return initial != null && initial > 0 ? initial : 60;
  }
}

String? _text(Map<String, dynamic>? values, String key, [String? alias]) {
  final value = values?[key] ?? (alias == null ? null : values?[alias]);
  return _nonEmpty(value?.toString());
}

String? _nonEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

int? _version(Object? value) => switch (value) {
  num value => value.toInt(),
  String value => int.tryParse(value),
  _ => null,
};
