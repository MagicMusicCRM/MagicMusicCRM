part of 'client_card.dart';

extension _ClientCardInternalContext on _ClientCardState {
  Future<void> _fetchInternalContext() async {
    try {
      final role = await _resolveActorRole();
      if (!crmHasManagerAccess(role)) return;
      if (mounted) {
        _emitState(() {
          _internalContextAllowed = true;
          _internalContextLoading = true;
          _internalContextError = null;
        });
      }
      final service = ref.read(magicCrmServiceProvider);
      final values = await Future.wait<Object>([
        service.getClientInternalNote(
          clientType: widget.entityType,
          clientId: _entityId,
        ),
        service.getClientOperationalHistory(
          clientType: widget.entityType,
          clientId: _entityId,
        ),
      ]);
      if (!mounted) return;
      final history = values[1] as ClientOperationalHistoryPage;
      _emitState(() {
        _internalNote = values[0] as ClientInternalNote;
        _operationalHistory = history.items;
        _operationalHistoryCursor = history.nextCursor;
        _internalContextLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      _emitState(() {
        _internalContextError = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить внутреннюю заметку.',
        );
        _internalContextLoading = false;
      });
    }
  }

  Future<ClientInternalNote> _saveInternalNote(
    String body,
    int expectedVersion,
  ) async {
    final note = await ref
        .read(magicCrmServiceProvider)
        .updateClientInternalNote(
          clientType: widget.entityType,
          clientId: _entityId,
          body: body,
          expectedVersion: expectedVersion,
        );
    if (mounted) {
      _emitState(() => _internalNote = note);
      unawaited(_reloadOperationalHistory());
    }
    return note;
  }

  Future<ClientInternalNote> _reloadInternalNote() async {
    final note = await ref
        .read(magicCrmServiceProvider)
        .getClientInternalNote(
          clientType: widget.entityType,
          clientId: _entityId,
        );
    if (mounted) _emitState(() => _internalNote = note);
    return note;
  }

  Future<void> _reloadOperationalHistory() async {
    if (!_internalContextAllowed) return;
    try {
      final history = await ref
          .read(magicCrmServiceProvider)
          .getClientOperationalHistory(
            clientType: widget.entityType,
            clientId: _entityId,
          );
      if (!mounted) return;
      _emitState(() {
        _operationalHistory = history.items;
        _operationalHistoryCursor = history.nextCursor;
      });
    } catch (error) {
      debugPrint('Operational history refresh failed: $error');
    }
  }

  Future<void> _loadMoreOperationalHistory() async {
    final cursor = _operationalHistoryCursor;
    if (cursor == null || _operationalHistoryLoadingMore) return;
    _emitState(() => _operationalHistoryLoadingMore = true);
    try {
      final history = await ref
          .read(magicCrmServiceProvider)
          .getClientOperationalHistory(
            clientType: widget.entityType,
            clientId: _entityId,
            cursor: cursor,
          );
      if (!mounted) return;
      _emitState(() {
        final known = _operationalHistory.map((item) => item.id).toSet();
        _operationalHistory = [
          ..._operationalHistory,
          ...history.items.where((item) => known.add(item.id)),
        ];
        _operationalHistoryCursor = history.nextCursor;
      });
    } finally {
      if (mounted) {
        _emitState(() => _operationalHistoryLoadingMore = false);
      }
    }
  }
}
