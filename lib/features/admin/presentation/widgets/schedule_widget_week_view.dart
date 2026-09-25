part of 'schedule_widget.dart';

extension _ScheduleWeekView on _ScheduleWidgetState {
  Widget _buildWeekView({bool singleDay = false}) {
    final teacherMode = _dayViewMode == DayViewMode.byTeacher;
    final selectedTeacherId = widget.fixedTeacherId ?? _filterTeacherId;
    if (teacherMode && _selectedBranchId == null) {
      return const MagicPageState(
        kind: MagicPageStateKind.empty,
        title: 'Выберите филиал',
        message:
            'Недельная доступность преподавателя строится для одного филиала.',
      );
    }
    final monday = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    ).subtract(Duration(days: _selectedDate.weekday - 1));
    final firstDay = singleDay ? _selectedDate : monday;
    final weekEnd = firstDay.add(Duration(days: singleDay ? 1 : 7));
    final cs = Theme.of(context).colorScheme;
    final columns = <ScheduleColumn>[];
    for (var i = 0; i < (singleDay ? 1 : 7); i++) {
      final date = firstDay.add(Duration(days: i));
      final isToday = DateUtils.isSameDay(date, DateTime.now());
      columns.add(
        ScheduleColumn(
          id: dateOnly(date),
          name:
              '${weekDays[date.weekday - 1]}\n${date.day} ${monthNamesGenitive[date.month]}',
          color: isToday ? AppColor.gold : cs.onSurfaceVariant,
          date: date,
          hasConflict: _scheduleConflicts.any((conflict) {
            final at = _parseServerTime(
              conflict['scheduled_at'],
              conflict['scheduled_utc_offset_minutes'],
            );
            return at != null &&
                DateUtils.isSameDay(scheduleDisplayDate(at), date);
          }),
        ),
      );
    }

    final entries = <ScheduleEntry>[];
    for (final lesson in _filteredLessons) {
      if (teacherMode &&
          lesson['teacher_id']?.toString() != selectedTeacherId) {
        continue;
      }
      final start = _parseLessonTime(lesson);
      final displayDate = start == null ? null : scheduleDisplayDate(start);
      if (start == null ||
          displayDate == null ||
          displayDate.isBefore(firstDay) ||
          !displayDate.isBefore(weekEnd)) {
        continue;
      }
      final leadName = lesson['lead_name']?.toString().trim() ?? '';
      final title =
          _studentNames[lesson['student_id']?.toString()] ??
          lesson['group_name']?.toString() ??
          (leadName.isEmpty ? 'Занятие' : leadName);
      final teacher = _teacherNames[lesson['teacher_id']?.toString()] ?? '';
      final room = _roomNames[lesson['room_id']?.toString()] ?? '';
      final branch = lesson['branch_name']?.toString().trim() ?? '';
      entries.add(
        ScheduleEntry(
          lesson: lesson,
          id: lesson['id']?.toString() ?? '',
          columnId: dateOnly(displayDate),
          startLocal: start,
          displayDate: displayDate,
          durationMinutes: _durationMinutes(lesson),
          title: title,
          subtitle: [
            if (!teacherMode) teacher,
            [
              branch.isEmpty ? 'Филиал' : branch,
              room.isEmpty ? 'Без аудитории' : room,
            ].join(' · '),
          ].where((value) => value.isNotEmpty).join(' · '),
          isTrial: lesson['is_trial'] == true,
          conflicts: conflictTypes(lesson['conflict_types']),
          highlighted:
              _highlightLessonId != null &&
              lesson['id']?.toString() == _highlightLessonId,
          clientContext: _hasClientContext,
          searchContext: _hasScheduleSearch,
          relatedClient: _isRelatedLesson(lesson),
        ),
      );
    }

    final canvas = ScheduleDayCanvas(
      fitToViewport: _fitDayToViewport,
      key: ValueKey(
        teacherMode
            ? (singleDay
                  ? 'schedule-teacher-day-view'
                  : 'schedule-teacher-week-view')
            : 'schedule-week-view',
      ),
      date: firstDay,
      columns: columns,
      entries: entries,
      blockedIntervals: teacherMode
          ? _teacherWeekBlockedIntervals(monday)
                .where(
                  (item) => !singleDay || item.columnId == dateOnly(firstDay),
                )
                .toList()
          : const [],
      allowCreate:
          widget.canWrite && (!teacherMode || _teacherWeekReference != null),
      onCreateSlot: (_, start, duration) => _openWeekCreate(
        start,
        duration,
        teacherId: teacherMode ? selectedTeacherId : null,
      ),
      onOpenLesson: _showLessonDetails,
      initialVerticalOffset: _dayScrollOffset,
      onVerticalOffsetChanged: _updateDayScrollOffset,
    );
    if (!teacherMode) return canvas;
    final assigned =
        _teacherWeekReference != null &&
        List.generate(
          singleDay ? 1 : 7,
          (index) => firstDay.add(Duration(days: index)),
        ).any((day) => _teacherAssignedOnDate(_teacherWeekReference!, day));
    return Column(
      children: [
        if (_teacherWeekReferenceLoading)
          const LinearProgressIndicator(minHeight: 2, color: AppColor.gold)
        else if (_teacherWeekReference == null)
          const _TeacherAvailabilityNotice(
            'Доступность преподавателя не загружена. Обновите расписание.',
          )
        else if (!assigned)
          Container(
            width: double.infinity,
            color: AppColor.warningSoft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: const Text(
              'Преподаватель не назначен в выбранный филиал.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        Expanded(child: canvas),
      ],
    );
  }

  bool _teacherAssignedOnDate(Map<String, dynamic> reference, DateTime day) {
    final teacher = reference['teacher'];
    final assignments = teacher is Map ? teacher['assignments'] : null;
    if (assignments is! List) {
      return reference['teacherBranchAssigned'] == true;
    }
    final date = dateOnly(day);
    return assignments.whereType<Map>().any((row) {
      final start = row['activeFrom']?.toString();
      final end = row['activeUntil']?.toString();
      return row['branchId']?.toString() == _selectedBranchId &&
          start != null &&
          start.compareTo(date) <= 0 &&
          (end == null || end.compareTo(date) >= 0);
    });
  }

  List<ScheduleBlockedInterval> _teacherWeekBlockedIntervals(DateTime monday) {
    final reference = _teacherWeekReference;
    if (reference == null) return const [];
    final rawRules = (reference['teacherRules'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final branchWindows = (reference['branchWindows'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final offset = _selectedBranchOffset;
    DateTime? local(Object? raw) {
      final parsed = DateTime.tryParse(raw?.toString() ?? '');
      if (parsed == null) return null;
      if (!parsed.isUtc) return parsed;
      final shifted = parsed.toUtc().add(Duration(minutes: offset));
      return DateTime(
        shifted.year,
        shifted.month,
        shifted.day,
        shifted.hour,
        shifted.minute,
        shifted.second,
        shifted.millisecond,
      );
    }

    final result = <ScheduleBlockedInterval>[];
    final positiveRules = rawRules
        .where((row) => row['available'] == true)
        .toList();
    for (var index = 0; index < 7; index++) {
      final day = monday.add(Duration(days: index));
      final visibleStart = DateTime(
        day.year,
        day.month,
        day.day,
        kDayStartHour,
      );
      final visibleEnd = DateTime(
        day.year,
        day.month,
        day.day + 1,
        kDayEndHour % 24,
      );
      final cuts = <DateTime>{visibleStart, visibleEnd};
      for (final row in [...rawRules, ...branchWindows]) {
        final start = local(row['startsAt'] ?? row['opensAt']);
        final end = local(row['endsAt'] ?? row['closesAt']);
        if (start != null &&
            start.isAfter(visibleStart) &&
            start.isBefore(visibleEnd)) {
          cuts.add(start);
        }
        if (end != null &&
            end.isAfter(visibleStart) &&
            end.isBefore(visibleEnd)) {
          cuts.add(end);
        }
      }
      final boundaries = cuts.toList()..sort();
      bool covers(Map row, DateTime at, {bool branch = false}) {
        final start = local(row[branch ? 'opensAt' : 'startsAt']);
        final end = local(row[branch ? 'closesAt' : 'endsAt']);
        return start != null &&
            !at.isBefore(start) &&
            (end == null || at.isBefore(end));
      }

      for (var i = 0; i < boundaries.length - 1; i++) {
        final start = boundaries[i];
        final end = boundaries[i + 1];
        final at = start.add(
          Duration(microseconds: end.difference(start).inMicroseconds ~/ 2),
        );
        final branchOpen =
            reference['branchHoursConfigured'] == true &&
            branchWindows.any((row) => covers(row, at, branch: true));
        final teacherOpen =
            positiveRules.isEmpty ||
            positiveRules.any((row) => covers(row, at));
        final busyRule = rawRules
            .where((row) => row['available'] == false)
            .where((row) => covers(row, at))
            .firstOrNull;
        final assigned = _teacherAssignedOnDate(reference, day);
        if (!assigned || !branchOpen || !teacherOpen || busyRule != null) {
          result.add(
            ScheduleBlockedInterval(
              columnId: dateOnly(day),
              startLocal: start,
              endLocal: end,
              reason: !assigned
                  ? 'Преподаватель не назначен в филиал'
                  : !branchOpen
                  ? 'Филиал закрыт'
                  : busyRule?['reason']?.toString() ??
                        'Не рабочее время преподавателя',
            ),
          );
        }
      }
    }
    return result;
  }
}

class _TeacherAvailabilityNotice extends StatelessWidget {
  const _TeacherAvailabilityNotice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColor.warningSoft,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    child: Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}
