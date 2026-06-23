import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/students_board_providers.dart';

/// Ученики board widget — per-branch STATUS columns (draggable kanban).
///
/// Mirrors the Leads board ([LeadsWidget]): each status column is a
/// [DragTarget], each card a [LongPressDraggable], the board auto-scrolls when a
/// card is dragged near a horizontal edge, and a drop onto a different status
/// optimistically moves the card then PATCHes the student's status. Tapping a
/// card opens the full student screen (`/student/:id`).
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
  bool _branchesLoaded = false;
  String? _branchLoadError;

  // ── Optimistic move state (mirrors leads_widget) ──────────────────────────
  /// studentId → status currently shown while a move is in flight / settled.
  final Map<String, String> _optimisticStatuses = {};

  /// studentIds with an update in flight (card shows a spinner, drag disabled).
  final Set<String> _pendingStudentIds = {};

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
    _autoScrollTimer?.cancel();
    _boardScrollController.dispose();
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

  // ── Status move (optimistic) ──────────────────────────────────────────────

  Future<void> _moveStatus(Map<String, dynamic> student, String newStatus) async {
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

  void _openStudent(String studentId) {
    if (studentId.isEmpty) return;
    context.push('/student/$studentId');
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

  Widget _buildBranchSelector() {
    final seen = <String>{};
    final items = _branches
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
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.school_rounded, size: 20, color: AppTheme.primaryGold),
          const SizedBox(width: 10),
          const Text(
            'Ученики',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          if (!_branchesLoaded && _branchLoadError == null)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_branchLoadError != null)
            // error inline placeholder — full error block is in build()
            const SizedBox.shrink()
          else if (_branches.isNotEmpty)
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                key: ValueKey('branch:$_selectedBranchId'),
                initialValue: _selectedBranchId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Филиал',
                  isDense: true,
                ),
                items: items,
                onChanged: (value) {
                  if (value != null && value.isNotEmpty) {
                    setState(() => _selectedBranchId = value);
                  }
                },
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshBoard,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Loading state — branches not yet fetched.
    if (!_branchesLoaded && _branchLoadError == null) {
      return Column(
        children: [
          _buildBranchSelector(),
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    // Error state — failed to load branches.
    if (_branchLoadError != null) {
      return Column(
        children: [
          _buildBranchSelector(),
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
          _buildBranchSelector(),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_off_rounded, size: 42, color: Colors.grey),
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
        children: [_buildBranchSelector(), const Expanded(child: KanbanSkeleton())],
      );
    }

    final boardAsync = ref.watch(studentBoardProvider(_selectedBranchId!));

    return Column(
      children: [
        _buildBranchSelector(),
        Expanded(
          child: boardAsync.when(
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
              final total = data.fold<int>(
                0,
                (sum, c) => sum + c.students.length,
              );
              if (total == 0) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 42,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Нет учеников',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Scrollbar(
                controller: _boardScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _boardScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: data.map((column) {
                      return _StatusColumn(
                        column: column,
                        pendingStudentIds: _pendingStudentIds,
                        onTap: _openStudent,
                        onMove: _moveStatus,
                        onDragUpdate: _handleDragUpdate,
                        onDragEnd: _stopAutoScroll,
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Column data ────────────────────────────────────────────────────────────

class _StatusColumnData {
  final String? status; // null → «Прочие», non-droppable
  final String name;
  final List<Map<String, dynamic>> students;

  _StatusColumnData({
    required this.status,
    required this.name,
    required this.students,
  });
}

// ── Column ───────────────────────────────────────────────────────────────────

class _StatusColumn extends StatelessWidget {
  final _StatusColumnData column;
  final Set<String> pendingStudentIds;
  final ValueChanged<String> onTap;
  final Future<void> Function(Map<String, dynamic>, String) onMove;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _StatusColumn({
    required this.column,
    required this.pendingStudentIds,
    required this.onTap,
    required this.onMove,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  bool get _droppable => column.status != null;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (_) => _droppable,
      onAcceptWithDetails: (details) {
        onDragEnd();
        if (column.status != null) {
          onMove(details.data, column.status!);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final hovering = _droppable && candidateData.isNotEmpty;
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
                ? AppTheme.primaryGold.withAlpha(30)
                : Theme.of(context).colorScheme.surface.withAlpha(127),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: hovering
                  ? AppTheme.primaryGold
                  : Theme.of(context).colorScheme.outlineVariant,
              width: hovering ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.school_rounded,
                      size: 14,
                      color: AppTheme.primaryGold,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        column.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${column.students.length}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Drop hint ─────────────────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: hovering
                    ? Container(
                        height: 40,
                        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.primaryGold),
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          color: AppTheme.primaryGold.withAlpha(25),
                        ),
                        child: const Center(
                          child: Text(
                            'Отпустите, чтобы перенести',
                            style: TextStyle(
                              color: AppTheme.primaryGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              // ── Cards ─────────────────────────────────────────────────────
              Expanded(
                child: column.students.isEmpty
                    ? _buildEmptyColumn(context)
                    : ListView.builder(
                        key: PageStorageKey(
                          'students_col_${column.status ?? 'other'}',
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: column.students.length,
                        itemBuilder: (context, index) {
                          final student = column.students[index];
                          final id = student['id']?.toString() ?? '';
                          return _StudentCard(
                            student: student,
                            isPending: pendingStudentIds.contains(id),
                            onTap: () => onTap(id),
                            onDragUpdate: onDragUpdate,
                            onDragEnd: onDragEnd,
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

  Widget _buildEmptyColumn(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              Icons.inbox_outlined,
              size: 28,
              color: cs.onSurfaceVariant.withAlpha(140),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Нет учеников',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_droppable) ...[
              const SizedBox(height: 2),
              Text(
                'Перетащите карточку сюда',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant.withAlpha(160),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Card ─────────────────────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final bool isPending;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _StudentCard({
    required this.student,
    required this.isPending,
    required this.onTap,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = student['first_name']?.toString() ?? '';
    final lastName = student['last_name']?.toString() ?? '';
    final displayName = '$firstName $lastName'.trim();
    final name = displayName.isEmpty ? 'Без имени' : displayName;
    final phone = student['phone']?.toString() ?? '';

    return LongPressDraggable<Map<String, dynamic>>(
      data: student,
      maxSimultaneousDrags: isPending ? 0 : null,
      // Platform-standard long-press (~500ms) cleanly separates a click
      // (tap → open the student) from a deliberate drag.
      delay: const Duration(milliseconds: 500),
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
                  border: Border.all(color: AppTheme.primaryGold, width: 2),
                  boxShadow: AppShadow.shLift,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.school_rounded,
                      size: 14,
                      color: AppTheme.primaryGold,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
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
      // Faded placeholder gap in the source column while dragging.
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            side: BorderSide(
              color: AppTheme.primaryGold.withAlpha(120),
            ),
          ),
          child: const SizedBox(height: 64, width: double.infinity),
        ),
      ),
      child: Opacity(
        opacity: isPending ? 0.62 : 1,
        child: AbsorbPointer(
          absorbing: isPending,
          child: GestureDetector(
            onTap: onTap,
            child: _CardBody(student: student, isPending: isPending),
          ),
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  final Map<String, dynamic> student;
  final bool isPending;

  const _CardBody({required this.student, required this.isPending});

  @override
  Widget build(BuildContext context) {
    final firstName = student['first_name']?.toString() ?? '';
    final lastName = student['last_name']?.toString() ?? '';
    final displayName = '$firstName $lastName'.trim();
    final name = displayName.isEmpty ? 'Без имени' : displayName;
    final phone = student['phone']?.toString() ?? '';
    final branchName = student['branch_name']?.toString() ?? '';
    final customData = student['custom_data'];
    final discipline = customData is Map
        ? customData['discipline']?.toString() ?? ''
        : '';
    final openTasks = _intValue(student['open_tasks_count']);
    final lessonsCount = _intValue(student['lessons_count']);
    final groupsCount = _intValue(student['groups_count']);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Name + pending spinner ────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isPending)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            // ── Phone ─────────────────────────────────────────────────────
            if (phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  phone,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // ── Discipline badge ──────────────────────────────────────────
            if (discipline.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withAlpha(51),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  discipline,
                  style: const TextStyle(
                    color: AppTheme.primaryGold,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            // ── Branch badge ──────────────────────────────────────────────
            if (branchName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _IconBadge(
                  icon: Icons.location_on_outlined,
                  text: branchName,
                ),
              ),
            // ── Metric badges (tasks / lessons / groups) ──────────────────
            if (openTasks > 0 || lessonsCount > 0 || groupsCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (openTasks > 0)
                      _MetricBadge(
                        icon: Icons.task_alt_rounded,
                        text: '$openTasks',
                      ),
                    if (lessonsCount > 0)
                      _MetricBadge(
                        icon: Icons.event_rounded,
                        text: '$lessonsCount',
                      ),
                    if (groupsCount > 0)
                      _MetricBadge(
                        icon: Icons.group_rounded,
                        text: '$groupsCount',
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

// ── Shared badge widgets ──────────────────────────────────────────────────────

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
        color: AppTheme.primaryGold.withAlpha(36),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.primaryGold),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.primaryGold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
