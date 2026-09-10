part of 'schedule_widget.dart';

extension _ScheduleToolbar on _ScheduleWidgetState {
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
        monthDaySummary: !_hasClientContext ? _monthDaySummary : const {},
        lessonsForDate: _lessonsForDate,
        parseLessonTime: _parseLessonTime,
        clientContext: _hasClientContext,
        searchContext: _hasScheduleSearch,
        isContextClientLesson: _isRelatedLesson,
        onDayTap: _onMonthDayTap,
      ),
      ScheduleView.week => _buildWeekView(),
      ScheduleView.day => _buildDayView(),
    };
  }

  Widget _buildScheduleToolbar({required bool firstLoad}) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 720) {
        return _buildDesktopToolbar(constraints, firstLoad: firstLoad);
      }
      final cs = Theme.of(context).colorScheme;
      return Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        padding: const EdgeInsets.all(AppSpace.md),
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
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 19,
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
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search_rounded, size: 21),
                  color: _hasScheduleSearch
                      ? AppColor.gold
                      : cs.onSurfaceVariant,
                  tooltip: _hasScheduleSearch
                      ? 'Поиск: $_scheduleSearchQuery'
                      : 'Найти занятие',
                  onPressed: firstLoad ? null : _showScheduleSearch,
                ),
                IconButton(
                  icon: Icon(
                    _hasExtraFilters
                        ? Icons.filter_alt_rounded
                        : Icons.tune_rounded,
                    size: 21,
                  ),
                  color: _hasExtraFilters ? AppColor.gold : cs.onSurfaceVariant,
                  tooltip: _hasExtraFilters
                      ? 'Фильтры расписания применены'
                      : 'Фильтры расписания',
                  onPressed: firstLoad ? null : _showScheduleFilters,
                ),
              ],
            ),
            if (widget.canWrite) ...[
              const SizedBox(height: AppSpace.sm),
              FilledButton.icon(
                key: const ValueKey('schedule-create-lesson'),
                onPressed: firstLoad ? null : _openLessonCreate,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Создать занятие'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  backgroundColor: AppColor.gold,
                  foregroundColor: AppColor.onGold,
                ),
              ),
            ],
            if (!firstLoad) ...[
              const SizedBox(height: AppSpace.md),
              _buildViewSwitcher(),
              const SizedBox(height: AppSpace.sm),
              _buildDateNavigation(),
              const SizedBox(height: AppSpace.sm),
              _buildBranchSelector(),
            ],
          ],
        ),
      );
    },
  );

  void _openLessonCreate() {
    if (!widget.canWrite) return;
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
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 340),
      child: SegmentedButton<ScheduleView>(
        key: const ValueKey('schedule-view-switcher'),
        segments: [
          if (widget.allowMonth)
            const ButtonSegment(
              value: ScheduleView.month,
              label: Text('Месяц'),
            ),
          const ButtonSegment(value: ScheduleView.week, label: Text('Неделя')),
          const ButtonSegment(value: ScheduleView.day, label: Text('День')),
        ],
        selected: {_currentView},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => _switchView(selection.single),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 36)),
          visualDensity: VisualDensity.compact,
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
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
    if (view == ScheduleView.month && !widget.allowMonth) return;
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
    final value = _allBranchesSelected
        ? _allBranchesScopeValue
        : selectedExists
        ? _selectedBranchId
        : _branches.first['id']?.toString();

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 330),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              menuMaxHeight: 256,
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
                const DropdownMenuItem(
                  value: _allBranchesScopeValue,
                  child: Text('Все филиалы'),
                ),
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
                if (id == null) return;
                final allBranches = id == _allBranchesScopeValue;
                if (allBranches == _allBranchesSelected &&
                    (allBranches || id == _selectedBranchId)) {
                  return;
                }
                _emitState(() {
                  _clearHighlight();
                  _allBranchesSelected = allBranches;
                  _selectedBranchId = allBranches ? null : id;
                });
                _fetchAll();
              },
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          IconButton(
            onPressed: !widget.canWrite || _selectedBranchId == null
                ? null
                : _editBranchTimezone,
            tooltip: 'Часовой пояс: ${offsetLabel(_selectedBranchOffset)}',
            icon: const Icon(Icons.schedule_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  Future<void> _editBranchTimezone() async {
    if (!widget.canWrite) return;
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
          content: Text(
            userErrorMessage(e, fallback: 'Не удалось обновить часовой пояс.'),
          ),
          backgroundColor: AppColor.danger,
        ),
      );
    }
  }

  // ── Day-view mode toggle (По аудиториям / По педагогу) ────────────────────

  // ── Date navigation ───────────────────────────────────────────────────────
  Widget _buildDateNavigation({bool compact = false}) {
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
            child: Tooltip(
              message: _dateNavigationLabel(),
              child: Text(
                _dateNavigationLabel(compact: compact),
                key: const ValueKey('schedule-date-label'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w600,
                ),
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

  String _dateNavigationLabel({bool compact = false}) {
    if (_currentView == ScheduleView.month) {
      return '${monthNamesNominative[_displayedMonth.month]} '
          '${_displayedMonth.year}';
    }
    if (_currentView == ScheduleView.week) {
      final monday = _selectedDate.subtract(
        Duration(days: _selectedDate.weekday - 1),
      );
      final sunday = monday.add(const Duration(days: 6));
      if (compact) {
        String dayMonth(DateTime date) =>
            '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
        final startYear = monday.year == sunday.year ? '' : '.${monday.year}';
        return '${dayMonth(monday)}$startYear – ${dayMonth(sunday)}.${sunday.year}';
      }
      return '${monday.day} ${monthNamesGenitive[monday.month]} - '
          '${sunday.day} ${monthNamesGenitive[sunday.month]} ${sunday.year}';
    }
    const weekDayNames = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    final wd = weekDayNames[_selectedDate.weekday - 1];
    return '$wd, ${_selectedDate.day} '
        '${monthNamesGenitive[_selectedDate.month]} ${_selectedDate.year}';
  }
}
