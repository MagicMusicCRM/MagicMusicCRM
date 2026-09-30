part of 'schedule_widget.dart';

extension _ScheduleContextBanners on _ScheduleWidgetState {
  void _setConflictFilter(bool selected) => _applyScheduleFilterResult((
    branchId: _selectedBranchId,
    mode: _dayViewMode,
    teacherId: _filterTeacherId,
    onlyTrial: _onlyTrial,
    onlyConflicts: selected,
    settlementTypes: _settlementTypes,
    compensationRules: _compensationRules,
  ));

  Widget _buildConflictFilterBanner() {
    final count = _lessonsInCurrentView()
        .where((lesson) => conflictTypes(lesson['conflict_types']).isNotEmpty)
        .length;
    if (count == 0 && !_onlyConflicts) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilterChip(
          key: const ValueKey('schedule-conflicts-shortcut'),
          avatar: const Icon(
            Icons.warning_amber_rounded,
            color: AppColor.danger,
            size: 18,
          ),
          label: Text('Занятий с конфликтами: $count'),
          tooltip: 'В показанном периоде с учётом выбранных фильтров',
          selected: _onlyConflicts,
          onSelected: _setConflictFilter,
        ),
      ),
    );
  }

  Widget _buildActiveFilterBanner() {
    void remove(String filter) => _applyScheduleFilterResult((
      branchId: _selectedBranchId,
      mode: _dayViewMode,
      teacherId: filter == 'teacher' ? null : _filterTeacherId,
      onlyTrial: filter == 'trial' ? false : _onlyTrial,
      onlyConflicts: filter == 'conflicts' ? false : _onlyConflicts,
      settlementTypes: filter == 'settlement' ? <String>{} : _settlementTypes,
      compensationRules: filter == 'compensation'
          ? <String>{}
          : _compensationRules,
    ));
    final labels = <String, String>{
      if (_filterTeacherId != null)
        'teacher':
            'Преподаватель: ${_teacherFilterOptions.where((t) => t.id == _filterTeacherId).firstOrNull?.name ?? 'Выбран'}',
      if (_onlyTrial) 'trial': 'Только пробные',
      if (_onlyConflicts) 'conflicts': 'Только конфликты',
      if (_settlementTypes.isNotEmpty)
        'settlement': 'Типы расчёта: ${_settlementTypes.length}',
      if (_compensationRules.isNotEmpty)
        'compensation': 'Правила оплаты: ${_compensationRules.length}',
    };
    if (labels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final entry in labels.entries)
            InputChip(
              label: Text(entry.value),
              onDeleted: () => remove(entry.key),
            ),
        ],
      ),
    );
  }

  Widget _buildClientFilterBanner() {
    final fallback = _filterClientType == 'lead' ? 'Лид' : 'Ученик';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(
        spacing: AppSpace.lg,
        runSpacing: AppSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InputChip(
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
          FilterChip(
            key: const ValueKey('client-calendar-hide-others'),
            selected: _hideOtherClientLessons,
            label: const Text('Скрывать чужие занятия'),
            onSelected: (selected) =>
                _emitState(() => _hideOtherClientLessons = selected),
          ),
          if (!_hideOtherClientLessons)
            _clientContextLegend(
              Icons.people_outline_rounded,
              AppColor.text2,
              'Другие клиенты',
            ),
        ],
      ),
    );
  }

  Widget _buildClientContextBanner() {
    final name = _contextClientName?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(
        spacing: AppSpace.lg,
        runSpacing: AppSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            key: const ValueKey('client-calendar-hide-others'),
            selected: _hideOtherClientLessons,
            label: const Text('Скрывать чужие занятия'),
            onSelected: (selected) =>
                _emitState(() => _hideOtherClientLessons = selected),
          ),
          _clientContextLegend(
            Icons.person_pin_circle_outlined,
            AppColor.success,
            name == null || name.isEmpty ? 'Клиент карточки' : name,
          ),
          if (!_hideOtherClientLessons)
            _clientContextLegend(
              Icons.people_outline_rounded,
              AppColor.text2,
              'Другие клиенты',
            ),
        ],
      ),
    );
  }

  Widget _buildScheduleSearchBanner() {
    final matchCount = _lessonsInCurrentView()
        .where(_matchesScheduleSearch)
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(
        spacing: AppSpace.lg,
        runSpacing: AppSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InputChip(
            avatar: const Icon(Icons.search_rounded, size: 18),
            label: Text('Поиск: $_scheduleSearchQuery'),
            onDeleted: _clearScheduleSearch,
          ),
          if (_scheduleSearchLoading)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          _clientContextLegend(
            matchCount == 0
                ? Icons.search_off_rounded
                : Icons.person_search_rounded,
            matchCount == 0 ? AppColor.warning : AppColor.success,
            'Совпадений: $matchCount',
          ),
          _clientContextLegend(
            Icons.people_outline_rounded,
            AppColor.text2,
            'Остальные занятия',
          ),
          _clientContextLegend(
            Icons.auto_awesome_rounded,
            AppColor.gold,
            'Первое совпадение',
          ),
        ],
      ),
    );
  }

  Widget _clientContextLegend(IconData icon, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );

  Widget _buildAvailabilitySummary() {
    final availability = _roomAvailability.where((item) {
      return _selectedBranchId == null ||
          item['branch_id']?.toString() == _selectedBranchId;
    }).toList();
    final emptyRoomCount = availability
        .where((item) => item['is_available'] == true)
        .length;
    final scheduledRoomCount = availability
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
                  ? 'Проверяем занятость аудиторий'
                  : 'Без занятий: $emptyRoomCount',
              color: AppColor.success,
            ),
            _ScheduleBadge(
              icon: Icons.event_busy_rounded,
              label: 'С занятиями: $scheduledRoomCount',
              color: scheduledRoomCount > 0
                  ? AppTheme.warning
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            ActionChip(
              avatar: const Icon(
                Icons.warning_amber_rounded,
                color: AppColor.danger,
                size: 18,
              ),
              label: Text('Конфликты: ${conflicts.length}'),
              onPressed: conflicts.isEmpty
                  ? null
                  : () => _setConflictFilter(true),
            ),
            if (availability.isEmpty && !_availabilityLoading)
              Text(
                'Занятость аудиторий появится после расчёта.',
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
      final dt = _parseServerTime(
        conflict['scheduled_at'],
        conflict['scheduled_utc_offset_minutes'],
      );
      return dt != null &&
          dt.year == _selectedDate.year &&
          dt.month == _selectedDate.month &&
          dt.day == _selectedDate.day;
    }).toList();
  }
}
