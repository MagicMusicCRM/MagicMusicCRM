part of 'schedule_widget.dart';

extension _ScheduleRoomDayView on _ScheduleWidgetState {
  Map<String, dynamic>? _availabilityForRoom(String roomId) {
    for (final item in _roomAvailability) {
      if (item['room_id']?.toString() == roomId) return item;
    }
    return null;
  }

  // Defensive: the backend may send duration as int, double, or string. A bare
  // `as int?` cast throws on a double and blanks the whole card (the lesson then
  // never renders), so parse leniently and fall back to a 60-minute slot.
  int _durationMinutes(Map<String, dynamic> lesson) {
    final raw = lesson['duration_minutes'];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    final parsed = int.tryParse(raw?.toString() ?? '');
    return parsed ?? 60;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MONTH VIEW
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDayView() {
    if (_dayViewMode == DayViewMode.byTeacher) {
      return _buildDayViewByTeacher();
    }
    return _buildDayViewByRoom();
  }

  // ── Day view by Rooms (2-axis canvas — KVA-195) ────────────────────────────
  Widget _buildDayViewByRoom() {
    final rooms = _filteredRooms;
    final dayLessons = _lessonsForDate(_selectedDate);

    // Lessons whose room is NOT among the rendered room columns (no room_id, a
    // room missing from the loaded list, or a different branch) get a synthetic
    // «Без аудитории» column so every lesson stays visible (KVA-166).
    final renderedRoomIds = rooms.map((r) => r['id'].toString()).toSet();
    final unassignedLessons = dayLessons.where((l) {
      final rid = l['room_id']?.toString();
      return rid == null || rid.isEmpty || !renderedRoomIds.contains(rid);
    }).toList();

    if (rooms.isEmpty && unassignedLessons.isEmpty) {
      return Center(
        child: Text(
          'Нет аудиторий для выбранного филиала',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;

    // Columns: one per room (+ the unassigned bucket when needed). A room turns
    // red only on a real backend-derived conflict, never just because it's busy.
    final columns = <ScheduleColumn>[
      for (final r in rooms)
        ScheduleColumn(
          id: r['id'].toString(),
          name: r['name']?.toString() ?? 'Аудитория',
          color: _roomColorMap[r['id'].toString()] ?? cs.onSurfaceVariant,
          hasConflict: conflictTypes(
            _availabilityForRoom(r['id'].toString())?['conflict_types'],
          ).isNotEmpty,
        ),
      if (unassignedLessons.isNotEmpty)
        ScheduleColumn(
          id: kUnassignedColumnId,
          name: 'Без аудитории',
          color: cs.onSurfaceVariant,
          isUnassigned: true,
        ),
    ];

    // Entries: branch-local positioned lesson blocks for the canvas.
    final entries = <ScheduleEntry>[];
    for (final l in dayLessons) {
      final start = _parseLessonTime(l);
      if (start == null) continue;
      final rid = l['room_id']?.toString();
      final columnId =
          (rid == null || rid.isEmpty || !renderedRoomIds.contains(rid))
          ? kUnassignedColumnId
          : rid;
      final teacher = _teacherNames[l['teacher_id']?.toString()] ?? '';
      final group = l['group_name']?.toString();
      final student = _studentNames[l['student_id']?.toString()] ?? '';
      // Пробное по лиду: ни группы, ни ученика — блок подписывается именем
      // лида, а не безликим «Занятие».
      final lead = l['lead_name']?.toString().trim() ?? '';
      final title = (group != null && group.isNotEmpty)
          ? group
          : (student.isNotEmpty
                ? student
                : (lead.isNotEmpty ? lead : 'Занятие'));
      entries.add(
        ScheduleEntry(
          lesson: l,
          id: l['id']?.toString() ?? '',
          columnId: columnId,
          startLocal: start,
          durationMinutes: _durationMinutes(l),
          title: title,
          subtitle: teacher,
          isTrial: l['is_trial'] == true,
          conflicts: conflictTypes(l['conflict_types']),
          highlighted:
              _highlightLessonId != null &&
              l['id']?.toString() == _highlightLessonId,
          clientContext: _hasClientContext,
          searchContext: _hasScheduleSearch,
          relatedClient: _isRelatedLesson(l),
        ),
      );
    }

    return ScheduleDayCanvas(
      key: ValueKey(
        'day-${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}'
        '-${_selectedBranchId ?? ''}-${columns.length}',
      ),
      date: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      columns: columns,
      entries: entries,
      allowCreate: widget.canWrite,
      onCreateSlot: _openQuickCreate,
      onOpenLesson: _showLessonDetails,
      initialVerticalOffset: _dayScrollOffset,
      onVerticalOffsetChanged: _updateDayScrollOffset,
    );
  }
}
