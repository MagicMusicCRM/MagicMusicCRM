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

  // ── One responsive schedule toolbar ───────────────────────────────────────
  // Date, mode, scope and the single primary action belong to one surface.
  // Keeping them together removes the old stack of unrelated header strips and
  // makes the same controls predictable at desktop and phone widths.
  Widget _buildScheduleToolbar({required bool firstLoad}) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final createButton = FilledButton.icon(
          key: const ValueKey('schedule-create-lesson'),
          onPressed: firstLoad ? null : _openLessonCreate,
          icon: const Icon(Icons.add_rounded, size: 19),
          label: const Text('Создать занятие'),
          style: FilledButton.styleFrom(
            minimumSize: Size(0, compact ? 42 : 44),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            backgroundColor: AppColor.gold,
            foregroundColor: AppColor.onGold,
          ),
        );
        final controls = <Widget>[
          _buildViewSwitcher(),
          _buildDateNavigation(),
          _buildBranchSelector(),
        ];

        return Container(
          margin: EdgeInsets.fromLTRB(
            compact ? AppSpace.sm : AppSpace.lg,
            AppSpace.sm,
            compact ? AppSpace.sm : AppSpace.lg,
            AppSpace.xs,
          ),
          padding: EdgeInsets.all(compact ? AppSpace.md : AppSpace.lg),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: cs.onSurfaceVariant.withAlpha(32)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Расписание',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: compact ? 19 : 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!firstLoad)
                          Text(
                            _schedulePeriodLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search_rounded, size: 21),
                    color: cs.onSurfaceVariant,
                    tooltip: 'Найти занятие',
                    onPressed: firstLoad ? null : _showScheduleSearch,
                  ),
                  IconButton(
                    icon: Icon(
                      _hasExtraFilters
                          ? Icons.filter_alt_rounded
                          : Icons.tune_rounded,
                      size: 21,
                    ),
                    color: _hasExtraFilters
                        ? AppColor.gold
                        : cs.onSurfaceVariant,
                    tooltip: _hasExtraFilters
                        ? 'Фильтры расписания применены'
                        : 'Фильтры расписания',
                    onPressed: firstLoad ? null : _showScheduleFilters,
                  ),
                  if (!compact)
                    IconButton(
                      tooltip: 'Обновить расписание',
                      icon: const Icon(Icons.refresh_rounded, size: 21),
                      color: cs.onSurfaceVariant,
                      onPressed: _fetchAll,
                    ),
                  if (!compact) ...[
                    const SizedBox(width: AppSpace.xs),
                    createButton,
                  ],
                ],
              ),
              if (compact) ...[
                const SizedBox(height: AppSpace.sm),
                SizedBox(width: double.infinity, child: createButton),
              ],
              if (!firstLoad) ...[
                const SizedBox(height: AppSpace.md),
                if (compact)
                  ...controls.expand(
                    (control) => [
                      control,
                      if (control != controls.last)
                        const SizedBox(height: AppSpace.sm),
                    ],
                  )
                else
                  Wrap(
                    spacing: AppSpace.md,
                    runSpacing: AppSpace.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: controls,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _openLessonCreate() {
    var date = _selectedDate;
    if (_currentView == ScheduleView.month &&
        (_selectedDate.year != _displayedMonth.year ||
            _selectedDate.month != _displayedMonth.month)) {
      final lastDay = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
        0,
      ).day;
      final todayDay = DateTime.now().day;
      date = DateTime(
        _displayedMonth.year,
        _displayedMonth.month,
        todayDay > lastDay ? lastDay : todayDay,
      );
    }
    _showAddLessonDialog(date, null);
  }

  String get _schedulePeriodLabel => switch (_currentView) {
    ScheduleView.month =>
      '${monthNamesNominative[_displayedMonth.month]} ${_displayedMonth.year}',
    ScheduleView.week => 'Неделя · ${_dateNavigationLabel()}',
    ScheduleView.day => 'День · ${_dateNavigationLabel()}',
  };

  // ── Месяц / Неделя / День segmented control (primary navigation) ──────────
  Widget _buildViewSwitcher() {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 340),
      child: SegmentedButton<ScheduleView>(
        key: const ValueKey('schedule-view-switcher'),
        segments: const [
          ButtonSegment(value: ScheduleView.month, label: Text('Месяц')),
          ButtonSegment(value: ScheduleView.week, label: Text('Неделя')),
          ButtonSegment(value: ScheduleView.day, label: Text('День')),
        ],
        selected: {_currentView},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => _switchView(selection.single),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(88, 40)),
          visualDensity: VisualDensity.compact,
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColor.gold
                : cs.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColor.onGold
                : cs.onSurfaceVariant,
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: cs.onSurfaceVariant.withAlpha(42)),
          ),
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
    final selectedExists = _branches.any(
      (branch) => branch['id']?.toString() == _selectedBranchId,
    );
    final value = selectedExists
        ? _selectedBranchId
        : _branches.first['id']?.toString();

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 330),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('schedule-branch-selector-${value ?? 'none'}'),
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Филиал',
                prefixIcon: Icon(Icons.location_on_outlined, size: 19),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              items: [
                for (final branch in _branches)
                  DropdownMenuItem(
                    value: branch['id']?.toString(),
                    child: Text(
                      branch['name']?.toString() ?? 'Филиал',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id == null || id == _selectedBranchId) return;
                _emitState(() {
                  _clearHighlight();
                  _selectedBranchId = id;
                });
                _fetchAll();
              },
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          IconButton(
            onPressed: _selectedBranchId == null ? null : _editBranchTimezone,
            tooltip: 'Часовой пояс: ${offsetLabel(_selectedBranchOffset)}',
            icon: const Icon(Icons.schedule_rounded, size: 19),
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
    VoidCallback onPrev, onNext;

    if (_currentView == ScheduleView.month) {
      onPrev = _prevMonth;
      onNext = _nextMonth;
    } else if (_currentView == ScheduleView.week) {
      onPrev = _prevWeek;
      onNext = _nextWeek;
    } else {
      onPrev = _prevDay;
      onNext = _nextDay;
    }

    final unit = switch (_currentView) {
      ScheduleView.month => 'месяц',
      ScheduleView.week => 'неделю',
      ScheduleView.day => 'день',
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 390),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onPrev,
            tooltip: 'Предыдущий $unit',
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
          ),
          Expanded(
            child: Text(
              _dateNavigationLabel(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: _goToToday, child: const Text('Сегодня')),
          IconButton(
            onPressed: onNext,
            tooltip: 'Следующий $unit',
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
          ),
        ],
      ),
    );
  }

  String _dateNavigationLabel() {
    if (_currentView == ScheduleView.month) {
      return '${monthNamesGenitive[_displayedMonth.month].toLowerCase()} '
          '${_displayedMonth.year}';
    }
    if (_currentView == ScheduleView.week) {
      final monday = _selectedDate.subtract(
        Duration(days: _selectedDate.weekday - 1),
      );
      final sunday = monday.add(const Duration(days: 6));
      return '${monday.day} ${monthNamesGenitive[monday.month]} — '
          '${sunday.day} ${monthNamesGenitive[sunday.month]} ${sunday.year}';
    }
    const weekDayNames = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    final wd = weekDayNames[_selectedDate.weekday - 1];
    return '$wd, ${_selectedDate.day} '
        '${monthNamesGenitive[_selectedDate.month]} ${_selectedDate.year}';
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
      initialVerticalOffset: _dayScrollOffset,
      onVerticalOffsetChanged: (value) => _dayScrollOffset = value,
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
      initialVerticalOffset: _dayScrollOffset,
      onVerticalOffsetChanged: (value) => _dayScrollOffset = value,
    );
  }

  // Interaction legend above the day grid: all the rules live here, not on every
  // cell (owner rule «инструкции в легенду, не поверх ячеек»).

  // ── Focus-on-lesson (Phase 5) ───────────────────────────────────────────────
  // Applies a [ScheduleFocusState] from the client card: switch to the lesson's
}
