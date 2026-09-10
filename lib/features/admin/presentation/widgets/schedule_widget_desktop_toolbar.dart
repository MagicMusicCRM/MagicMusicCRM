part of 'schedule_widget.dart';

extension _ScheduleDesktopToolbar on _ScheduleWidgetState {
  Widget _buildDesktopToolbar(
    BoxConstraints constraints, {
    required bool firstLoad,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final narrow = constraints.maxWidth < 900 * textScale;
    final singleRow =
        constraints.maxWidth >=
        1100 * MediaQuery.textScalerOf(context).scale(1);
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _desktopFilters(firstLoad),
        _desktopLegend(),
        if ((_currentView == ScheduleView.week ||
            (_currentView == ScheduleView.day &&
                _dayViewMode != DayViewMode.byTeacher)))
          IconButton(
            key: const ValueKey('schedule-density-toggle'),
            tooltip: _fitDayToViewport ? 'Крупнее' : 'Весь день',
            onPressed: () =>
                _emitState(() => _fitDayToViewport = !_fitDayToViewport),
            icon: Icon(
              _fitDayToViewport
                  ? Icons.zoom_in_rounded
                  : Icons.fit_screen_rounded,
              size: 19,
            ),
          ),
        IconButton(
          tooltip: 'Обновить расписание',
          onPressed: _isLoading ? null : _fetchAll,
          icon: const Icon(Icons.refresh_rounded, size: 19),
        ),
        if (widget.canWrite)
          Tooltip(
            message: 'Создать занятие',
            child: FilledButton(
              key: const ValueKey('schedule-create-lesson'),
              onPressed: firstLoad ? null : _openLessonCreate,
              style: FilledButton.styleFrom(
                minimumSize: const Size(36, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                backgroundColor: AppColor.gold,
                foregroundColor: AppColor.onGold,
              ),
              child: constraints.maxWidth >= 1450
                  ? const Text('+ Создать занятие')
                  : const Icon(Icons.add_rounded, size: 20),
            ),
          ),
      ],
    );
    final navigation = SizedBox(
      width: (_currentView == ScheduleView.week ? 360 : 308) * textScale,
      child: _buildDateNavigation(compact: true),
    );
    final views = SizedBox(width: 240 * textScale, child: _buildViewSwitcher());
    final mode = SizedBox(
      width: 176 * textScale,
      child: DropdownButtonFormField<DayViewMode>(
        menuMaxHeight: 256,
        key: const ValueKey('schedule-day-mode-switcher'),
        initialValue: _dayViewMode,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 12,
          fontFamily: 'Inter',
        ),
        items: const [
          DropdownMenuItem(
            value: DayViewMode.byRoom,
            child: Text('По аудиториям'),
          ),
          DropdownMenuItem(
            value: DayViewMode.byTeacher,
            child: Text('По преподавателям'),
          ),
        ],
        onChanged: firstLoad
            ? null
            : (value) {
                if (value == null || value == _dayViewMode) return;
                _emitState(() => _dayViewMode = value);
                _fetchAll();
              },
      ),
    );
    final search = TextFormField(
      key: const ValueKey('schedule-search-field'),
      controller: _desktopSearchController,
      enabled: !firstLoad && !_scheduleSearchLoading,
      textInputAction: TextInputAction.search,
      onFieldSubmitted: _runScheduleSearch,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: 'Поиск занятий',
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 32),
        suffixIcon: _hasScheduleSearch
            ? IconButton(
                tooltip: 'Очистить поиск',
                onPressed: _clearScheduleSearch,
                icon: const Icon(Icons.close_rounded, size: 16),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );
    return Container(
      key: const ValueKey('schedule-desktop-toolbar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            maximumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
          ),
        ),
        child: singleRow
            ? Row(
                children: [
                  navigation,
                  const SizedBox(width: 8),
                  views,
                  if (_currentView == ScheduleView.day) mode,
                  const SizedBox(width: 8),
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  actions,
                ],
              )
            : Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: navigation),
                      const SizedBox(width: 8),
                      if (!narrow) views,
                      actions,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (narrow) ...[views, const SizedBox(width: 8)],
                      Expanded(child: search),
                      if (_currentView == ScheduleView.day) ...[
                        const SizedBox(width: 8),
                        mode,
                      ],
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _desktopFilters(bool firstLoad) => MenuAnchor(
    style: const MenuStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
    menuChildren: [
      SizedBox(
        width: 540,
        height: (MediaQuery.sizeOf(context).height - 100).clamp(240.0, 480.0),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Builder(
              builder: (menuContext) => ScheduleFiltersPanel(
                initialBranchId: _selectedBranchId,
                initialMode: _dayViewMode,
                branches: _branches,
                isDayView: _currentView == ScheduleView.day,
                initialOnlyTrial: _onlyTrial,
                initialOnlyConflicts: _onlyConflicts,
                initialTeacherId: _filterTeacherId,
                teacherOptions: _teacherFilterOptions,
                showHeader: true,
                onApply: (result) {
                  MenuController.maybeOf(menuContext)?.close();
                  _applyScheduleFilterResult(result);
                },
              ),
            ),
          ),
        ),
      ),
    ],
    builder: (context, controller, child) => Badge(
      isLabelVisible: _activeScheduleFilterCount > 0,
      label: Text('$_activeScheduleFilterCount'),
      child: IconButton(
        key: const ValueKey('schedule-filter-toggle'),
        tooltip: _activeScheduleFilterCount == 0
            ? 'Фильтры расписания'
            : 'Фильтры ($_activeScheduleFilterCount)',
        onPressed: firstLoad
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        icon: Icon(
          Icons.tune_rounded,
          size: 19,
          color: _hasExtraFilters ? AppColor.gold : null,
        ),
      ),
    ),
  );

  Widget _desktopLegend() => MenuAnchor(
    menuChildren: [
      SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScheduleDayLegend(week: _currentView == ScheduleView.week),
              if (_currentView == ScheduleView.day) _buildAvailabilitySummary(),
            ],
          ),
        ),
      ),
    ],
    builder: (context, controller, child) => IconButton(
      tooltip: 'Обозначения и занятость',
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: Icon(
        _conflictsForSelectedDay().isEmpty
            ? Icons.info_outline_rounded
            : Icons.warning_amber_rounded,
        color: _conflictsForSelectedDay().isEmpty ? null : AppColor.danger,
        size: 19,
      ),
    ),
  );
}
