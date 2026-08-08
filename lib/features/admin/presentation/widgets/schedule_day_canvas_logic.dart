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

  double _yForTime(DateTime time) =>
      ((time.hour - kDayStartHour) + time.minute / 60.0) * kHourHeight;

  DateTime _timeForY(double y, {DateTime? date}) {
    final minutes = (kDayStartHour * 60 + (y / kHourHeight) * 60).round().clamp(
      kDayStartHour * 60,
      kDayEndHour * 60 - 60,
    );
    final target = date ?? widget.date;
    return DateTime(
      target.year,
      target.month,
      target.day,
      minutes ~/ 60,
      minutes % 60,
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
    final lanes = _layoutOverlappingEntries(entries);
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
    final top = _yForTime(entry.startLocal);
    final height = ((entry.durationMinutes / 60) * kHourHeight).clamp(
      22.0,
      _gridHeight,
    );
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
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpenLesson(entry.lesson),
          child: _LessonCard(entry: entry),
        ),
      ),
    );
  }
}
