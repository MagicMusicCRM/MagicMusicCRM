part of 'schedule_widget.dart';

extension _ScheduleTeacherDayView on _ScheduleWidgetState {
  Widget _buildDayViewByTeacher() {
    final dayLessons = _lessonsForDate(_selectedDate);
    final teacherIds = _filterTeacherId == null
        ? _teacherFilterOptions.map((teacher) => teacher.id).toList()
        : <String>[_filterTeacherId!];
    if (teacherIds.isEmpty) {
      return Center(
        child: Text(
          'Нет преподавателей в выбранном филиале',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final rows = <ScheduleTeacherRow>[];
    for (var i = 0; i < teacherIds.length; i++) {
      final teacherId = teacherIds[i];
      final teacherLessons = dayLessons
          .where((lesson) => lesson['teacher_id']?.toString() == teacherId)
          .toList();
      rows.add(
        ScheduleTeacherRow(
          id: teacherId,
          name: _teacherNames[teacherId] ?? 'Преподаватель',
          color: _roomColors[i % _roomColors.length],
          lessonCount: teacherLessons.length,
          totalMinutes: teacherLessons.fold<int>(
            0,
            (total, lesson) => total + _durationMinutes(lesson),
          ),
          hasConflict: teacherLessons.any(
            (lesson) => conflictTypes(lesson['conflict_types']).isNotEmpty,
          ),
        ),
      );
    }
    final entries = <ScheduleEntry>[];
    for (final lesson in dayLessons) {
      final start = _parseLessonTime(lesson);
      final teacherId = lesson['teacher_id']?.toString();
      if (start == null || teacherId == null) continue;
      final group = lesson['group_name']?.toString().trim() ?? '';
      final student = _studentNames[lesson['student_id']?.toString()] ?? '';
      final lead = lesson['lead_name']?.toString().trim() ?? '';
      final branch = lesson['branch_name']?.toString().trim() ?? '';
      final room = lesson['room_name']?.toString().trim() ?? '';
      entries.add(
        ScheduleEntry(
          lesson: lesson,
          id: lesson['id']?.toString() ?? '',
          columnId: teacherId,
          startLocal: start,
          durationMinutes: _durationMinutes(lesson),
          title: group.isNotEmpty
              ? group
              : student.isNotEmpty
              ? student
              : lead.isNotEmpty
              ? lead
              : 'Занятие',
          subtitle: [
            branch.isEmpty ? 'Филиал' : branch,
            room.isEmpty ? 'Без аудитории' : room,
          ].join(' · '),
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

    return ScheduleTeacherTimeline(
      key: ValueKey(
        'teacher-day-${dateOnly(_selectedDate)}-'
        '${_selectedBranchId ?? ''}-${rows.length}',
      ),
      date: _selectedDate,
      rows: rows,
      entries: entries,
      allowCreate: widget.canWrite,
      onCreateSlot: (_, start, duration) => _openWeekCreate(start, duration),
      onOpenLesson: _showLessonDetails,
      initialVerticalOffset: _dayScrollOffset,
      onVerticalOffsetChanged: _updateDayScrollOffset,
    );
  }
}
