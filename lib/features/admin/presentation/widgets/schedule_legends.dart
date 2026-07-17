import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Colour legend for the month view. The «Сегодня» shortcut used to live here
/// too, but the date-navigation row already carries one (white, in every
/// view) — two identical buttons on the month screen was the reported dupe, so
/// this keeps only the colour legend.
class ScheduleMonthLegend extends StatelessWidget {
  const ScheduleMonthLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget chip(Color c, String label) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withAlpha(22),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.withAlpha(70)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(AppColor.actionBlue, 'Обычные'),
            chip(AppColor.success, 'Пробные'),
            chip(AppColor.warning, 'Пиковая'),
            chip(AppColor.danger, 'Конфликт'),
          ],
        ),
      ),
    );
  }
}

/// Colour/gesture legend for the day view. Extracted from _ScheduleWidgetState
/// — pure display.
class ScheduleDayLegend extends StatelessWidget {
  const ScheduleDayLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget chip(Color c, String label) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: c.withAlpha(22),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.withAlpha(70)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(AppColor.transferCyan, 'Зажать и тянуть вниз — выбрать часы'),
            chip(AppColor.actionBlue, 'Перетащить — время / комната'),
            chip(AppColor.gold, 'Край — растянуть'),
            chip(AppColor.danger, 'Конфликт'),
          ],
        ),
      ),
    );
  }
}
