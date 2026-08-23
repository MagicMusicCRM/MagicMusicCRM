part of 'schedule_widget.dart';

extension _ScheduleWeekView on _ScheduleWidgetState {
  Widget _buildWeekView() {
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
            final at = _parseServerTime(conflict['scheduled_at']);
            return at != null && DateUtils.isSameDay(at, date);
          }),
        ),
      );
    }

    final entries = <ScheduleEntry>[];
    for (final lesson in _filteredLessons) {
      final start = _parseLessonTime(lesson);
      if (start == null || start.isBefore(monday) || !start.isBefore(weekEnd)) {
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
          columnId: dateOnly(start),
          startLocal: start,
          durationMinutes: _durationMinutes(lesson),
          title: title,
          subtitle: [
            teacher,
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

    return ScheduleDayCanvas(
      key: const ValueKey('schedule-week-view'),
      date: monday,
      columns: columns,
      entries: entries,
      allowCreate: widget.canWrite,
      onCreateSlot: (_, start, duration) => _openWeekCreate(start, duration),
      onOpenLesson: _showLessonDetails,
      initialVerticalOffset: _dayScrollOffset,
      onVerticalOffsetChanged: _updateDayScrollOffset,
    );
  }
}
