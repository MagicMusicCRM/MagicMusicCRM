part of 'schedule_widget.dart';

extension _ScheduleActions on _ScheduleWidgetState {
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
      clientType: _contextClientType,
      clientId: _contextClientId,
      clientName: _contextClientName,
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
      clientType: _contextClientType,
      clientId: _contextClientId,
      clientName: _contextClientName,
    );
    if (created == true && mounted) await _fetchAll();
  }

  Future<void> _refreshEditedSchedule() {
    return _currentView == ScheduleView.week
        ? _fetchAll()
        : _fetchDayLessons(_selectedDate);
  }

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
    final lifecycleState =
        lesson['lifecycle_state']?.toString() ??
        lesson['lifecycleState']?.toString() ??
        currentStatus;
    final settlementIssue = lifecycleState == 'settlement_pending'
        ? lessonSettlementIssueLabel(
            lesson['settlement_failure_code']?.toString(),
          )
        : null;
    var settlementHistory = <Map<String, dynamic>>[];
    if (widget.canWrite && lessonId?.isNotEmpty == true) {
      try {
        final response = await ref
            .read(magicCrmServiceProvider)
            .getLessonSettlementHistory(lessonId!);
        settlementHistory = [
          for (final item in response['items'] as List? ?? const [])
            if (item is Map) Map<String, dynamic>.from(item),
        ];
      } catch (_) {
        // Детали занятия остаются доступны; мутация всё равно потребует
        // актуальный подписанный preview с сервера.
      }
    }
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
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - '
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
      timeRange: timeRange,
      currentStatus: lifecycleState,
      conflicts: conflicts,
      settlementIssue: settlementIssue,
      settlementHistory: settlementHistory,
      lessonId: widget.canWrite ? lessonId : null,
      onEdit: () => _editLesson(lesson),
      onCancel: () => _cancelLesson(lesson),
      onSettle: lifecycleState == 'settlement_pending'
          ? () => _settleLesson(lesson)
          : null,
      onAdjustSettlement:
          lifecycleState == 'successfully_completed' ||
              currentStatus == 'completed' ||
              currentStatus == 'done'
          ? () => _adjustLessonSettlement(
              lesson,
              LessonDecisionOperation.correction,
            )
          : lifecycleState == 'scheduled' && start.isAfter(DateTime.now())
          ? () => _adjustLessonSettlement(
              lesson,
              LessonDecisionOperation.plannedSettlement,
            )
          : null,
      adjustSettlementLabel:
          lifecycleState == 'successfully_completed' ||
              currentStatus == 'completed' ||
              currentStatus == 'done'
          ? 'Исправить расчёт'
          : 'Изменить расчёт',
    );
  }

  Future<void> _editLesson(Map<String, dynamic> lesson) async {
    if (!widget.canWrite) return;
    final changed = await CreateLessonDialog.show(context, lesson: lesson);
    if (changed == true && mounted) await _fetchAll();
  }

  Future<void> _cancelLesson(Map<String, dynamic> lesson) async {
    if (!widget.canWrite) return;
    final changed = await showLessonDecisionFlow(
      context,
      crm: ref.read(magicCrmServiceProvider),
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
      crm: ref.read(magicCrmServiceProvider),
      operation: LessonDecisionOperation.settle,
      lesson: lesson,
    );
    if (changed == true && mounted) {
      await _refreshEditedSchedule();
      if (!mounted) return;
      MagicToast.show(
        context,
        'Расчёт занятия исправлен',
        type: MagicToastType.success,
      );
    }
  }

  Future<void> _adjustLessonSettlement(
    Map<String, dynamic> lesson,
    LessonDecisionOperation operation,
  ) async {
    if (!widget.canWrite) return;
    final changed = await showLessonDecisionFlow(
      context,
      crm: ref.read(magicCrmServiceProvider),
      operation: operation,
      lesson: lesson,
    );
    if (changed == true && mounted) {
      await _refreshEditedSchedule();
      if (!mounted) return;
      MagicToast.show(
        context,
        operation == LessonDecisionOperation.correction
            ? 'Расчёт занятия исправлен'
            : 'Расчёт занятия изменён',
        type: MagicToastType.success,
      );
    }
  }

  // ── Data fetching ─────────────────────────────────────────────────────────
  Future<void> _fetchAll() async {
    _emitState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final DateTime from;
      final DateTime to;
      if (_currentView == ScheduleView.week) {
        final monday = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        ).subtract(Duration(days: _selectedDate.weekday - 1));
        // One-day guards keep the whole branch-local week inside the UTC query
        // for every supported branch offset; rendering still clips to Mon–Sun.
        from = monday.subtract(const Duration(days: 1));
        to = monday.add(const Duration(days: 8));
      } else {
        from = DateTime(
          _displayedMonth.year,
          _displayedMonth.month,
          1,
        ).subtract(const Duration(days: 7));
        to = DateTime(
          _displayedMonth.year,
          _displayedMonth.month + 1,
          1,
        ).add(const Duration(days: 7));
      }
      final fromIso = from.toUtc().toIso8601String();
      final toIso = to.toUtc().toIso8601String();

      // Wave 1: branches + rooms only (small, fast).
      // Teachers/students/lessons are NOT loaded separately — the schedule
      // matrix already returns names inline, saving 3 HTTP round-trips.
      final wave1 = await Future.wait([
        crm.listBranches(limit: 100),
        crm.listRooms(limit: 100),
      ]);
      final branches = wave1[0];
      final rooms = wave1[1];

      // First open with no branch chosen yet → default to the user's OWN
      // branch (staff assignment), resolved once. Falls back to the first
      // branch only when the user has no assignment or it isn't in the list.
      if (_selectedBranchId == null &&
          widget.fixedTeacherId == null &&
          !_homeBranchResolved) {
        _homeBranchResolved = true;
        try {
          final me = await ref
              .read(magicProfileAdminServiceProvider)
              .getMyProfile();
          final home = me['homeBranchId']?.toString();
          if (home != null && home.isNotEmpty) _homeBranchId = home;
        } catch (_) {
          // Non-fatal: fall back to the first branch below.
        }
      }

      String? defaultBranch = _selectedBranchId;
      if (defaultBranch == null &&
          widget.fixedTeacherId == null &&
          branches.isNotEmpty) {
        final home = _homeBranchId;
        final hasHome =
            home != null && branches.any((b) => b['id'].toString() == home);
        defaultBranch = hasHome ? home : branches.first['id'].toString();
      }

      // Per-branch UTC offset map (minutes), for rendering lesson times in the
      // branch's local zone.
      final offsets = <String, int>{};
      for (final b in branches) {
        final bid = b['id']?.toString();
        if (bid == null) continue;
        final raw = b['utc_offset_minutes'];
        offsets[bid] = raw is int
            ? raw
            : int.tryParse(raw?.toString() ?? '') ?? 180;
      }

      // Room color map
      final colorMap = <String, Color>{};
      final nameMap = <String, String>{};
      for (int i = 0; i < rooms.length; i++) {
        final rid = rooms[i]['id'].toString();
        colorMap[rid] = _roomColors[i % _roomColors.length];
        nameMap[rid] = rooms[i]['name']?.toString() ?? 'Аудитория';
      }

      // Wave 2: matrix + availability + month-summary (all parallel).
      var enrichedLessons = <Map<String, dynamic>>[];
      var scheduleConflicts = <Map<String, dynamic>>[];
      var roomAvailability = <Map<String, dynamic>>[];
      final monthSummary = <String, Map<String, dynamic>>{};

      final wave2 = await Future.wait<Object?>([
        crm.getScheduleMatrix(
          from: fromIso,
          to: toIso,
          branchId: defaultBranch,
          groupBy: _dayViewMode == DayViewMode.byTeacher ? 'teacher' : 'room',
          teacherId: widget.fixedTeacherId ?? _filterTeacherId,
          limit: _currentView == ScheduleView.week || _filterClientId != null
              ? 500
              : 300,
        ),
        defaultBranch == null
            ? Future.value(<String, dynamic>{})
            : crm
                  .listRoomAvailability(
                    branchId: defaultBranch,
                    date: dateOnly(_selectedDate),
                    from: _slotIso(_selectedDate, 6),
                    to: _slotIso(_selectedDate, 23),
                    limit: 100,
                  )
                  .catchError((e) {
                    debugPrint('Error fetching room availability: $e');
                    return <String, dynamic>{};
                  }),
        !widget.allowMonth
            ? Future.value(<Map<String, dynamic>>[])
            : crm
                  .getScheduleMonthSummary(
                    from: fromIso,
                    to: toIso,
                    branchId: defaultBranch,
                  )
                  .catchError((e) {
                    debugPrint('Error fetching month summary: $e');
                    return <Map<String, dynamic>>[];
                  }),
      ]);

      final matrixResult = wave2[0] as Map<String, dynamic>;
      final availabilityResult = wave2[1] as Map<String, dynamic>;
      final summaryResult = wave2[2] as List<Map<String, dynamic>>;

      final matrixItems = matrixResult['items'];
      if (matrixItems is List && matrixItems.isNotEmpty) {
        enrichedLessons = matrixItems
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      final conflicts = matrixResult['conflicts'];
      if (conflicts is List) {
        scheduleConflicts = conflicts
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      final availabilityItems = availabilityResult['items'];
      if (availabilityItems is List) {
        roomAvailability = availabilityItems
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      for (final item in summaryResult) {
        final day = item['day']?.toString();
        if (day != null) monthSummary[day] = item;
      }

      var visibleBranches = branches;
      var visibleRooms = rooms;
      if (widget.fixedTeacherId != null) {
        final assignedBranchIds = enrichedLessons
            .map((lesson) => lesson['branch_id']?.toString())
            .whereType<String>()
            .toSet();
        visibleBranches = branches
            .where(
              (branch) => assignedBranchIds.contains(branch['id']?.toString()),
            )
            .toList();
        visibleRooms = rooms
            .where(
              (room) =>
                  assignedBranchIds.contains(room['branch_id']?.toString()),
            )
            .toList();
        defaultBranch ??= enrichedLessons.firstOrNull?['branch_id']?.toString();
      }

      // Build teacher/student name maps from matrix data (no extra API calls).
      final tNames = <String, String>{};
      final sNames = <String, String>{};
      for (final lesson in enrichedLessons) {
        final tid = lesson['teacher_id']?.toString();
        if (tid != null && tid.isNotEmpty) {
          final name = lesson['teacher_name']?.toString() ?? '';
          if (name.isNotEmpty) tNames[tid] = name;
        }
        final sid = lesson['student_id']?.toString();
        if (sid != null && sid.isNotEmpty) {
          final name = lesson['student_name']?.toString() ?? '';
          if (name.isNotEmpty) sNames[sid] = name;
        }
      }

      // If the auto-selected branch returned no lessons, try to pick one that
      // has data (from month-summary which covers all branches). The matrix was
      // fetched for the original branch, so switching here alone would leave the
      // day view empty (lessons belong to the old branch) — we must re-fetch the
      // matrix for the newly chosen branch. Guard with _autoBranchRetried so this
      // happens at most once and never loops (KVA-166).
      var rerunForBranch = false;
      if (enrichedLessons.isEmpty &&
          _selectedBranchId == null &&
          !_autoBranchRetried &&
          visibleBranches.length > 1) {
        for (final b in visibleBranches) {
          final bid = b['id'].toString();
          if (bid != defaultBranch) {
            defaultBranch = bid;
            rerunForBranch = true;
            break;
          }
        }
      }

      if (rerunForBranch) {
        _autoBranchRetried = true;
        _selectedBranchId = defaultBranch;
        // Re-fetch the full payload for the branch that actually has lessons so
        // the day grid isn't left empty against the original (empty) branch.
        if (mounted) await _fetchAll();
        return;
      }

      _emitState(() {
        _branches = visibleBranches;
        _branchOffsets = offsets;
        _rooms = visibleRooms;
        _lessons = enrichedLessons;
        _scheduleConflicts = scheduleConflicts;
        _roomAvailability = roomAvailability;
        _selectedBranchId = defaultBranch;
        _roomColorMap = colorMap;
        _roomNames = nameMap;
        _monthDaySummary = monthSummary;
        _teacherNames = tNames;
        _studentNames = sNames;
        _isLoading = false;
        _hasLoadedOnce = true;
      });

      // The month-wide matrix is capped at 300 rows; if we're already in the day
      // view, backfill the selected day so it isn't left empty for dates past the
      // cap (e.g. today mid-month).
      if (_currentView == ScheduleView.day) {
        _fetchAvailabilityForSelectedDay();
        _fetchDayLessons(_selectedDate);
      }
    } catch (e) {
      debugPrint('Error fetching schedule: $e');
      _emitState(() {
        _loadError = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchAvailabilityForSelectedDay() async {
    final branchId = _selectedBranchId;
    if (branchId == null || branchId.isEmpty) return;
    _emitState(() => _availabilityLoading = true);
    try {
      final response = await ref
          .read(magicCrmServiceProvider)
          .listRoomAvailability(
            branchId: branchId,
            date: dateOnly(_selectedDate),
            from: _slotIso(_selectedDate, 6),
            to: _slotIso(_selectedDate, 23),
            limit: 100,
          );
      final items = response['items'];
      if (!mounted) return;
      _emitState(() {
        _roomAvailability = items is List
            ? items.whereType<Map<String, dynamic>>().toList()
            : const <Map<String, dynamic>>[];
      });
    } catch (e) {
      debugPrint('Error fetching room availability: $e');
    } finally {
      if (mounted) _emitState(() => _availabilityLoading = false);
    }
  }

  // Fetch the lessons for ONE day (branch-local) and merge them into _lessons.
  // The month-wide matrix in _fetchAll is capped at limit=300 ordered ascending,
  // so days past the first few are missing from the in-memory list and the day
  // grid renders empty even though the month summary counts them. A day-scoped
  // fetch (≈tens of lessons, well under the cap) backfills the selected day.
  Future<void> _fetchDayLessons(DateTime date) async {
    final branchId = _selectedBranchId;
    if (branchId == null || branchId.isEmpty) return;
    final offset = _branchOffsets[branchId] ?? 180;
    // Branch-local midnight expressed as the corresponding UTC instant.
    final dayStartUtc = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(minutes: offset));
    final dayEndUtc = dayStartUtc.add(const Duration(days: 1));
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .getScheduleMatrix(
            from: dayStartUtc.toIso8601String(),
            to: dayEndUtc.toIso8601String(),
            branchId: branchId,
            groupBy: _dayViewMode == DayViewMode.byTeacher ? 'teacher' : 'room',
            teacherId: widget.fixedTeacherId ?? _filterTeacherId,
            limit: 500,
          );
      final items = result['items'];
      if (items is! List || !mounted) return;
      final dayLessons = items.whereType<Map<String, dynamic>>().toList();

      // Upsert by id so the rest of the loaded window is preserved while the
      // selected day becomes complete.
      final byId = <String, Map<String, dynamic>>{
        for (final l in _lessons)
          if (l['id'] != null) l['id'].toString(): l,
      };
      for (final l in dayLessons) {
        final id = l['id']?.toString();
        if (id != null) byId[id] = l;
      }

      final tNames = Map<String, String>.from(_teacherNames);
      final sNames = Map<String, String>.from(_studentNames);
      for (final l in dayLessons) {
        final tid = l['teacher_id']?.toString();
        final tn = l['teacher_name']?.toString();
        if (tid != null && tid.isNotEmpty && tn != null && tn.isNotEmpty) {
          tNames[tid] = tn;
        }
        final sid = l['student_id']?.toString();
        final sn = l['student_name']?.toString();
        if (sid != null && sid.isNotEmpty && sn != null && sn.isNotEmpty) {
          sNames[sid] = sn;
        }
      }

      _emitState(() {
        _lessons = byId.values.toList();
        _teacherNames = tNames;
        _studentNames = sNames;
      });
      if (!_highlightUnavailableShown &&
          _highlightLessonId != null &&
          !dayLessons.any(
            (lesson) => lesson['id']?.toString() == _highlightLessonId,
          )) {
        _highlightUnavailableShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Связанная запись недоступна.')),
          );
        });
      }
    } catch (e) {
      debugPrint('Error fetching day lessons: $e');
    }
  }

  // ── Filtered helpers ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredRooms {
    if (_selectedBranchId == null) return _rooms;
    return _rooms
        .where((r) => r['branch_id']?.toString() == _selectedBranchId)
        .toList();
  }

  List<Map<String, dynamic>> get _filteredLessons {
    return _lessons.where((l) {
      if (l['scheduled_at'] == null) return false;
      if (_selectedBranchId != null &&
          l['branch_id'] != null &&
          l['branch_id'].toString() != _selectedBranchId) {
        return false;
      }
      // Optional filters — applied over the already-loaded matrix, no refetch.
      if (_onlyTrial && l['is_trial'] != true) return false;
      if (_onlyConflicts && conflictTypes(l['conflict_types']).isEmpty) {
        return false;
      }
      if (_filterTeacherId != null &&
          l['teacher_id']?.toString() != _filterTeacherId) {
        return false;
      }
      if (_filterRoomId != null && l['room_id']?.toString() != _filterRoomId) {
        return false;
      }
      if (_hasClientContext &&
          _hideOtherClientLessons &&
          !_isContextClientLesson(l)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Teacher options for the filter sheet, from the lessons currently loaded.
  List<({String id, String name})> get _teacherFilterOptions {
    final seen = <String, String>{};
    for (final l in _lessons) {
      final id = l['teacher_id']?.toString();
      if (id == null || id.isEmpty) continue;
      seen[id] = _teacherNames[id] ?? l['teacher_name']?.toString() ?? id;
    }
    final list = seen.entries.map((e) => (id: e.key, name: e.value)).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  bool get _hasExtraFilters =>
      _onlyTrial ||
      _onlyConflicts ||
      _filterTeacherId != null ||
      _filterRoomId != null ||
      _filterClientId != null;

  int get _activeScheduleFilterCount =>
      (_onlyTrial ? 1 : 0) +
      (_onlyConflicts ? 1 : 0) +
      (_filterTeacherId != null ? 1 : 0);

  List<Map<String, dynamic>> _lessonsForDate(DateTime date) {
    return _filteredLessons.where((l) {
      final dt = _parseLessonTime(l);
      return dt != null &&
          dt.year == date.year &&
          dt.month == date.month &&
          dt.day == date.day;
    }).toList();
  }

  // UTC offset (minutes) for the selected branch, falling back to Moscow.
  int get _selectedBranchOffset => _branchOffsets[_selectedBranchId] ?? 180;

  // Offset for a specific lesson based on its branch, falling back to the
  // selected branch / Moscow.
  int _offsetForLesson(Map<String, dynamic> lesson) {
    final bid = lesson['branch_id']?.toString();
    return _branchOffsets[bid] ?? _selectedBranchOffset;
  }

  DateTime? _parseLessonTime(Map<String, dynamic> lesson) {
    if (lesson['scheduled_at'] == null) return null;
    final dbTime = DateTime.parse(lesson['scheduled_at']).toUtc();
    return dbTime.add(Duration(minutes: _offsetForLesson(lesson)));
  }

  DateTime? _parseServerTime(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return parsed.toUtc().add(Duration(minutes: _selectedBranchOffset));
  }

  String _slotIso(DateTime date, int hour) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
    ).toUtc().toIso8601String();
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _goToToday() {
    _emitState(() {
      _clearHighlight();
      _selectedDate = DateTime.now();
      _displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    });
    _fetchAll();
  }

  void _prevMonth() {
    _emitState(() {
      _clearHighlight();
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
    _fetchAll();
  }

  void _nextMonth() {
    _emitState(() {
      _clearHighlight();
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
    });
    _fetchAll();
  }

  void _prevWeek() {
    _emitState(() {
      _clearHighlight();
      _selectedDate = _selectedDate.subtract(const Duration(days: 7));
      _displayedMonth = DateTime(_selectedDate.year, _selectedDate.month);
    });
    _fetchAll();
  }

  void _nextWeek() {
    _emitState(() {
      _clearHighlight();
      _selectedDate = _selectedDate.add(const Duration(days: 7));
      _displayedMonth = DateTime(_selectedDate.year, _selectedDate.month);
    });
    _fetchAll();
  }

  void _prevDay() {
    _emitState(() {
      _clearHighlight();
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(_selectedDate);
  }

  void _nextDay() {
    _emitState(() {
      _clearHighlight();
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    });
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(_selectedDate);
  }

  void _onMonthDayTap(DateTime date) {
    _emitState(() {
      _clearHighlight();
      _selectedDate = date;
      _currentView = ScheduleView.day;
    });
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(_selectedDate);
  }

  void _showAddLessonDialog(DateTime date, String? roomId) async {
    if (!widget.canWrite) return;
    final created = await CreateLessonDialog.show(
      context,
      initialDate: date,
      initialRoomId: roomId,
      initialBranchId: _selectedBranchId,
      clientType: _contextClientType,
      clientId: _contextClientId,
      clientName: _contextClientName,
    );
    if (created == true) _fetchAll();
  }

  Future<void> _showScheduleSearch() async {
    final query = await showScheduleSearchDialog(
      context,
      initialValue: _scheduleSearchQuery,
    );

    final normalized = query?.trim().toLowerCase();
    if (normalized == null) return;
    if (normalized.isEmpty) {
      _clearScheduleSearch();
      return;
    }

    final dateMatch = RegExp(
      r'^(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?$',
    ).firstMatch(normalized);
    if (dateMatch != null) {
      final day = int.tryParse(dateMatch.group(1)!);
      final month = int.tryParse(dateMatch.group(2)!);
      final rawYear = dateMatch.group(3);
      final year = rawYear == null
          ? _displayedMonth.year
          : int.tryParse(rawYear.length == 2 ? '20$rawYear' : rawYear);
      if (day != null && month != null && year != null) {
        final date = DateTime(year, month, day);
        if (date.year != year || date.month != month || date.day != day) {
          return;
        }
        _emitState(() {
          _scheduleSearchQuery = '';
          _clearHighlight();
          _selectedDate = date;
          _displayedMonth = DateTime(date.year, date.month);
          _currentView = ScheduleView.day;
        });
        // Reload the window for the (possibly new) month; since the view is now
        // day, _fetchAll backfills the selected day's lessons too.
        _fetchAll();
        return;
      }
    }

    var matches = _lessonsInCurrentView().where(
      (lesson) => _matchesScheduleSearch(lesson, normalized),
    );
    var foundLesson = matches.firstOrNull;
    _emitState(() {
      _scheduleSearchQuery = normalized;
      _highlightLessonId = foundLesson?['id']?.toString();
      _scheduleSearchLoading = true;
    });
    if (foundLesson != null) _armHighlightClear();

    try {
      await _loadExactScheduleSearchMatches(normalized);
    } catch (error) {
      debugPrint('Exact schedule search failed: $error');
    }
    if (!mounted) return;
    matches = _lessonsInCurrentView().where(
      (lesson) => _matchesScheduleSearch(lesson, normalized),
    );
    foundLesson = matches.firstOrNull;
    _emitState(() {
      _scheduleSearchLoading = false;
      _highlightLessonId = foundLesson?['id']?.toString();
    });
    if (foundLesson == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ничего не найдено в текущем диапазоне')),
      );
    } else {
      _armHighlightClear();
    }
  }

  Future<void> _loadExactScheduleSearchMatches(String query) async {
    final crm = ref.read(magicCrmServiceProvider);
    final targets = <String, ({String type, String id})>{};
    void addTarget(String type, String? id, Object? label) {
      final normalizedLabel = label?.toString().trim().toLowerCase() ?? '';
      if (id == null || id.isEmpty || !normalizedLabel.contains(query)) return;
      targets['$type:$id'] = (type: type, id: id);
    }

    for (final lesson in _lessonsInCurrentView()) {
      final studentId = lesson['student_id']?.toString();
      final leadId = lesson['lead_id']?.toString();
      final teacherId = lesson['teacher_id']?.toString();
      final roomId = lesson['room_id']?.toString();
      addTarget(
        'student',
        studentId,
        _studentNames[studentId] ?? lesson['student_name'],
      );
      addTarget('lead', leadId, lesson['lead_name']);
      addTarget(
        'teacher',
        teacherId,
        _teacherNames[teacherId] ?? lesson['teacher_name'],
      );
      addTarget('room', roomId, _roomNames[roomId] ?? lesson['room_name']);
    }

    final refs = await crm.searchClientRefs(q: query, limit: 10);
    for (final item in refs) {
      final clientRef = item['ref'];
      if (clientRef is! Map) continue;
      final type = clientRef['type']?.toString();
      final id = clientRef['id']?.toString();
      if ((type == 'student' || type == 'lead') && id?.isNotEmpty == true) {
        targets['$type:$id'] = (type: type!, id: id!);
      }
    }

    final range = _scheduleSearchRange();
    final responses = await Future.wait([
      for (final target in targets.values.take(12))
        crm.getScheduleMatrix(
          from: range.$1,
          to: range.$2,
          branchId: _selectedBranchId,
          groupBy: _dayViewMode == DayViewMode.byTeacher ? 'teacher' : 'room',
          studentId: target.type == 'student' ? target.id : null,
          leadId: target.type == 'lead' ? target.id : null,
          teacherId: target.type == 'teacher' ? target.id : null,
          roomId: target.type == 'room' ? target.id : null,
          limit: 500,
        ),
    ]);

    final byId = <String, Map<String, dynamic>>{
      for (final lesson in _lessons)
        if (lesson['id'] != null) lesson['id'].toString(): lesson,
    };
    final teacherNames = Map<String, String>.from(_teacherNames);
    final studentNames = Map<String, String>.from(_studentNames);
    for (final response in responses) {
      final items = response['items'];
      if (items is! List) continue;
      for (final lesson in items.whereType<Map<String, dynamic>>()) {
        final id = lesson['id']?.toString();
        if (id != null) byId[id] = lesson;
        final teacherId = lesson['teacher_id']?.toString();
        final teacherName = lesson['teacher_name']?.toString();
        if (teacherId?.isNotEmpty == true && teacherName?.isNotEmpty == true) {
          teacherNames[teacherId!] = teacherName!;
        }
        final studentId = lesson['student_id']?.toString();
        final studentName = lesson['student_name']?.toString();
        if (studentId?.isNotEmpty == true && studentName?.isNotEmpty == true) {
          studentNames[studentId!] = studentName!;
        }
      }
    }
    if (!mounted) return;
    _emitState(() {
      _lessons = byId.values.toList();
      _teacherNames = teacherNames;
      _studentNames = studentNames;
    });
  }

  (String, String) _scheduleSearchRange() {
    late DateTime start;
    late DateTime end;
    if (_currentView == ScheduleView.day) {
      start = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      end = start.add(const Duration(days: 1));
    } else if (_currentView == ScheduleView.week) {
      start = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ).subtract(Duration(days: _selectedDate.weekday - 1));
      end = start.add(const Duration(days: 7));
    } else {
      start = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
      end = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    }
    DateTime utc(DateTime local) => DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).subtract(Duration(minutes: _selectedBranchOffset));
    return (utc(start).toIso8601String(), utc(end).toIso8601String());
  }

  Iterable<Map<String, dynamic>> _lessonsInCurrentView() {
    if (_currentView == ScheduleView.day) {
      return _lessonsForDate(_selectedDate);
    }
    if (_currentView == ScheduleView.week) {
      final monday = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ).subtract(Duration(days: _selectedDate.weekday - 1));
      final end = monday.add(const Duration(days: 7));
      return _filteredLessons.where((lesson) {
        final at = _parseLessonTime(lesson);
        return at != null && !at.isBefore(monday) && at.isBefore(end);
      });
    }
    return _filteredLessons.where((lesson) {
      final at = _parseLessonTime(lesson);
      return at != null &&
          at.year == _displayedMonth.year &&
          at.month == _displayedMonth.month;
    });
  }

  void _clearScheduleSearch() {
    if (!_hasScheduleSearch && _highlightLessonId == null) return;
    _emitState(() {
      _scheduleSearchQuery = '';
      _scheduleSearchLoading = false;
      _clearHighlight();
    });
  }

  Future<void> _showScheduleFilters() async {
    final result = await showScheduleFiltersSheet(
      context,
      initialBranchId: _selectedBranchId,
      initialMode: _dayViewMode,
      branches: _branches,
      isDayView: _currentView == ScheduleView.day,
      initialOnlyTrial: _onlyTrial,
      initialOnlyConflicts: _onlyConflicts,
      initialTeacherId: _filterTeacherId,
      teacherOptions: _teacherFilterOptions,
    );
    if (result == null) return;
    _applyScheduleFilterResult(result);
  }

  void _applyScheduleFilterResult(ScheduleFilterResult result) {
    final branchChanged = result.branchId != _selectedBranchId;
    final modeChanged = result.mode != _dayViewMode;
    _emitState(() {
      _clearHighlight();
      _selectedBranchId = result.branchId;
      _dayViewMode = result.mode;
      _onlyTrial = result.onlyTrial;
      _onlyConflicts = result.onlyConflicts;
      _filterTeacherId = result.teacherId;
      if (_selectedTeacherId != null &&
          !_filteredLessons.any(
            (lesson) => lesson['teacher_id']?.toString() == _selectedTeacherId,
          )) {
        _selectedTeacherId = null;
      }
    });
    // The trial/conflict/teacher filters are applied client-side over the
    // loaded matrix, so they need only a rebuild (done by _emitState). Only a
    // branch or layout change actually needs a refetch.
    if (branchChanged || modeChanged) _fetchAll();
  }

  // ═══════════════════════════════════════════════════════════════════════════
}
