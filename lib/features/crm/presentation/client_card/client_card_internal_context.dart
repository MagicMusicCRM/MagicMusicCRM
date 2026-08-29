part of 'client_card.dart';

extension _ClientCardInternalContext on _ClientCardState {
  Future<void> _fetchInternalContext() async {
    try {
      final role = (await ref.read(releaseGateStatusProvider.future)).role;
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

  // ── Merged section data (Phase 4) ─────────────────────────────────────────
  // Each merge tags rows with `_origin` (entityType) so converted views can show
  // an origin chip, then de-dups by `id` and sorts desc by date. Single-side
  // modes return just their own half (no behavioural change vs Phase 1/2).

  /// Lead status history + student timeline, normalised onto a shared shape and
  /// merged/sorted desc. Returns rows with: `_kind` ('status'|'event'),
  /// `_origin`, `_date`, `_title`, `_subtitle`.
  List<Map<String, dynamic>> get _mergedHistory {
    final out = <List<Map<String, dynamic>>>[];
    if (_mode.hasLeadHalf) {
      out.add(
        _statusHistory.map((h) {
          final from = h['old_status']?.toString();
          final to = h['new_status']?.toString();
          final transition = [
            if (from != null && from.isNotEmpty) from else 'Не указано',
            '→',
            if (to != null && to.isNotEmpty) to else 'Не указано',
          ].join(' ');
          final comment = h['comment']?.toString().trim() ?? '';
          return {
            'id': h['id'],
            '_origin': 'lead',
            '_kind': 'status',
            '_date': h['changed_at'],
            '_title': transition,
            '_subtitle': comment,
          };
        }).toList(),
      );
      // Field edits («кто поменял телефон»). Only the audit rows of the lead
      // timeline: the rest of it (comments, tasks, trials) already has its own
      // sections on the card and would show up twice here.
      out.add(
        _list(
          _leadCard?['timeline'],
        ).where((t) => t['type']?.toString() == 'audit').map((t) {
          return {
            'id': t['id'],
            '_origin': 'lead',
            '_kind': 'event',
            '_date': t['occurred_at'],
            '_title': t['title']?.toString() ?? 'Событие',
            '_subtitle': [
              if ((t['actor_name']?.toString().trim() ?? '').isNotEmpty)
                t['actor_name'].toString().trim(),
              if ((t['body']?.toString().trim() ?? '').isNotEmpty)
                t['body'].toString().trim(),
            ].join('\n'),
          };
        }).toList(),
      );
    }
    if (_mode.hasStudentHalf) {
      out.add(
        _list(_studentCardTimeline).map((t) {
          final body = t['body']?.toString().trim() ?? '';
          final actor = t['actor_name']?.toString().trim() ?? '';
          // For a field edit the author IS the point («кто поменял телефон»);
          // for a comment or lesson the card already shows it elsewhere.
          final isAudit = t['type']?.toString() == 'audit';
          return {
            'id': t['id'],
            '_origin': 'student',
            '_kind': 'event',
            '_date': t['occurred_at'],
            '_title': t['title']?.toString() ?? 'Событие',
            '_subtitle': isAudit && actor.isNotEmpty
                ? [actor, if (body.isNotEmpty) body].join('\n')
                : body,
          };
        }).toList(),
      );
    }
    return mergeByIdSorted(out, dateKey: '_date');
  }
}
