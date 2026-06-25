import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

// ── Day-canvas geometry (08:00 → 00:00) ──────────────────────────────────────
const int kDayStartHour = 8;
const int kDayEndHour = 24; // exclusive bottom edge = 00:00
const double kHourHeight = 64;
const double kTimeColWidth = 64;
const double kMinRoomColWidth = 150; // floor before horizontal scroll engages
const double kHeaderHeight = 58;
const double kEdgeZone = 56; // autoscroll trigger band
const String kUnassignedColumnId = '__unassigned__';

/// One day-grid column (a room, or the synthetic «Без аудитории» bucket).
class ScheduleColumn {
  final String id;
  final String name;
  final Color color;
  final bool isUnassigned;
  final bool hasConflict;

  const ScheduleColumn({
    required this.id,
    required this.name,
    required this.color,
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

  const ScheduleDayCanvas({
    super.key,
    required this.date,
    required this.columns,
    required this.entries,
    required this.onCreateSlot,
    required this.onMove,
    required this.onResize,
    required this.onOpenLesson,
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
  int? _selStartColIndex;
  double? _selStartY;
  double? _selEndY;
  int? _selForbidColIndex; // a different column the finger wandered into

  // Hover (desktop) reveals the resize handles on a lesson.
  String? _hoverId;

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
    _bodyV.addListener(_syncGutter);
    _bodyH.addListener(_syncHeader);
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

  void _syncGutter() {
    if (_gutterV.hasClients && _gutterV.offset != _bodyV.offset) {
      _gutterV.jumpTo(_bodyV.offset.clamp(0.0, _gutterV.position.maxScrollExtent));
    }
  }

  void _syncHeader() {
    if (_headerH.hasClients && _headerH.offset != _bodyH.offset) {
      _headerH.jumpTo(_bodyH.offset.clamp(0.0, _headerH.position.maxScrollExtent));
    }
  }

  // ── Time ↔ pixels ──────────────────────────────────────────────────────────
  double _yForTime(DateTime t) =>
      ((t.hour - kDayStartHour) + t.minute / 60.0) * kHourHeight;

  DateTime _timeForY(double y, {int snap = 15}) {
    final rawMin = kDayStartHour * 60 + (y / kHourHeight) * 60.0;
    var minutes = (rawMin / snap).round() * snap;
    minutes = minutes.clamp(kDayStartHour * 60, kDayEndHour * 60 - snap);
    return DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      minutes ~/ 60,
      minutes % 60,
    );
  }

  // ── Autoscroll while dragging near an edge ──────────────────────────────────
  void _onPointerMove(PointerMoveEvent e) {
    if (!_dragging) return;
    _pointerGlobal = e.position;
    _ensureAutoScrollTicking();
  }

  void _ensureAutoScrollTicking() {
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_dragging || _pointerGlobal == null) return;
      final box =
          _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final local = box.globalToLocal(_pointerGlobal!);
      final size = box.size;
      const step = 14.0;

      if (local.dy < kEdgeZone) {
        _scrollBy(_bodyV, -step);
      } else if (local.dy > size.height - kEdgeZone) {
        _scrollBy(_bodyV, step);
      }
      // A vertical drag-select stays in its start column, so it only autoscrolls
      // vertically; only an existing-lesson MOVE pans horizontally too.
      if (_selColumnId == null) {
        if (local.dx < kEdgeZone) {
          _scrollBy(_bodyH, -step);
        } else if (local.dx > size.width - kEdgeZone) {
          _scrollBy(_bodyH, step);
        }
      }
    });
  }

  void _scrollBy(ScrollController c, double delta) {
    if (!c.hasClients) return;
    final next = (c.offset + delta).clamp(0.0, c.position.maxScrollExtent);
    if (next != c.offset) c.jumpTo(next);
  }

  void _startDrag() {
    setState(() => _dragging = true);
  }

  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _pointerGlobal = null;
    if (mounted && _dragging) setState(() => _dragging = false);
  }

  // ── Empty-cell tap / vertical select ────────────────────────────────────────
  void _onColumnTap(ScheduleColumn col, double localY) {
    final start = _timeForY(localY, snap: 60);
    widget.onCreateSlot(col.id, start, 60);
  }

  void _onSelectStart(ScheduleColumn col, int colIndex, double localY) {
    setState(() {
      _selColumnId = col.id;
      _selStartColIndex = colIndex;
      _selStartY = localY;
      _selEndY = localY;
      _selForbidColIndex = null;
      // Arm edge autoscroll for the select too (the raw-pointer Listener feeds
      // _pointerGlobal + ticks while _dragging is true) — vertical-only above.
      _dragging = true;
    });
  }

  void _onSelectUpdate(double localY, double localX) {
    if (_selColumnId == null || _selStartColIndex == null) return;
    // Vertical only: the selection block never leaves its start column. If the
    // finger wanders horizontally we flag the column it entered as «forbidden»
    // (flow-02) but never extend the range there.
    final wanderCols = (localX / _colW).floor();
    final target = _selStartColIndex! + wanderCols;
    setState(() {
      _selEndY = localY;
      _selForbidColIndex =
          (target != _selStartColIndex) ? target : null;
    });
  }

  void _onSelectEnd() {
    final colId = _selColumnId;
    final a = _selStartY;
    final b = _selEndY;
    setState(() {
      _selColumnId = null;
      _selStartColIndex = null;
      _selStartY = null;
      _selEndY = null;
      _selForbidColIndex = null;
    });
    _endDrag(); // stop autoscroll + hide edge bands
    if (colId == null || a == null || b == null) return;
    final start = _timeForY(a < b ? a : b, snap: 15);
    final end = _timeForY(a < b ? b : a, snap: 15);
    var duration = end.difference(start).inMinutes;
    if (duration < 30) duration = 60; // a near-tap behaves like one slot
    widget.onCreateSlot(colId, start, duration);
  }

  // ── Drop (move) ─────────────────────────────────────────────────────────────
  void _onDropOnColumn(
    ScheduleColumn col,
    Map<String, dynamic> lesson,
    Offset globalOffset,
  ) {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localY = box.globalToLocal(globalOffset).dy;
    final start = _timeForY(localY, snap: 5);
    widget.onMove(lesson, start, col.id);
  }

  // ── Resize ──────────────────────────────────────────────────────────────────
  void _onResizeEnd(ScheduleEntry e) {
    final deltaMin = ((_resizeDelta / kHourHeight) * 60 / 5).round() * 5;
    final id = _resizingId;
    final top = _resizeTop;
    setState(() {
      _resizingId = null;
      _resizeDelta = 0;
    });
    if (id == null || deltaMin == 0) return;
    if (top) {
      // Top edge moves the START while the END stays fixed. Derive the duration
      // from the (clamped) start against the original end, so clamping start to
      // 08:00 shrinks the duration instead of dragging the end later.
      final originalEnd = e.startLocal.add(
        Duration(minutes: e.durationMinutes),
      );
      final dayStart = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
        kDayStartHour,
      );
      var newStart = e.startLocal.add(Duration(minutes: deltaMin));
      // Don't let the start cross the fixed end (keep ≥30 min), nor 08:00.
      final latestStart = originalEnd.subtract(const Duration(minutes: 30));
      if (newStart.isAfter(latestStart)) newStart = latestStart;
      if (newStart.isBefore(dayStart)) newStart = dayStart;
      final newDur = originalEnd.difference(newStart).inMinutes;
      widget.onResize(e.lesson, newStart, newDur);
    } else {
      // Bottom edge moves the END → duration only.
      var newDur = e.durationMinutes + deltaMin;
      if (newDur < 30) newDur = 30;
      final maxDur =
          (kDayEndHour * 60) - (e.startLocal.hour * 60 + e.startLocal.minute);
      if (newDur > maxDur) newDur = maxDur;
      widget.onResize(e.lesson, e.startLocal, newDur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cols = widget.columns;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the available width when there are few rooms; fall back to a
        // minimum width (→ horizontal scroll) only when many rooms can't fit.
        final avail =
            (constraints.maxWidth - kTimeColWidth).clamp(0.0, double.infinity);
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
                        for (int i = 0; i <= kDayEndHour - kDayStartHour; i++)
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
                      SingleChildScrollView(
                        controller: _bodyV,
                        child: SingleChildScrollView(
                          controller: _bodyH,
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
                                  i <= kDayEndHour - kDayStartHour;
                                  i++
                                )
                                  Positioned(
                                    top: i * kHourHeight,
                                    left: 0,
                                    width: contentWidth,
                                    child: Container(
                                      height: 1,
                                      color: cs.onSurfaceVariant.withAlpha(16),
                                    ),
                                  ),
                                // Columns.
                                for (int i = 0; i < cols.length; i++)
                                  Positioned(
                                    left: i * colWidth,
                                    top: 0,
                                    width: colWidth,
                                    height: _gridHeight,
                                    child: _buildColumn(cols[i], i, colWidth),
                                  ),
                              ],
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

  List<Widget> _edgeZones() {
    Widget band({
      Alignment begin = Alignment.topCenter,
      Alignment end = Alignment.bottomCenter,
      required String label,
      double? top,
      double? bottom,
      double? left,
      double? right,
      double? height,
      double? width,
    }) {
      return Positioned(
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        height: height,
        width: width,
        child: IgnorePointer(
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: begin,
                end: end,
                colors: [
                  AppColor.transferCyan.withAlpha(60),
                  AppColor.transferCyan.withAlpha(0),
                ],
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColor.transferCyan,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return [
      band(
        top: 0,
        left: 0,
        right: 0,
        height: kEdgeZone,
        label: '▲ автоскролл',
      ),
      band(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        bottom: 0,
        left: 0,
        right: 0,
        height: kEdgeZone,
        label: '▼ автоскролл',
      ),
    ];
  }

  Widget _buildColumn(ScheduleColumn col, int colIndex, double colWidth) {
    final cs = Theme.of(context).colorScheme;
    final entries =
        widget.entries.where((e) => e.columnId == col.id).toList();
    final selecting = _selColumnId == col.id &&
        _selStartY != null &&
        _selEndY != null;
    final showForbidden = _selForbidColIndex == colIndex;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: cs.onSurfaceVariant.withAlpha(14)),
        ),
      ),
      child: Stack(
        children: [
          // Empty-area gesture layer (tap = 1h create, desktop drag / touch
          // long-press-drag = multi-hour select).
          Positioned.fill(
            child: DragTarget<Map<String, dynamic>>(
              // «Без аудитории» only accepts lessons that are ALREADY roomless
              // (re-timing within it). Clearing a room isn't expressible via the
              // PATCH contract, so a roomed lesson can't be dropped here (it
              // would silently keep its room). Real room columns accept anything.
              onWillAcceptWithDetails: (d) {
                if (!col.isUnassigned) return true;
                final rid = d.data['room_id']?.toString();
                return rid == null || rid.isEmpty;
              },
              onAcceptWithDetails: (d) =>
                  _onDropOnColumn(col, d.data, d.offset),
              builder: (context, candidate, rejected) {
                final platform = Theme.of(context).platform;
                final desktop = platform == TargetPlatform.windows ||
                    platform == TargetPlatform.linux ||
                    platform == TargetPlatform.macOS;
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (d) => _onColumnTap(col, d.localPosition.dy),
                  onPanStart: desktop
                      ? (d) => _onSelectStart(
                            col,
                            colIndex,
                            d.localPosition.dy,
                          )
                      : null,
                  onPanUpdate: desktop
                      ? (d) => _onSelectUpdate(
                            d.localPosition.dy,
                            d.localPosition.dx,
                          )
                      : null,
                  onPanEnd: desktop ? (_) => _onSelectEnd() : null,
                  onLongPressStart: (d) =>
                      _onSelectStart(col, colIndex, d.localPosition.dy),
                  onLongPressMoveUpdate: (d) => _onSelectUpdate(
                    d.localPosition.dy,
                    d.localPosition.dx,
                  ),
                  onLongPressEnd: (_) => _onSelectEnd(),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
          // Vertical selection block (dashed teal — flow-02/03). New booking.
          if (selecting) _selectionBlock(),
          // Forbidden horizontal hint (dashed red — flow-02).
          if (showForbidden) _forbiddenBlock(),
          // Lesson cards (on top — own their tap/drag/resize).
          for (final e in entries) _entryBlock(e, colWidth),
        ],
      ),
    );
  }

  Widget _selectionBlock() {
    final top = _selStartY! < _selEndY! ? _selStartY! : _selEndY!;
    final height = (_selStartY! - _selEndY!).abs().clamp(12.0, _gridHeight);
    final start = _timeForY(top, snap: 15);
    final mins = ((height / kHourHeight) * 60 / 15).round() * 15;
    final dur = mins < 30 ? 60 : mins;
    final end = start.add(Duration(minutes: dur));
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Positioned(
      left: 3,
      right: 3,
      top: top,
      height: height,
      child: _DashedBox(
        color: AppColor.transferCyan,
        fill: AppColor.transferCyan.withAlpha(28),
        child: Center(
          child: Text(
            '${hm(start)}–${hm(end)}\n${dur % 60 == 0 ? '${dur ~/ 60} ч' : '$dur мин'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColor.transferCyan,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _forbiddenBlock() {
    return Positioned(
      left: 3,
      right: 3,
      top: _selStartY! < _selEndY! ? _selStartY! : _selEndY!,
      height: (_selStartY! - _selEndY!).abs().clamp(12.0, _gridHeight),
      child: const IgnorePointer(
        child: _DashedBox(
          color: AppColor.danger,
          fill: Color(0x1FEF4444),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Text(
                'Горизонтально\nнельзя',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColor.danger,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entryBlock(ScheduleEntry e, double colWidth) {
    var top = _yForTime(e.startLocal);
    var height = (e.durationMinutes / 60.0) * kHourHeight;

    // Live resize preview.
    if (_resizingId == e.id) {
      if (_resizeTop) {
        top += _resizeDelta;
        height -= _resizeDelta;
      } else {
        height += _resizeDelta;
      }
    }
    height = height.clamp(22.0, _gridHeight);

    final platform = Theme.of(context).platform;
    final desktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onOpenLesson(e.lesson),
      child: _LessonCard(entry: e),
    );

    // Move: an immediate drag on desktop (mouse) so it doesn't need a long hold;
    // a long-press on touch so it doesn't fight finger-scroll. A plain click
    // (no movement) still falls through to onTap → open the lesson.
    Widget movable;
    if (e.movable && desktop) {
      movable = Draggable<Map<String, dynamic>>(
        data: e.lesson,
        onDragStarted: _startDrag,
        onDragEnd: (_) => _endDrag(),
        onDraggableCanceled: (_, _) => _endDrag(),
        feedback: _dragFeedback(e, colWidth, height),
        childWhenDragging: _LessonCard(entry: e, ghost: true),
        child: tappable,
      );
    } else if (e.movable) {
      movable = LongPressDraggable<Map<String, dynamic>>(
        data: e.lesson,
        onDragStarted: _startDrag,
        onDragEnd: (_) => _endDrag(),
        onDraggableCanceled: (_, _) => _endDrag(),
        feedback: _dragFeedback(e, colWidth, height),
        childWhenDragging: _LessonCard(entry: e, ghost: true),
        child: tappable,
      );
    } else {
      movable = tappable;
    }

    // Resize strips show on hover (desktop) and STAY through an active resize so
    // the gesture is never cancelled when the (shrinking) card slips out from
    // under the cursor. They sit at the very top/bottom as separate opaque
    // strips, so they never steal the body's tap/drag.
    final showHandles = e.movable &&
        desktop &&
        height >= 52 &&
        (_hoverId == e.id || _resizingId == e.id);

    return Positioned(
      left: 3,
      right: 3,
      top: top,
      height: height,
      child: MouseRegion(
        onEnter: (_) {
          if (_hoverId != e.id) setState(() => _hoverId = e.id);
        },
        onExit: (_) {
          // Keep handles while resizing even though the pointer left the card.
          if (_resizingId == e.id) return;
          if (_hoverId == e.id) setState(() => _hoverId = null);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: movable),
            if (showHandles) _resizeStrip(e, top: true),
            if (showHandles) _resizeStrip(e, top: false),
          ],
        ),
      ),
    );
  }

  Widget _dragFeedback(ScheduleEntry e, double colWidth, double height) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: colWidth - 6,
        height: height,
        child: _LessonCard(entry: e, inHand: true),
      ),
    );
  }

  Widget _resizeStrip(ScheduleEntry e, {required bool top}) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      height: 16,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => setState(() {
            _resizingId = e.id;
            _resizeTop = top;
            _resizeDelta = 0;
          }),
          onVerticalDragUpdate: (d) =>
              setState(() => _resizeDelta += d.delta.dy),
          onVerticalDragEnd: (_) => _onResizeEnd(e),
          onVerticalDragCancel: () {
            if (_resizingId == e.id) {
              setState(() {
                _resizingId = null;
                _resizeDelta = 0;
              });
            }
          },
          child: Center(
            child: Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: AppColor.gold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────────────────────
class _GutterCell extends StatelessWidget {
  final double width;
  final Widget child;
  const _GutterCell({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Center(child: child),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  final ScheduleColumn column;
  final double width;
  const _RoomHeader({required this.column, required this.width});

  @override
  Widget build(BuildContext context) {
    final danger = column.hasConflict;
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: column.color.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: danger ? AppColor.danger : column.color.withAlpha(60),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (danger)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: AppColor.danger,
              ),
            ),
          Flexible(
            child: Text(
              column.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: column.isUnassigned
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : column.color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final ScheduleEntry entry;
  final bool inHand;
  final bool ghost;
  const _LessonCard({required this.entry, this.inHand = false, this.ghost = false});

  Color get _accent {
    if (entry.conflicts.isNotEmpty) return AppColor.danger;
    if (entry.isTrial) return AppColor.success;
    return AppColor.actionBlue;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = entry.highlighted ? AppColor.gold : _accent;
    final start = entry.startLocal;
    final end = start.add(Duration(minutes: entry.durationMinutes));
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final timeStr = inHand
        ? 'в руках → ${hm(start)}'
        : '${hm(start)}–${hm(end)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        // `ghost` is the SOURCE left behind during a move — it stays clearly
        // HIGHLIGHTED in place (gold wash + ring), never dimmed-out (rule 7).
        color: ghost
            ? AppColor.goldSoft
            : inHand
            ? cs.surface
            : accent.withAlpha(34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ghost ? AppColor.gold : accent,
          width: ghost || entry.highlighted || inHand ? 2 : 1,
        ),
        boxShadow: inHand ? AppShadow.shLift : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (entry.conflicts.isNotEmpty)
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColor.danger,
                  size: 12,
                ),
            ],
          ),
          if (entry.durationMinutes >= 45 && entry.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                entry.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ),
          const Spacer(),
          Text(
            timeStr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple dashed-border box (Flutter has no built-in dashed border) used for
/// the new-booking selection and the forbidden-horizontal hint.
class _DashedBox extends StatelessWidget {
  final Color color;
  final Color fill;
  final Widget child;
  const _DashedBox({required this.color, required this.fill, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedPainter(color),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  final Color color;
  _DashedPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final path = Path()..addRRect(rrect);
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) => old.color != color;
}
