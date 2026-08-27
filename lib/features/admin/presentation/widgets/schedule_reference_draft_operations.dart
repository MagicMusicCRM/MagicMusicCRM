import 'schedule_reference_models.dart';

BranchHoursDraft withBranchDayEnabled(
  BranchHoursDraft draft,
  int weekday, {
  required bool enabled,
}) {
  final weekly = copyIndexedScheduleRows(draft.weekly);
  if (enabled) {
    weekly[weekday] = {'weekday': weekday, 'open': '09:00', 'close': '21:00'};
  } else {
    weekly.remove(weekday);
  }
  return draft.copyWith(weekly: weekly);
}

BranchHoursDraft withBranchTime(
  BranchHoursDraft draft,
  int weekday,
  String field,
  String value,
) {
  final weekly = copyIndexedScheduleRows(draft.weekly);
  weekly[weekday] = {...draft.weekly[weekday]!, field: value};
  return draft.copyWith(weekly: weekly);
}

BranchHoursDraft withBranchException(
  BranchHoursDraft draft,
  Map<String, dynamic> exception,
) {
  final date = exception['date'].toString();
  final exceptions =
      [
        for (final row in draft.exceptions)
          if (row['date']?.toString() != date) {...row},
        {...exception},
      ]..sort(
        (left, right) =>
            left['date'].toString().compareTo(right['date'].toString()),
      );
  return draft.copyWith(exceptions: exceptions);
}

BranchHoursDraft withoutBranchException(BranchHoursDraft draft, String date) {
  return draft.copyWith(
    exceptions: [
      for (final row in draft.exceptions)
        if (row['date']?.toString() != date) {...row},
    ],
  );
}

TeacherScheduleDraft withTeacherAssignment(
  TeacherScheduleDraft draft,
  String branchId, {
  required bool selected,
}) {
  final assignments = copyNamedScheduleRows(draft.assignments);
  if (selected) {
    assignments[branchId] = {'branchId': branchId, 'activeFrom': '1970-01-01'};
  } else {
    assignments.remove(branchId);
  }
  return draft.copyWith(assignments: assignments);
}

TeacherScheduleDraft withRecurringDay(
  TeacherScheduleDraft draft,
  int weekday, {
  required bool enabled,
  required String timezone,
  required String validFrom,
}) {
  final recurring = copyIndexedScheduleRows(draft.recurring);
  if (enabled) {
    recurring[weekday] = {
      'kind': 'recurring',
      'available': true,
      'timezone': timezone,
      'weekday': weekday,
      'localStart': '09:00',
      'localEnd': '21:00',
      'validFrom': validFrom,
    };
  } else {
    recurring.remove(weekday);
  }
  return draft.copyWith(recurring: recurring);
}

TeacherScheduleDraft withRecurringTime(
  TeacherScheduleDraft draft,
  int weekday,
  String field,
  String value,
) {
  final recurring = copyIndexedScheduleRows(draft.recurring);
  recurring[weekday] = {...draft.recurring[weekday]!, field: value};
  return draft.copyWith(recurring: recurring);
}

TeacherScheduleDraft withUnavailableInterval(
  TeacherScheduleDraft draft,
  Map<String, dynamic> interval,
) {
  final reason = interval['reason']?.toString().trim() ?? '';
  final startsAt = DateTime.tryParse(interval['startsAt']?.toString() ?? '');
  final endsAt = DateTime.tryParse(interval['endsAt']?.toString() ?? '');
  if (reason.isEmpty || startsAt == null || endsAt == null) {
    throw ArgumentError('Interval requires UTC bounds and a reason.');
  }
  return draft.copyWith(
    intervals: [
      for (final row in draft.intervals) {...row},
      {
        ...interval,
        'kind': 'interval',
        'available': false,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
        'reason': reason,
      },
    ],
  );
}

TeacherScheduleDraft withoutUnavailableInterval(
  TeacherScheduleDraft draft,
  Map<String, dynamic> interval,
) {
  return draft.copyWith(
    intervals: [
      for (final row in draft.intervals)
        if (!sameScheduleInterval(row, interval)) {...row},
    ],
  );
}

List<Map<String, dynamic>> branchWeeklyPayload(BranchHoursDraft draft) => [
  for (final entry
      in (draft.weekly.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))))
    cleanScheduleReferenceMap({...entry.value, 'weekday': entry.key}),
];

List<Map<String, dynamic>> branchExceptionsPayload(BranchHoursDraft draft) => [
  for (final row in draft.exceptions) cleanScheduleReferenceMap(row),
];

List<Map<String, dynamic>> teacherAssignmentsPayload(
  TeacherScheduleDraft draft,
) => [
  for (final row in draft.assignments.values)
    cleanScheduleReferenceMap({
      ...row,
      'activeFrom': row['activeFrom'] ?? '1970-01-01',
    }),
];

List<Map<String, dynamic>> teacherAvailabilityPayload(
  TeacherScheduleDraft draft,
) => [
  for (final row in draft.recurring.values) cleanScheduleReferenceMap(row),
  for (final row in draft.extraRecurring) cleanScheduleReferenceMap(row),
  for (final row in draft.intervals) cleanScheduleReferenceMap(row),
];
