part of 'schedule_widget.dart';

extension _ScheduleViewsB on _ScheduleWidgetState {
  // day-view, remember the highlight id (matched by `id` in the day's data) and
  // backfill the day. The canvas renders the gold pulse; we arm a timer to clear
  // it. We then consume the navigation request so re-tapping re-fires focus.
  void _applyScheduleFocus(ScheduleFocusState focus) {
    final date = focus.focusDate;
    final day = DateTime(date.year, date.month, date.day);
    _highlightClearTimer?.cancel();
    if (focus.openMonth && focus.clientId?.isNotEmpty == true) {
      _emitState(() {
        _selectedDate = day;
        _displayedMonth = DateTime(day.year, day.month);
        _currentView = ScheduleView.month;
        _highlightLessonId = null;
        _filterClientType = focus.clientType;
        _filterClientId = focus.clientId;
        _filterClientName = focus.clientName;
      });
      ref.read(scheduleNavigationProvider.notifier).clear();
      unawaited(_fetchAll());
      return;
    }
    _emitState(() {
      _selectedDate = day;
      _displayedMonth = DateTime(day.year, day.month);
      _currentView = ScheduleView.day;
      _highlightLessonId = focus.highlightLessonId;
      _filterClientType = null;
      _filterClientId = null;
      _filterClientName = null;
    });
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(day);
    _armHighlightClear();
    ref.read(scheduleNavigationProvider.notifier).clear();
    if (focus.leadId != null && focus.leadId!.isNotEmpty) {
      // The navigation request is consumed only after the Schedule screen owns
      // the flow. Opening the dialog here keeps lesson creation exclusive to
      // the Schedule tab while retaining the lead/date preset from the card.
      unawaited(_openLeadCreateFromSchedule(focus, day));
    }
  }

  Future<void> _openLeadCreateFromSchedule(
    ScheduleFocusState focus,
    DateTime day,
  ) async {
    if (!widget.canWrite) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final created = await CreateLessonDialog.show(
      context,
      initialDate: day,
      initialBranchId: _selectedBranchId,
      leadId: focus.leadId,
      leadName: focus.leadName,
      initialIsTrial: true,
    );
    if (created == true && mounted) await _fetchDayLessons(day);
  }

  void _armHighlightClear() {
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _highlightLessonId == null) return;
      _emitState(() => _highlightLessonId = null);
    });
  }

  // Drop the focus highlight on the next day / view / branch change so it never
  // lingers on an unrelated day. Safe to call when nothing is highlighted.
  void _clearHighlight() {
    if (_highlightLessonId == null) return;
    _highlightClearTimer?.cancel();
    _highlightLessonId = null;
  }

  // ── Create from the grid (tap = 1h, vertical-select = span) ────────────────
  // Consolidated to the ONE create window — the full [CreateLessonDialog],
  // pre-filled with the picked room/time/duration. (Previously a separate compact
  // "quick" sheet existed too; having three near-identical lesson windows was
  // confusing, so the grid now opens the same dialog the «+» button uses.)
  Future<void> _openQuickCreate(
    String columnId,
    DateTime startLocal,
    int durationMinutes,
  ) async {
    if (!widget.canWrite) return;
    final roomId = (columnId == kUnassignedColumnId || columnId.isEmpty)
        ? null
        : columnId;
    final created = await CreateLessonDialog.show(
      context,
      initialDate: startLocal,
      initialRoomId: roomId,
      initialBranchId: _selectedBranchId,
      initialDurationMinutes: durationMinutes,
      clientType: widget.clientType,
      clientId: widget.clientId,
      clientName: widget.clientName,
    );
    if (created == true && mounted) {
      _fetchDayLessons(_selectedDate);
    }
  }

  Future<void> _openWeekCreate(DateTime startLocal, int durationMinutes) async {
    if (!widget.canWrite) return;
    final created = await CreateLessonDialog.show(
      context,
      initialDate: startLocal,
      initialBranchId: _selectedBranchId,
      initialDurationMinutes: durationMinutes,
      clientType: widget.clientType,
      clientId: widget.clientId,
      clientName: widget.clientName,
    );
    if (created == true && mounted) await _fetchAll();
  }

  Future<void> _refreshEditedSchedule() {
    return _currentView == ScheduleView.week
        ? _fetchAll()
        : _fetchDayLessons(_selectedDate);
  }

  // Drag/drop never mutates the local card before the shared financial decision
  // is previewed and confirmed. A failed or dismissed flow therefore leaves the
  // source lesson exactly where it was.
  Future<void> _moveLessonOptimistic(
    Map<String, dynamic> lesson,
    DateTime newStartLocal,
    String? newColumnId, {
    bool preserveRoom = false,
    bool teacherColumns = false,
  }) async {
    final lessonId = lesson['id']?.toString();
    if (lessonId == null || _movingLesson) return;

    final currentRoomId = lesson['room_id']?.toString();
    final currentTeacherId = lesson['teacher_id']?.toString();
    final targetTeacherId = teacherColumns ? newColumnId : currentTeacherId;
    final targetRoomId = preserveRoom || teacherColumns
        ? currentRoomId
        : (newColumnId == null ||
              newColumnId == kUnassignedColumnId ||
              newColumnId.isEmpty)
        ? null
        : newColumnId;
    final currentStart = _parseLessonTime(lesson);

    // No-op drop (same room + same minute) → skip the round-trip.
    if (currentStart != null &&
        DateUtils.isSameDay(currentStart, newStartLocal) &&
        currentStart.hour == newStartLocal.hour &&
        currentStart.minute == newStartLocal.minute &&
        (targetRoomId ?? '') == (currentRoomId ?? '') &&
        (targetTeacherId ?? '') == (currentTeacherId ?? '')) {
      return;
    }

    final offset = _offsetForLesson(lesson);
    final utc = DateTime.utc(
      newStartLocal.year,
      newStartLocal.month,
      newStartLocal.day,
      newStartLocal.hour,
      newStartLocal.minute,
    ).subtract(Duration(minutes: offset));
    final newScheduledAtIso = utc.toIso8601String();
    final roomChanged =
        !preserveRoom && targetRoomId != null && targetRoomId != currentRoomId;
    final teacherChanged =
        teacherColumns &&
        targetTeacherId != null &&
        targetTeacherId != currentTeacherId;

    _emitState(() => _movingLesson = true);
    try {
      final changed = await showLessonDecisionFlow(
        context,
        api: ref.read(magicApiClientProvider),
        operation: LessonDecisionOperation.reschedule,
        lesson: lesson,
        successor: {
          'scheduledAt': newScheduledAtIso,
          if (roomChanged) 'roomId': targetRoomId,
          if (teacherChanged) 'teacherId': targetTeacherId,
        },
      );
      if (changed == true && mounted) {
        await _refreshEditedSchedule();
        if (!mounted) return;
        MagicToast.show(
          context,
          'Занятие перенесено',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось перенести занятие',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _movingLesson = false);
    }
  }

  // ── Resize via hover/focus edge handles (KVA-195) ──────────────────────────
  // Top handle moves the start, bottom handle moves the end. The shared decision
  // surface owns preview, conflicts, settlement and final commit.
  Future<void> _resizeLesson(
    Map<String, dynamic> lesson,
    DateTime newStartLocal,
    int newDurationMinutes,
  ) async {
    if (!widget.canWrite) return;
    final lessonId = lesson['id']?.toString();
    if (lessonId == null || _movingLesson) return;

    final offset = _offsetForLesson(lesson);
    final utc = DateTime.utc(
      newStartLocal.year,
      newStartLocal.month,
      newStartLocal.day,
      newStartLocal.hour,
      newStartLocal.minute,
    ).subtract(Duration(minutes: offset));
    final newScheduledAtIso = utc.toIso8601String();
    _emitState(() => _movingLesson = true);
    try {
      final changed = await showLessonDecisionFlow(
        context,
        api: ref.read(magicApiClientProvider),
        operation: LessonDecisionOperation.reschedule,
        lesson: lesson,
        successor: {
          'scheduledAt': newScheduledAtIso,
          'durationMinutes': newDurationMinutes,
        },
      );
      if (changed == true && mounted) {
        await _refreshEditedSchedule();
        if (!mounted) return;
        MagicToast.show(
          context,
          'Длительность обновлена',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось изменить длительность',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _movingLesson = false);
    }
  }

  // ── Day view by Teacher ───────────────────────────────────────────────────
  Widget _buildDayViewByTeacher() {
    final dayLessons = _lessonsForDate(_selectedDate);
    final teacherIds =
        dayLessons
            .map((lesson) => lesson['teacher_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList()
          ..sort(
            (left, right) => (_teacherNames[left] ?? '').compareTo(
              _teacherNames[right] ?? '',
            ),
          );
    if (teacherIds.isEmpty) {
      return Center(
        child: Text(
          'Нет занятий на этот день',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final columns = [
      for (var i = 0; i < teacherIds.length; i++)
        ScheduleColumn(
          id: teacherIds[i],
          name: _teacherNames[teacherIds[i]] ?? 'Педагог',
          color: _roomColors[i % _roomColors.length],
          hasConflict: dayLessons.any(
            (lesson) =>
                lesson['teacher_id']?.toString() == teacherIds[i] &&
                conflictTypes(lesson['conflict_types']).isNotEmpty,
          ),
        ),
    ];
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
          movable:
              widget.canWrite &&
              lesson['id'] != null &&
              lesson['status'] != 'cancelled',
          highlighted:
              _highlightLessonId != null &&
              lesson['id']?.toString() == _highlightLessonId,
          clientContext: widget.clientId != null,
          searchContext: _hasScheduleSearch,
          relatedClient: _isRelatedLesson(lesson),
        ),
      );
    }

    return ScheduleDayCanvas(
      key: ValueKey(
        'teacher-day-${dateOnly(_selectedDate)}-'
        '${_selectedBranchId ?? ''}-${columns.length}',
      ),
      date: _selectedDate,
      columns: columns,
      entries: entries,
      allowCreate: widget.canWrite,
      onCreateSlot: (_, start, duration) => _openWeekCreate(start, duration),
      onMove: (lesson, start, teacherId) =>
          _moveLessonOptimistic(lesson, start, teacherId, teacherColumns: true),
      onResize: _resizeLesson,
      onOpenLesson: _showLessonDetails,
      initialVerticalOffset: _dayScrollOffset,
      onVerticalOffsetChanged: _updateDayScrollOffset,
    );
  }

  // ── Lesson details dialog ─────────────────────────────────────────────────
  Future<void> _showLessonDetails(Map<String, dynamic> lesson) async {
    final start = _parseLessonTime(lesson);
    if (start == null) return;

    final duration = _durationMinutes(lesson);
    final end = start.add(Duration(minutes: duration));

    final teacherName =
        _teacherNames[lesson['teacher_id']?.toString()] ?? 'Не назначен';
    // Занятие лида (пробное): ученика нет, показываем имя лида вместо
    // ложного «Не назначен».
    final leadName = lesson['lead_name']?.toString().trim() ?? '';
    final studentName =
        _studentNames[lesson['student_id']?.toString()] ??
        (leadName.isNotEmpty ? '$leadName (лид)' : 'Не назначен');
    final roomId = lesson['room_id']?.toString();
    final roomName = roomId != null
        ? (_roomNames[roomId] ?? 'Аудитория')
        : 'Без аудитории';
    final conflicts = conflictTypes(lesson['conflict_types']);
    final lessonId = lesson['id']?.toString();
    final currentStatus = lesson['status']?.toString() ?? 'scheduled';
    CapabilitySnapshot? snapshot;
    try {
      snapshot = await ref.read(capabilitySnapshotProvider.future);
    } catch (_) {
      // Linked rows fail closed below; lesson details themselves remain useful.
    }
    if (!mounted) return;
    final registry = EntityRouteRegistry();
    LessonEntityReference reference({
      required IconData icon,
      required String label,
      required String value,
      required EntityLink? link,
    }) => LessonEntityReference(
      icon: icon,
      label: label,
      value: value,
      link: link,
      available:
          link == null ||
          (snapshot != null && registry.resolve(link, snapshot).canOpen),
    );
    final studentId = lesson['student_id']?.toString();
    final leadId = lesson['lead_id']?.toString();
    final teacherId = lesson['teacher_id']?.toString();
    final groupId = lesson['group_id']?.toString();
    final branchId = lesson['branch_id']?.toString();
    final branchName = lesson['branch_name']?.toString() ?? 'Филиал';
    final groupName = lesson['group_name']?.toString() ?? 'Группа';
    final dateFilter = DateTime(
      start.year,
      start.month,
      start.day,
    ).toIso8601String();
    final references = [
      if (lessonId?.isNotEmpty == true)
        reference(
          icon: Icons.event_note_rounded,
          label: 'Занятие',
          value: studentName,
          link: EntityLink.typed(
            entityType: EntityLinkType.lesson,
            entityId: lessonId!,
            presentation: EntityPresentationReference(
              primary: studentName,
              context: branchName,
            ),
            optionalFocus: EntityLinkFocus(
              focus: 'lesson',
              filter: {
                'date': dateFilter,
                if (branchId?.isNotEmpty == true) 'branchId': branchId,
                if (studentId?.isNotEmpty == true) 'clientType': 'student',
                if (leadId?.isNotEmpty == true) 'clientType': 'lead',
                if (studentId?.isNotEmpty == true) 'clientId': studentId,
                if (leadId?.isNotEmpty == true) 'clientId': leadId,
              },
            ),
          ),
        ),
      reference(
        icon: Icons.person_rounded,
        label: leadId?.isNotEmpty == true ? 'Лид' : 'Ученик',
        value: studentName,
        link: (studentId?.isNotEmpty == true || leadId?.isNotEmpty == true)
            ? EntityLink.typed(
                entityType: EntityLinkType.client,
                entityId: leadId?.isNotEmpty == true ? leadId! : studentId!,
                variant: leadId?.isNotEmpty == true ? 'lead' : 'student',
                presentation: EntityPresentationReference(
                  primary: studentName,
                  context: branchName,
                ),
              )
            : null,
      ),
      reference(
        icon: Icons.school_rounded,
        label: 'Педагог',
        value: teacherName,
        link: teacherId?.isNotEmpty == true
            ? EntityLink.typed(
                entityType: EntityLinkType.teacher,
                entityId: teacherId!,
                presentation: EntityPresentationReference(
                  primary: teacherName,
                  context: branchName,
                ),
                optionalFocus: EntityLinkFocus(
                  focus: 'schedule',
                  filter: {'teacherId': teacherId, 'date': dateFilter},
                ),
              )
            : null,
      ),
      reference(
        icon: Icons.room_rounded,
        label: 'Аудитория',
        value: roomName,
        link: roomId?.isNotEmpty == true
            ? EntityLink.typed(
                entityType: EntityLinkType.room,
                entityId: roomId!,
                presentation: EntityPresentationReference(
                  primary: roomName,
                  context: branchName,
                ),
                optionalFocus: EntityLinkFocus(
                  focus: 'schedule',
                  filter: {'roomId': roomId, 'date': dateFilter},
                ),
              )
            : null,
      ),
      if (groupId?.isNotEmpty == true)
        reference(
          icon: Icons.groups_rounded,
          label: 'Группа',
          value: groupName,
          link: EntityLink.typed(
            entityType: EntityLinkType.group,
            entityId: groupId!,
            presentation: EntityPresentationReference(
              primary: groupName,
              context: branchName,
            ),
            optionalFocus: EntityLinkFocus(
              focus: 'schedule',
              filter: {'date': dateFilter},
            ),
          ),
        ),
      if (branchId?.isNotEmpty == true)
        reference(
          icon: Icons.apartment_rounded,
          label: 'Филиал',
          value: branchName,
          link: EntityLink.typed(
            entityType: EntityLinkType.branch,
            entityId: branchId!,
            presentation: EntityPresentationReference(primary: branchName),
            optionalFocus: EntityLinkFocus(
              focus: 'schedule',
              filter: {'branchId': branchId, 'date': dateFilter},
            ),
          ),
        ),
    ];

    final timeRange =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    await showLessonDetailsSheet(
      context,
      teacherName: teacherName,
      studentName: studentName,
      roomName: roomName,
      references: references,
      onOpenReference: (link, target) {
        Future.microtask(() {
          if (!mounted) return;
          unawaited(
            openEntityLink(
              context,
              ref,
              link,
              target: target,
              sourceViewState: _scheduleViewState(),
            ),
          );
        });
      },
      showNewTabAction:
          WorkspaceNavigationScope.maybeOf(context)?.isDesktop == true,
      timeRange: timeRange,
      currentStatus: currentStatus,
      conflicts: conflicts,
      lessonId: widget.canWrite ? lessonId : null,
      onEdit: () => _editLesson(lesson),
      onCancel: () => _cancelLesson(lesson),
      onSettle:
          currentStatus == 'scheduled' || currentStatus == 'settlement_pending'
          ? () => _settleLesson(lesson)
          : null,
    );
  }

  Future<void> _editLesson(Map<String, dynamic> lesson) async {
    if (!widget.canWrite) return;
    final changed = await CreateLessonDialog.show(context, lesson: lesson);
    if (changed == true) _fetchAll();
  }

  Future<void> _cancelLesson(Map<String, dynamic> lesson) async {
    if (!widget.canWrite) return;
    final changed = await showLessonDecisionFlow(
      context,
      api: ref.read(magicApiClientProvider),
      operation: LessonDecisionOperation.cancel,
      lesson: lesson,
    );
    if (changed == true && mounted) {
      await _refreshEditedSchedule();
      if (!mounted) return;
      MagicToast.show(
        context,
        'Занятие отменено',
        type: MagicToastType.success,
      );
    }
  }

  Future<void> _settleLesson(Map<String, dynamic> lesson) async {
    if (!widget.canWrite) return;
    final changed = await showLessonDecisionFlow(
      context,
      api: ref.read(magicApiClientProvider),
      operation: LessonDecisionOperation.settle,
      lesson: lesson,
    );
    if (changed == true && mounted) {
      await _refreshEditedSchedule();
      if (!mounted) return;
      MagicToast.show(
        context,
        'Результат занятия зафиксирован',
        type: MagicToastType.success,
      );
    }
  }
}
