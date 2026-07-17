part of 'schedule_widget.dart';

extension _ScheduleActions on _ScheduleWidgetState {

  // ── Data fetching ─────────────────────────────────────────────────────────
  Future<void> _fetchAll() async {
    _emitState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final from = DateTime(
        _displayedMonth.year,
        _displayedMonth.month,
        1,
      ).subtract(const Duration(days: 7));
      final to = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
        1,
      ).add(const Duration(days: 7));
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

      String? defaultBranch = _selectedBranchId;
      if (defaultBranch == null && branches.isNotEmpty) {
        defaultBranch = branches.first['id'].toString();
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
          groupBy:
              _dayViewMode == DayViewMode.byTeacher ? 'teacher' : 'room',
          limit: 300,
        ).catchError((e) {
          debugPrint('Error fetching schedule matrix: $e');
          return <String, dynamic>{};
        }),
        crm.listRoomAvailability(
          branchId: defaultBranch,
          date: dateOnly(_selectedDate),
          from: _slotIso(_selectedDate, 6),
          to: _slotIso(_selectedDate, 23),
          limit: 100,
        ).catchError((e) {
          debugPrint('Error fetching room availability: $e');
          return <String, dynamic>{};
        }),
        crm.getScheduleMonthSummary(
          from: fromIso,
          to: toIso,
          branchId: defaultBranch,
        ).catchError((e) {
          debugPrint('Error fetching month summary: $e');
          return <Map<String, dynamic>>[];
        }),
      ]);

      final matrixResult = wave2[0] as Map<String, dynamic>;
      final availabilityResult = wave2[1] as Map<String, dynamic>;
      final summaryResult = wave2[2] as List<Map<String, dynamic>>;

      final matrixItems = matrixResult['items'];
      if (matrixItems is List && matrixItems.isNotEmpty) {
        enrichedLessons =
            matrixItems.whereType<Map<String, dynamic>>().toList();
      }
      final conflicts = matrixResult['conflicts'];
      if (conflicts is List) {
        scheduleConflicts =
            conflicts.whereType<Map<String, dynamic>>().toList();
      }
      final availabilityItems = availabilityResult['items'];
      if (availabilityItems is List) {
        roomAvailability =
            availabilityItems.whereType<Map<String, dynamic>>().toList();
      }
      for (final item in summaryResult) {
        final day = item['day']?.toString();
        if (day != null) monthSummary[day] = item;
      }

      // Build teacher/student name maps from matrix data (no extra API calls).
      final tNames = <String, String>{};
      final sNames = <String, String>{};
      final teacherSet = <String, Map<String, dynamic>>{};
      for (final lesson in enrichedLessons) {
        final tid = lesson['teacher_id']?.toString();
        if (tid != null && tid.isNotEmpty) {
          final name = lesson['teacher_name']?.toString() ?? '';
          if (name.isNotEmpty) tNames[tid] = name;
          teacherSet.putIfAbsent(tid, () => {'id': tid, 'name': name});
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
          branches.length > 1) {
        for (final b in branches) {
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
        _branches = branches;
        _branchOffsets = offsets;
        _rooms = rooms;
        _lessons = enrichedLessons;
        _teachers = teacherSet.values.toList();
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
        _fetchDayLessons(_selectedDate);
      } else if (_currentView == ScheduleView.year) {
        _fetchYearSummary();
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
    final dayStartUtc = DateTime.utc(date.year, date.month, date.day)
        .subtract(Duration(minutes: offset));
    final dayEndUtc = dayStartUtc.add(const Duration(days: 1));
    try {
      final result = await ref.read(magicCrmServiceProvider).getScheduleMatrix(
        from: dayStartUtc.toIso8601String(),
        to: dayEndUtc.toIso8601String(),
        branchId: branchId,
        groupBy: _dayViewMode == DayViewMode.byTeacher ? 'teacher' : 'room',
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
      _onlyTrial || _onlyConflicts || _filterTeacherId != null;

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
  int get _selectedBranchOffset =>
      _branchOffsets[_selectedBranchId] ?? 180;

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

  void _prevYear() {
    _emitState(() => _displayedYear -= 1);
    _fetchYearSummary();
  }

  void _nextYear() {
    _emitState(() => _displayedYear += 1);
    _fetchYearSummary();
  }

  // Opening a month from the year overview drops the user into that month.
  void _onYearMonthTap(int month) {
    _emitState(() {
      _clearHighlight();
      _displayedMonth = DateTime(_displayedYear, month);
      _selectedDate = DateTime(_displayedYear, month, 1);
      _currentView = ScheduleView.month;
    });
    _fetchAll();
  }

  // Whole-year per-month aggregate from the lightweight day-level month-summary
  // (one HTTP call, ≈365 small rows). Counts/active-days are SERVER-derived; we
  // never invent conflict numbers the summary endpoint doesn't return.
  Future<void> _fetchYearSummary() async {
    final branchId = _selectedBranchId;
    final guard = _displayedYear * 31 + (branchId?.hashCode ?? 0) % 31;
    if (_yearLoadedFor == guard && _yearMonths.isNotEmpty) return;
    _emitState(() => _yearLoading = true);
    try {
      final from = DateTime.utc(_displayedYear, 1, 1).toIso8601String();
      final to = DateTime.utc(_displayedYear + 1, 1, 1).toIso8601String();
      final summary = await ref
          .read(magicCrmServiceProvider)
          .getScheduleMonthSummary(from: from, to: to, branchId: branchId);
      final months = <int, ({int count, int activeDays})>{};
      for (final item in summary) {
        final day = item['day']?.toString();
        if (day == null) continue;
        final parts = day.split('-');
        if (parts.length < 2) continue;
        final m = int.tryParse(parts[1]);
        if (m == null) continue;
        final c = item['count'] is int
            ? item['count'] as int
            : int.tryParse('${item['count']}') ?? 0;
        final cur = months[m] ?? (count: 0, activeDays: 0);
        months[m] = (
          count: cur.count + c,
          activeDays: cur.activeDays + (c > 0 ? 1 : 0),
        );
      }
      if (!mounted) return;
      _emitState(() {
        _yearMonths = months;
        _yearLoading = false;
        _yearLoadedFor = guard;
      });
    } catch (e) {
      debugPrint('Error fetching year summary: $e');
      if (mounted) _emitState(() => _yearLoading = false);
    }
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
    final created = await CreateLessonDialog.show(
      context,
      initialDate: date,
      initialRoomId: roomId,
      initialBranchId: _selectedBranchId,
    );
    if (created == true) _fetchAll();
  }

  Future<void> _showScheduleSearch() async {
    final query = await showScheduleSearchDialog(context);

    final normalized = query?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return;

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
        _emitState(() {
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

    Map<String, dynamic>? foundLesson;
    String? foundTeacherId;
    for (final lesson in _filteredLessons) {
      final teacherId = lesson['teacher_id']?.toString();
      final studentId = lesson['student_id']?.toString();
      final roomId = lesson['room_id']?.toString();
      final searchable = [
        if (teacherId != null) _teacherNames[teacherId],
        if (studentId != null) _studentNames[studentId],
        if (roomId != null) _roomNames[roomId],
        lesson['status']?.toString(),
      ].whereType<String>().join(' ').toLowerCase();

      if (searchable.contains(normalized)) {
        foundLesson = lesson;
        foundTeacherId = teacherId;
        break;
      }
    }

    final lessonDate = foundLesson == null
        ? null
        : _parseLessonTime(foundLesson);
    if (lessonDate == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ничего не найдено в текущем диапазоне')),
      );
      return;
    }

    _emitState(() {
      _selectedDate = lessonDate;
      _displayedMonth = DateTime(lessonDate.year, lessonDate.month);
      _currentView = ScheduleView.day;
      if (foundTeacherId != null) {
        _dayViewMode = DayViewMode.byTeacher;
        _selectedTeacherId = foundTeacherId;
      }
    });
    _fetchDayLessons(lessonDate);
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
