part of 'schedule_widget.dart';

extension _ScheduleFocus on _ScheduleWidgetState {
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
        if (focus.branchId != null) {
          _selectedBranchId = focus.branchId;
          _allBranchesSelected = false;
        }
        _hideOtherClientLessons = false;
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

  void _armHighlightClear() {
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _highlightLessonId == null) return;
      _emitState(() => _highlightLessonId = null);
    });
  }

  void _clearHighlight() {
    if (_highlightLessonId == null) return;
    _highlightClearTimer?.cancel();
    _highlightLessonId = null;
  }
}
