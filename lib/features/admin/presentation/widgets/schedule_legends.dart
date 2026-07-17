import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Colour legend for the month view + a «Сегодня» shortcut. Extracted from
/// _ScheduleWidgetState — pure display + onToday callback.
class ScheduleMonthLegend extends StatelessWidget {
  final VoidCallback onToday;
  const ScheduleMonthLegend({super.key, required this.onToday});

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
      child: Row(
        children: [
          Expanded(
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
          ),
          GestureDetector(
            onTap: onToday,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColor.goldLine),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const Text(
                'Сегодня',
                style: TextStyle(
                  color: AppColor.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
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
