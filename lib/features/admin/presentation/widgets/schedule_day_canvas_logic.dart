part of 'schedule_day_canvas.dart';

extension _ScheduleDayCanvasLogic on _ScheduleDayCanvasState {
  void _syncGutter() {
    if (_gutterV.hasClients && _gutterV.offset != _bodyV.offset) {
      _gutterV.jumpTo(
        _bodyV.offset.clamp(0.0, _gutterV.position.maxScrollExtent),
      );
    }
  }

  void _syncHeader() {
    if (_headerH.hasClients && _headerH.offset != _bodyH.offset) {
      _headerH.jumpTo(
        _bodyH.offset.clamp(0.0, _headerH.position.maxScrollExtent),
      );
    }
  }

  // ── Time ↔ pixels ──────────────────────────────────────────────────────────
  double _yForTime(DateTime t) =>
      ((t.hour - kDayStartHour) + t.minute / 60.0) * kHourHeight;

  DateTime _timeForY(double y, {int snap = 15, DateTime? date}) {
    final rawMin = kDayStartHour * 60 + (y / kHourHeight) * 60.0;
    var minutes = (rawMin / snap).round() * snap;
    minutes = minutes.clamp(kDayStartHour * 60, kDayEndHour * 60 - snap);
    final targetDate = date ?? widget.date;
    return DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
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
      final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
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
    _emitState(() => _dragging = true);
  }

  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _pointerGlobal = null;
    if (mounted && _dragging) _emitState(() => _dragging = false);
  }

  // ── Empty-cell tap / vertical select ────────────────────────────────────────
  void _onColumnTap(ScheduleColumn col, double localY) {
    if (!widget.allowCreate) return;
    // A card is selected → the first tap on empty space dismisses it rather
    // than booking an hour. Deselecting must never cost a create dialog.
    if (_selectedId != null) {
      _emitState(() => _selectedId = null);
      return;
    }
    final start = _timeForY(localY, snap: 60, date: col.date);
    widget.onCreateSlot(col.id, start, 60);
  }

  void _onSelectStart(ScheduleColumn col, int colIndex, double localY) {
    if (!widget.allowCreate) return;
    // Anchor only. Nothing is shown and _dragging stays false until the pointer
    // actually travels [kSelectSlop] — see _onSelectUpdate.
    _selColumnId = col.id;
    _selColumnDate = col.date;
    _selStartColIndex = colIndex;
    _selStartY = localY;
    _selEndY = localY;
    _selForbidColIndex = null;
    _selArmed = false;
  }

  void _onSelectUpdate(double localY, double localX) {
    if (_selColumnId == null || _selStartColIndex == null) return;
    if (!_selArmed) {
      if ((localY - _selStartY!).abs() < kSelectSlop) {
        // Still inside the slop: keep tracking silently.
        _selEndY = localY;
        return;
      }
      // Now it is a deliberate drag: show the block and arm edge autoscroll
      // (the raw-pointer Listener feeds _pointerGlobal while _dragging).
      _selArmed = true;
      _dragging = true;
    }
    // Vertical only: the selection block never leaves its start column. If the
    // finger wanders horizontally we flag the column it entered as «forbidden»
    // (flow-02) but never extend the range there.
    final wanderCols = (localX / _colW).floor();
    final target = _selStartColIndex! + wanderCols;
    _emitState(() {
      _selEndY = localY;
      _selForbidColIndex = (target != _selStartColIndex) ? target : null;
    });
  }

  /// Drop the select without booking anything.
  void _onSelectCancel() {
    if (_selColumnId == null) return;
    _emitState(() {
      _selColumnId = null;
      _selColumnDate = null;
      _selStartColIndex = null;
      _selStartY = null;
      _selEndY = null;
      _selForbidColIndex = null;
      _selArmed = false;
    });
    _endDrag();
  }

  void _onSelectEnd() {
    final colId = _selColumnId;
    final columnDate = _selColumnDate;
    final armed = _selArmed;
    final a = _selStartY;
    final b = _selEndY;
    _emitState(() {
      _selColumnId = null;
      _selColumnDate = null;
      _selStartColIndex = null;
      _selStartY = null;
      _selEndY = null;
      _selForbidColIndex = null;
      _selArmed = false;
    });
    _endDrag(); // stop autoscroll + hide edge bands
    // Never armed → this was a click that wobbled, not a booking. The tap
    // handler owns that case; creating here too would double-fire.
    if (!armed || colId == null || a == null || b == null) return;
    final start = _timeForY(a < b ? a : b, snap: 15, date: columnDate);
    final end = _timeForY(a < b ? b : a, snap: 15, date: columnDate);
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
    final start = _timeForY(localY, snap: 5, date: col.date);
    widget.onMove(lesson, start, col.id);
  }

  // ── Resize ──────────────────────────────────────────────────────────────────
  void _onResizeEnd(ScheduleEntry e) {
    final deltaMin = ((_resizeDelta / kHourHeight) * 60 / 5).round() * 5;
    final id = _resizingId;
    final top = _resizeTop;
    _emitState(() {
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
        e.startLocal.year,
        e.startLocal.month,
        e.startLocal.day,
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
      band(top: 0, left: 0, right: 0, height: kEdgeZone, label: '▲ автоскролл'),
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
    final entries = widget.entries.where((e) => e.columnId == col.id).toList();
    final lanes = _layoutOverlappingEntries(entries);
    final selecting =
        _selArmed &&
        _selColumnId == col.id &&
        _selStartY != null &&
        _selEndY != null;
    final showForbidden = _selForbidColIndex == colIndex;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: cs.onSurfaceVariant.withAlpha(14)),
        ),
      ),
      // DragTarget wraps the WHOLE column (ancestor of the lesson cards) so a
      // drop over an existing card still reaches it. Previously it was a sibling
      // painted *under* the cards, whose opaque tap layers stopped the hit-test
      // and swallowed every drop on a populated day — that's why drag-and-drop
      // "stopped working".
      child: DragTarget<Map<String, dynamic>>(
        // «Без аудитории» only accepts lessons that are ALREADY roomless
        // (re-timing within it). Clearing a room isn't expressible via the
        // PATCH contract, so a roomed lesson can't be dropped here (it would
        // silently keep its room). Real room columns accept anything.
        onWillAcceptWithDetails: (d) {
          if (!col.isUnassigned) return true;
          final rid = d.data['room_id']?.toString();
          return rid == null || rid.isEmpty;
        },
        onAcceptWithDetails: (d) => _onDropOnColumn(col, d.data, d.offset),
        builder: (context, candidate, rejected) {
          return Stack(
            children: [
              // Empty-area gesture layer (bottom): tap = 1h create,
              // press-and-hold then drag = multi-hour select.
              //
              // The hold is what makes the select deliberate. Desktop used to
              // select on a bare pan, which meant any drag across empty grid
              // drew a booking — including the ones a touchpad produces when
              // the user is only trying to scroll the day. A gesture that must
              // first sit still for ~500 ms cannot be triggered by scrolling at
              // all: a trackpad pan-zoom carries no button-press to hold, and a
              // stray flick moves too soon. Deliberate range-picking survives
              // unchanged, one beat slower.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: widget.allowCreate
                      ? (d) => _onColumnTap(col, d.localPosition.dy)
                      : null,
                  onLongPressStart: widget.allowCreate
                      ? (d) => _onSelectStart(col, colIndex, d.localPosition.dy)
                      : null,
                  onLongPressMoveUpdate: widget.allowCreate
                      ? (d) => _onSelectUpdate(
                          d.localPosition.dy,
                          d.localPosition.dx,
                        )
                      : null,
                  onLongPressEnd: widget.allowCreate
                      ? (_) => _onSelectEnd()
                      : null,
                  // A cancelled gesture must drop the anchor too, or the teal
                  // block is left painted over a day nobody is dragging on.
                  onLongPressCancel: widget.allowCreate
                      ? _onSelectCancel
                      : null,
                  child: const SizedBox.expand(),
                ),
              ),
              // Vertical selection block (dashed teal — flow-02/03). New booking.
              if (selecting) _selectionBlock(),
              // Forbidden horizontal hint (dashed red — flow-02).
              if (showForbidden) _forbiddenBlock(),
              // Lesson cards (on top — own their tap/drag/resize).
              for (final e in entries) _entryBlock(e, colWidth, lane: lanes[e]),
            ],
          );
        },
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

  Widget _entryBlock(ScheduleEntry e, double colWidth, {_EntryLane? lane}) {
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
    final desktop =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    final selected = _selectedId == e.id;
    const gap = 3.0;
    final laneCount = lane?.count ?? 1;
    final cardWidth = (colWidth - 6 - (laneCount - 1) * gap) / laneCount;
    final cardLeft = 3 + (lane?.index ?? 0) * (cardWidth + gap);

    // Desktop: click opens — hover already reveals the handles, so there is
    // nothing to select and no reason to make the user click twice.
    // Touch: single tap SELECTS (revealing the handles), double tap opens. A
    // finger has no hover, so without a selection step the only way to expose a
    // resize handle would be to touch the card — i.e. every open would risk a
    // resize and every resize would risk an open.
    final tappable = desktop
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onOpenLesson(e.lesson),
            child: _LessonCard(entry: e),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _emitState(() => _selectedId = selected ? null : e.id),
            onDoubleTap: () => widget.onOpenLesson(e.lesson),
            child: _LessonCard(entry: e, selected: selected),
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
        feedback: _dragFeedback(e, cardWidth, height),
        childWhenDragging: _LessonCard(entry: e, ghost: true),
        child: tappable,
      );
    } else if (e.movable) {
      movable = LongPressDraggable<Map<String, dynamic>>(
        data: e.lesson,
        onDragStarted: _startDrag,
        onDragEnd: (_) => _endDrag(),
        onDraggableCanceled: (_, _) => _endDrag(),
        feedback: _dragFeedback(e, cardWidth, height),
        childWhenDragging: _LessonCard(entry: e, ghost: true),
        child: tappable,
      );
    } else {
      movable = tappable;
    }

    // Resize strips show on hover (desktop) or while selected (touch), and STAY
    // through an active resize so the gesture is never cancelled when the
    // (shrinking) card slips out from under the cursor. They sit at the very
    // top/bottom as separate opaque strips, so they never steal the body's
    // tap/drag.
    final showHandles =
        e.movable &&
        height >= kMinResizeHeight &&
        (_resizingId == e.id || (desktop ? _hoverId == e.id : selected));

    // A finger needs a bigger target than a cursor, but the strips must still
    // leave the middle of the card tappable — hence a share of the height
    // rather than a fixed band that would swallow a short lesson whole.
    final stripH = (height / 3).clamp(8.0, desktop ? 16.0 : 22.0);

    return Positioned(
      left: cardLeft,
      width: cardWidth,
      top: top,
      height: height,
      child: MouseRegion(
        onEnter: (_) {
          if (_hoverId != e.id) _emitState(() => _hoverId = e.id);
        },
        onExit: (_) {
          // Keep handles while resizing even though the pointer left the card.
          if (_resizingId == e.id) return;
          if (_hoverId == e.id) _emitState(() => _hoverId = null);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: movable),
            if (showHandles) _resizeStrip(e, top: true, height: stripH),
            if (showHandles) _resizeStrip(e, top: false, height: stripH),
          ],
        ),
      ),
    );
  }

  Widget _dragFeedback(ScheduleEntry e, double width, double height) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: width,
        height: height,
        child: _LessonCard(entry: e, inHand: true),
      ),
    );
  }

  Widget _resizeStrip(
    ScheduleEntry e, {
    required bool top,
    required double height,
  }) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      height: height,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _emitState(() {
            _resizingId = e.id;
            _resizeTop = top;
            _resizeDelta = 0;
          }),
          onVerticalDragUpdate: (d) =>
              _emitState(() => _resizeDelta += d.delta.dy),
          onVerticalDragEnd: (_) => _onResizeEnd(e),
          onVerticalDragCancel: () {
            if (_resizingId == e.id) {
              _emitState(() {
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
