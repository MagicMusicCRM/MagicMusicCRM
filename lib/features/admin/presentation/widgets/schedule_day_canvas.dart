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
const String kUnassignedColumnId = '__unassigned__';

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
  final bool highlighted;
  final bool clientContext;
  final bool searchContext;
  final bool relatedClient;

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
    required this.highlighted,
    this.clientContext = false,
    this.searchContext = false,
    this.relatedClient = false,
  });
}

class _EntryLane {
  const _EntryLane(this.index, this.count);

  final int index;
  final int count;
}

Map<ScheduleEntry, _EntryLane> _layoutOverlappingEntries(
  List<ScheduleEntry> entries,
) {
  final sorted = [...entries]
    ..sort((left, right) {
      final byStart = left.startLocal.compareTo(right.startLocal);
      return byStart != 0
          ? byStart
          : right.durationMinutes.compareTo(left.durationMinutes);
    });
  final result = <ScheduleEntry, _EntryLane>{};
  final cluster = <(ScheduleEntry, int)>[];
  final laneEnds = <DateTime>[];
  DateTime? clusterEnd;

  void flush() {
    final count = laneEnds.length;
    for (final item in cluster) {
      result[item.$1] = _EntryLane(item.$2, count);
    }
    cluster.clear();
    laneEnds.clear();
    clusterEnd = null;
  }

  for (final entry in sorted) {
    if (clusterEnd != null && !entry.startLocal.isBefore(clusterEnd!)) flush();
    var lane = laneEnds.indexWhere((end) => !entry.startLocal.isBefore(end));
    final end = entry.startLocal.add(Duration(minutes: entry.durationMinutes));
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(end);
    } else {
      laneEnds[lane] = end;
    }
    cluster.add((entry, lane));
    if (clusterEnd == null || end.isAfter(clusterEnd!)) clusterEnd = end;
  }
  if (cluster.isNotEmpty) flush();
  return result;
}

/// The day-view canvas: a read-first 2-axis time grid. Empty-slot taps create a
/// lesson; existing cards open the explicit edit/transfer actions. Direct
/// drag/drop mutations are intentionally absent.
class ScheduleDayCanvas extends StatefulWidget {
  final DateTime date; // branch-local selected day (date only)
  final List<ScheduleColumn> columns;
  final List<ScheduleEntry> entries;
  final bool allowCreate;

  /// Tap an empty hour → one-hour create.
  final void Function(String columnId, DateTime startLocal, int durationMinutes)
  onCreateSlot;

  final void Function(Map<String, dynamic> lesson) onOpenLesson;
  final double initialVerticalOffset;
  final ValueChanged<double>? onVerticalOffsetChanged;

  const ScheduleDayCanvas({
    super.key,
    required this.date,
    required this.columns,
    required this.entries,
    this.allowCreate = true,
    required this.onCreateSlot,
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
    _bodyV.dispose();
    _bodyH.dispose();
    _headerH.dispose();
    _gutterV.dispose();
    super.dispose();
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
                    child: MagicDesktopScrollbar(
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
                                      width: contentWidth,
                                      height: _gridHeight,
                                      child: Stack(
                                        children: [
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
                                                color: cs.onSurfaceVariant
                                                    .withAlpha(16),
                                              ),
                                            ),
                                          for (int i = 0; i < cols.length; i++)
                                            Positioned(
                                              left: i * colWidth,
                                              top: 0,
                                              width: colWidth,
                                              height: _gridHeight,
                                              child: _buildColumn(
                                                cols[i],
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
