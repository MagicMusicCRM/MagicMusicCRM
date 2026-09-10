part of 'schedule_day_canvas.dart';

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

  static TextStyle textStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelMedium!
      .copyWith(fontSize: 12, fontWeight: FontWeight.w700, height: 1.15);

  static double heightFor(
    BuildContext context,
    List<ScheduleColumn> columns,
    double width,
  ) {
    var textHeight = MediaQuery.textScalerOf(context).scale(12) * 1.15;
    for (final column in columns) {
      final painter =
          TextPainter(
            text: TextSpan(text: column.name, style: textStyle(context)),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 2,
          )..layout(
            maxWidth: (width - 18 - (column.hasConflict ? 18 : 0)).clamp(
              1.0,
              double.infinity,
            ),
          );
      if (painter.height > textHeight) textHeight = painter.height;
      painter.dispose();
    }
    // Account for both margins, padding and borders around the measured text.
    return (textHeight + 22).ceilToDouble();
  }

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
              style: textStyle(context).copyWith(
                color: column.isUnassigned
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : column.color,
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

  const _LessonCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final projection = LessonStateProjection.fromMap(
      entry.lesson,
      hasConflict: entry.conflicts.isNotEmpty,
    );
    final accent = projection.token.accent;
    final borderColor = entry.highlighted ? AppColor.gold : accent;
    final start = entry.startLocal;
    final end = start.add(Duration(minutes: entry.durationMinutes));
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final timeStr = '${hm(start)}-${hm(end)}';

    return Tooltip(
      message: [
        entry.title,
        timeStr,
        entry.subtitle,
        projection.label,
        if (entry.isTrial) 'Пробное',
        if (lessonHasSubscriptionCoverage(entry.lesson)) 'Абонемент',
        if (entry.conflicts.isNotEmpty) 'Конфликт расписания',
      ].where((line) => line.isNotEmpty).join('\n'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final showTime = constraints.maxHeight >= 34 * scale;
          final showSubtitle = constraints.maxHeight >= 52 * scale;
          final showBadges = constraints.maxWidth >= 130;
          return Container(
            key: ValueKey('schedule-lesson-${entry.id}'),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: projection.token.soft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderColor,
                width: entry.highlighted ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      if (entry.clientContext || entry.searchContext) ...[
                        Icon(
                          entry.relatedClient
                              ? Icons.person_pin_circle_outlined
                              : Icons.people_outline_rounded,
                          color: accent,
                          size: 12,
                        ),
                        const SizedBox(width: 3),
                      ],
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
                      Tooltip(
                        message: projection.label,
                        child: Icon(
                          projection.token.icon,
                          color: accent,
                          size: 12,
                        ),
                      ),
                      if (showBadges &&
                          lessonHasSubscriptionCoverage(entry.lesson)) ...[
                        const SizedBox(width: 3),
                        const LessonSubscriptionBadge(
                          compact: true,
                          iconOnly: true,
                        ),
                      ],
                      if (showBadges && entry.isTrial && showSubtitle) ...[
                        const SizedBox(width: 3),
                        const LessonTrialBadge(compact: true),
                      ],
                    ],
                  ),
                ),
                if (showSubtitle && entry.subtitle.isNotEmpty)
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
                if (showTime)
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
        },
      ),
    );
  }
}
