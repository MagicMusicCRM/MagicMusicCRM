import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/no_open_tasks_highlight.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_desktop_scrollbar.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/client_board_toolbar.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/students_board_providers.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_widgets.dart';

part 'students_board_widgets.dart';

/// Ученики board widget — per-branch STATUS columns (draggable kanban).
///
/// Mirrors the Leads board ([LeadsWidget]): each status column is a
/// [DragTarget], each card a [LongPressDraggable], the board auto-scrolls when a
/// card is dragged near a horizontal edge, and a drop onto a different status
/// optimistically moves the card then PATCHes the student's status. Tapping a
/// card opens the unified «Карточка клиента» dialog ([showClientCard]).
class StudentsBoardWidget extends ConsumerStatefulWidget {
  const StudentsBoardWidget({super.key});

  @override
  ConsumerState<StudentsBoardWidget> createState() =>
      _StudentsBoardWidgetState();
}

class _StudentsBoardWidgetState extends ConsumerState<StudentsBoardWidget> {
  final _boardScrollController = ScrollController();
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId;
  // Live client-side search across the loaded student cards (B6: parity with the
  // Лиды board search). Lowercased; empty == no filter.
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _filtersOpen = false;
  bool _branchesLoaded = false;
  String? _branchLoadError;

  // ── Optimistic move state (mirrors leads_widget) ──────────────────────────
  /// studentId → status currently shown while a move is in flight / settled.
  final Map<String, String> _optimisticStatuses = {};

  /// studentIds with an update in flight (card shows a spinner, drag disabled).
  final Set<String> _pendingStudentIds = {};

  // ── Realtime invalidation (crm.changed) ───────────────────────────────────
  Timer? _realtimeDebounce;

  // ── Auto-scroll while dragging near the board edges (mirrors leads_widget) ──
  Timer? _autoScrollTimer;
  int _autoScrollDir = 0;
  double _autoScrollSpeed = 0;
  Offset? _dragStartPosition;
  bool _dragMovedEnough = false;
  static const double _autoScrollMinSpeed = 8.0;
  static const double _autoScrollMaxSpeed = 24.0;
  static const double _dragStartThreshold = 12.0;
  static const double _autoScrollEdge = 110.0;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _autoScrollTimer?.cancel();
    _boardScrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final branches = await crm.listBranches(limit: 100);
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(branches);
        if (_branches.isNotEmpty && _selectedBranchId == null) {
          _selectedBranchId = _branches.first['id']?.toString();
        }
        _branchesLoaded = true;
        _branchLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _branchLoadError = 'Не удалось загрузить филиалы';
        _branchesLoaded = true;
      });
    }
  }

  void _refreshBoard() {
    if (_selectedBranchId != null) {
      ref.invalidate(studentFunnelProvider(_selectedBranchId!));
      ref.invalidate(studentBoardProvider(_selectedBranchId!));
    }
  }

  // ── Auto-scroll handlers (mirrors leads_widget) ───────────────────────────

  /// While a card is dragged near the left/right edge of the board, scroll the
  /// horizontal view so off-screen columns can be reached without dropping. The
  /// speed eases from a small min rate at the activation threshold up to a max
  /// at the very edge; suppressed when the platform requests reduced motion.
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
          _dragStartThreshold) {
        return;
      }
      _dragMovedEnough = true;
    }

    final width = MediaQuery.of(context).size.width;
    double penetration = 0;
    if (globalPosition.dx < _autoScrollEdge) {
      _autoScrollDir = -1;
      penetration = ((_autoScrollEdge - globalPosition.dx) / _autoScrollEdge)
          .clamp(0.0, 1.0);
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

  // ── Status move (optimistic) ──────────────────────────────────────────────

  Future<void> _moveStatus(
    Map<String, dynamic> student,
    String newStatus,
  ) async {
    final id = student['id']?.toString() ?? '';
    if (id.isEmpty || _pendingStudentIds.contains(id)) return;

    final current =
        _optimisticStatuses[id] ?? student['status']?.toString() ?? '';
    if (current == newStatus) return; // already there → no-op

    final previous = _optimisticStatuses[id];
    setState(() {
      _optimisticStatuses[id] = newStatus;
      _pendingStudentIds.add(id);
    });

    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateStudent(id, status: newStatus);
      _refreshBoard();
      if (_selectedBranchId != null) {
        await ref.read(studentBoardProvider(_selectedBranchId!).future);
      }
      if (!mounted) return;
      setState(() {
        _optimisticStatuses.remove(id);
        _pendingStudentIds.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (previous == null) {
          _optimisticStatuses.remove(id);
        } else {
          _optimisticStatuses[id] = previous;
        }
        _pendingStudentIds.remove(id);
      });
      _showError('Не удалось изменить статус ученика: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  Future<void> _openStudent(Map<String, dynamic> student) async {
    final studentId = student['id']?.toString() ?? '';
    if (studentId.isEmpty) return;
    final changed = await showClientCard(
      context,
      entityType: 'student',
      entityId: studentId,
      seed: student,
    );
    if (changed == true) _refreshBoard();
  }

  Future<void> _createStudent() async {
    final branchId = _selectedBranchId == kNoBranchBoardId
        ? null
        : _selectedBranchId;
    final student = await showStudentCreateSurface(
      context,
      initialBranchId: branchId,
    );
    if (!mounted || student == null) return;
    _refreshBoard();
    await _openStudent(student);
  }

  /// Re-bucket the board's columns honoring any in-flight optimistic moves so
  /// the dragged card appears in its target column immediately.
  List<_StatusColumnData> _applyOptimistic(List<Map<String, dynamic>> columns) {
    // Index every column by its status key (null = «Прочие», non-droppable).
    final result = [
      for (final column in columns)
        _StatusColumnData(
          status: column['status'] as String?,
          name: column['name']?.toString() ?? 'Без названия',
          style: column['style']?.toString() ?? 'gray',
          allowedTransitions:
              (column['allowedTransitions'] as List? ?? const [])
                  .map((value) => value.toString())
                  .toSet(),
          students: column['students'] is List
              ? (column['students'] as List)
                    .whereType<Map<String, dynamic>>()
                    .toList()
              : <Map<String, dynamic>>[],
        ),
    ];

    if (_optimisticStatuses.isEmpty) return result;

    final byStatus = <String, _StatusColumnData>{
      for (final c in result)
        if (c.status != null) c.status!: c,
    };

    for (final entry in _optimisticStatuses.entries) {
      final id = entry.key;
      final target = byStatus[entry.value];
      if (target == null) continue;
      // Find the card in its current column.
      Map<String, dynamic>? card;
      _StatusColumnData? source;
      for (final c in result) {
        final idx = c.students.indexWhere((s) => s['id']?.toString() == id);
        if (idx != -1) {
          card = c.students[idx];
          source = c;
          break;
        }
      }
      if (card == null || source == null || identical(source, target)) {
        continue;
      }
      source.students.remove(card);
      target.students.add(card);
    }
    return result;
  }

  Widget _buildToolbar() {
    final seen = <String>{};
    final items =
        _branches
            .where((b) => seen.add(b['id']?.toString() ?? ''))
            .map(
              (b) => DropdownMenuItem<String>(
                value: b['id']?.toString() ?? '',
                child: Text(
                  b['name']?.toString() ?? b['id']?.toString() ?? '',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList()
          // «Без филиала» board — students with no branch assigned.
          ..add(
            const DropdownMenuItem<String>(
              value: kNoBranchBoardId,
              child: Text('Без филиала'),
            ),
          );

    final branchField = DropdownButtonFormField<String>(
      menuMaxHeight: 256,
      key: ValueKey('branch:$_selectedBranchId'),
      initialValue: _selectedBranchId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Филиал', isDense: true),
      items: items,
      onChanged: (value) {
        if (value != null && value.isNotEmpty) {
          setState(() => _selectedBranchId = value);
        }
      },
    );
    final filterPanel =
        _filtersOpen &&
            _branchesLoaded &&
            _branchLoadError == null &&
            _branches.isNotEmpty
        ? Container(
            key: const ValueKey('students-filters-panel'),
            width: 360,
            margin: const EdgeInsets.only(top: AppSpace.sm),
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: branchField,
          )
        : null;
    return ClientBoardToolbar(
      title: 'Ученики',
      searchKey: const ValueKey('students-search'),
      searchController: _searchCtrl,
      searchHint: 'Имя или телефон',
      activeFilterCount: _selectedBranchId == null ? 0 : 1,
      onSearchChanged: (value) =>
          setState(() => _query = value.trim().toLowerCase()),
      onSearchSubmitted: (value) =>
          setState(() => _query = value.trim().toLowerCase()),
      onClearSearch: () {
        _searchCtrl.clear();
        setState(() => _query = '');
      },
      onFiltersPressed: () => setState(() => _filtersOpen = !_filtersOpen),
      inlineFilters: filterPanel,
    );
  }

  bool _matchesQuery(Map<String, dynamic> s) {
    if (_query.isEmpty) return true;
    final hay = [
      s['name'],
      s['first_name'],
      s['last_name'],
      s['phone'],
    ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
    return hay.contains(_query);
  }

  @override
  Widget build(BuildContext context) {
    final canWrite =
        ref
            .watch(capabilitySnapshotProvider)
            .asData
            ?.value
            .allows('crm.client.write') ==
        true;
    // Realtime: refresh the board when another staff member changes a student.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || event.entity != 'student' || !mounted) return;
      if (event.isFallbackPoll) return;
      // Don't refetch while an optimistic move is in flight — a mid-flight
      // reload would clobber the in-place patch (the move refetches on completion).
      if (_pendingStudentIds.isNotEmpty) return;
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _pendingStudentIds.isNotEmpty) return;
        _refreshBoard();
      });
    });
    final transfer = ref.watch(leadTransferControllerProvider);
    // Persist the branch chosen during a transfer into the local selection so it
    // stays the active filter once the flow finishes (storyboard screen 7).
    ref.listen<String?>(
      leadTransferControllerProvider.select((c) => c.selectedBranchId),
      (prev, next) {
        if (next != null && next != _selectedBranchId && mounted) {
          setState(() => _selectedBranchId = next);
        }
      },
    );

    // During a transfer the host's branch strip drives the selection — render
    // the chosen branch's board directly (no local selector chrome) so the card
    // can be dropped into a status column.
    if (transfer.isActive) {
      final branchId = transfer.selectedBranchId ?? _selectedBranchId;
      if (branchId != null) {
        return Column(
          children: [Expanded(child: _buildBoardArea(branchId, transfer))],
        );
      }
    }

    // Loading state — branches not yet fetched.
    if (!_branchesLoaded && _branchLoadError == null) {
      return Column(
        children: [
          _buildToolbar(),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    // Error state — failed to load branches.
    if (_branchLoadError != null) {
      return Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppTheme.danger,
                      size: 42,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _branchLoadError!,
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
                      onPressed: () {
                        setState(() {
                          _branchesLoaded = false;
                          _branchLoadError = null;
                        });
                        _loadBranches();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Loaded-empty state — no branches configured.
    if (_branches.isEmpty) {
      return Column(
        children: [
          _buildToolbar(),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_off_rounded,
                    size: 42,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Нет филиалов',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Добавьте хотя бы один филиал в настройках.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_selectedBranchId == null) {
      return Column(
        children: [
          _buildToolbar(),
          const Expanded(child: KanbanSkeleton()),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canWrite
          ? FloatingActionButton(
              key: const ValueKey('students-create'),
              onPressed: _createStudent,
              tooltip: 'Новый ученик',
              child: const Icon(Icons.person_add_rounded),
            )
          : null,
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(child: _buildBoardArea(_selectedBranchId!, transfer)),
        ],
      ),
    );
  }

  /// The kanban area for [branchId]. Shared by the normal path and the active
  /// transfer path. When [transfer] is active, each droppable status column is
  /// wrapped in a [TransferDropZone] so the dragged lead can be released into it.
  Widget _buildBoardArea(String branchId, LeadTransferController transfer) {
    final boardAsync = ref.watch(studentBoardProvider(branchId));
    return boardAsync.when(
      loading: () => const KanbanSkeleton(),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppTheme.danger,
                size: 42,
              ),
              const SizedBox(height: 10),
              Text(
                'Не удалось загрузить учеников',
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
      ),
      data: (columns) {
        final data = _applyOptimistic(columns);
        final filtered = _query.isEmpty
            ? data
            : data
                  .map(
                    (c) => _StatusColumnData(
                      status: c.status,
                      name: c.name,
                      style: c.style,
                      allowedTransitions: c.allowedTransitions,
                      students: c.students.where(_matchesQuery).toList(),
                    ),
                  )
                  .toList();
        final transitions = <String, Set<String>>{
          for (final item in filtered)
            if (item.status != null) item.status!: item.allowedTransitions,
        };
        return MagicDesktopScrollbar(
          axis: Axis.horizontal,
          controller: _boardScrollController,
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: filtered.map((column) {
                final col = _StatusColumn(
                  column: column,
                  transitions: transitions,
                  pendingStudentIds: _pendingStudentIds,
                  onTap: _openStudent,
                  onMove: _moveStatus,
                  onDragUpdate: _handleDragUpdate,
                  onDragEnd: _stopAutoScroll,
                );
                if (transfer.isActive && column.status != null) {
                  return TransferDropZone(
                    zoneId: 'column:${column.status}',
                    kind: TransferZoneKind.column,
                    value: column.status,
                    label: column.name,
                    controller: transfer,
                    // Keep the column wrapped at all times (transparent → cyan)
                    // so toggling the hover highlight never rebuilds its subtree.
                    builder: (ctx, hovering, _) => DashedRoundedBorder(
                      color: hovering
                          ? AppColor.transferCyan
                          : Colors.transparent,
                      child: col,
                    ),
                  );
                }
                return col;
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
