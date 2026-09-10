part of 'client_card.dart';

enum _CardRefreshRegion {
  lead,
  student,
  commerce,
  family,
  access,
  context,
  comments,
  homework,
}

extension _ClientCardRealtime on _ClientCardState {
  void _scheduleRealtimeRefresh(CrmChangedEvent event) {
    if (!mounted || !_realtimeEventTargetsThisCard(event)) return;
    final regions = switch (event.entity) {
      // Task reconciliation is owned by SharedTasksPanel.
      'comment' => {_CardRefreshRegion.comments},
      'homework' => {_CardRefreshRegion.homework},
      'finance' => {_CardRefreshRegion.commerce},
      'lesson' ||
      'group' => {_CardRefreshRegion.student, _CardRefreshRegion.context},
      'chat_work' => {_CardRefreshRegion.context},
      'lead' || 'student' => {
        _CardRefreshRegion.lead,
        _CardRefreshRegion.student,
        _CardRefreshRegion.family,
        _CardRefreshRegion.access,
        _CardRefreshRegion.context,
      },
      _ => <_CardRefreshRegion>{},
    };
    _realtimeRefreshRegions.addAll(regions);
    _queueRealtimeRefresh();
  }

  bool _realtimeEventTargetsThisCard(CrmChangedEvent event) {
    final eventId = event.id?.trim();
    if (eventId == null || eventId.isEmpty) return true;
    return switch (event.entity) {
      'lead' => _mode.hasLeadHalf && eventId == _leadId,
      'student' => _mode.hasStudentHalf && eventId == _studentId,
      // Finance hints intentionally contain no student identifiers. Never
      // interpret an aggregate id or branch as a complete recipient scope.
      _ => true,
    };
  }

  void _queueRealtimeRefresh() {
    if (!mounted ||
        !_realtimeVisible ||
        _realtimeRefreshQueued ||
        _realtimeRefreshInFlight ||
        _realtimeRefreshRegions.isEmpty) {
      return;
    }
    // Finish opening before background reads can invalidate the initial
    // response that seeds the editable identity.
    if ((_mode.hasStudentHalf && _loadingStudent) ||
        (_mode.hasLeadHalf && _loadingCard)) {
      return;
    }
    _realtimeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _realtimeRefreshQueued = false;
      if (!mounted || !_realtimeVisible) return;
      unawaited(_drainRealtimeRefresh());
    });
    // A socket event need not otherwise schedule a frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _runDeferredRealtimeRefresh() => _queueRealtimeRefresh();

  Future<void> _drainRealtimeRefresh() async {
    if (_realtimeRefreshInFlight) return;
    if ((_mode.hasStudentHalf && _loadingStudent) ||
        (_mode.hasLeadHalf && _loadingCard)) {
      return;
    }
    final regions = _realtimeRefreshRegions
        .where(
          (region) =>
              !_edited ||
              region == _CardRefreshRegion.comments ||
              region == _CardRefreshRegion.homework,
        )
        .toSet();
    if (regions.isEmpty) return;
    _realtimeRefreshRegions.removeAll(regions);
    _realtimeRefreshInFlight = true;
    try {
      final requests = <Future<void>>[];
      if (regions.contains(_CardRefreshRegion.comments)) {
        _emitState(() => _commentsRefreshKey++);
      }
      if (regions.contains(_CardRefreshRegion.homework)) {
        _emitState(() => _homeworkRefreshKey++);
      }
      if (regions.contains(_CardRefreshRegion.lead) &&
          _mode.hasLeadHalf &&
          _leadId.isNotEmpty) {
        requests.add(_fetchCard(preserveVisibleContent: true));
      }
      if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
        if (regions.contains(_CardRefreshRegion.student)) {
          requests.add(_fetchStudentData(preserveVisibleContent: true));
        } else if (regions.contains(_CardRefreshRegion.commerce)) {
          requests.add(_readController.refreshCommerce(_studentId));
        }
      }
      if (regions.contains(_CardRefreshRegion.family)) {
        requests.add(_fetchFamily());
      }
      if (regions.contains(_CardRefreshRegion.access)) {
        requests.add(_fetchClientAccess());
      }
      if (regions.contains(_CardRefreshRegion.context)) {
        requests.add(_fetchInternalContext());
      }
      await Future.wait(requests);
    } finally {
      _realtimeRefreshInFlight = false;
      // Events received during the request require one trailing refresh: the
      // active read may have started before those mutations committed.
      if (!_edited) _queueRealtimeRefresh();
    }
  }
}
