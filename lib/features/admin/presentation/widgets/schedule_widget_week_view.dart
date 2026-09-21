part of 'schedule_widget.dart';

extension _ScheduleWeekView on _ScheduleWidgetState {
  Widget _buildWeekView() {
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
    final weekEnd = monday.add(const Duration(days: 7));
    final cs = Theme.of(context).colorScheme;
    final columns = <ScheduleColumn>[];
    for (var i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final isToday = DateUtils.isSameDay(date, DateTime.now());
      columns.add(
        ScheduleColumn(
          id: dateOnly(date),
          name: '${weekDays[i]}\n${date.day} ${monthNamesGenitive[date.month]}',
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
          displayDate.isBefore(monday) ||
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
        teacherMode ? 'schedule-teacher-week-view' : 'schedule-week-view',
      ),
      date: monday,
      columns: columns,
      entries: entries,
      blockedIntervals: teacherMode
          ? _teacherWeekBlockedIntervals(monday)
          : const [],
      allowCreate: widget.canWrite,
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
    final assigned = _teacherWeekReference?['teacherBranchAssigned'] != false;
    return Column(
      children: [
        if (_teacherWeekReferenceLoading)
          const LinearProgressIndicator(minHeight: 2, color: AppColor.gold)
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

  List<ScheduleBlockedInterval> _teacherWeekBlockedIntervals(DateTime monday) {
    final rawRules = _teacherWeekReference?['teacherRules'];
    if (rawRules is! List) return const [];
    final offset = _selectedBranchOffset;
    DateTime? local(Object? raw) {
      final parsed = DateTime.tryParse(raw?.toString() ?? '');
      if (parsed == null) return null;
      return parsed.isUtc
          ? parsed.toUtc().add(Duration(minutes: offset))
          : parsed;
    }

    final result = <ScheduleBlockedInterval>[];
    for (final raw in rawRules.whereType<Map>()) {
      if (raw['available'] != false) continue;
      final startsAt = local(raw['startsAt'] ?? raw['starts_at']);
      final endsAt = local(raw['endsAt'] ?? raw['ends_at']);
      if (startsAt == null || endsAt == null || !endsAt.isAfter(startsAt)) {
        continue;
      }
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
        final overlapStart = startsAt.isAfter(visibleStart)
            ? startsAt
            : visibleStart;
        final overlapEnd = endsAt.isBefore(visibleEnd) ? endsAt : visibleEnd;
        if (!overlapEnd.isAfter(overlapStart)) continue;
        result.add(
          ScheduleBlockedInterval(
            columnId: dateOnly(day),
            startLocal: overlapStart,
            endLocal: overlapEnd,
            reason: raw['reason']?.toString(),
          ),
        );
      }
    }
    return result;
  }
}
