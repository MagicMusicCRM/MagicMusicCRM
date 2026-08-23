part of 'client_card.dart';

extension _ClientCardTasksTab on _ClientCardState {
  Widget _buildTasksTab(ColorScheme cs) {
    final targetType = _isConverted ? 'student' : widget.entityType;
    final targetId = _isConverted ? _studentId : _entityId;
    return SharedTasksPanel(
      embedded: true,
      linkedEntity: EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: targetId,
        variant: targetType,
        presentation: EntityPresentationReference(
          primary: _clientPresentationLabel,
        ),
      ),
      scrollController: _taskScrollController,
      canWrite:
          widget.capabilitySnapshot?.allows('workflow.task.write') == true,
    );
  }

  /// Opens the month containing the nearest upcoming lesson and keeps the
  /// schedule scoped to this client. With no future lesson it opens this month.
  void _openScheduleFromCard() {
    final now = DateTime.now();
    DateTime? bestDt;
    for (final l in _lessons) {
      final dt = DateTime.tryParse(l.scheduledAt ?? '');
      final id = l.id;
      if (dt == null || id == null || id.isEmpty || dt.isBefore(now)) continue;
      if (bestDt == null || dt.isBefore(bestDt)) {
        bestDt = dt;
      }
    }
    final clientType = _isStudent && _studentId.isNotEmpty ? 'student' : 'lead';
    final clientId = clientType == 'student' ? _studentId : _leadId;
    if (clientId.isEmpty) return;
    final date = bestDt ?? now;
    final name = [_clientFirstName, _clientLastName]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' ');
    ref
        .read(scheduleNavigationProvider.notifier)
        .focusClientMonth(
          date,
          clientType: clientType,
          clientId: clientId,
          clientName: name.isEmpty ? null : name,
          branchId: _clientBranchId,
        );
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(
          CrmNavigationRequest.schedule(
            date: date,
            clientType: clientType,
            clientId: clientId,
          ),
        );
  }
}
