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
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_widgets.dart';
import 'manage_statuses_dialog.dart';

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
      final picked = await _pickLossReason();
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

  /// P3-7: ask for a loss/pause reason (+ optional comment) before a terminal
  /// move. Returns `(reasonId, comment)` or `null` when the user cancels.
  Future<(String?, String?)?> _pickLossReason() async {
    List<Map<String, dynamic>> reasons = const [];
    try {
      reasons = await ref.read(magicCrmServiceProvider).listLossReasons();
    } catch (_) {
      // Reasons failed to load — still allow confirming with a free comment.
    }
    if (!mounted) return null;
    String? selectedId;
    final commentController = TextEditingController();
    final confirmed = await showMagicSheet<bool>(
      context,
      title: 'Причина',
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final cs = Theme.of(ctx).colorScheme;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final r in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    onTap: () =>
                        setSheet(() => selectedId = r['id']?.toString()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.md,
                        vertical: AppSpace.sm,
                      ),
                      decoration: BoxDecoration(
                        color: r['id']?.toString() == selectedId
                            ? AppColor.goldSoft
                            : cs.surface,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(
                          color: r['id']?.toString() == selectedId
                              ? AppColor.gold
                              : cs.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            r['id']?.toString() == selectedId
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                            color: r['id']?.toString() == selectedId
                                ? AppColor.gold
                                : cs.outline,
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(child: Text(r['name']?.toString() ?? '—')),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: commentController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (необязательно)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColor.gold,
                        foregroundColor: AppColor.onGold,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: const Text('Подтвердить'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    final comment = commentController.text.trim();
    commentController.dispose();
    if (confirmed != true) return null;
    return (selectedId, comment.isEmpty ? null : comment);
  }

  Future<void> _deleteLead(String id) async {
    if (id.isEmpty || _pendingLeadIds.contains(id)) return;
    final confirmed = await _confirmDelete(
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

  // Desktop inline filters: drops BELOW the «Фильтры» button (not a side drawer),
  // controls wrap onto multiple rows (never one long horizontal strip), and each
  // edit applies live through the same [_setFilters] path the drawer used.
  Widget _buildInlineFilterPanel() {
    Widget quickChip(String value, String chipLabel) => ChoiceChip(
      label: Text(chipLabel),
      selected: _filters.quick == value,
      onSelected: (_) => _setFilters(_filters.copyWith(quick: value)),
    );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColor.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              quickChip('all', 'Все'),
              quickChip('active', 'В работе'),
              quickChip('deferred', 'Отложенные'),
              quickChip('processed', 'Обработанные'),
              FilterChip(
                label: const Text('Есть задачи'),
                selected: _filters.openTasks,
                onSelected: (v) => _setFilters(_filters.copyWith(openTasks: v)),
              ),
              _filterDropdown(
                width: 200,
                label: 'Филиал',
                value: _filters.branchId,
                options: _branches,
                onChanged: (v) =>
                    _setFilters(_filters.copyWith(branchId: v ?? '')),
              ),
              _filterDropdown(
                width: 200,
                label: 'Статус',
                value: _filters.statusId,
                options: _activeStatuses
                    .map((s) => {'id': s.$1, 'name': s.$2})
                    .toList(),
                onChanged: (v) =>
                    _setFilters(_filters.copyWith(statusId: v ?? '')),
              ),
              _filterDropdown(
                width: 200,
                label: 'Направление',
                value: _filters.discipline,
                options: _disciplines,
                valueField: 'name',
                onChanged: (v) =>
                    _setFilters(_filters.copyWith(discipline: v ?? '')),
              ),
              _filterDropdown(
                width: 200,
                label: 'Уровень',
                value: _filters.level,
                options: _levels,
                valueField: 'name',
                onChanged: (v) =>
                    _setFilters(_filters.copyWith(level: v ?? '')),
              ),
              _filterDropdown(
                width: 200,
                label: 'Категория',
                value: _filters.category,
                options: _categories,
                valueField: 'name',
                onChanged: (v) =>
                    _setFilters(_filters.copyWith(category: v ?? '')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    _setFilters(LeadBoardFilters(q: _searchCtrl.text.trim())),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Сбросить'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _filtersOpen = false),
                child: const Text('Свернуть'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens the secondary filters in a v7 right-side slide-out drawer.
  ///
  /// The drawer edits a local *draft* copy of [_filters]; nothing touches the
  /// board until «Применить», which routes through the exact same
  /// [_setFilters] path the inline controls used — so the fetched/shown leads
  /// for a given combination are byte-for-byte identical to before. «Сбросить»
  /// returns the draft to defaults while preserving the active quick-search.
  Future<void> _openFiltersDrawer() async {
    // Seed the draft from the live filters, keeping the current search text so
    // applying the drawer never clobbers the inline quick search.
    var draft = _filters.copyWith(q: _searchCtrl.text.trim());

    final applied = await showMagicDrawer<bool>(
      context,
      title: 'Фильтры',
      builder: (drawerContext) {
        return StatefulBuilder(
          builder: (drawerContext, setDrawerState) {
            void update(LeadBoardFilters next) =>
                setDrawerState(() => draft = next);

            Widget section(String label, Widget child) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColor.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                child,
                const SizedBox(height: AppSpace.lg),
              ],
            );

            Widget quickChip(String value, String chipLabel) => ChoiceChip(
              label: Text(chipLabel),
              selected: draft.quick == value,
              onSelected: (_) => update(draft.copyWith(quick: value)),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                section(
                  'Быстрый фильтр',
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      quickChip('all', 'Все'),
                      quickChip('active', 'В работе'),
                      quickChip('deferred', 'Отложенные'),
                      quickChip('processed', 'Обработанные'),
                    ],
                  ),
                ),
                section(
                  'Задачи',
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilterChip(
                      label: const Text('Есть задачи'),
                      selected: draft.openTasks,
                      onSelected: (selected) =>
                          update(draft.copyWith(openTasks: selected)),
                    ),
                  ),
                ),
                section(
                  'Филиал',
                  _filterDropdown(
                    width: double.infinity,
                    label: 'Филиал',
                    value: draft.branchId,
                    options: _branches,
                    onChanged: (value) =>
                        update(draft.copyWith(branchId: value ?? '')),
                  ),
                ),
                section(
                  'Статус',
                  _filterDropdown(
                    width: double.infinity,
                    label: 'Статус',
                    value: draft.statusId,
                    options: _activeStatuses
                        .map((s) => {'id': s.$1, 'name': s.$2})
                        .toList(),
                    onChanged: (value) =>
                        update(draft.copyWith(statusId: value ?? '')),
                  ),
                ),
                section(
                  'Направление',
                  _filterDropdown(
                    width: double.infinity,
                    label: 'Направление',
                    value: draft.discipline,
                    options: _disciplines,
                    valueField: 'name',
                    onChanged: (value) =>
                        update(draft.copyWith(discipline: value ?? '')),
                  ),
                ),
                section(
                  'Уровень',
                  _filterDropdown(
                    width: double.infinity,
                    label: 'Уровень',
                    value: draft.level,
                    options: _levels,
                    valueField: 'name',
                    onChanged: (value) =>
                        update(draft.copyWith(level: value ?? '')),
                  ),
                ),
                section(
                  'Категория',
                  _filterDropdown(
                    width: double.infinity,
                    label: 'Категория',
                    value: draft.category,
                    options: _categories,
                    valueField: 'name',
                    onChanged: (value) =>
                        update(draft.copyWith(category: value ?? '')),
                  ),
                ),
              ],
            );
          },
        );
      },
      actions: [
        OutlinedButton(
          onPressed: () {
            // Reset the secondary filters to defaults, but keep the active
            // quick-search text the toolbar field still shows.
            draft = LeadBoardFilters(q: _searchCtrl.text.trim());
            _setFilters(draft);
            Navigator.of(context).maybePop(false);
          },
          child: const Text('Сбросить'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).maybePop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColor.gold,
            foregroundColor: AppColor.onGold,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
          child: const Text('Применить'),
        ),
      ],
    );

    // Commit the draft only on «Применить»; «Сбросить» already applied above.
    if (applied == true) {
      _setFilters(draft);
    }
  }

  Future<bool> _confirmDelete({
    required String title,
    required String body,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColor.danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

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

  Widget _filterDropdown({
    required double width,
    required String label,
    required String value,
    required List<Map<String, dynamic>> options,
    required ValueChanged<String?> onChanged,
    String valueField = 'id',
  }) {
    final normalizedValue = value.isEmpty ? '' : value;
    final seen = <String>{};
    final optionItems = options
        .map((item) {
          final optionValue = item[valueField]?.toString() ?? '';
          final optionLabel =
              item['name']?.toString() ??
              item['label']?.toString() ??
              optionValue;
          return (optionValue, optionLabel);
        })
        .where((item) => item.$1.isNotEmpty && seen.add(item.$1))
        .toList();
    final hasSelected =
        normalizedValue.isEmpty ||
        optionItems.any((item) => item.$1 == normalizedValue);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: width,
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label:$normalizedValue'),
          initialValue: normalizedValue,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            const DropdownMenuItem(value: '', child: Text('Все')),
            if (!hasSelected)
              DropdownMenuItem(
                value: normalizedValue,
                child: Text(normalizedValue, overflow: TextOverflow.ellipsis),
              ),
            ...optionItems.map(
              (item) => DropdownMenuItem(
                value: item.$1,
                child: Text(item.$2, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
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
      return _buildBoardError();
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

  Widget _buildBoardError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColor.danger,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'Не удалось загрузить воронку',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Проверьте подключение и попробуйте снова.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _refreshBoard,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
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
                ? _buildNoResults()
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
  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'Ничего не найдено',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Измените запрос или сбросьте поиск и фильтры.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Сбросить поиск'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KanbanColumn extends StatefulWidget {
  final StatusRecord status;
  final List<Map<String, dynamic>> leads;
  final int totalCount;
  final Function(String, String) onMove;
  final Function(String) onDelete;
  final Function(Map<String, dynamic>) onTap;
  final List<StatusRecord> allStatuses;
  final VoidCallback onRefresh;
  final Set<String> pendingLeadIds;
  final String? nextCursor;
  final bool loadingMore;
  final ValueChanged<String?> onLoadMore;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  // D1/D5: whether a board-wide search query is active, so an empty column
  // shows the right message («ничего не найдено» vs «нет лидов»).
  final bool hasActiveQuery;

  const _KanbanColumn({
    required this.status,
    required this.leads,
    required this.totalCount,
    required this.onMove,
    required this.onDelete,
    required this.onTap,
    required this.allStatuses,
    required this.onRefresh,
    required this.pendingLeadIds,
    required this.nextCursor,
    required this.loadingMore,
    required this.onLoadMore,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.hasActiveQuery = false,
  });

  @override
  State<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<_KanbanColumn> {
  @override
  Widget build(BuildContext context) {
    final hasMore =
        (widget.nextCursor?.trim().isNotEmpty ?? false) &&
        widget.totalCount > widget.leads.length;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        widget.onDragEnd();
        widget.onMove(details.data, widget.status.$1);
      },
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        // Cap the column to a fraction of the screen so cards are never
        // horizontally clipped on a narrow (mobile) viewport, while keeping a
        // comfortable fixed width on wider (desktop) screens. The 24 subtracts
        // the column's own horizontal margins (6 + 6) plus board padding so a
        // single column still fits fully inside the viewport on small phones.
        final screenWidth = MediaQuery.of(context).size.width;
        final columnWidth = screenWidth < 360
            ? (screenWidth - 24).clamp(220.0, 300.0)
            : 300.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: columnWidth,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: hovering
                ? widget.status.$3.withAlpha(30)
                : Theme.of(context).colorScheme.surface.withAlpha(127),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: hovering
                  ? widget.status.$3
                  : widget.status.$3.withAlpha(45),
              width: hovering ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.status.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.status.$2,
                      style: TextStyle(
                        color: widget.status.$3,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(
                          color: widget.status.$3.withAlpha(70),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${widget.totalCount}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: hovering
                    ? Container(
                        height: 40,
                        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: widget.status.$3,
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          color: widget.status.$3.withAlpha(25),
                        ),
                        child: Center(
                          child: Text(
                            'Отпустите, чтобы перенести',
                            style: TextStyle(
                              color: widget.status.$3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: widget.leads.isEmpty && !hasMore
                    ? _buildEmptyColumn(context)
                    : ListView.builder(
                  key: PageStorageKey('leads_col_${widget.status.$1}'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.leads.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= widget.leads.length) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
                        child: OutlinedButton.icon(
                          onPressed: widget.loadingMore
                              ? null
                              : () => widget.onLoadMore(widget.nextCursor),
                          icon: widget.loadingMore
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more_rounded),
                          label: Text(
                            widget.loadingMore
                                ? 'Загрузка...'
                                : 'Загрузить ещё',
                          ),
                        ),
                      );
                    }
                    final lead = widget.leads[index];
                    final leadId = lead['id']?.toString() ?? '';
                    return _LeadCard(
                      lead: lead,
                      statusColor: widget.status.$3,
                      allStatuses: widget.allStatuses,
                      onMove: widget.onMove,
                      onDelete: widget.onDelete,
                      onTap: () => widget.onTap(lead),
                      onRefresh: widget.onRefresh,
                      isPending: widget.pendingLeadIds.contains(leadId),
                      onDragUpdate: widget.onDragUpdate,
                      onDragEnd: widget.onDragEnd,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// D5: per-column empty state. Distinguishes a search miss («ничего не
  /// найдено») from a genuinely empty column («перетащите карточку сюда»).
  Widget _buildEmptyColumn(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final searching = widget.hasActiveQuery;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.search_off_rounded
                  : Icons.inbox_outlined,
              size: 28,
              color: cs.onSurfaceVariant.withAlpha(140),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              searching ? 'Ничего не найдено' : 'Нет лидов',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              searching
                  ? 'Измените запрос'
                  : 'Перетащите карточку сюда',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant.withAlpha(160),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Finalizing kanban column structure

class _LeadCard extends ConsumerWidget {
  final Map<String, dynamic> lead;
  final Color statusColor;
  final List<StatusRecord> allStatuses;
  final Function(String, String) onMove;
  final Function(String) onDelete;
  final VoidCallback onTap;
  final VoidCallback onRefresh;
  final bool isPending;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _LeadCard({
    required this.lead,
    required this.statusColor,
    required this.allStatuses,
    required this.onMove,
    required this.onDelete,
    required this.onTap,
    required this.onRefresh,
    required this.isPending,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = lead['id']?.toString() ?? '';
    final firstName = lead['name']?.toString() ?? '';
    final lName = lead['last_name']?.toString() ?? '';
    final name = '$firstName $lName'.trim();
    final displayName = name.isEmpty ? 'Без имени' : name;
    final phone = lead['phone']?.toString() ?? '';
    final source = lead['source']?.toString() ?? '';
    final branchName = lead['branch_name']?.toString() ?? '';
    final assignedName = lead['assigned_name']?.toString() ?? '';
    final linkedStudentId = lead['linked_student_id']?.toString() ?? '';
    final openTasks = _intValue(lead['open_tasks_count']);
    final comments = _intValue(lead['comments_count']);
    final trials = _intValue(lead['trial_lessons_count']);
    final currentStatus = lead['status']?.toString() ?? 'new';
    final dtStr = lead['created_at']?.toString();
    final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
    final dateStr = dt != null ? DateFormat('d MMM', 'ru').format(dt) : '';

    final customData = lead['custom_data'] as Map<String, dynamic>? ?? {};
    final discipline = customData['discipline']?.toString() ?? '';
    final level = customData['level']?.toString() ?? '';

    final transfer = ref.read(leadTransferControllerProvider);
    // True while THIS card is the one carried by the transfer drag — the card
    // stays mounted (so the Draggable survives) but renders as a faded source
    // placeholder.
    final beingTransferred = ref.watch(
      leadTransferControllerProvider.select(
        (c) => c.isActive && c.leadId == id,
      ),
    );

    return LongPressDraggable<String>(
      data: id,
      maxSimultaneousDrags: isPending ? 0 : null,
      // Snappier than the platform 500ms long-press, but still long enough that a
      // normal click (tap → open) doesn't linger past the threshold and silently
      // move the lead (a 180ms delay mis-fired that way). 250ms reads as instant
      // while keeping click vs. deliberate-drag cleanly separated on mouse+touch.
      delay: const Duration(milliseconds: 250),
      hapticFeedbackOnStart: true,
      onDragUpdate: (details) => onDragUpdate(details.globalPosition),
      onDragEnd: (_) => onDragEnd(),
      onDraggableCanceled: (_, _) => onDragEnd(),
      onDragCompleted: onDragEnd,
      feedback: Transform.rotate(
        angle: 0.03,
        child: Material(
          color: Colors.transparent,
          child: Builder(
            builder: (context) {
              // Match the dragged card's width to the responsive column inner
              // width so the feedback is not clipped on a narrow screen.
              final screenWidth = MediaQuery.of(context).size.width;
              final feedbackWidth = screenWidth < 360
                  ? (screenWidth - 24).clamp(220.0, 300.0) - 24
                  : 276.0;
              return Container(
                width: feedbackWidth,
                padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: statusColor, width: 2),
              boxShadow: AppShadow.shLift,
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.drag_indicator_rounded, size: 18),
              ],
            ),
              );
            },
          ),
        ),
      ),
      // Leave a faded placeholder gap in the source column while dragging.
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            side: BorderSide(
              color: statusColor.withAlpha(120),
              style: BorderStyle.solid,
            ),
          ),
          child: const SizedBox(height: 64, width: double.infinity),
        ),
      ),
      child: Opacity(
        opacity: beingTransferred ? 0.4 : (isPending ? 0.62 : 1),
        child: AbsorbPointer(
          absorbing: isPending,
          child: GestureDetector(
            onTap: onTap,
            child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(
                  color: beingTransferred
                      ? AppColor.transferCyan
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: beingTransferred ? 1.4 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (linkedStudentId.isEmpty)
                          _LeadDragHandle(lead: lead, controller: transfer),
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Написать в чат',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: AppColor.gold,
                          ),
                          onPressed: () => _openChat(context, ref),
                        ),
                        PopupMenuButton<String>(
                          icon: isPending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.more_horiz_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  size: 18,
                                ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 150),
                          onSelected: (v) {
                            if (v == 'delete') {
                              onDelete(id);
                            } else if (v == 'comment') {
                              _addComment(context, ref);
                            } else if (v == 'task') {
                              _addTask(context, ref);
                            } else if (v == 'trial') {
                              _scheduleTrial(context, ref);
                            } else if (v == 'convert') {
                              _convertToStudent(context, ref);
                            } else {
                              onMove(id, v);
                            }
                          },
                          itemBuilder: (_) {
                            final currentMatch = allStatuses.where(
                              (s) => s.$1 == currentStatus,
                            );
                            final currentLabel = currentMatch.isEmpty
                                ? currentStatus
                                : currentMatch.first.$2;
                            return [
                              // Show the current status (disabled, checked) so a
                              // status move makes the present state explicit.
                              PopupMenuItem<String>(
                                enabled: false,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: AppColor.success,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text('Сейчас: $currentLabel'),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              ...allStatuses
                                  .where((s) => s.$1 != currentStatus)
                                  .map(
                                    (s) => PopupMenuItem(
                                      value: s.$1,
                                      child: Text('Перевести в: ${s.$2}'),
                                    ),
                                  ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'comment',
                                child: Text('Добавить комментарий'),
                              ),
                              const PopupMenuItem(
                                value: 'task',
                                child: Text('Создать задачу'),
                              ),
                              const PopupMenuItem(
                                value: 'trial',
                                child: Text('Назначить пробный'),
                              ),
                              if (linkedStudentId.isEmpty) ...[
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'convert',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.school_rounded,
                                        size: 18,
                                        color: AppColor.success,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Сделать учеником',
                                        style: TextStyle(
                                          color: AppColor.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Удалить',
                                  style: TextStyle(color: AppColor.danger),
                                ),
                              ),
                            ];
                          },
                        ),
                      ],
                    ),
                    if (phone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          phone,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (discipline.isNotEmpty)
                          _InfoBadge(
                            text: discipline,
                            color: AppColor.gold.withAlpha(51),
                            textColor: AppColor.gold,
                          ),
                        if (level.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _InfoBadge(
                              text: level,
                              color: AppTheme.warning.withAlpha(51),
                              textColor: AppTheme.warning,
                            ),
                          ),
                      ],
                    ),
                    if (branchName.isNotEmpty || assignedName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (branchName.isNotEmpty)
                              _IconBadge(
                                icon: Icons.location_on_outlined,
                                text: branchName,
                              ),
                            if (assignedName.isNotEmpty)
                              _IconBadge(
                                icon: Icons.person_pin_circle_outlined,
                                text: assignedName,
                              ),
                          ],
                        ),
                      ),
                    if (openTasks > 0 ||
                        comments > 0 ||
                        trials > 0 ||
                        linkedStudentId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (openTasks > 0)
                              _MetricBadge(
                                icon: Icons.task_alt_rounded,
                                text: '$openTasks',
                              ),
                            if (comments > 0)
                              _MetricBadge(
                                icon: Icons.chat_bubble_outline_rounded,
                                text: '$comments',
                              ),
                            if (trials > 0)
                              _MetricBadge(
                                icon: Icons.event_available_rounded,
                                text: '$trials',
                              ),
                            if (linkedStudentId.isNotEmpty)
                              const _MetricBadge(
                                icon: Icons.link_rounded,
                                text: 'ученик',
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (source.isNotEmpty)
                          Text(
                            source,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _addComment(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Комментарий к лиду'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Текст...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (content != null && content.trim().isNotEmpty) {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: 'lead',
            entityId: lead['id'],
            body: content.trim(),
          );
      onRefresh();
    }
  }

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Задача по лиду'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Что сделать?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (title != null && title.trim().isNotEmpty) {
      await ref
          .read(magicCrmServiceProvider)
          .createTask(
            entityType: 'lead',
            entityId: lead['id'],
            title: title.trim(),
          );
      onRefresh();
    }
  }

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    final leadId = lead['id']?.toString();
    if (leadId == null || leadId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .resolveLeadChatUser(leadId);
      final userId = result['userId']?.toString();
      if (userId == null || userId.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'У этого лида пока нет связанного пользователя для чата. '
              'Свяжите его по телефону в разделе «Пользователи».',
            ),
          ),
        );
        return;
      }
      // The leads board lives inside the messenger shell — setting the
      // navigation target makes the shell open/create the direct chat and
      // switch to the chat tab.
      ref
          .read(messengerNavigationProvider.notifier)
          .navigateTo(MessengerNavigationState(partnerId: userId));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось открыть чат: $e'),
          backgroundColor: AppColor.danger,
        ),
      );
    }
  }

  Future<void> _convertToStudent(BuildContext context, WidgetRef ref) async {
    if ((lead['linked_student_id']?.toString() ?? '').isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лид уже связан с учеником')),
      );
      return;
    }
    final student = await ConvertLeadDialog.show(context, lead: lead);
    if (student == null) return; // cancelled / failed in-dialog
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Лид конвертирован в ученика'),
          backgroundColor: AppColor.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    onRefresh();
  }

  Future<void> _scheduleTrial(BuildContext context, WidgetRef ref) async {
    final crm = ref.read(magicCrmServiceProvider);
    final [teachersRes, roomsRes] = await Future.wait([
      crm.listTeachers(limit: 100),
      crm.listRooms(limit: 100),
    ]);

    final teachers = List<Map<String, dynamic>>.from(teachersRes);
    final rooms = List<Map<String, dynamic>>.from(roomsRes);

    if (!context.mounted) return;
    if (teachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступных преподавателей')),
      );
      return;
    }

    String? selectedTeacher = teachers.isNotEmpty ? teachers.first['id'] : null;
    String? selectedRoom = rooms.isNotEmpty ? rooms.first['id'] : null;
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Пробное занятие'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedTeacher,
                decoration: const InputDecoration(labelText: 'Учитель'),
                items: teachers
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'].toString(),
                        child: Text('${t['first_name']} ${t['last_name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocalState(() => selectedTeacher = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRoom,
                decoration: const InputDecoration(labelText: 'Кабинет'),
                items: rooms
                    .map(
                      (r) => DropdownMenuItem(
                        value: r['id'].toString(),
                        child: Text(r['name']),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocalState(() => selectedRoom = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(
                  'Дата: ${DateFormat('dd.MM.yyyy').format(selectedDate)}',
                ),
                trailing: const Icon(Icons.calendar_today_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) {
                    setLocalState(() => selectedDate = picked);
                  }
                },
              ),
              ListTile(
                title: Text('Время: ${selectedTime.format(ctx)}'),
                trailing: const Icon(Icons.access_time_rounded),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: selectedTime,
                  );
                  if (picked != null) {
                    setLocalState(() => selectedTime = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Назначить'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selectedTeacher != null) {
      final scheduledAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );

      await crm.createLesson(
        leadId: lead['id'],
        teacherId: selectedTeacher,
        roomId: selectedRoom,
        scheduledAt: scheduledAt.toIso8601String(),
        isTrial: true,
        status: 'scheduled',
        notes: 'Пробное занятие по лиду: ${lead['name'] ?? ''}',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пробное занятие назначено')),
        );
      }
      onRefresh();
    }
  }
}

/// Visible drag affordance that starts the Лид → Ученик transfer flow.
///
/// A plain [Draggable] (immediate, movement-threshold) so a normal desktop
/// mouse drag works without a long press — and crucially its `feedback` ghost is
/// pointer-routed, so the card stays "in hand" even after the host switches the
/// segment to Ученики mid-drag. The hover/timer/branch/column logic all run in
/// [LeadTransferController] fed by `onDragUpdate`.
class _LeadDragHandle extends StatelessWidget {
  final Map<String, dynamic> lead;
  final LeadTransferController controller;

  const _LeadDragHandle({required this.lead, required this.controller});

  @override
  Widget build(BuildContext context) {
    final id = lead['id']?.toString() ?? '';
    return Draggable<String>(
      data: id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => controller.startFromLead(lead),
      onDragUpdate: (d) => controller.updatePointer(d.globalPosition),
      // No DragTarget is used, so both callbacks fire — endDrag is idempotent.
      onDragEnd: (_) => controller.endDrag(),
      onDraggableCanceled: (_, _) => controller.endDrag(),
      feedback: TransferGhostCard(controller: controller, lead: lead),
      childWhenDragging: const _HandleIcon(faded: true),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: 'Перетащите в «Ученики»',
          child: const _HandleIcon(),
        ),
      ),
    );
  }
}

class _HandleIcon extends StatelessWidget {
  final bool faded;
  const _HandleIcon({this.faded = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 32,
      child: Icon(
        Icons.drag_indicator_rounded,
        size: 18,
        color: AppColor.transferCyan.withValues(alpha: faded ? 0.3 : 0.9),
      ),
    );
  }
}

/// Toolbar trigger that opens the secondary-filter drawer, with a gold count
/// badge when one or more drawer filters are active.
class _FiltersButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onPressed;

  const _FiltersButton({required this.activeCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final hasActive = activeCount > 0;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: hasActive
          ? OutlinedButton.styleFrom(
              foregroundColor: AppColor.gold,
              side: const BorderSide(color: AppColor.goldLine),
            )
          : null,
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Фильтры'),
          if (hasActive) ...[
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColor.gold,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$activeCount',
                style: const TextStyle(
                  color: AppColor.onGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _InfoBadge({
    required this.text,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetricBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColor.gold.withAlpha(36),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColor.gold),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppColor.gold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadDialog extends StatefulWidget {
  const _LeadDialog();

  @override
  State<_LeadDialog> createState() => _LeadDialogState();
}

class _LeadDialogState extends State<_LeadDialog> {
  final _nameCtrl = TextEditingController();
  String _canonicalPhone = '';
  final _sourceCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('Новый лид'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 10),
          RuPhoneField(
            onCanonicalChanged: (c) => _canonicalPhone = c,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sourceCtrl,
            decoration: const InputDecoration(
              labelText: 'Источник (ВКонтакте, сайт...)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isNotEmpty) {
              Navigator.pop(context, {
                'name': _nameCtrl.text.trim(),
                'phone': _canonicalPhone,
                'source': _sourceCtrl.text.trim(),
              });
            }
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
