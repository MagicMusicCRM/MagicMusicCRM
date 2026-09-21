import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/lesson_settlement_corner.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';

class ScheduleMonthLegend extends StatelessWidget {
  const ScheduleMonthLegend({super.key});

  @override
  Widget build(BuildContext context) =>
      const _ScheduleLessonLegend(padding: EdgeInsets.fromLTRB(16, 2, 16, 8));
}

class ScheduleDayLegend extends StatelessWidget {
  final bool week;

  const ScheduleDayLegend({super.key, this.week = false});

  @override
  Widget build(BuildContext context) =>
      const _ScheduleLessonLegend(padding: EdgeInsets.fromLTRB(16, 2, 16, 6));
}

/// One canonical legend for every operational schedule view.
class _ScheduleLessonLegend extends StatelessWidget {
  const _ScheduleLessonLegend({required this.padding});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget statusChip(LessonStateToken token) {
      final accent = token.accent;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: token.soft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(token.icon, size: 13, color: accent),
            const SizedBox(width: 5),
            Text(
              token.label,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final token in LessonStateToken.values) statusChip(token),
          TextButton.icon(
            icon: const Icon(Icons.info_outline, size: 16),
            label: const Text('Фон — тип списания · значок — статус'),
            onPressed: () => showMagicDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Тип списания с клиента'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Фон показывает тип списания. Статус занятия, включая завершение, показывает значок.',
                    ),
                    const SizedBox(height: 12),
                    for (final key in const [
                      'lesson',
                      'trial_lesson',
                      'partially_paid_lesson',
                      'free_lesson',
                      'paid_miss',
                      'partially_paid_miss',
                      'unpaid_miss',
                      'penalty_lesson',
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: LessonSettlementCorner(
                                settlementTypeKey: key,
                                child: const SizedBox.expand(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                LessonSettlementCorner.labelFor(key)!,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Понятно'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const LessonSubscriptionBadge(),
        ],
      ),
    );
  }
}
