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
  return draft.copyWith(
    recurring: recurring,
    extraRecurring: enabled
        ? draft.extraRecurring
        : [
            for (final row in draft.extraRecurring)
              if ((row['weekday'] as num?)?.toInt() != weekday) {...row},
          ],
  );
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

List<Map<String, dynamic>> recurringRulesForDay(
  TeacherScheduleDraft draft,
  int weekday,
) {
  final rules = <Map<String, dynamic>>[
    ?draft.recurring[weekday],
    for (final row in draft.extraRecurring)
      if ((row['weekday'] as num?)?.toInt() == weekday) row,
  ];
  rules.sort(
    (left, right) => (left['localStart']?.toString() ?? '').compareTo(
      right['localStart']?.toString() ?? '',
    ),
  );
  return rules;
}

TeacherScheduleDraft withRecurringRuleAdded(
  TeacherScheduleDraft draft,
  int weekday, {
  required String timezone,
  required String validFrom,
}) {
  final current = recurringRulesForDay(draft, weekday);
  final start = current.isEmpty
      ? '09:00'
      : current.last['localEnd']?.toString() ?? '18:00';
  return _replaceRecurringRules(draft, [
    ..._allRecurringRules(draft),
    {
      'kind': 'recurring',
      'available': true,
      'timezone': timezone,
      'weekday': weekday,
      'localStart': start,
      'localEnd': _oneHourAfter(start),
      'validFrom': validFrom,
    },
  ]);
}

TeacherScheduleDraft withRecurringRuleUpdated(
  TeacherScheduleDraft draft,
  Map<String, dynamic> target,
  String field,
  Object? value,
) {
  final rules = _allRecurringRules(draft);
  final index = rules.indexWhere((row) => _sameRecurringRule(row, target));
  if (index < 0) return draft;
  final updated = {...rules[index]};
  if (value == null || value.toString().trim().isEmpty) {
    updated.remove(field);
  } else {
    updated[field] = value;
  }
  rules[index] = updated;
  return _replaceRecurringRules(draft, rules);
}

TeacherScheduleDraft withoutRecurringRule(
  TeacherScheduleDraft draft,
  Map<String, dynamic> target,
) => _replaceRecurringRules(draft, [
  for (final row in _allRecurringRules(draft))
    if (!_sameRecurringRule(row, target)) row,
]);

List<Map<String, dynamic>> _allRecurringRules(TeacherScheduleDraft draft) => [
  for (final row in draft.recurring.values) {...row},
  for (final row in draft.extraRecurring) {...row},
];

TeacherScheduleDraft _replaceRecurringRules(
  TeacherScheduleDraft draft,
  List<Map<String, dynamic>> rules,
) {
  rules.sort((left, right) {
    final day = ((left['weekday'] as num?)?.toInt() ?? 0).compareTo(
      (right['weekday'] as num?)?.toInt() ?? 0,
    );
    if (day != 0) return day;
    return (left['localStart']?.toString() ?? '').compareTo(
      right['localStart']?.toString() ?? '',
    );
  });
  final primary = <int, Map<String, dynamic>>{};
  final extras = <Map<String, dynamic>>[];
  for (final row in rules) {
    final weekday = (row['weekday'] as num?)?.toInt();
    if (weekday == null) continue;
    if (primary.containsKey(weekday)) {
      extras.add({...row});
    } else {
      primary[weekday] = {...row};
    }
  }
  return draft.copyWith(recurring: primary, extraRecurring: extras);
}

bool _sameRecurringRule(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (identical(left, right)) return true;
  final leftId = left['id']?.toString();
  final rightId = right['id']?.toString();
  if (leftId != null && leftId.isNotEmpty && rightId != null) {
    return leftId == rightId;
  }
  return left['weekday'] == right['weekday'] &&
      left['localStart'] == right['localStart'] &&
      left['localEnd'] == right['localEnd'] &&
      left['validFrom'] == right['validFrom'] &&
      left['validUntil'] == right['validUntil'];
}

String _oneHourAfter(String value) {
  final parts = value.split(':');
  final hour = int.tryParse(parts.first) ?? 9;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final total = (hour * 60 + minute + 60).clamp(0, 23 * 60 + 59);
  final resultHour = total ~/ 60;
  final resultMinute = total % 60;
  return '${resultHour.toString().padLeft(2, '0')}:'
      '${resultMinute.toString().padLeft(2, '0')}';
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
