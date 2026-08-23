part of 'schedule_widget.dart';

extension _ScheduleContextBanners on _ScheduleWidgetState {
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
            _ScheduleBadge(
              icon: Icons.warning_amber_rounded,
              label: 'Конфликты: ${conflicts.length}',
              color: conflicts.isEmpty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : AppColor.danger,
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
      final dt = _parseServerTime(conflict['scheduled_at']);
      return dt != null &&
          dt.year == _selectedDate.year &&
          dt.month == _selectedDate.month &&
          dt.day == _selectedDate.day;
    }).toList();
  }
}
