import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';
import 'schedule_legends.dart';
import 'schedule_shared.dart';

/// Month grid (weekday header + day cells with load/conflict marks) plus a
/// wide-layout side panel for the focused day. Extracted from
/// _ScheduleWidgetState — presentation only; lesson lookups and navigation are
/// supplied as callbacks so the branch-timezone offset logic stays in the State.
class ScheduleMonthView extends StatelessWidget {
  final DateTime selectedDate;
  final DateTime displayedMonth;
  final Map<String, String> studentNames;
  final Map<String, Map<String, dynamic>> monthDaySummary;
  final List<Map<String, dynamic>> Function(DateTime) lessonsForDate;
  final DateTime? Function(Map<String, dynamic>) parseLessonTime;
  final bool clientContext;
  final bool searchContext;
  final bool Function(Map<String, dynamic>) isContextClientLesson;
  final void Function(DateTime) onDayTap;

  const ScheduleMonthView({
    super.key,
    required this.selectedDate,
    required this.displayedMonth,
    required this.studentNames,
    required this.monthDaySummary,
    required this.lessonsForDate,
    required this.parseLessonTime,
    this.clientContext = false,
    this.searchContext = false,
    required this.isContextClientLesson,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final year = displayedMonth.year;
    final month = displayedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday; // 1=Mon..7=Sun
    final prevDays = startWeekday - 1;
    final prevMonthLastDay = DateTime(year, month, 0).day;
    final totalSlots = prevDays + daysInMonth;
    final rows = (totalSlots / 7).ceil();
    final now = DateTime.now();

    // Focal day for the side summary: the selected day if it's in this month,
    // else today (if today is this month), else the 1st.
    DateTime focal;
    if (selectedDate.year == year && selectedDate.month == month) {
      focal = selectedDate;
    } else if (now.year == year && now.month == month) {
      focal = DateTime(year, month, now.day);
    } else {
      focal = DateTime(year, month, 1);
    }

    final calendar = Column(
      children: [
        // Weekday headers.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: weekDays
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(180),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              children: List.generate(rows, (row) {
                return Expanded(
                  child: Row(
                    children: List.generate(7, (col) {
                      final index = row * 7 + col;
                      if (index < prevDays) {
                        final day = prevMonthLastDay - prevDays + 1 + index;
                        return _cellRich(
                          context,
                          day,
                          isCurrentMonth: false,
                          date: null,
                        );
                      }
                      final dayNum = index - prevDays + 1;
                      if (dayNum > daysInMonth) {
                        return _cellRich(
                          context,
                          dayNum - daysInMonth,
                          isCurrentMonth: false,
                          date: null,
                        );
                      }
                      final date = DateTime(year, month, dayNum);
                      final isToday =
                          date.year == now.year &&
                          date.month == now.month &&
                          date.day == now.day;
                      return _cellRich(
                        context,
                        dayNum,
                        isCurrentMonth: true,
                        date: date,
                        isToday: isToday,
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );

    return Column(
      children: [
        const ScheduleMonthLegend(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 760 && c.maxHeight >= 420;
              if (!wide) return calendar;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: calendar),
                  const SizedBox(width: 10),
                  SizedBox(width: 260, child: _sidePanel(context, focal)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cellRich(
    BuildContext context,
    int day, {
    required bool isCurrentMonth,
    DateTime? date,
    bool isToday = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final summary = date != null ? monthDaySummary[dateOnly(date)] : null;
    final lessons = date != null ? lessonsForDate(date) : const [];
    final count = summary != null
        ? (summary['count'] as int? ?? 0)
        : lessons.length;
    final isSelected =
        date != null &&
        selectedDate.year == date.year &&
        selectedDate.month == date.month &&
        selectedDate.day == date.day;
    final related =
        searchContext && lessons.any((lesson) => isContextClientLesson(lesson));

    // Up to two preview chips from the in-memory (capped) matrix; the count
    // badge stays authoritative for the full-day total.
    final sorted = [...lessons];
    sorted.sort((a, b) {
      final ta = parseLessonTime(a);
      final tb = parseLessonTime(b);
      if (ta == null || tb == null) return 0;
      return ta.compareTo(tb);
    });

    return Expanded(
      child: GestureDetector(
        onTap: date != null ? () => onDayTap(date) : null,
        child: Container(
          key: date == null
              ? null
              : ValueKey('schedule-month-day-${dateOnly(date)}'),
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
          decoration: BoxDecoration(
            color: isCurrentMonth
                ? searchContext
                      ? (related
                            ? AppColor.success.withAlpha(28)
                            : AppColor.text2.withAlpha(12))
                      : cs.surface.withAlpha(isSelected ? 220 : 120)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: searchContext
                  ? (related ? AppColor.success : AppColor.text2.withAlpha(70))
                  : isToday
                  ? AppColor.gold
                  : isSelected
                  ? AppColor.goldLine
                  : cs.onSurfaceVariant.withAlpha(14),
              width: searchContext && related || !searchContext && isToday
                  ? 1.5
                  : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? BoxDecoration(
                            color: AppColor.gold,
                            borderRadius: BorderRadius.circular(7),
                          )
                        : null,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: isToday
                            ? Colors.white
                            : isCurrentMonth
                            ? AppColor.text
                            : cs.onSurfaceVariant.withAlpha(90),
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (isCurrentMonth && count > 0)
                    Text(
                      '$count',
                      style: TextStyle(
                        color: searchContext
                            ? (related ? AppColor.success : AppColor.text2)
                            : count >= 9
                            ? AppColor.warning
                            : AppColor.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (isCurrentMonth) ...[
                const SizedBox(height: 3),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final l in sorted.take(2)) _chip(context, l),
                        if (count > sorted.take(2).length)
                          Padding(
                            padding: const EdgeInsets.only(top: 1, left: 2),
                            child: Text(
                              '+${count - sorted.take(2).length} ${pluralRu(count - sorted.take(2).length, 'занятие', 'занятия', 'занятий')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurfaceVariant.withAlpha(170),
                                fontSize: 9,
                              ),
                            ),
                          )
                        else if (count == 0 && sorted.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1, left: 2),
                            child: Text(
                              'нет занятий',
                              style: TextStyle(
                                color: cs.onSurfaceVariant.withAlpha(110),
                                fontSize: 9,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, Map<String, dynamic> lesson) {
    final cs = Theme.of(context).colorScheme;
    final start = parseLessonTime(lesson);
    final conflicts = conflictTypes(lesson['conflict_types']);
    final relationContext = clientContext || searchContext;
    final related = relationContext && isContextClientLesson(lesson);
    final color = searchContext
        ? (related ? AppColor.success : AppColor.text2)
        : conflicts.isNotEmpty
        ? AppColor.danger
        : clientContext
        ? (related ? AppColor.success : AppColor.text2)
        : LessonStateProjection.fromMap(lesson).token.accent;
    final time = start == null
        ? ''
        : '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} ';
    // Пробное по лиду: student_id/group_name пусты, имя приходит в lead_name.
    final leadName = lesson['lead_name']?.toString().trim() ?? '';
    final name =
        studentNames[lesson['student_id']?.toString()] ??
        lesson['group_name']?.toString() ??
        (leadName.isNotEmpty ? leadName : 'Занятие');
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trial = lesson['is_trial'] == true;
          final showTrialText =
              trial && constraints.maxWidth >= (relationContext ? 90 : 70);
          final showTrialIcon =
              trial && constraints.maxWidth >= (relationContext ? 38 : 22);
          return Row(
            children: [
              if (relationContext) ...[
                Icon(
                  related
                      ? Icons.person_pin_circle_outlined
                      : Icons.people_outline_rounded,
                  size: 10,
                  color: color,
                ),
                const SizedBox(width: 2),
              ],
              if (showTrialText) ...[
                const LessonTrialBadge(compact: true),
                const SizedBox(width: 3),
              ] else if (showTrialIcon) ...[
                const Tooltip(
                  message: 'Пробный урок',
                  child: Icon(
                    Icons.star_rounded,
                    size: 10,
                    color: AppColor.gold,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              Expanded(
                child: Text(
                  '$time$name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurface, fontSize: 9.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sidePanel(BuildContext context, DateTime focal) {
    final cs = Theme.of(context).colorScheme;
    final lessons = lessonsForDate(focal);
    final summary = monthDaySummary[dateOnly(focal)];
    final count = summary != null
        ? (summary['count'] as int? ?? 0)
        : lessons.length;
    final trials = lessons.where((l) => l['is_trial'] == true).length;
    final conflicts = lessons
        .where((l) => conflictTypes(l['conflict_types']).isNotEmpty)
        .length;

    Widget stat(String value, String label, Color color) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withAlpha(120),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: cs.onSurfaceVariant.withAlpha(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface.withAlpha(90),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: cs.onSurfaceVariant.withAlpha(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${focal.day} ${monthNamesGenitive[focal.month]}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stat('$count', 'занятий в выбранном дне', AppColor.gold),
                  stat(
                    '$conflicts',
                    'конфликтов комнаты/педагога',
                    conflicts > 0 ? AppColor.danger : AppColor.text,
                  ),
                  stat(
                    '$trials',
                    'пробных уроков',
                    trials > 0 ? AppColor.success : AppColor.text,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: Material(
              color: AppColor.gold,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => onDayTap(focal),
                child: const Center(
                  child: Text(
                    'Открыть день',
                    style: TextStyle(
                      color: AppColor.onGold,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
