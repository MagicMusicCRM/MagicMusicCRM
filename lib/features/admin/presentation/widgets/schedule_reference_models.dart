enum ScheduleReferenceSection { branchHours, teacherSchedule }

const scheduleReferenceDayNames = <int, String>{
  1: 'Понедельник',
  2: 'Вторник',
  3: 'Среда',
  4: 'Четверг',
  5: 'Пятница',
  6: 'Суббота',
  7: 'Воскресенье',
};

class ScheduleReferenceSnapshot {
  const ScheduleReferenceSnapshot({
    required this.branches,
    required this.teachers,
    required this.branchId,
    required this.teacherId,
    required this.branchDraft,
    required this.teacherDraft,
    required this.loading,
    required this.saving,
    required this.error,
  });

  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final String? branchId;
  final String? teacherId;
  final BranchHoursDraft? branchDraft;
  final TeacherScheduleDraft? teacherDraft;
  final bool loading;
  final bool saving;
  final Object? error;
}

class BranchHoursDraft {
  const BranchHoursDraft({
    required this.version,
    required this.timezone,
    required this.weekly,
    required this.exceptions,
  });

  factory BranchHoursDraft.fromJson(Map<String, dynamic> json) {
    final weekly = <int, Map<String, dynamic>>{};
    for (final row in scheduleReferenceMaps(json['weekly'])) {
      final weekday = row['weekday'];
      if (weekday is num) weekly[weekday.toInt()] = {...row};
    }
    return BranchHoursDraft(
      version: (json['version'] as num?)?.toInt() ?? 1,
      timezone: json['timezone']?.toString() ?? 'Europe/Moscow',
      weekly: weekly,
      exceptions: [
        for (final row in scheduleReferenceMaps(json['exceptions'])) {...row},
      ],
    );
  }

  final int version;
  final String timezone;
  final Map<int, Map<String, dynamic>> weekly;
  final List<Map<String, dynamic>> exceptions;

  BranchHoursDraft copyWith({
    int? version,
    String? timezone,
    Map<int, Map<String, dynamic>>? weekly,
    List<Map<String, dynamic>>? exceptions,
  }) => BranchHoursDraft(
    version: version ?? this.version,
    timezone: timezone ?? this.timezone,
    weekly: weekly ?? this.weekly,
    exceptions: exceptions ?? this.exceptions,
  );
}

class TeacherScheduleDraft {
  const TeacherScheduleDraft({
    required this.version,
    required this.assignments,
    required this.recurring,
    required this.extraRecurring,
    required this.unavailableRecurring,
    required this.intervals,
    required this.availableIntervals,
  });

  factory TeacherScheduleDraft.fromJson(Map<String, dynamic> json) {
    final assignments = <String, Map<String, dynamic>>{};
    for (final row in scheduleReferenceMaps(json['assignments'])) {
      final branchId = row['branchId']?.toString();
      if (branchId != null) assignments[branchId] = {...row};
    }
    final recurring = <int, Map<String, dynamic>>{};
    final extraRecurring = <Map<String, dynamic>>[];
    final unavailableRecurring = <Map<String, dynamic>>[];
    final intervals = <Map<String, dynamic>>[];
    final availableIntervals = <Map<String, dynamic>>[];
    for (final row in scheduleReferenceMaps(json['availability'])) {
      final weekday = row['weekday'];
      if (row['kind'] == 'recurring' && weekday is num) {
        if (row['available'] == false) {
          unavailableRecurring.add({...row});
          continue;
        }
        final day = weekday.toInt();
        if (recurring.containsKey(day)) {
          extraRecurring.add({...row});
        } else {
          recurring[day] = {...row};
        }
      } else if (row['kind'] == 'interval') {
        if (row['available'] == false) {
          intervals.add({...row});
        } else {
          availableIntervals.add({...row});
        }
      }
    }
    return TeacherScheduleDraft(
      version: (json['version'] as num?)?.toInt() ?? 1,
      assignments: assignments,
      recurring: recurring,
      extraRecurring: extraRecurring,
      unavailableRecurring: unavailableRecurring,
      intervals: intervals,
      availableIntervals: availableIntervals,
    );
  }

  final int version;
  final Map<String, Map<String, dynamic>> assignments;
  final Map<int, Map<String, dynamic>> recurring;
  final List<Map<String, dynamic>> extraRecurring;
  final List<Map<String, dynamic>> unavailableRecurring;
  final List<Map<String, dynamic>> intervals;
  final List<Map<String, dynamic>> availableIntervals;

  TeacherScheduleDraft copyWith({
    int? version,
    Map<String, Map<String, dynamic>>? assignments,
    Map<int, Map<String, dynamic>>? recurring,
    List<Map<String, dynamic>>? extraRecurring,
    List<Map<String, dynamic>>? unavailableRecurring,
    List<Map<String, dynamic>>? intervals,
    List<Map<String, dynamic>>? availableIntervals,
  }) => TeacherScheduleDraft(
    version: version ?? this.version,
    assignments: assignments ?? this.assignments,
    recurring: recurring ?? this.recurring,
    extraRecurring: extraRecurring ?? this.extraRecurring,
    unavailableRecurring: unavailableRecurring ?? this.unavailableRecurring,
    intervals: intervals ?? this.intervals,
    availableIntervals: availableIntervals ?? this.availableIntervals,
  );
}

List<Map<String, dynamic>> scheduleReferenceMaps(dynamic value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

Map<String, dynamic> cleanScheduleReferenceMap(Map<String, dynamic> source) => {
  for (final entry in source.entries)
    if (entry.value != null) entry.key: entry.value,
};

bool containsScheduleReferenceId(List<Map<String, dynamic>> items, String id) =>
    items.any((item) => scheduleReferenceId(item) == id);

String? scheduleReferenceId(Map<String, dynamic> item) {
  final id = item['id']?.toString().trim();
  return id == null || id.isEmpty ? null : id;
}

String? validScheduleReferenceSelection(
  String? selected,
  List<Map<String, dynamic>> items,
) {
  if (selected != null && containsScheduleReferenceId(items, selected)) {
    return selected;
  }
  for (final item in items) {
    final id = scheduleReferenceId(item);
    if (id != null) return id;
  }
  return null;
}

Map<int, Map<String, dynamic>> copyIndexedScheduleRows(
  Map<int, Map<String, dynamic>> source,
) => {
  for (final entry in source.entries) entry.key: {...entry.value},
};

Map<String, Map<String, dynamic>> copyNamedScheduleRows(
  Map<String, Map<String, dynamic>> source,
) => {
  for (final entry in source.entries) entry.key: {...entry.value},
};

bool sameScheduleInterval(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) => left['startsAt'] == right['startsAt'] && left['endsAt'] == right['endsAt'];

int returnedScheduleVersion(Map<String, dynamic> result, int fallback) =>
    (result['version'] as num?)?.toInt() ?? fallback;
