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
  final bool inHand;
  final bool ghost;

  /// Touch-only: this card is the tapped one, so its resize handles are out and
  /// a second tap opens it. It has to LOOK picked, or the handles appear to
  /// belong to nothing.
  final bool selected;

  const _LessonCard({
    required this.entry,
    this.inHand = false,
    this.ghost = false,
    this.selected = false,
  });

  Color get _accent {
    if (entry.clientContext || entry.searchContext) {
      return entry.relatedClient ? AppColor.success : AppColor.text2;
    }
    if (entry.conflicts.isNotEmpty) return AppColor.danger;
    return LessonStateProjection.fromMap(entry.lesson).token.accent;
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
      key: ValueKey('schedule-lesson-${entry.id}'),
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
          color: ghost || selected ? AppColor.gold : accent,
          width: ghost || selected || entry.highlighted || inHand ? 2 : 1,
        ),
        boxShadow: inHand || selected ? AppShadow.shLift : null,
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
              // A frozen lesson used to look exactly like a movable one, so
              // «drag does nothing» read as a broken grid rather than a rule.
              if (!entry.movable && !inHand)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    color: cs.onSurfaceVariant,
                    size: 11,
                  ),
                ),
              if (entry.conflicts.isNotEmpty)
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColor.danger,
                  size: 12,
                ),
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

/// A simple dashed-border box (Flutter has no built-in dashed border) used for
/// the new-booking selection and the forbidden-horizontal hint.
class _DashedBox extends StatelessWidget {
  final Color color;
  final Color fill;
  final Widget child;
  const _DashedBox({
    required this.color,
    required this.fill,
    required this.child,
  });

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
