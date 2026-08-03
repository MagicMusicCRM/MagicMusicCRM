part of 'schedule_widget.dart';

extension _ScheduleViewsA on _ScheduleWidgetState {
  Widget _buildScheduleContent() {
    // Skeleton only on the very first load. On re-fetches we keep the existing
    // calendar on screen (a thin progress bar in the header signals the refresh)
    // so changing branch/date/view never blanks the grid.
    if (_isLoading && !_hasLoadedOnce) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ScheduleSkeleton(rows: 7, columns: 6),
      );
    }
    if (_loadError != null && !_hasLoadedOnce) {
      return _ScheduleError(error: _loadError, onRetry: _fetchAll);
    }
    return switch (_currentView) {
      ScheduleView.month => ScheduleMonthView(
        selectedDate: _selectedDate,
        displayedMonth: _displayedMonth,
        studentNames: _studentNames,
        monthDaySummary: _filterClientId == null ? _monthDaySummary : const {},
        lessonsForDate: _lessonsForDate,
        parseLessonTime: _parseLessonTime,
        onDayTap: _onMonthDayTap,
      ),
      ScheduleView.week => _buildWeekView(),
      ScheduleView.day => _buildDayView(),
    };
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final title = switch (_currentView) {
      ScheduleView.month =>
        '${monthNamesNominative[_displayedMonth.month]} ${_displayedMonth.year}',
      ScheduleView.week => 'Расписание / Неделя',
      ScheduleView.day => 'Расписание / День',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.search_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 22,
            ),
            tooltip: 'Поиск',
            onPressed: _showScheduleSearch,
          ),
          IconButton(
            icon: Icon(
              // A dot on the funnel signals filters are active — otherwise a
              // half-empty grid reads as «нет занятий», not «отфильтровано».
              _hasExtraFilters ? Icons.filter_alt_rounded : Icons.tune_rounded,
              color: _hasExtraFilters
                  ? AppColor.gold
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 22,
            ),
            tooltip: 'Фильтры',
            onPressed: _showScheduleFilters,
          ),
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 22,
            ),
            onPressed: _fetchAll,
          ),
        ],
      ),
    );
  }

  // ── Месяц / Неделя / День segmented control (primary navigation) ──────────
  Widget _buildViewSwitcher() {
    Widget seg(String label, ScheduleView view) {
      final active = _currentView == view;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchView(view),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.ease,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColor.gold : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? AppColor.onGold
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.control + 4),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(28),
          ),
        ),
        child: Row(
          children: [
            seg('Месяц', ScheduleView.month),
            const SizedBox(width: 4),
            seg('Неделя', ScheduleView.week),
            const SizedBox(width: 4),
            seg('День', ScheduleView.day),
          ],
        ),
      ),
    );
  }

  void _switchView(ScheduleView view) {
    if (_currentView == view) return;
    _emitState(() {
      _clearHighlight();
      _currentView = view;
    });
    if (view == ScheduleView.day) {
      _fetchAvailabilityForSelectedDay();
      _fetchDayLessons(_selectedDate);
    } else {
      _displayedMonth = DateTime(_selectedDate.year, _selectedDate.month);
      _fetchAll();
    }
  }

  // ── Branch selector pills ─────────────────────────────────────────────────
  Widget _buildBranchSelector() {
    if (_branches.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          ..._branches.map((b) {
            final id = b['id'].toString();
            final isSelected = id == _selectedBranchId;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  b['name'].toString(),
                  style: TextStyle(
                    color: isSelected
                        ? AppColor.gold
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) {
                  _emitState(() {
                    _clearHighlight();
                    _selectedBranchId = id;
                  });
                  _fetchAll();
                },
                backgroundColor: Theme.of(context).colorScheme.surface,
                selectedColor: AppColor.gold.withAlpha(25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? AppColor.gold
                        : Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(60),
                    width: 1,
                  ),
                ),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
              ),
            );
          }),
          if (_selectedBranchId != null)
            TextButton.icon(
              onPressed: _editBranchTimezone,
              icon: const Icon(Icons.schedule_rounded, size: 16),
              label: Text(offsetLabel(_selectedBranchOffset)),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editBranchTimezone() async {
    final branchId = _selectedBranchId;
    if (branchId == null) return;
    final branch = _branches.firstWhere(
      (b) => b['id'].toString() == branchId,
      orElse: () => <String, dynamic>{},
    );
    final branchName = branch['name']?.toString() ?? 'Филиал';
    final saved = await showBranchTimezoneDialog(
      context,
      branchName: branchName,
      currentOffset: _selectedBranchOffset,
    );
    if (saved == null || saved == _selectedBranchOffset || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateBranch(branchId, utcOffsetMinutes: saved);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Часовой пояс обновлён: ${offsetLabel(saved)}'),
          backgroundColor: AppColor.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _fetchAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось обновить пояс: $e'),
          backgroundColor: AppColor.danger,
        ),
      );
    }
  }

  // ── Day-view mode toggle (По аудиториям / По педагогу) ────────────────────

  // ── Date navigation ───────────────────────────────────────────────────────
  Widget _buildDateNavigation() {
    String dateLabel;
    VoidCallback onPrev, onNext;

    if (_currentView == ScheduleView.month) {
      dateLabel =
          '${monthNamesGenitive[_displayedMonth.month].toLowerCase()} ${_displayedMonth.year}';
      onPrev = _prevMonth;
      onNext = _nextMonth;
    } else if (_currentView == ScheduleView.week) {
      final monday = _selectedDate.subtract(
        Duration(days: _selectedDate.weekday - 1),
      );
      final sunday = monday.add(const Duration(days: 6));
      dateLabel =
          '${monday.day} ${monthNamesGenitive[monday.month]} — '
          '${sunday.day} ${monthNamesGenitive[sunday.month]} ${sunday.year}';
      onPrev = _prevWeek;
      onNext = _nextWeek;
    } else {
      final weekDayNames = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
      final wd = weekDayNames[_selectedDate.weekday - 1];
      dateLabel =
          '$wd, ${_selectedDate.day} ${monthNamesGenitive[_selectedDate.month]} ${_selectedDate.year}';
      onPrev = _prevDay;
      onNext = _nextDay;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          InkWell(
            onTap: onPrev,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.chevron_left_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ),
          ),
          Expanded(
            child: Text(
              dateLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: _goToToday,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withAlpha(80),
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'сегодня',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onNext,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
      entries.add(
        ScheduleEntry(
          lesson: lesson,
          id: lesson['id']?.toString() ?? '',
          columnId: dateOnly(start),
          startLocal: start,
          durationMinutes: _durationMinutes(lesson),
          title: title,
          subtitle: [
            room,
            teacher,
          ].where((value) => value.isNotEmpty).join(' · '),
          isTrial: lesson['is_trial'] == true,
          conflicts: conflictTypes(lesson['conflict_types']),
          movable: lesson['id'] != null && lesson['status'] != 'cancelled',
          highlighted: false,
        ),
      );
    }

    return ScheduleDayCanvas(
      key: const ValueKey('schedule-week-view'),
      date: monday,
      columns: columns,
      entries: entries,
      onCreateSlot: (_, start, duration) => _openWeekCreate(start, duration),
      onMove: (lesson, start, _) =>
          _moveLessonOptimistic(lesson, start, null, preserveRoom: true),
      onResize: _resizeLesson,
      onOpenLesson: _showLessonDetails,
    );
  }

  Widget _buildClientFilterBanner() {
    final fallback = _filterClientType == 'lead' ? 'Лид' : 'Ученик';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          avatar: const Icon(Icons.person_search_rounded, size: 18),
          label: Text(
            'Клиент: ${_filterClientName?.trim().isNotEmpty == true ? _filterClientName : fallback}',
          ),
          onDeleted: () => _emitState(() {
            _filterClientType = null;
            _filterClientId = null;
            _filterClientName = null;
          }),
        ),
      ),
    );
  }

  Widget _buildAvailabilitySummary() {
    final availability = _roomAvailability.where((item) {
      return _selectedBranchId == null ||
          item['branch_id']?.toString() == _selectedBranchId;
    }).toList();
    final availableCount = availability
        .where((item) => item['is_available'] == true)
        .length;
    final busyCount = availability
        .where((item) => item['is_available'] == false)
        .length;
    final conflicts = _conflictsForSelectedDay();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withAlpha(150),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(24),
          ),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ScheduleBadge(
              icon: _availabilityLoading
                  ? Icons.sync_rounded
                  : Icons.meeting_room_outlined,
              label: _availabilityLoading
                  ? 'Проверяем аудитории'
                  : 'Свободно: $availableCount',
              color: AppColor.success,
            ),
            _ScheduleBadge(
              icon: Icons.event_busy_rounded,
              label: 'Занято: $busyCount',
              color: busyCount > 0
                  ? AppTheme.warning
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            _ScheduleBadge(
              icon: Icons.warning_amber_rounded,
              label: 'Конфликты: ${conflicts.length}',
              color: conflicts.isEmpty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : AppColor.danger,
            ),
            if (availability.isEmpty && !_availabilityLoading)
              Text(
                'Доступность аудиторий появится после расчета backend.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _conflictsForSelectedDay() {
    return _scheduleConflicts.where((conflict) {
      final dt = _parseServerTime(conflict['scheduled_at']);
      return dt != null &&
          dt.year == _selectedDate.year &&
          dt.month == _selectedDate.month &&
          dt.day == _selectedDate.day;
    }).toList();
  }

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
      final status = l['status']?.toString();
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
          // Only a CANCELLED lesson is frozen — rescheduling one is meaningless
          // (it never happens; a new lesson is created instead).
          //
          // «completed»/«done» used to freeze a card too, which is why drag and
          // resize looked broken on some cards and fine on others: the importer
          // stamps `completed` on every lesson dated before the import run
          // (hollihop-import.ts — `attended || isPast`), so the ~33k historical
          // lessons — the whole schedule up to today — were all silently
          // immovable, while tomorrow's moved fine. That status marks «in the
          // past», not «audited»; it must not be a write lock. Fixing a
          // mistyped past lesson is ordinary admin work.
          movable: l['id'] != null && status != 'cancelled',
          highlighted:
              _highlightLessonId != null &&
              l['id']?.toString() == _highlightLessonId,
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
      onCreateSlot: _openQuickCreate,
      onMove: _moveLessonOptimistic,
      onResize: _resizeLesson,
      onOpenLesson: _showLessonDetails,
    );
  }

  // Interaction legend above the day grid: all the rules live here, not on every
  // cell (owner rule «инструкции в легенду, не поверх ячеек»).

  // ── Focus-on-lesson (Phase 5) ───────────────────────────────────────────────
  // Applies a [ScheduleFocusState] from the client card: switch to the lesson's
}
