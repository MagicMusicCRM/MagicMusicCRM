part of 'client_card.dart';

extension _ClientCardRealtime on _ClientCardState {
  void _scheduleRealtimeRefresh(String entity) {
    if (!mounted || _realtimeRefreshQueued) return;
    if (_edited && (entity == 'lead' || entity == 'student')) return;
    _realtimeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _realtimeRefreshQueued = false;
      _refreshFromRealtime(entity);
    });
  }

  void _refreshFromRealtime(String entity) {
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
          _fetchCard();
          _fetchStatusHistory();
        }
        if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
          _fetchStudentData();
        }
        _fetchFamily();
        _fetchClientAccess();
        _fetchInternalContext();
        break;
    }
  }
}
