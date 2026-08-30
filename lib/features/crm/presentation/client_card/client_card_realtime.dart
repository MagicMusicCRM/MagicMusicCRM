part of 'client_card.dart';

extension _ClientCardRealtime on _ClientCardState {
  void _scheduleRealtimeRefresh(CrmChangedEvent event) {
    if (!mounted || !_realtimeEventTargetsThisCard(event)) return;

    // SharedTasksPanel owns task reconciliation. Reloading its parent card
    // duplicated that request and remounted unrelated editors.
    if (event.entity == 'task') return;
    if (event.entity == 'comment') {
      _emitState(() => _commentsRefreshKey++);
      return;
    }
    if (event.entity == 'homework') {
      _emitState(() => _homeworkRefreshKey++);
      return;
    }

    if (_edited) {
      _addRealtimeEvent(_realtimeRefreshDeferred, event);
      return;
    }
    _addRealtimeEvent(_realtimeRefreshQueue, event);
    if (_realtimeRefreshQueued) return;
    _realtimeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _realtimeRefreshQueued = false;
      final queued = List<CrmChangedEvent>.of(_realtimeRefreshQueue);
      _realtimeRefreshQueue.clear();
      for (final queuedEvent in queued) {
        if (_edited) {
          _addRealtimeEvent(_realtimeRefreshDeferred, queuedEvent);
        } else {
          _refreshFromRealtime(queuedEvent);
        }
      }
    });
  }

  bool _realtimeEventTargetsThisCard(CrmChangedEvent event) {
    final eventId = event.id?.trim();
    if (eventId == null || eventId.isEmpty) return true;
    return switch (event.entity) {
      'lead' => _mode.hasLeadHalf && eventId == _leadId,
      'student' => _mode.hasStudentHalf && eventId == _studentId,
      _ => true,
    };
  }

  void _addRealtimeEvent(List<CrmChangedEvent> target, CrmChangedEvent event) {
    final duplicate = target.any(
      (item) =>
          item.entity == event.entity &&
          item.action == event.action &&
          item.id == event.id,
    );
    if (!duplicate) target.add(event);
  }

  void _runDeferredRealtimeRefresh() {
    if (!mounted || _edited || _realtimeRefreshDeferred.isEmpty) return;
    final deferred = List<CrmChangedEvent>.of(_realtimeRefreshDeferred);
    _realtimeRefreshDeferred.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final event in deferred) {
        _scheduleRealtimeRefresh(event);
      }
    });
  }

  void _refreshFromRealtime(CrmChangedEvent event) {
    switch (event.entity) {
      case 'lead':
      case 'student':
      case 'lesson':
      case 'finance':
      case 'group':
      case 'chat_work':
        // Reconcile section data in the background. Identity values and the
        // editor epoch stay local, so focus/caret/drafts survive late echoes.
        if (_mode.hasLeadHalf && _leadId.isNotEmpty) {
          _fetchCard(preserveVisibleContent: true);
        }
        if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
          _fetchStudentData(preserveVisibleContent: true);
        }
        _fetchFamily();
        _fetchClientAccess();
        _fetchInternalContext();
        break;
    }
  }
}
