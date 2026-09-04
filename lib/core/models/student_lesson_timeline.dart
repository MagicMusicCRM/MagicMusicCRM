enum StudentLessonLifecycleState {
  scheduled,
  settlementPending,
  successfullyCompleted,
  cancelled,
  rescheduled;

  factory StudentLessonLifecycleState.fromWire(Object? value) =>
      switch (value) {
        'scheduled' => StudentLessonLifecycleState.scheduled,
        'settlement_pending' => StudentLessonLifecycleState.settlementPending,
        'successfully_completed' =>
          StudentLessonLifecycleState.successfullyCompleted,
        'cancelled' => StudentLessonLifecycleState.cancelled,
        'rescheduled' => StudentLessonLifecycleState.rescheduled,
        _ => throw FormatException(
          'Unknown student lesson lifecycle state: $value',
        ),
      };
}

enum StudentLessonOriginKind {
  manual,
  schedulePlan,
  oneOffException;

  factory StudentLessonOriginKind.fromWire(Object? value) => switch (value) {
    'manual' => StudentLessonOriginKind.manual,
    'generated' => StudentLessonOriginKind.schedulePlan,
    'one_off_exception' => StudentLessonOriginKind.oneOffException,
    _ => throw FormatException('Unknown student lesson origin kind: $value'),
  };
}

class StudentLessonTimelineReference {
  const StudentLessonTimelineReference({required this.id, required this.name});

  factory StudentLessonTimelineReference.fromJson(Map<String, dynamic> json) =>
      StudentLessonTimelineReference(
        id: _requiredString(json, 'id'),
        name: _requiredString(json, 'name'),
      );

  final String id;
  final String name;
}

class StudentLessonOrigin {
  const StudentLessonOrigin({
    required this.kind,
    required this.planId,
    required this.seriesId,
  });

  factory StudentLessonOrigin.fromJson(Map<String, dynamic> json) =>
      StudentLessonOrigin(
        kind: StudentLessonOriginKind.fromWire(json['kind']),
        planId: _nullableString(json, 'planId'),
        seriesId: _nullableString(json, 'seriesId'),
      );

  final StudentLessonOriginKind kind;
  final String? planId;
  final String? seriesId;
}

class StudentLessonSettlement {
  const StudentLessonSettlement({
    required this.coveredBySubscription,
    required this.settlementTypeKey,
  });

  factory StudentLessonSettlement.fromJson(Map<String, dynamic> json) =>
      StudentLessonSettlement(
        coveredBySubscription: _requiredBool(json, 'coveredBySubscription'),
        settlementTypeKey: _nullableString(json, 'settlementTypeKey'),
      );

  final bool coveredBySubscription;

  /// Null when no settlement applies or the actor cannot read finance fields.
  final String? settlementTypeKey;
}

class StudentLessonReschedule {
  const StudentLessonReschedule({
    required this.predecessorId,
    required this.successorId,
    required this.actionableLessonId,
  });

  factory StudentLessonReschedule.fromJson(Map<String, dynamic> json) =>
      StudentLessonReschedule(
        predecessorId: _nullableString(json, 'predecessorId'),
        successorId: _nullableString(json, 'successorId'),
        actionableLessonId: _requiredString(json, 'actionableLessonId'),
      );

  final String? predecessorId;
  final String? successorId;
  final String actionableLessonId;
}

class StudentLessonTimelineItem {
  const StudentLessonTimelineItem({
    required this.id,
    required this.version,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.lifecycleState,
    required this.student,
    required this.group,
    required this.teacher,
    required this.room,
    required this.branch,
    required this.origin,
    required this.settlement,
    required this.reschedule,
  });

  factory StudentLessonTimelineItem.fromJson(Map<String, dynamic> json) =>
      StudentLessonTimelineItem(
        id: _requiredString(json, 'id'),
        version: _requiredInt(json, 'version'),
        scheduledAt: _requiredDateTime(json, 'scheduledAt'),
        durationMinutes: _requiredInt(json, 'durationMinutes'),
        lifecycleState: StudentLessonLifecycleState.fromWire(
          json['lifecycleState'],
        ),
        student: StudentLessonTimelineReference.fromJson(
          _requiredMap(json, 'student'),
        ),
        group: _nullableReference(json, 'group'),
        teacher: _nullableReference(json, 'teacher'),
        room: _nullableReference(json, 'room'),
        branch: _nullableReference(json, 'branch'),
        origin: StudentLessonOrigin.fromJson(_requiredMap(json, 'origin')),
        settlement: StudentLessonSettlement.fromJson(
          _requiredMap(json, 'settlement'),
        ),
        reschedule: StudentLessonReschedule.fromJson(
          _requiredMap(json, 'reschedule'),
        ),
      );

  final String id;
  final int version;
  final DateTime scheduledAt;
  final int durationMinutes;
  final StudentLessonLifecycleState lifecycleState;
  final StudentLessonTimelineReference student;
  final StudentLessonTimelineReference? group;
  final StudentLessonTimelineReference? teacher;
  final StudentLessonTimelineReference? room;
  final StudentLessonTimelineReference? branch;
  final StudentLessonOrigin origin;
  final StudentLessonSettlement settlement;
  final StudentLessonReschedule reschedule;
}

class StudentLessonTimelinePage {
  const StudentLessonTimelinePage({
    required this.items,
    required this.previousCursor,
    required this.nextCursor,
    required this.hasPrevious,
    required this.hasNext,
  });

  const StudentLessonTimelinePage.empty()
    : items = const [],
      previousCursor = null,
      nextCursor = null,
      hasPrevious = false,
      hasNext = false;

  factory StudentLessonTimelinePage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'Student lesson timeline items must be a list',
      );
    }
    return StudentLessonTimelinePage(
      items: List.unmodifiable(
        rawItems.map((raw) {
          if (raw is! Map) {
            throw const FormatException(
              'Student lesson timeline item must be an object',
            );
          }
          return StudentLessonTimelineItem.fromJson(
            Map<String, dynamic>.from(raw),
          );
        }),
      ),
      previousCursor: _nullableString(json, 'previousCursor'),
      nextCursor: _nullableString(json, 'nextCursor'),
      hasPrevious: _requiredBool(json, 'hasPrevious'),
      hasNext: _requiredBool(json, 'hasNext'),
    );
  }

  final List<StudentLessonTimelineItem> items;
  final String? previousCursor;
  final String? nextCursor;
  final bool hasPrevious;
  final bool hasNext;
}

StudentLessonTimelineReference? _nullableReference(
  Map<String, dynamic> json,
  String field,
) {
  final value = json[field];
  if (value == null) return null;
  if (value is! Map) {
    throw FormatException(
      'Student lesson timeline field $field must be an object',
    );
  }
  return StudentLessonTimelineReference.fromJson(
    Map<String, dynamic>.from(value),
  );
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! Map) {
    throw FormatException(
      'Student lesson timeline field $field must be an object',
    );
  }
  return Map<String, dynamic>.from(value);
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String) {
    throw FormatException(
      'Student lesson timeline field $field must be a string',
    );
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException(
      'Student lesson timeline field $field must be a string or null',
    );
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! num || value.toInt() != value) {
    throw FormatException(
      'Student lesson timeline field $field must be an integer',
    );
  }
  return value.toInt();
}

bool _requiredBool(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! bool) {
    throw FormatException(
      'Student lesson timeline field $field must be a boolean',
    );
  }
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> json, String field) {
  final value = _requiredString(json, field);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException(
      'Student lesson timeline field $field must be an ISO timestamp',
    );
  }
  return parsed;
}
