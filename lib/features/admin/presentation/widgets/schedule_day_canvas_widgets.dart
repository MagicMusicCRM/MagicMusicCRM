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

    return Container(
      key: ValueKey('schedule-lesson-${entry.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
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
          Row(
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
                child: Icon(projection.token.icon, color: accent, size: 12),
              ),
              if (lessonHasSubscriptionCoverage(entry.lesson)) ...[
                const SizedBox(width: 3),
                const LessonSubscriptionBadge(compact: true, iconOnly: true),
              ],
              if (entry.isTrial && entry.durationMinutes >= 45) ...[
                const SizedBox(width: 3),
                const LessonTrialBadge(compact: true),
              ],
            ],
          ),
          if (entry.durationMinutes >= 45 && entry.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                entry.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
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
