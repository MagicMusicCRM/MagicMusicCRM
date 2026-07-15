import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/convert_lead_dialog.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/core/services/hollihop_service.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_widgets.dart';
import 'manage_statuses_dialog.dart';
import 'lead_dialogs.dart';
import 'lead_board_filters.dart';
import 'leads_board_states.dart';

part 'kanban_column.dart';
part 'lead_card.dart';
part 'lead_drag_handle.dart';
part 'filters_button.dart';
part 'lead_badges.dart';
part 'lead_dialog.dart';

class LeadsWidget extends ConsumerStatefulWidget {
  const LeadsWidget({super.key});

  @override
  ConsumerState<LeadsWidget> createState() => _LeadsWidgetState();
}

class _LeadsWidgetState extends ConsumerState<LeadsWidget>
    with AutomaticKeepAliveClientMixin {
  static final _uuidRegExp = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  // D5: keep this board alive across tab/segment switches so the horizontal
  // scroll position, loaded-more pages and active filters survive navigation.
  @override
  bool get wantKeepAlive => true;
  final _searchCtrl = TextEditingController();
  final _boardScrollController = ScrollController();
  List<StatusRecord> _activeStatuses = [];
  // P3-7: status id → whether moving a lead here needs a loss/pause reason.
  final Map<String, bool> _statusRequiresReason = {};
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _disciplines = [];
  List<Map<String, dynamic>> _levels = [];
  List<Map<String, dynamic>> _categories = [];
  LeadBoardFilters _filters = const LeadBoardFilters();
  // Desktop: the secondary filters drop down as an inline panel below the
  // «Фильтры» button. On phones they still open in the side drawer.
  bool _filtersOpen = false;
  Timer? _searchDebounce;
  // D1 real-time search: the live (un-debounced) query typed into the toolbar
  // field. Used to client-side filter the already-loaded cards instantly while
  // the debounced server refetch is still in flight. Empty == no live filter.
  String _liveQuery = '';
  // True between a keystroke and the moment the matching server board lands —
  // drives a small inline «идёт поиск…» hint (never a full-board skeleton).
  bool _searchInFlight = false;
  final Map<String, String> _optimisticLeadStatuses = {};
  final Set<String> _hiddenLeadIds = {};
  final Set<String> _pendingLeadIds = {};
  final Map<String, List<Map<String, dynamic>>> _extraLeadsByStatus = {};
  final Set<String> _loadedExtraLeadIds = {};
  bool _hasLoadedMore = false;
  bool _loadingMore = false;
  String? _nextCursor;
  // Horizontal board auto-scroll while dragging a card near an edge.
  Timer? _autoScrollTimer;
  double _autoScrollDir = 0;
  // D3: per-tick scroll speed, eased from ~8 px near the activation threshold
  // up to ~24 px at the very edge (0 when outside the active band).
  double _autoScrollSpeed = 0;
  // D3: a small drag-start threshold — the card must travel this far from
  // where the long-press began before autoscroll is allowed to engage, so a
  // stationary press near an edge never triggers an unwanted scroll.
  Offset? _dragStartPosition;
  bool _dragMovedEnough = false;
  static const double _dragStartThreshold = 12.0;
  static const double _autoScrollMinSpeed = 8.0;
  static const double _autoScrollMaxSpeed = 24.0;
  static const double _autoScrollEdge = 110.0;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
    _loadFilterMetadata();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _autoScrollTimer?.cancel();
    _searchCtrl.dispose();
    _boardScrollController.dispose();
    super.dispose();
  }

  // While a card is dragged near the left/right edge of the board, scroll the
  // horizontal view so columns out of sight can be reached without dropping.
  //
  // D3 tuning: the speed eases from ~8 px/tick at the activation threshold up
  // to ~24 px/tick at the very edge (not a constant rate), a small drag-start
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
      if ((globalPosition - _dragStartPosition!).distance < _dragStartThreshold) {
        return;
      }
      _dragMovedEnough = true;
    }

    final width = MediaQuery.of(context).size.width;
    // Penetration into the edge band, 0 at the threshold → 1 at the very edge.
    double penetration = 0;
    if (globalPosition.dx < _autoScrollEdge) {
      _autoScrollDir = -1;
      penetration =
          ((_autoScrollEdge - globalPosition.dx) / _autoScrollEdge).clamp(
            0.0,
            1.0,
          );
    } else if (globalPosition.dx > width - _autoScrollEdge) {
      _autoScrollDir = 1;
      penetration =
          ((globalPosition.dx - (width - _autoScrollEdge)) / _autoScrollEdge)
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
        _autoScrollMinSpeed +
        (_autoScrollMaxSpeed - _autoScrollMinSpeed) * eased;

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
    setState(() => _activeStatuses = statuses);
  }

  Future<void> _loadFilterMetadata() async {
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final hollihop = ref.read(hollihopServiceProvider);
      final results = await Future.wait<dynamic>([
        crm.listBranches(limit: 100),
        hollihop.getDisciplines(),
        hollihop.getLevels(),
        hollihop.getCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(results[0] as List);
        _disciplines = _stringOptions(results[1] as List);
        _levels = _stringOptions(results[2] as List);
        _categories = _stringOptions(results[3] as List);
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
    setState(() {
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
    setState(() {
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
    setState(() => _liveQuery = query);
    _setFilters(_filters.copyWith(q: query));
  }

  /// D1: clear the toolbar search.
  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {
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
    ref.invalidate(leadsStreamProvider);
  }

  void _resetLoadedPages() {
    _extraLeadsByStatus.clear();
    _loadedExtraLeadIds.clear();
    _hasLoadedMore = false;
    _nextCursor = null;
  }

  Future<void> _loadMoreLeads(String? cursor) async {
    final activeCursor = cursor?.trim();
    if (activeCursor == null || activeCursor.isEmpty || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _filters.fetchBoard(
        ref.read(magicCrmServiceProvider),
        cursor: activeCursor,
      );
      final columns = page['columns'] is List
          ? (page['columns'] as List).whereType<Map<String, dynamic>>()
          : const Iterable<Map<String, dynamic>>.empty();
      var appended = 0;
      for (final column in columns) {
        final statusId =
            column['key']?.toString() ?? column['id']?.toString() ?? '';
        if (statusId.isEmpty) continue;
        final items = column['items'] is List
            ? (column['items'] as List).whereType<Map<String, dynamic>>()
            : const Iterable<Map<String, dynamic>>.empty();
        final target = _extraLeadsByStatus.putIfAbsent(
          statusId,
          () => <Map<String, dynamic>>[],
        );
        for (final lead in items) {
          final leadId = lead['id']?.toString() ?? '';
          if (leadId.isEmpty || !_loadedExtraLeadIds.add(leadId)) continue;
          target.add(lead);
          appended++;
        }
      }
      if (!mounted) return;
      setState(() {
        _hasLoadedMore = true;
        _nextCursor = page['next_cursor']?.toString();
        _loadingMore = false;
      });
      if (appended == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Новых лидов для догрузки нет')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _showError('Не удалось загрузить ещё лидов: $e');
    }
  }

  Future<void> _addLead() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _LeadDialog(),
    );
    if (result != null) {
      await ref
          .read(magicCrmServiceProvider)
          .createLead(
            firstName: result['name']!,
            phone: result['phone']!,
            source: result['source']!,
          );
      _refreshBoard();
    }
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
    setState(() {
      _optimisticLeadStatuses[id] = newStatus;
      _pendingLeadIds.add(id);
    });
    try {
      // The board's "Без статуса" column has id == "unassigned" (not a UUID);
      // every real status column carries the lead_status UUID. Send statusId
      // only for a real UUID, otherwise ask the server to clear the status —
      // sending the raw column id was the cause of "statusId must be a UUID".
      final isUuid = _uuidRegExp.hasMatch(newStatus);
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
      setState(() {
        _optimisticLeadStatuses.remove(id);
        _pendingLeadIds.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (previous == null) {
          _optimisticLeadStatuses.remove(id);
        } else {
          _optimisticLeadStatuses[id] = previous;
        }
        _pendingLeadIds.remove(id);
      });
      _showError('Не удалось изменить статус лида: $e');
    }
  }

  Future<void> _deleteLead(String id) async {
    if (id.isEmpty || _pendingLeadIds.contains(id)) return;
    final confirmed = await confirmDelete(
      context,
      title: 'Удалить лид?',
      body: 'Лид будет скрыт из воронки.',
    );
    if (!confirmed) return;
    setState(() {
      _hiddenLeadIds.add(id);
      _pendingLeadIds.add(id);
    });
    try {
      await ref.read(magicCrmServiceProvider).deleteLead(id);
      _refreshBoard();
      await ref.read(leadBoardProvider(_filters).future);
      if (!mounted) return;
      setState(() {
        _hiddenLeadIds.remove(id);
        _pendingLeadIds.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hiddenLeadIds.remove(id);
        _pendingLeadIds.remove(id);
      });
      _showError('Не удалось удалить лид: $e');
    }
  }

  /// Public entry-point for the lead→student conversion.
  ///
  /// Opens [ConvertLeadDialog], then performs an optimistic hide of the lead
  /// card from the Лиды funnel and shows an «Отменить» SnackBar (undo reverts
  /// the visual move only — the created student is not deleted).
  ///
  /// **DragTarget contract:** The future Ученики board's DragTarget should call
  /// `convertLeadToStudent(leadById(dragData))` from
  /// `DragTarget<String>.onAcceptWithDetails`.
  Future<void> convertLeadToStudent(Map<String, dynamic> lead) async {
    final id = lead['id']?.toString() ?? '';
    if (id.isEmpty || _pendingLeadIds.contains(id)) return;
    if ((lead['linked_student_id']?.toString() ?? '').isNotEmpty) {
      _showError('Лид уже связан с учеником');
      return;
    }

    final student = await ConvertLeadDialog.show(context, lead: lead);
    if (student == null || !mounted) return; // cancelled or failed in-dialog

    // Optimistic move: hide the card from the Лиды board immediately.
    setState(() {
      _hiddenLeadIds.add(id);
      _pendingLeadIds.add(id);
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Лид конвертирован в ученика'),
        backgroundColor: AppColor.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Отменить',
          textColor: Colors.white,
          onPressed: () {
            // Undo only reverts the visual move — the student stays created.
            if (!mounted) return;
            setState(() {
              _hiddenLeadIds.remove(id);
              _pendingLeadIds.remove(id);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Карточка лида возвращена. Ученик остаётся созданным — '
                  'удалите его вручную при необходимости.',
                ),
              ),
            );
          },
        ),
      ),
    );

    // Reconcile with the server: the lead now carries linked_student_id, so a
    // board refresh keeps it out of the funnel on its own.
    _refreshBoard();
    try {
      await ref.read(leadBoardProvider(_filters).future);
    } catch (_) {
      // Refresh failure is non-fatal; the optimistic hide already moved it.
    }
    if (!mounted) return;
    setState(() => _pendingLeadIds.remove(id));
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
    if (_filters.branchId.isNotEmpty) count++;
    if (_filters.statusId.isNotEmpty) count++;
    if (_filters.discipline.isNotEmpty) count++;
    if (_filters.level.isNotEmpty) count++;
    if (_filters.category.isNotEmpty) count++;
    return count;
  }

  void _onFiltersPressed() {
    // Desktop → inline dropdown panel below the button; phone → side drawer.
    if (MediaQuery.sizeOf(context).width >= 720) {
      setState(() => _filtersOpen = !_filtersOpen);
    } else {
      _openFiltersDrawer();
    }
  }

  Widget _buildInlineFilterPanel() => LeadsInlineFilterPanel(
    filters: _filters,
    searchText: _searchCtrl.text.trim(),
    branches: _branches,
    statuses: _activeStatuses,
    disciplines: _disciplines,
    levels: _levels,
    categories: _categories,
    onApply: _setFilters,
    onCollapse: () => setState(() => _filtersOpen = false),
  );

  Future<void> _openFiltersDrawer() => openLeadsFilterDrawer(
    context,
    filters: _filters,
    searchText: _searchCtrl.text.trim(),
    branches: _branches,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Воронка продаж · $total',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await ManageStatusesDialog.show(context);
                  await _loadStatuses();
                  _refreshBoard();
                },
                icon: const Icon(Icons.settings_rounded, size: 16),
                label: const Text('Колонки'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText: 'Имя, телефон, источник',
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: _clearSearch,
                            ),
                    ),
                    onChanged: _onSearchChanged,
                    onSubmitted: _submitSearch,
                  ),
                ),
                const SizedBox(width: 8),
                _FiltersButton(
                  activeCount: _activeFilterCount,
                  onPressed: _onFiltersPressed,
                ),
              ],
            ),
          ),
          if (_filtersOpen && MediaQuery.sizeOf(context).width >= 720)
            _buildInlineFilterPanel(),
          // D1: a small inline progress hint shown only while the debounced
          // server refetch for the current query is in flight. It never
          // replaces the board, so the previous results stay visible.
          if (_searchInFlight && _liveQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    'идёт поиск…',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    super.build(context); // D5: required by AutomaticKeepAliveClientMixin.
    // Rebuild when the transfer flow hides a converted lead (optimistic) so the
    // dragged card leaves the funnel the instant the drop completes.
    ref.watch(leadTransferControllerProvider);
    // Realtime: refresh when another staff member changes a lead.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || event.entity != 'lead' || !mounted) return;
      if (event.isFallbackPoll) return;
      _refreshBoard();
    });
    final boardAsync = ref.watch(leadBoardProvider(_filters));

    // D1: keep the PREVIOUS board visible during a (debounced) refetch instead
    // of flashing a full-board skeleton. Only the very first load — when there
    // is no value to fall back on — shows the skeleton.
    if (boardAsync.isLoading && !boardAsync.hasValue) {
      return const KanbanSkeleton();
    }
    if (boardAsync.hasError && !boardAsync.hasValue) {
      return LeadsBoardError(onRetry: _refreshBoard);
    }

    final board = boardAsync.value ?? const <String, dynamic>{};

    // D1: once the matching server result has landed, drop the in-flight hint.
    // Done after this frame so we never call setState during build.
    if (_searchInFlight &&
        !boardAsync.isLoading &&
        _filters.q == _liveQuery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchInFlight) {
          setState(() => _searchInFlight = false);
        }
      });
    }

    return _buildBoard(board);
  }


  Widget _buildBoard(Map<String, dynamic> board) {
    final columns = board['columns'] is List
        ? (board['columns'] as List).whereType<Map<String, dynamic>>()
        : const Iterable<Map<String, dynamic>>.empty();
    final active = columns.map(_statusFromColumn).toList();
    final pageCursor = _hasLoadedMore
        ? _nextCursor
        : board['next_cursor']?.toString();

    // D1: while a query is live, instantly client-side filter the already
    // loaded cards so the result updates on this frame (server confirms later).
    final query = _liveQuery;

    // Leads optimistically removed by a completed transfer (kept here so the
    // converted card disappears at once and «Отменить» can restore it).
    final transferHidden =
        ref.read(leadTransferControllerProvider).hiddenLeadIds;

    // D1: pre-compute the per-column leads so we can detect a wholly empty
    // result (after the client-side filter) and show «Ничего не найдено».
    final columnData = <(StatusRecord, List<Map<String, dynamic>>, int)>[];
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
          .where(
            (lead) => !_hiddenLeadIds.contains(lead['id']?.toString()),
          )
          .where(
            (lead) => !transferHidden.contains(lead['id']?.toString()),
          )
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
      totalVisible += leads.length;
      columnData.add((status, leads, totalCount));
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
                : Scrollbar(
                    controller: _boardScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      key: const PageStorageKey('leads_board_scroll'),
                      controller: _boardScrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: columnData.map((entry) {
                          final (status, leads, totalCount) = entry;
                          return _KanbanColumn(
                            status: status,
                            leads: leads,
                            totalCount: totalCount,
                            onMove: _moveStatus,
                            onDelete: _deleteLead,
                            onTap: _openDetail,
                            allStatuses: active,
                            onRefresh: _refreshBoard,
                            pendingLeadIds: _pendingLeadIds,
                            nextCursor: pageCursor,
                            loadingMore: _loadingMore,
                            onLoadMore: _loadMoreLeads,
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

  /// D1: board-wide empty state shown when a search matches nothing.
}

