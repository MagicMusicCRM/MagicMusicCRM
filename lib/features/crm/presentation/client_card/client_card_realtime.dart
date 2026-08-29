part of 'client_card.dart';

extension _ClientCardRealtime on _ClientCardState {
  void _scheduleRealtimeRefresh(String entity) {
    if (!mounted || _realtimeRefreshQueued) return;
    if (_edited && entity != 'homework') {
      _realtimeRefreshDeferred = true;
      return;
    }
    _realtimeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _realtimeRefreshQueued = false;
      _refreshFromRealtime(entity);
    });
  }

  void _runDeferredRealtimeRefresh() {
    if (!mounted || _edited || !_realtimeRefreshDeferred) return;
    _realtimeRefreshDeferred = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_edited) {
        _refreshFromRealtime('lead', preserveVisibleContent: true);
      }
    });
  }

  void _refreshFromRealtime(
    String entity, {
    bool preserveVisibleContent = false,
  }) {
    switch (entity) {
      case 'homework':
        _emitState(() => _homeworkRefreshKey++);
        break;
      case 'lead':
      case 'student':
      case 'task':
      case 'comment':
      case 'lesson':
      case 'finance':
      case 'group':
      case 'chat_work':
        if (_mode.hasLeadHalf && _leadId.isNotEmpty) {
          _fetchCard(preserveVisibleContent: preserveVisibleContent);
          _fetchStatusHistory();
        }
        if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
          _fetchStudentData(preserveVisibleContent: preserveVisibleContent);
        }
        _fetchFamily();
        _fetchClientAccess();
        _fetchInternalContext();
        break;
    }
  }
}
