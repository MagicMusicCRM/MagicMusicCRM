import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_desktop_scrollbar.dart';

import 'schedule_day_canvas.dart';
import 'schedule_shared.dart';

const double _teacherColumnWidth = 196;
const double _minimumHourWidth = 72;
const double _timeHeaderHeight = 48;
const double _minimumTeacherRowHeight = 92;
const double _lessonLaneHeight = 48;

/// One teacher row in the horizontal day timeline.
class ScheduleTeacherRow {
  const ScheduleTeacherRow({
    required this.id,
    required this.name,
    required this.color,
    required this.lessonCount,
    required this.totalMinutes,
    this.hasConflict = false,
  });

  final String id;
  final String name;
  final Color color;
  final int lessonCount;
  final int totalMinutes;
  final bool hasConflict;
}

class _TimelineLane {
  const _TimelineLane(this.index, this.count);

  final int index;
  final int count;
}

Map<ScheduleEntry, _TimelineLane> _layoutTeacherEntries(
  List<ScheduleEntry> entries,
) {
  final sorted = [...entries]
    ..sort((left, right) {
      final byStart = left.startLocal.compareTo(right.startLocal);
      return byStart != 0
          ? byStart
          : right.durationMinutes.compareTo(left.durationMinutes);
    });
  final result = <ScheduleEntry, _TimelineLane>{};
  final cluster = <(ScheduleEntry, int)>[];
  final laneEnds = <DateTime>[];
  DateTime? clusterEnd;

  void flush() {
    final count = laneEnds.length;
    for (final item in cluster) {
      result[item.$1] = _TimelineLane(item.$2, count);
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

/// Teacher-oriented day view inspired by a roster table: teachers are stable
/// rows on the left and time runs left-to-right in two-hour header bands.
/// Header and teacher labels stay visible while the grid scrolls on both axes.
class ScheduleTeacherTimeline extends StatefulWidget {
  const ScheduleTeacherTimeline({
    super.key,
    required this.date,
    required this.rows,
    required this.entries,
    required this.onCreateSlot,
    required this.onOpenLesson,
    this.allowCreate = true,
    this.initialVerticalOffset = 0,
    this.onVerticalOffsetChanged,
  });

  final DateTime date;
  final List<ScheduleTeacherRow> rows;
  final List<ScheduleEntry> entries;
  final bool allowCreate;
  final void Function(
    String teacherId,
    DateTime startLocal,
    int durationMinutes,
  )
  onCreateSlot;
  final void Function(Map<String, dynamic> lesson) onOpenLesson;
  final double initialVerticalOffset;
  final ValueChanged<double>? onVerticalOffsetChanged;

  @override
  State<ScheduleTeacherTimeline> createState() =>
      _ScheduleTeacherTimelineState();
}

class _ScheduleTeacherTimelineState extends State<ScheduleTeacherTimeline> {
  final ScrollController _bodyV = ScrollController();
  final ScrollController _bodyH = ScrollController();
  final ScrollController _headerH = ScrollController();
  final ScrollController _labelsV = ScrollController();

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
    if (_labelsV.hasClients && _labelsV.offset != _bodyV.offset) {
      _labelsV.jumpTo(
        _bodyV.offset.clamp(0.0, _labelsV.position.maxScrollExtent),
      );
    }
    widget.onVerticalOffsetChanged?.call(_bodyV.offset);
  }

  void _syncHeader() {
    if (_headerH.hasClients && _headerH.offset != _bodyH.offset) {
      _headerH.jumpTo(
        _bodyH.offset.clamp(0.0, _headerH.position.maxScrollExtent),
      );
    }
  }

  @override
  void dispose() {
    _bodyV.dispose();
    _bodyH.dispose();
    _headerH.dispose();
    _labelsV.dispose();
    super.dispose();
  }

  double _rowHeight(List<ScheduleEntry> entries) {
    final lanes = _layoutTeacherEntries(entries);
    final maxLanes = lanes.values.fold<int>(
      1,
      (value, lane) => math.max(value, lane.count),
    );
    return math.max(
      _minimumTeacherRowHeight,
      maxLanes * _lessonLaneHeight + 20,
    );
  }

  String _dayTitle() {
    const names = [
      'Понедельник',
      'Вторник',
      'Среда',
      'Четверг',
      'Пятница',
      'Суббота',
      'Воскресенье',
    ];
    return names[widget.date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entriesByTeacher = <String, List<ScheduleEntry>>{
      for (final row in widget.rows) row.id: <ScheduleEntry>[],
    };
    for (final entry in widget.entries) {
      entriesByTeacher[entry.columnId]?.add(entry);
    }
    final rowHeights = <String, double>{
      for (final row in widget.rows)
        row.id: _rowHeight(entriesByTeacher[row.id] ?? const []),
    };
    final totalHeight = rowHeights.values.fold<double>(0, (a, b) => a + b);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableTimelineWidth = math.max(
          0.0,
          constraints.maxWidth - _teacherColumnWidth,
        );
        final hourWidth = math.max(
          _minimumHourWidth,
          availableTimelineWidth / (kDayEndHour - kDayStartHour),
        );
        final timelineWidth = (kDayEndHour - kDayStartHour) * hourWidth;

        return Column(
          key: const ValueKey('schedule-teacher-timeline'),
          children: [
            SizedBox(
              height: 46,
              child: Center(
                child: Text(
                  _dayTitle(),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.25,
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  top: BorderSide(color: cs.onSurfaceVariant.withAlpha(28)),
                  bottom: BorderSide(color: cs.onSurfaceVariant.withAlpha(40)),
                ),
              ),
              height: _timeHeaderHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: _teacherColumnWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.md,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 17,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Text(
                              'Преподаватель',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _headerH,
                      physics: const NeverScrollableScrollPhysics(),
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: timelineWidth,
                        child: Row(
                          children: [
                            for (
                              var hour = kDayStartHour;
                              hour < kDayEndHour;
                              hour += 2
                            )
                              _TimeBandHeader(
                                startHour: hour,
                                width: hourWidth * 2,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _teacherColumnWidth,
                    child: SingleChildScrollView(
                      controller: _labelsV,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          for (final row in widget.rows)
                            _TeacherLabelCell(
                              row: row,
                              height: rowHeights[row.id]!,
                            ),
                        ],
                      ),
                    ),
                  ),
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
                                      width: timelineWidth,
                                      height: totalHeight,
                                      child: Column(
                                        children: [
                                          for (final row in widget.rows)
                                            _TeacherTimelineRow(
                                              date: widget.date,
                                              row: row,
                                              height: rowHeights[row.id]!,
                                              width: timelineWidth,
                                              hourWidth: hourWidth,
                                              entries:
                                                  entriesByTeacher[row.id] ??
                                                  const [],
                                              allowCreate: widget.allowCreate,
                                              onCreateSlot: widget.onCreateSlot,
                                              onOpenLesson: widget.onOpenLesson,
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

class _TimeBandHeader extends StatelessWidget {
  const _TimeBandHeader({required this.startHour, required this.width});

  final int startHour;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final endHour = (startHour + 2) % 24;
    String hh(int hour) => hour.toString().padLeft(2, '0');
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: cs.onSurfaceVariant.withAlpha(28)),
        ),
      ),
      child: Text(
        '${hh(startHour)}:00–${hh(endHour)}:00',
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _TeacherLabelCell extends StatelessWidget {
  const _TeacherLabelCell({required this.row, required this.height});

  final ScheduleTeacherRow row;
  final double height;

  String get _durationLabel {
    final hours = row.totalMinutes ~/ 60;
    final minutes = row.totalMinutes % 60;
    if (hours == 0) return '$minutes мин';
    if (minutes == 0) return '$hours ч';
    return '$hours ч $minutes мин';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cs.surface.withAlpha(205),
        border: Border(
          right: BorderSide(color: cs.onSurfaceVariant.withAlpha(34)),
          bottom: BorderSide(color: cs.onSurfaceVariant.withAlpha(28)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3, color: row.color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      ),
                      if (row.hasConflict)
                        const Padding(
                          padding: EdgeInsets.only(left: AppSpace.xs),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: AppColor.danger,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '${row.lessonCount} ${pluralRu(row.lessonCount, 'занятие', 'занятия', 'занятий')} · $_durationLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherTimelineRow extends StatelessWidget {
  const _TeacherTimelineRow({
    required this.date,
    required this.row,
    required this.height,
    required this.width,
    required this.hourWidth,
    required this.entries,
    required this.allowCreate,
    required this.onCreateSlot,
    required this.onOpenLesson,
  });

  final DateTime date;
  final ScheduleTeacherRow row;
  final double height;
  final double width;
  final double hourWidth;
  final List<ScheduleEntry> entries;
  final bool allowCreate;
  final void Function(String, DateTime, int) onCreateSlot;
  final void Function(Map<String, dynamic>) onOpenLesson;

  double _xForTime(DateTime time) =>
      ((time.hour - kDayStartHour) + time.minute / 60) * hourWidth;

  void _createAt(double x) {
    if (!allowCreate) return;
    final rawMinutes = ((x / hourWidth) * 60).round();
    final snappedMinutes = ((rawMinutes / 30).round() * 30).clamp(
      0,
      (kDayEndHour - kDayStartHour) * 60 - 60,
    );
    onCreateSlot(
      row.id,
      DateTime(
        date.year,
        date.month,
        date.day,
        kDayStartHour + snappedMinutes ~/ 60,
        snappedMinutes % 60,
      ),
      60,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lanes = _layoutTeacherEntries(entries);
    return SizedBox(
      height: height,
      width: width,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: allowCreate
                  ? (details) => _createAt(details.localPosition.dx)
                  : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surface.withAlpha(78),
                  border: Border(
                    bottom: BorderSide(
                      color: cs.onSurfaceVariant.withAlpha(28),
                    ),
                  ),
                ),
              ),
            ),
          ),
          for (var index = 0; index <= kDayEndHour - kDayStartHour; index++)
            Positioned(
              left: index * hourWidth,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1,
                color: cs.onSurfaceVariant.withAlpha(index.isEven ? 28 : 14),
              ),
            ),
          for (final entry in entries)
            _positionedEntry(context, entry, lanes[entry]),
        ],
      ),
    );
  }

  Widget _positionedEntry(
    BuildContext context,
    ScheduleEntry entry,
    _TimelineLane? lane,
  ) {
    final naturalLeft = _xForTime(entry.startLocal);
    final naturalRight = naturalLeft + entry.durationMinutes / 60 * hourWidth;
    final left = naturalLeft.clamp(0.0, width).toDouble();
    final right = naturalRight.clamp(0.0, width).toDouble();
    final cardWidth = math.max(42.0, right - left - 5);
    final top = 10 + (lane?.index ?? 0) * _lessonLaneHeight;
    return Positioned(
      left: left + 3,
      top: top,
      width: math.min(cardWidth, width - left - 3),
      height: 40,
      child: Semantics(
        button: true,
        label: 'Открыть занятие ${entry.title}',
        child: _TimelineLessonCard(
          entry: entry,
          onTap: () => onOpenLesson(entry.lesson),
        ),
      ),
    );
  }
}

class _TimelineLessonCard extends StatefulWidget {
  const _TimelineLessonCard({required this.entry, required this.onTap});

  final ScheduleEntry entry;
  final VoidCallback onTap;

  @override
  State<_TimelineLessonCard> createState() => _TimelineLessonCardState();
}

class _TimelineLessonCardState extends State<_TimelineLessonCard> {
  bool _hovered = false;

  String _hm(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final projection = LessonStateProjection.fromMap(
      widget.entry.lesson,
      hasConflict: widget.entry.conflicts.isNotEmpty,
    );
    final accent = projection.token.accent;
    final borderColor = widget.entry.highlighted ? AppColor.gold : accent;
    final end = widget.entry.startLocal.add(
      Duration(minutes: widget.entry.durationMinutes),
    );
    final time = '${_hm(widget.entry.startLocal)}–${_hm(end)}';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.effective(context, AppMotion.fast),
        transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: accent.withAlpha(_hovered ? 54 : 38),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: borderColor,
            width: widget.entry.highlighted ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('schedule-lesson-${widget.entry.id}'),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showTrailingMetadata = constraints.maxWidth >= 96;
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${widget.entry.subtitle} · $time',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showTrailingMetadata)
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Tooltip(
                            message: projection.label,
                            child: Icon(
                              projection.token.icon,
                              color: accent,
                              size: 13,
                            ),
                          ),
                        ),
                      if (showTrailingMetadata && widget.entry.isTrial)
                        const Padding(
                          padding: EdgeInsets.only(left: 3),
                          child: LessonTrialBadge(compact: true),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
