part of 'schedule_widget.dart';

extension _ScheduleViewsB on _ScheduleWidgetState {
  // day-view, remember the highlight id (matched by `id` in the day's data) and
  // backfill the day. The canvas renders the gold pulse; we arm a timer to clear
  // it. We then consume the navigation request so re-tapping re-fires focus.
  void _applyScheduleFocus(ScheduleFocusState focus) {
    final date = focus.focusDate;
    final day = DateTime(date.year, date.month, date.day);
    _highlightClearTimer?.cancel();
    _emitState(() {
      _selectedDate = day;
      _displayedMonth = DateTime(day.year, day.month);
      _currentView = ScheduleView.day;
      _highlightLessonId = focus.highlightLessonId;
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
    final roomId = (columnId == kUnassignedColumnId || columnId.isEmpty)
        ? null
        : columnId;
    final created = await CreateLessonDialog.show(
      context,
      initialDate: startLocal,
      initialRoomId: roomId,
      initialBranchId: _selectedBranchId,
      initialDurationMinutes: durationMinutes,
    );
    if (created == true && mounted) {
      _fetchDayLessons(_selectedDate);
    }
  }

  // ── Optimistic move + rollback + undo (KVA-195) ────────────────────────────
  // Vertical drop → new time; horizontal drop → new room. The block jumps to the
  // new slot immediately (the rest of the grid stays put), then the move commits
  // via the SAME `updateLesson` PATCH the app already used. On error we roll the
  // block back; on success a short «Отменить» snackbar reverts it.
  Future<void> _moveLessonOptimistic(
    Map<String, dynamic> lesson,
    DateTime newStartLocal,
    String newColumnId,
  ) async {
    final lessonId = lesson['id']?.toString();
    if (lessonId == null || _movingLesson) return;

    final targetRoomId =
        (newColumnId == kUnassignedColumnId || newColumnId.isEmpty)
        ? null
        : newColumnId;
    final currentRoomId = lesson['room_id']?.toString();
    final currentStart = _parseLessonTime(lesson);

    // No-op drop (same room + same minute) → skip the round-trip.
    if (currentStart != null &&
        currentStart.hour == newStartLocal.hour &&
        currentStart.minute == newStartLocal.minute &&
        (targetRoomId ?? '') == (currentRoomId ?? '')) {
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

    // Snapshot for rollback / undo BEFORE the in-place patch.
    final prevScheduledAt = lesson['scheduled_at'];
    final prevRoomId = lesson['room_id'];
    final prevConflicts = lesson['conflict_types'];
    final roomChanged = targetRoomId != null && targetRoomId != currentRoomId;

    _emitState(() {
      _movingLesson = true;
      lesson['scheduled_at'] = newScheduledAtIso;
      // Drop the stale conflict flag immediately — the slot changed, so the old
      // verdict no longer applies. The refetch below re-derives it server-side
      // and re-flags only if the new slot genuinely conflicts.
      lesson['conflict_types'] = const <String>[];
      if (roomChanged) {
        lesson['room_id'] = targetRoomId;
        lesson['room_name'] = _roomNames[targetRoomId];
      }
    });

    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateLesson(
            lessonId,
            expectedVersion: (lesson['version'] as num?)?.toInt() ?? 1,
            scheduledAt: newScheduledAtIso,
            roomId: roomChanged ? targetRoomId : null,
          );
      if (!mounted) return;
      await _fetchDayLessons(_selectedDate); // server re-derives conflicts
      if (!mounted) return;
      final moved = _lessons.firstWhere(
        (l) => l['id']?.toString() == lessonId,
        orElse: () => const <String, dynamic>{},
      );
      final conflicts = conflictTypes(moved['conflict_types']);
      if (conflicts.isNotEmpty) {
        MagicToast.show(
          context,
          'Перенесено, но есть конфликт',
          detail: conflicts.map(conflictLabel).join(', '),
          type: MagicToastType.danger,
        );
      } else if (prevRoomId != null || !roomChanged) {
        // Undo restores time + room. Clearing a room back to «Без аудитории»
        // isn't expressible via the PATCH contract, so only offer undo when the
        // previous room is reversible (a real room, or the room didn't change).
        _showUndoableMove(lessonId, prevScheduledAt, prevRoomId);
      } else {
        MagicToast.show(
          context,
          'Занятие перенесено',
          type: MagicToastType.success,
        );
      }
    } on MagicApiException catch (e) {
      if (!mounted) return;
      _emitState(() {
        lesson['scheduled_at'] = prevScheduledAt;
        lesson['room_id'] = prevRoomId;
        lesson['room_name'] = prevRoomId == null
            ? null
            : _roomNames[prevRoomId.toString()];
        lesson['conflict_types'] = prevConflicts;
      });
      final violations = lessonConstraintViolations(e);
      final conflicts = scheduleConflictsFrom409(e);
      if (violations != null && violations.isNotEmpty) {
        await _showScheduleViolations(violations);
      } else if (conflicts != null) {
        await _confirmScheduleBusy(conflicts);
      } else {
        MagicToast.show(
          context,
          'Не удалось перенести занятие',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } catch (e) {
      if (mounted) {
        _emitState(() {
          lesson['scheduled_at'] = prevScheduledAt;
          lesson['room_id'] = prevRoomId;
          lesson['room_name'] = prevRoomId == null
              ? null
              : _roomNames[prevRoomId.toString()];
          lesson['conflict_types'] = prevConflicts;
        });
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

  Future<void> _confirmScheduleBusy(List<ScheduleConflictInfo> conflicts) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColor.danger),
        title: const Text('Время занято'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('В этот слот уже есть занятия:'),
            const SizedBox(height: 8),
            for (final conflict in conflicts.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${conflict.label()}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            const SizedBox(height: 4),
            const Text('Выберите другой слот: обход конфликтов недоступен.'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Исправить'),
          ),
        ],
      ),
    );
  }

  Future<void> _showScheduleViolations(
    List<LessonConstraintViolation> violations,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.rule_rounded, color: AppColor.danger),
        title: const Text('Изменение не сохранено'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final violation in violations)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${violation.title}\n'
                  '  ${violation.resourceLabel}: ${violation.resourceId}',
                ),
              ),
            const Text('Исправьте все ограничения и повторите действие.'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Исправить'),
          ),
        ],
      ),
    );
  }

  void _showUndoableMove(
    String lessonId,
    dynamic prevScheduledAt,
    dynamic prevRoomId,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Занятие перенесено'),
        backgroundColor: AppColor.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Отменить',
          textColor: Colors.white,
          onPressed: () => _undoMove(lessonId, prevScheduledAt, prevRoomId),
        ),
      ),
    );
  }

  Future<void> _undoMove(
    String lessonId,
    dynamic prevScheduledAt,
    dynamic prevRoomId,
  ) async {
    if (prevScheduledAt == null) return;
    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateLesson(
            lessonId,
            expectedVersion:
                (_lessons.firstWhere(
                          (row) => row['id']?.toString() == lessonId,
                          orElse: () => const <String, dynamic>{},
                        )['version']
                        as num?)
                    ?.toInt() ??
                1,
            scheduledAt: prevScheduledAt.toString(),
            roomId: prevRoomId?.toString(),
          );
      if (mounted) await _fetchDayLessons(_selectedDate);
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось отменить перенос',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  // ── Resize via hover/focus edge handles (KVA-195) ──────────────────────────
  // Top handle moves the start, bottom handle moves the end. Committed on release
  // through the existing `updateLesson` PATCH — never opens the editor.
  Future<void> _resizeLesson(
    Map<String, dynamic> lesson,
    DateTime newStartLocal,
    int newDurationMinutes,
  ) async {
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

    final prevScheduledAt = lesson['scheduled_at'];
    final prevDuration = lesson['duration_minutes'];
    final prevConflicts = lesson['conflict_types'];

    _emitState(() {
      _movingLesson = true;
      lesson['scheduled_at'] = newScheduledAtIso;
      lesson['duration_minutes'] = newDurationMinutes;
      lesson['conflict_types'] = const <String>[];
    });

    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateLesson(
            lessonId,
            expectedVersion: (lesson['version'] as num?)?.toInt() ?? 1,
            scheduledAt: newScheduledAtIso,
            durationMinutes: newDurationMinutes,
          );
      if (!mounted) return;
      await _fetchDayLessons(_selectedDate);
      if (!mounted) return;
      MagicToast.show(
        context,
        'Длительность обновлена',
        type: MagicToastType.success,
      );
    } on MagicApiException catch (e) {
      if (!mounted) return;
      _emitState(() {
        lesson['scheduled_at'] = prevScheduledAt;
        lesson['duration_minutes'] = prevDuration;
        lesson['conflict_types'] = prevConflicts;
      });
      final violations = lessonConstraintViolations(e);
      final conflicts = scheduleConflictsFrom409(e);
      if (violations != null && violations.isNotEmpty) {
        await _showScheduleViolations(violations);
      } else if (conflicts != null) {
        await _confirmScheduleBusy(conflicts);
      } else {
        MagicToast.show(
          context,
          'Не удалось изменить длительность',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } catch (e) {
      if (mounted) {
        _emitState(() {
          lesson['scheduled_at'] = prevScheduledAt;
          lesson['duration_minutes'] = prevDuration;
          lesson['conflict_types'] = prevConflicts;
        });
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

    // Get unique teacher IDs for this day
    final teacherIds = dayLessons
        .map((l) => l['teacher_id']?.toString())
        .where((id) => id != null)
        .toSet()
        .toList();
    teacherIds.sort(
      (a, b) => (_teacherNames[a] ?? '').compareTo(_teacherNames[b] ?? ''),
    );

    if (_selectedTeacherId == null && teacherIds.isNotEmpty) {
      _selectedTeacherId = teacherIds.first;
    }

    // Filter lessons for selected teacher
    final teacherLessons = dayLessons
        .where((l) => l['teacher_id']?.toString() == _selectedTeacherId)
        .toList();
    teacherLessons.sort((a, b) {
      final aTime = _parseLessonTime(a);
      final bTime = _parseLessonTime(b);
      if (aTime == null || bTime == null) return 0;
      return aTime.compareTo(bTime);
    });

    // All teachers from the data (not just today)
    final allTeachers = _teachers.where((t) {
      // Only show teachers that have lessons in this branch
      return true;
    }).toList();

    return Column(
      children: [
        // Teacher selector
        if (allTeachers.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: allTeachers.length,
              itemBuilder: (context, i) {
                final t = allTeachers[i];
                final tid = t['id'].toString();
                final isSelected = _selectedTeacherId == tid;
                final name = _teacherNames[tid] ?? 'Без имени';
                final initials = name
                    .split(' ')
                    .map((w) => w.isNotEmpty ? w[0] : '')
                    .take(2)
                    .join('')
                    .toUpperCase();
                final lessonsCount = dayLessons
                    .where((l) => l['teacher_id']?.toString() == tid)
                    .length;

                return GestureDetector(
                  onTap: () => _emitState(() => _selectedTeacherId = tid),
                  child: Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColor.gold.withAlpha(30)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColor.gold : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColor.gold.withAlpha(50),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: AppColor.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$lessonsCount зан.',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant.withAlpha(150),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        SizedBox(height: 8),
        // Teacher lessons list
        Expanded(
          child: teacherLessons.isEmpty
              ? Center(
                  child: Text(
                    _selectedTeacherId == null
                        ? 'Выберите педагога'
                        : 'Нет занятий на этот день',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: teacherLessons.length,
                  itemBuilder: (context, i) =>
                      _buildTeacherLessonCard(teacherLessons[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildTeacherLessonCard(Map<String, dynamic> lesson) {
    final start = _parseLessonTime(lesson);
    if (start == null) return const SizedBox.shrink();

    final duration = _durationMinutes(lesson);
    final end = start.add(Duration(minutes: duration));

    final timeStr =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';

    // Пробное по лиду: student_id пуст, имя приходит в lead_name — карточка
    // не должна падать в безликое «Ученик».
    final leadName = lesson['lead_name']?.toString().trim() ?? '';
    final studentName =
        _studentNames[lesson['student_id']?.toString()] ??
        (leadName.isNotEmpty ? '$leadName (лид)' : 'Ученик');
    final roomId = lesson['room_id']?.toString();
    final roomName = roomId != null
        ? (_roomNames[roomId] ?? 'Аудитория')
        : 'Без аудитории';
    final roomColor = roomId != null
        ? (_roomColorMap[roomId] ??
              Theme.of(context).colorScheme.onSurfaceVariant)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final conflicts = conflictTypes(lesson['conflict_types']);

    return TeacherLessonCard(
      timeStr: timeStr,
      studentName: studentName,
      roomName: roomName,
      roomColor: roomColor,
      stateProjection: LessonStateProjection.fromMap(lesson),
      isTrial: lesson['is_trial'] == true,
      hasConflict: conflicts.isNotEmpty,
      onTap: () => _showLessonDetails(lesson),
    );
  }

  // ── Lesson details dialog ─────────────────────────────────────────────────
  void _showLessonDetails(Map<String, dynamic> lesson) {
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

    final timeRange =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    showLessonDetailsSheet(
      context,
      teacherName: teacherName,
      studentName: studentName,
      roomName: roomName,
      timeRange: timeRange,
      currentStatus: currentStatus,
      conflicts: conflicts,
      lessonId: lessonId,
      onEdit: () => _editLesson(lesson),
      onDelete: () => _deleteLesson(lessonId!),
    );
  }

  Future<void> _editLesson(Map<String, dynamic> lesson) async {
    final changed = await CreateLessonDialog.show(context, lesson: lesson);
    if (changed == true) _fetchAll();
  }

  Future<void> _deleteLesson(String lessonId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(magicCrmServiceProvider).deleteLesson(lessonId);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Занятие удалено'),
          backgroundColor: AppColor.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _fetchAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось удалить занятие: $e'),
          backgroundColor: AppColor.danger,
        ),
      );
    }
  }
}
