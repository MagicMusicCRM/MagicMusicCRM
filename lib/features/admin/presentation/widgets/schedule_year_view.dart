import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'schedule_shared.dart';

/// Year overview: a 12-month grid of load heatmap cards plus a summary side
/// panel on wide layouts. Extracted from _ScheduleWidgetState — presentation
/// only; the caller supplies the aggregated month data and the tap handler.
class ScheduleYearView extends StatelessWidget {
  final Map<int, ({int count, int activeDays})> yearMonths;
  final int displayedYear;
  final DateTime displayedMonth;
  final bool yearLoading;
  final void Function(int month) onMonthTap;

  const ScheduleYearView({
    super.key,
    required this.yearMonths,
    required this.displayedYear,
    required this.displayedMonth,
    required this.yearLoading,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    if (yearLoading && yearMonths.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ScheduleSkeleton(rows: 4, columns: 3),
      );
    }
    final now = DateTime.now();
    final maxCount = yearMonths.values.fold<int>(
      0,
      (m, v) => v.count > m ? v.count : m,
    );
    final totalLessons = yearMonths.values.fold<int>(
      0,
      (s, v) => s + v.count,
    );
    final activeMonths = yearMonths.values.where((v) => v.count > 0).length;

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760 && c.maxHeight >= 360;
        final cols = c.maxWidth >= 1040
            ? 4
            : c.maxWidth >= 520
            ? 3
            : 2;
        final grid = GridView.count(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          crossAxisCount: cols,
          childAspectRatio: 1.18,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (int m = 1; m <= 12; m++)
              _yearCard(
                context,
                m,
                maxCount,
                selected: displayedMonth.year == displayedYear &&
                    displayedMonth.month == m,
                isCurrent: now.year == displayedYear && now.month == m,
              ),
          ],
        );
        if (!wide) return grid;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: grid),
            SizedBox(
              width: 260,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 12, 16),
                child: _summaryPanel(context, totalLessons, activeMonths),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _yearCard(
    BuildContext context,
    int month,
    int maxCount, {
    required bool selected,
    required bool isCurrent,
  }) {
    final cs = Theme.of(context).colorScheme;
    final data = yearMonths[month] ?? (count: 0, activeDays: 0);
    final intensity = maxCount == 0 ? 0.0 : data.count / maxCount;
    final loadColor = intensity > 0.85
        ? AppColor.warning
        : intensity > 0
        ? AppColor.success
        : cs.onSurfaceVariant;

    // 24-cell density heatmap (≈ working days), brightness ~ month load.
    final heat = List<Widget>.generate(24, (i) {
      final on = data.activeDays > 0 && i < (data.activeDays * 24 / 31).round();
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: on
                ? loadColor.withAlpha((40 + intensity * 150).round())
                : cs.onSurfaceVariant.withAlpha(18),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    });

    return GestureDetector(
      onTap: () => onMonthTap(month),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withAlpha(selected ? 220 : 120),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected
                ? AppColor.gold
                : isCurrent
                ? AppColor.goldLine
                : cs.onSurfaceVariant.withAlpha(20),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    monthNamesNominative[month],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.goldSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColor.goldLine),
                  ),
                  child: Text(
                    '${data.count}',
                    style: const TextStyle(
                      color: AppColor.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Column(
                children: [
                  for (int r = 0; r < 3; r++)
                    Expanded(
                      child: Row(children: heat.sublist(r * 8, r * 8 + 8)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: Text(
                    '${data.activeDays} ${pluralRu(data.activeDays, 'активный день', 'активных дня', 'активных дней')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                if (intensity > 0.85)
                  const Text(
                    'пик',
                    style: TextStyle(
                      color: AppColor.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (selected)
                  const Text(
                    'выбран',
                    style: TextStyle(
                      color: AppColor.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryPanel(
    BuildContext context,
    int totalLessons,
    int activeMonths,
  ) {
    final cs = Theme.of(context).colorScheme;
    Widget stat(String value, String label) {
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
              style: const TextStyle(
                color: AppColor.text,
                fontSize: 22,
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
            'Сводка $displayedYear',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          stat('$totalLessons', 'занятий за год'),
          stat('$activeMonths', 'месяцев с занятиями'),
          if (yearLoading)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(AppColor.gold),
              ),
            ),
        ],
      ),
    );
  }
}
