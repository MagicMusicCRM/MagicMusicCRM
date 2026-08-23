part of 'leads_widget.dart';

extension _LeadsActions on _LeadsWidgetState {
  // threshold prevents accidental scroll from a stationary press, and the
  // whole behaviour is suppressed when the platform requests reduced motion.
  void _handleDragUpdate(Offset globalPosition) {
    if (!mounted) return;

    // Reduced-motion: skip the eased autoscroll entirely.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _stopAutoScroll();
      return;
    }

    // Drag-start threshold: ignore tiny jitters until the pointer has moved a
    // meaningful distance from where the long-press began.
    _dragStartPosition ??= globalPosition;
    if (!_dragMovedEnough) {
      if ((globalPosition - _dragStartPosition!).distance <
          _LeadsWidgetState._dragStartThreshold) {
        return;
      }
      _dragMovedEnough = true;
    }

    final width = MediaQuery.of(context).size.width;
    // Penetration into the edge band, 0 at the threshold → 1 at the very edge.
    double penetration = 0;
    if (globalPosition.dx < _LeadsWidgetState._autoScrollEdge) {
      _autoScrollDir = -1;
      penetration =
          ((_LeadsWidgetState._autoScrollEdge - globalPosition.dx) /
                  _LeadsWidgetState._autoScrollEdge)
              .clamp(0.0, 1.0);
    } else if (globalPosition.dx > width - _LeadsWidgetState._autoScrollEdge) {
      _autoScrollDir = 1;
      penetration =
          ((globalPosition.dx - (width - _LeadsWidgetState._autoScrollEdge)) /
                  _LeadsWidgetState._autoScrollEdge)
              .clamp(0.0, 1.0);
    } else {
      _autoScrollDir = 0;
    }

    if (_autoScrollDir == 0) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      _autoScrollSpeed = 0;
      return;
    }

    // Ease-in (quadratic) ramp from min → max speed across the band.
    final eased = penetration * penetration;
    _autoScrollSpeed =
        _LeadsWidgetState._autoScrollMinSpeed +
        (_LeadsWidgetState._autoScrollMaxSpeed -
                _LeadsWidgetState._autoScrollMinSpeed) *
            eased;

    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_boardScrollController.hasClients || _autoScrollDir == 0) return;
      final pos = _boardScrollController.position;
      final next = (pos.pixels + _autoScrollDir * _autoScrollSpeed).clamp(
        0.0,
        pos.maxScrollExtent,
      );
      if (next != pos.pixels) _boardScrollController.jumpTo(next);
    });
  }

  void _stopAutoScroll() {
    _autoScrollDir = 0;
    _autoScrollSpeed = 0;
    _dragStartPosition = null;
    _dragMovedEnough = false;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  Future<void> _loadStatuses() async {
    final res = await ref.read(leadStatusesProvider.future);
    final statuses = <StatusRecord>[];
    for (final r in res) {
      final key = r['key'].toString();
      final label = r['label'].toString();
      final color = statusColorFromValue(r['color']);
      statuses.add((key, label, color));
    }

    if (!mounted) return;
    _emitState(() => _activeStatuses = statuses);
  }

  Future<void> _loadFilterMetadata() async {
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final hollihop = ref.read(hollihopServiceProvider);
      final results = await Future.wait<dynamic>([
        crm.listBranches(limit: 100),
        crm.listLeadSources(),
        crm.listResponsibleStaff(),
        hollihop.getDisciplines(),
        hollihop.getLevels(),
        hollihop.getCategories(),
      ]);
      if (!mounted) return;
      _emitState(() {
        _branches = List<Map<String, dynamic>>.from(results[0] as List);
        _sources = List<Map<String, dynamic>>.from(results[1] as List);
        _responsibles = List<Map<String, dynamic>>.from(results[2] as List);
        _disciplines = _stringOptions(results[3] as List);
        _levels = _stringOptions(results[4] as List);
        _categories = _stringOptions(results[5] as List);
      });
    } catch (_) {
      // Filter metadata is progressive; the board remains usable without it.
    }
  }

  List<Map<String, dynamic>> _stringOptions(List values) {
    return values
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .map((value) => {'id': value, 'name': value})
        .toList();
  }

  void _setFilters(LeadBoardFilters filters) {
    _emitState(() {
      _filters = filters;
      _resetLoadedPages();
    });
  }

  /// D1: handle a keystroke in the toolbar search field.
  ///
  /// Instantly updates [_liveQuery] so the already-loaded cards are filtered
  /// client-side on this frame (no waiting on the server), marks the search as
  /// in-flight to show the inline «идёт поиск…» hint, and debounces the actual
  /// server refetch through the existing [_setFilters] → [leadBoardProvider]
  /// path (service call/contract unchanged).
  void _onSearchChanged(String value) {
    final query = value.trim();
    _emitState(() {
      _liveQuery = query;
      _searchInFlight = query != _filters.q;
    });
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _setFilters(_filters.copyWith(q: query));
    });
  }

  /// D1: commit the search immediately (Enter pressed) — bypasses the debounce.
  void _submitSearch(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    _emitState(() => _liveQuery = query);
    _setFilters(_filters.copyWith(q: query));
  }

  /// D1: clear the toolbar search.
  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    _emitState(() {
      _liveQuery = '';
      _searchInFlight = false;
    });
    _setFilters(_filters.copyWith(q: ''));
  }

  /// D1: case-insensitive client-side match across the same fields the server
  /// search covers (name, phone, source) plus last name / branch / assignee so
  /// the instant in-flight result mirrors what the server will return.
  bool _matchesLiveQuery(Map<String, dynamic> lead, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    final haystack = [
      lead['name'],
      lead['last_name'],
      lead['phone'],
      lead['source'],
      lead['branch_name'],
      lead['assigned_name'],
    ].map((v) => v?.toString().toLowerCase() ?? '').join(' ');
    return haystack.contains(q);
  }

  void _refreshBoard() {
    _resetLoadedPages();
    ref.invalidate(leadBoardProvider(_filters));
    ref.invalidate(leadBoardItemsProvider);
  }

  void _resetLoadedPages() {
    _extraLeadsByStatus.clear();
    _nextCursorByStatus.clear();
    _loadingMoreStatuses.clear();
  }

  Future<void> _loadMoreLeads(String statusId, String? cursor) async {
    final activeCursor = cursor?.trim();
    if (activeCursor == null ||
        activeCursor.isEmpty ||
        _loadingMoreStatuses.contains(statusId)) {
      return;
    }
    _emitState(() => _loadingMoreStatuses.add(statusId));
    try {
      final page = await _filters.fetchBoard(
        ref.read(magicCrmServiceProvider),
        cursor: activeCursor,
        columnId: statusId,
      );
      final columns = page['columns'] is List
          ? (page['columns'] as List).whereType<Map<String, dynamic>>()
          : const Iterable<Map<String, dynamic>>.empty();
      Map<String, dynamic>? pageColumn;
      for (final column in columns) {
        final columnId =
            column['key']?.toString() ?? column['id']?.toString() ?? '';
        if (columnId == statusId) {
          pageColumn = column;
          break;
        }
      }
      if (!mounted) return;

      // Dedupe against this column only: its initial provider page plus its
      // already appended pages. Loading A must never mutate/reset B's extras.
      final knownIds = <String>{};
      final currentBoard = ref.read(leadBoardProvider(_filters)).value;
      final currentColumns = currentBoard?['columns'];
      if (currentColumns is List) {
        for (final rawColumn
            in currentColumns.whereType<Map<String, dynamic>>()) {
          final columnId =
              rawColumn['key']?.toString() ?? rawColumn['id']?.toString() ?? '';
          if (columnId != statusId || rawColumn['items'] is! List) continue;
          for (final lead
              in (rawColumn['items'] as List)
                  .whereType<Map<String, dynamic>>()) {
            final leadId = lead['id']?.toString() ?? '';
            if (leadId.isNotEmpty) knownIds.add(leadId);
          }
        }
      }
      final target = _extraLeadsByStatus.putIfAbsent(
        statusId,
        () => <Map<String, dynamic>>[],
      );
      knownIds.addAll(
        target
            .map((lead) => lead['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty),
      );
      var appended = 0;
      final items = pageColumn?['items'];
      if (items is List) {
        for (final lead in items.whereType<Map<String, dynamic>>()) {
          final leadId = lead['id']?.toString() ?? '';
          if (leadId.isEmpty || !knownIds.add(leadId)) continue;
          target.add(lead);
          appended++;
        }
      }
      final rawNextCursor = pageColumn?['next_cursor']?.toString().trim();
      _emitState(() {
        _nextCursorByStatus[statusId] =
            rawNextCursor == null || rawNextCursor.isEmpty
            ? null
            : rawNextCursor;
        _loadingMoreStatuses.remove(statusId);
      });
      if (appended == 0 && rawNextCursor == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Новых лидов для догрузки нет')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _emitState(() => _loadingMoreStatuses.remove(statusId));
      _showError(
        userErrorMessage(e, fallback: 'Не удалось загрузить ещё лидов.'),
      );
    }
  }

  Future<void> _addLead() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const LeadCreateDialog(),
    );
    if (result != null && mounted) _refreshBoard();
  }

  Future<void> _moveStatus(String id, String newStatus) async {
    if (id.isEmpty || _pendingLeadIds.contains(id)) return;
    // P3-7: a move into a terminal/requires-reason column must capture why.
    String? reasonId;
    String? statusComment;
    if (_statusRequiresReason[newStatus] == true) {
      final picked = await pickLossReason(context, ref);
      if (picked == null) return; // cancelled → leave the lead in place
      reasonId = picked.$1;
      statusComment = picked.$2;
    }
    final previous = _optimisticLeadStatuses[id];
    _emitState(() {
      _optimisticLeadStatuses[id] = newStatus;
      _pendingLeadIds.add(id);
    });
    try {
      // The board's "Без статуса" column has id == "unassigned" (not a UUID);
      // every real status column carries the lead_status UUID. Send statusId
      // only for a real UUID, otherwise ask the server to clear the status —
      // sending the raw column id was the cause of "statusId must be a UUID".
      final isUuid = _LeadsWidgetState._uuidRegExp.hasMatch(newStatus);
      await ref
          .read(magicCrmServiceProvider)
          .updateLead(
            id,
            statusId: isUuid ? newStatus : null,
            clearStatus: !isUuid,
            reasonId: reasonId,
            statusComment: statusComment,
          );
      _refreshBoard();
      await ref.read(leadBoardProvider(_filters).future);
      if (!mounted) return;
      _emitState(() {
        _optimisticLeadStatuses.remove(id);
        _pendingLeadIds.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      _emitState(() {
        if (previous == null) {
          _optimisticLeadStatuses.remove(id);
        } else {
          _optimisticLeadStatuses[id] = previous;
        }
        _pendingLeadIds.remove(id);
      });
      _showError(
        userErrorMessage(e, fallback: 'Не удалось изменить статус лида.'),
      );
    }
  }

  void _openDetail(Map<String, dynamic> lead) async {
    final changed = await showClientCard(
      context,
      entityType: 'lead',
      entityId: lead['id'].toString(),
      seed: lead,
    );
    if (changed == true) {
      _refreshBoard();
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColor.danger),
    );
  }

  /// Number of *secondary* filters currently active (everything the drawer
  /// holds). The inline quick-search [LeadBoardFilters.q] is intentionally
  /// excluded — it lives in the persistent toolbar field, not the drawer.
  int get _activeFilterCount {
    var count = 0;
    if (_filters.quick != 'all') count++;
    if (_filters.openTasks) count++;
    if (_filters.hideConverted) count++;
    if (_filters.branchId.isNotEmpty) count++;
    if (_filters.statusId.isNotEmpty) count++;
    if (_filters.assignedTo.isNotEmpty) count++;
    if (_filters.source.isNotEmpty) count++;
    if (_filters.discipline.isNotEmpty) count++;
    if (_filters.level.isNotEmpty) count++;
    if (_filters.category.isNotEmpty) count++;
    if (_filters.requestType.isNotEmpty) count++;
    if (_filters.goal.isNotEmpty) count++;
    if (_filters.gender.isNotEmpty) count++;
    if (_filters.preferredSchedule.isNotEmpty) count++;
    if (_filters.from.isNotEmpty || _filters.to.isNotEmpty) count++;
    return count;
  }

  void _onFiltersPressed() {
    // Desktop → inline dropdown panel below the button; phone → side drawer.
    if (MediaQuery.sizeOf(context).width >= 720) {
      _emitState(() => _filtersOpen = !_filtersOpen);
    } else {
      _openFiltersDrawer();
    }
  }

  Widget _buildInlineFilterPanel() => LeadsInlineFilterPanel(
    filters: _filters,
    searchText: _searchCtrl.text.trim(),
    branches: _branches,
    sources: _sources,
    responsibles: _responsibles,
    statuses: _activeStatuses,
    disciplines: _disciplines,
    levels: _levels,
    categories: _categories,
    onApply: _setFilters,
    onCollapse: () => _emitState(() => _filtersOpen = false),
  );

  Future<void> _openFiltersDrawer() => openLeadsFilterDrawer(
    context,
    filters: _filters,
    searchText: _searchCtrl.text.trim(),
    branches: _branches,
    sources: _sources,
    responsibles: _responsibles,
    statuses: _activeStatuses,
    disciplines: _disciplines,
    levels: _levels,
    categories: _categories,
    onApply: _setFilters,
  );

  StatusRecord _statusFromColumn(Map<String, dynamic> column) {
    final color = statusColorFromValue(column['color']);
    final columnId = column['id']?.toString();
    if (columnId != null && columnId.isNotEmpty) {
      _statusRequiresReason[columnId] =
          column['requiresReason'] == true || column['requires_reason'] == true;
    }
    return (
      column['key']?.toString() ?? column['id']?.toString() ?? 'new',
      column['label']?.toString() ??
          column['name']?.toString() ??
          'Без статуса',
      color,
    );
  }

  Widget _buildToolbar(Map<String, dynamic> board) {
    final total = board['total_count'] ?? 0;
    return ClientBoardToolbar(
      title: 'Воронка продаж · $total',
      searchKey: const ValueKey('leads-search'),
      searchController: _searchCtrl,
      searchHint: 'Имя, телефон, источник',
      activeFilterCount: _activeFilterCount,
      onSearchChanged: _onSearchChanged,
      onSearchSubmitted: _submitSearch,
      onClearSearch: _clearSearch,
      onFiltersPressed: _onFiltersPressed,
      inlineFilters: _filtersOpen && MediaQuery.sizeOf(context).width >= 720
          ? _buildInlineFilterPanel()
          : null,
      searching: _searchInFlight && _liveQuery.isNotEmpty,
    );
  }

  Widget _buildBoard(Map<String, dynamic> board) {
    final columns = board['columns'] is List
        ? (board['columns'] as List).whereType<Map<String, dynamic>>()
        : const Iterable<Map<String, dynamic>>.empty();
    final active = columns.map(_statusFromColumn).toList();

    // D1: while a query is live, instantly client-side filter the already
    // loaded cards so the result updates on this frame (server confirms later).
    final query = _liveQuery;

    // Leads optimistically removed by a completed transfer (kept here so the
    // converted card disappears at once and «Отменить» can restore it).
    final transferHidden = ref
        .read(leadTransferControllerProvider)
        .hiddenLeadIds;

    // D1: pre-compute the per-column leads so we can detect a wholly empty
    // result (after the client-side filter) and show «Ничего не найдено».
    final columnData =
        <(StatusRecord, List<Map<String, dynamic>>, int, String?)>[];
    var totalVisible = 0;
    for (final column in columns) {
      final status = _statusFromColumn(column);
      final rawLeads = column['items'] is List
          ? (column['items'] as List).whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      final extraLeads =
          _extraLeadsByStatus[status.$1] ?? const <Map<String, dynamic>>[];
      final leads = rawLeads
          .followedBy(extraLeads)
          .where((lead) => !_hiddenLeadIds.contains(lead['id']?.toString()))
          .where((lead) => !transferHidden.contains(lead['id']?.toString()))
          .where((lead) => _matchesLiveQuery(lead, query))
          .map((lead) {
            final id = lead['id']?.toString() ?? '';
            final status = _optimisticLeadStatuses[id];
            return status == null ? lead : {...lead, 'status': status};
          })
          .toList();
      final totalCountRaw = column['total_count'];
      final totalCount = totalCountRaw is num
          ? totalCountRaw.toInt()
          : int.tryParse(totalCountRaw?.toString() ?? '') ?? leads.length;
      final serverCursor = column['next_cursor']?.toString();
      final nextCursor = _nextCursorByStatus.containsKey(status.$1)
          ? _nextCursorByStatus[status.$1]
          : serverCursor;
      totalVisible += leads.length;
      columnData.add((status, leads, totalCount, nextCursor));
    }

    // D1: a wholly-empty board with an active query is a "no matches" state.
    final showNoResults =
        query.isNotEmpty && totalVisible == 0 && columnData.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _addLead,
        tooltip: 'Новый контакт',
        child: const Icon(Icons.person_add_rounded),
      ),
      body: Column(
        children: [
          _buildToolbar(board),
          Expanded(
            child: showNoResults
                ? LeadsNoResults(onClear: _clearSearch)
                : MagicDesktopScrollbar(
                    axis: Axis.horizontal,
                    controller: _boardScrollController,
                    builder: (context, controller) => SingleChildScrollView(
                      key: const PageStorageKey('leads_board_scroll'),
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: columnData.map((entry) {
                          final (status, leads, totalCount, nextCursor) = entry;
                          return _KanbanColumn(
                            status: status,
                            leads: leads,
                            totalCount: totalCount,
                            onMove: _moveStatus,
                            onTap: _openDetail,
                            allStatuses: active,
                            onRefresh: _refreshBoard,
                            pendingLeadIds: _pendingLeadIds,
                            nextCursor: nextCursor,
                            loadingMore: _loadingMoreStatuses.contains(
                              status.$1,
                            ),
                            onLoadMore: (cursor) =>
                                _loadMoreLeads(status.$1, cursor),
                            onDragUpdate: _handleDragUpdate,
                            onDragEnd: _stopAutoScroll,
                            hasActiveQuery: query.isNotEmpty,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
