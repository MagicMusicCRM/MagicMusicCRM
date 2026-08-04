import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_desktop_scrollbar.dart';
part 'schedule_day_canvas_logic.dart';
part 'schedule_day_canvas_widgets.dart';

// ── Day-canvas geometry (08:00 → 00:00) ──────────────────────────────────────
const int kDayStartHour = 8;
const int kDayEndHour = 24; // exclusive bottom edge = 00:00
const double kHourHeight = 64;
const double kTimeColWidth = 64;
const double kMinRoomColWidth = 150; // floor before horizontal scroll engages
const double kHeaderHeight = 58;
const double kEdgeZone = 56; // autoscroll trigger band
const String kUnassignedColumnId = '__unassigned__';

/// How far a pointer must travel before an empty-area drag counts as a
/// booking-select. Below this it is jitter around a click, and a create dialog
/// popping up for it reads as the app firing on its own.
const double kSelectSlop = 12;

/// A card must be at least this tall to carry resize handles. A 45-minute
/// lesson is 48 px, a 30-minute one 32 px — the old 52 px floor silently denied
/// both, which is why resize «worked on some lessons, not on others».
const double kMinResizeHeight = 26;

/// One day-grid column (a room, or the synthetic «Без аудитории» bucket).
class ScheduleColumn {
  final String id;
  final String name;
  final Color color;
  final DateTime? date;
  final bool isUnassigned;
  final bool hasConflict;

  const ScheduleColumn({
    required this.id,
    required this.name,
    required this.color,
    this.date,
    this.isUnassigned = false,
    this.hasConflict = false,
  });
}

/// One positioned lesson block on the day grid. [startLocal] is branch-local
/// wall-clock; the parent converts back to UTC on commit.
class ScheduleEntry {
  final Map<String, dynamic> lesson;
  final String id;
  final String columnId; // room id, or [kUnassignedColumnId]
  final DateTime startLocal;
  final int durationMinutes;
  final String title;
  final String subtitle;
  final bool isTrial;
  final List<String> conflicts;
  final bool movable;
  final bool highlighted;

  const ScheduleEntry({
    required this.lesson,
    required this.id,
    required this.columnId,
    required this.startLocal,
    required this.durationMinutes,
    required this.title,
    required this.subtitle,
    required this.isTrial,
    required this.conflicts,
    required this.movable,
    required this.highlighted,
  });
}

/// The day-view canvas: a 2-axis scrollable time grid with a sticky time gutter
/// (left) and sticky room headers (top), block-drag move, hover/focus resize
/// handles and drag-edge autoscroll. It owns NO data — every mutation is routed
/// up through a callback so the parent keeps the single source of truth and the
/// existing service-call paths (`updateLesson`/`createLesson`) are reused
/// verbatim (KVA-195 is a wire-up, not a contract change).
class ScheduleDayCanvas extends StatefulWidget {
  final DateTime date; // branch-local selected day (date only)
  final List<ScheduleColumn> columns;
  final List<ScheduleEntry> entries;

  /// Tap an empty hour → 1h create; vertical drag-select → multi-hour create.
  final void Function(String columnId, DateTime startLocal, int durationMinutes)
  onCreateSlot;

  /// Existing lesson moved: vertical → time, horizontal → room.
  final void Function(
    Map<String, dynamic> lesson,
    DateTime newStartLocal,
    String newColumnId,
  )
  onMove;

  /// Top/bottom edge resize committed on release.
  final void Function(
    Map<String, dynamic> lesson,
    DateTime newStartLocal,
    int newDurationMinutes,
  )
  onResize;

  final void Function(Map<String, dynamic> lesson) onOpenLesson;
  final double initialVerticalOffset;
  final ValueChanged<double>? onVerticalOffsetChanged;

  const ScheduleDayCanvas({
    super.key,
    required this.date,
    required this.columns,
    required this.entries,
    required this.onCreateSlot,
    required this.onMove,
    required this.onResize,
    required this.onOpenLesson,
    this.initialVerticalOffset = 0,
    this.onVerticalOffsetChanged,
  });

  @override
  State<ScheduleDayCanvas> createState() => _ScheduleDayCanvasState();
}

class _ScheduleDayCanvasState extends State<ScheduleDayCanvas> {
  // Body owns the real scroll; header/gutter are slaved to it (Never physics).
  final ScrollController _bodyV = ScrollController();
  final ScrollController _bodyH = ScrollController();
  final ScrollController _headerH = ScrollController();
  final ScrollController _gutterV = ScrollController();
  final GlobalKey _bodyKey = GlobalKey(); // scrolled grid content
  final GlobalKey _viewportKey = GlobalKey(); // body viewport (for edge math)

  // Vertical drag-select (new booking) — vertical only, single column.
  String? _selColumnId;
  DateTime? _selColumnDate;
  int? _selStartColIndex;
  double? _selStartY;
  double? _selEndY;
  int? _selForbidColIndex; // a different column the finger wandered into
  // Armed only once the pointer has travelled [kSelectSlop]. Until then the
  // gesture is still a click as far as the user is concerned: no teal block,
  // and releasing creates nothing.
  bool _selArmed = false;

  // Hover (desktop) reveals the resize handles on a lesson.
  String? _hoverId;

  // Touch selection: on a phone there is no hover, so a single tap SELECTS a
  // card (that is what reveals its resize handles) and a double tap opens it.
  // Desktop keeps click = open, since hover already exposes the handles.
  String? _selectedId;

  // Column width resolved each build from the real viewport (LayoutBuilder), so
  // columns fill the width when few and scroll horizontally when many. Gesture
  // handlers read it without a build context.
  double _colW = kMinRoomColWidth;

  // Live resize preview.
  String? _resizingId;
  bool _resizeTop = false;
  double _resizeDelta = 0; // px

  // Drag + autoscroll.
  bool _dragging = false;
  Offset? _pointerGlobal;
  Timer? _autoScroll;

  double get _gridHeight => (kDayEndHour - kDayStartHour) * kHourHeight;

  @override
  void initState() {
    super.initState();
    _bodyV.addListener(_handleVerticalScroll);
    _bodyH.addListener(_syncHeader);
    if (widget.initialVerticalOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_bodyV.hasClients) return;
        _bodyV.jumpTo(
          widget.initialVerticalOffset.clamp(
            0.0,
            _bodyV.position.maxScrollExtent,
          ),
        );
      });
    }
  }

  void _handleVerticalScroll() {
    _syncGutter();
    widget.onVerticalOffsetChanged?.call(_bodyV.offset);
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _bodyV.dispose();
    _bodyH.dispose();
    _headerH.dispose();
    _gutterV.dispose();
    super.dispose();
  }

  void _emitState(void Function() fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cols = widget.columns;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the available width when there are few rooms; fall back to a
        // minimum width (→ horizontal scroll) only when many rooms can't fit.
        final avail = (constraints.maxWidth - kTimeColWidth).clamp(
          0.0,
          double.infinity,
        );
        final fit = cols.isEmpty ? kMinRoomColWidth : avail / cols.length;
        final colWidth = fit >= kMinRoomColWidth ? fit : kMinRoomColWidth;
        _colW = colWidth;
        final contentWidth = cols.length * colWidth;
        return Column(
          children: [
            // ── Sticky header: corner + horizontally-slaved room headers ──────────
            SizedBox(
              height: kHeaderHeight,
              child: Row(
                children: [
                  _GutterCell(
                    width: kTimeColWidth,
                    child: Text(
                      'Время',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _headerH,
                      physics: const NeverScrollableScrollPhysics(),
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentWidth,
                        child: Row(
                          children: [
                            for (final c in cols)
                              _RoomHeader(column: c, width: colWidth),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: cs.onSurfaceVariant.withAlpha(28)),
            // ── Body: sticky gutter + 2-axis scrollable grid ──────────────────────
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time gutter — vertically slaved to the body.
                  SizedBox(
                    width: kTimeColWidth,
                    child: SingleChildScrollView(
                      controller: _gutterV,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        height: _gridHeight,
                        child: Stack(
                          children: [
                            for (
                              int i = 0;
                              i <= kDayEndHour - kDayStartHour;
                              i++
                            )
                              Positioned(
                                top: i * kHourHeight - 7,
                                right: 8,
                                child: Text(
                                  '${(kDayStartHour + i) % 24 == 0 ? '00' : (kDayStartHour + i).toString().padLeft(2, '0')}:00',
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant.withAlpha(160),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Grid body.
                  Expanded(
                    child: Listener(
                      key: _viewportKey,
                      onPointerMove: _onPointerMove,
                      child: Stack(
                        children: [
                          MagicDesktopScrollbar(
                            axis: Axis.vertical,
                            controller: _bodyV,
                            builder: (context, verticalController) =>
                                SingleChildScrollView(
                                  controller: verticalController,
                                  child: MagicDesktopScrollbar(
                                    axis: Axis.horizontal,
                                    controller: _bodyH,
                                    builder: (context, horizontalController) =>
                                        SingleChildScrollView(
                                          controller: horizontalController,
                                          scrollDirection: Axis.horizontal,
                                          child: SizedBox(
                                            key: _bodyKey,
                                            width: contentWidth,
                                            height: _gridHeight,
                                            child: Stack(
                                              children: [
                                                // Full-width hour lines.
                                                for (
                                                  int i = 0;
                                                  i <=
                                                      kDayEndHour -
                                                          kDayStartHour;
                                                  i++
                                                )
                                                  Positioned(
                                                    top: i * kHourHeight,
                                                    left: 0,
                                                    width: contentWidth,
                                                    child: Container(
                                                      height: 1,
                                                      color: cs.onSurfaceVariant
                                                          .withAlpha(16),
                                                    ),
                                                  ),
                                                // Columns.
                                                for (
                                                  int i = 0;
                                                  i < cols.length;
                                                  i++
                                                )
                                                  Positioned(
                                                    left: i * colWidth,
                                                    top: 0,
                                                    width: colWidth,
                                                    height: _gridHeight,
                                                    child: _buildColumn(
                                                      cols[i],
                                                      i,
                                                      colWidth,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                          ),
                          // Edge autoscroll affordances (visible only while dragging).
                          if (_dragging) ..._edgeZones(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
