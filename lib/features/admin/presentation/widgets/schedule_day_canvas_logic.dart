part of 'schedule_day_canvas.dart';

extension _ScheduleDayCanvasLogic on _ScheduleDayCanvasState {
  Future<void> _finishMove(ScheduleEntry entry, double colWidth) async {
    final from = _dragStart;
    final to = _dragEnd;
    _dragStart = _dragEnd = null;
    _updateCanvas(() => _dragEntry = null);
    final callback = widget.onProposeMove;
    if (from == null || to == null || callback == null || _movePending) return;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null ||
        !(Offset.zero & viewport.size).contains(viewport.globalToLocal(to))) {
      return;
    }
    final point = box.globalToLocal(to);
    if (!(Offset.zero & box.size).contains(point)) return;
    final index = (point.dx / colWidth).floor();
    if (index < 0 || index >= widget.columns.length) return;
    final column = widget.columns[index];
    if (column.isUnassigned || column.date != null) return;
    final start = scheduleDayMoveStart(
      entry.startLocal,
      verticalDelta: to.dy - from.dy,
      hourHeight: _hourHeight,
    );
    // Day drag must not silently become an inter-date transfer.
    if (start.year != entry.startLocal.year ||
        start.month != entry.startLocal.month ||
        start.day != entry.startLocal.day) {
      return;
    }
    if (column.id == entry.columnId && start == entry.startLocal) return;
    _updateCanvas(() => _movePending = true);
    try {
      await callback(entry, column.id, start);
    } finally {
      if (mounted) _updateCanvas(() => _movePending = false);
    }
  }

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

  double _yForTime(ScheduleEntry entry) =>
      _ScheduleDayCanvasState._edgeInset +
      (entry.startMinute / 60 - _startHour) * _hourHeight;

  DateTime _timeForY(double y, {DateTime? date}) {
    final minutes =
        (_startHour * 60 +
        ((y - _ScheduleDayCanvasState._edgeInset) / _hourHeight) * 60);
    final snapped = ((minutes / 15).floor() * 15).clamp(
      _startHour * 60,
      _endHour * 60 - 60,
    );
    final target = date ?? widget.date;
    return DateTime(
      target.year,
      target.month,
      target.day,
      snapped ~/ 60,
      snapped % 60,
    );
  }

  void _onColumnTap(ScheduleColumn column, double localY) {
    if (!widget.allowCreate) return;
    widget.onCreateSlot(column.id, _timeForY(localY, date: column.date), 60);
  }

  Widget _buildColumn(ScheduleColumn column, double colWidth) {
    final scheme = Theme.of(context).colorScheme;
    final entries = widget.entries
        .where((entry) => entry.columnId == column.id)
        .toList();
    final lanes = _layoutOverlappingEntries(
      entries,
      minimumMinutes:
          18 * MediaQuery.textScalerOf(context).scale(1) / _hourHeight * 60,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: scheme.onSurfaceVariant.withAlpha(14)),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: widget.allowCreate
                  ? (details) => _onColumnTap(column, details.localPosition.dy)
                  : null,
              child: const SizedBox.expand(),
            ),
          ),
          for (final entry in entries)
            _entryBlock(entry, colWidth, lane: lanes[entry]),
        ],
      ),
    );
  }

  Widget _entryBlock(ScheduleEntry entry, double colWidth, {_EntryLane? lane}) {
    final top = _yForTime(entry);
    final height = ((entry.durationMinutes / 60) * _hourHeight)
        .clamp(18 * MediaQuery.textScalerOf(context).scale(1), _gridHeight)
        .clamp(0.0, _gridHeight - top);
    const gap = 3.0;
    final laneCount = lane?.count ?? 1;
    final width = (colWidth - 6 - (laneCount - 1) * gap) / laneCount;
    final left = 3 + (lane?.index ?? 0) * (width + gap);
    return Positioned(
      left: left,
      width: width,
      top: top,
      height: height,
      child: Semantics(
        button: true,
        label: 'Открыть занятие ${entry.title}',
        child: GestureDetector(
          supportedDevices: const {PointerDeviceKind.mouse},
          dragStartBehavior: DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          onPanStart: widget.onProposeMove == null || _movePending
              ? null
              : (details) => _updateCanvas(() {
                  _dragEntry = entry;
                  _dragStart = _dragEnd = details.globalPosition;
                }),
          onPanUpdate: widget.onProposeMove == null || _movePending
              ? null
              : (details) =>
                    _updateCanvas(() => _dragEnd = details.globalPosition),
          onPanCancel: () => _updateCanvas(() {
            _dragEntry = null;
            _dragStart = _dragEnd = null;
          }),
          onPanEnd: widget.onProposeMove == null || _movePending
              ? null
              : (_) => _finishMove(entry, colWidth),
          child: GestureDetector(
            onTap: () => widget.onOpenLesson(entry.lesson),
            child: _LessonCard(entry: entry),
          ),
        ),
      ),
    );
  }

  Widget _movePreview(double colWidth) {
    final entry = _dragEntry!;
    final box = _gridKey.currentContext!.findRenderObject() as RenderBox;
    final point = box.globalToLocal(_dragEnd!);
    final column = (point.dx / colWidth).floor().clamp(
      0,
      widget.columns.length - 1,
    );
    final start = scheduleDayMoveStart(
      entry.startLocal,
      verticalDelta: _dragEnd!.dy - _dragStart!.dy,
      hourHeight: _hourHeight,
    );
    final top =
        _ScheduleDayCanvasState._edgeInset +
        (start.hour + start.minute / 60 - _startHour) * _hourHeight;
    return Positioned(
      left: column * colWidth + 3,
      top: top,
      width: colWidth - 6,
      height: (entry.durationMinutes / 60 * _hourHeight).clamp(
        18.0,
        _gridHeight,
      ),
      child: IgnorePointer(
        child: Container(
          key: const ValueKey('schedule-move-preview'),
          decoration: BoxDecoration(
            color: AppColor.selectionBg.withValues(alpha: 0.88),
            border: Border.all(color: AppColor.selectionBorder, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            '${start.hour.toString().padLeft(2, '0')}:'
            '${start.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 11, color: AppColor.text),
          ),
        ),
      ),
    );
  }
}

/// Horizontal movement tolerates pointer jitter and preserves manual minutes.
/// A vertical movement selects an exact hour, never a quarter-hour.
DateTime scheduleDayMoveStart(
  DateTime source, {
  required double verticalDelta,
  required double hourHeight,
}) {
  if (verticalDelta.abs() < hourHeight / 2) return source;
  final hour = (source.hour + source.minute / 60 + verticalDelta / hourHeight)
      .round();
  return DateTime(source.year, source.month, source.day, hour);
}
