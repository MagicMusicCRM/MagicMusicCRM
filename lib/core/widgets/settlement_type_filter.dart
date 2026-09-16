import 'package:flutter/material.dart';
import 'lesson_settlement_corner.dart';
import 'choice_dropdown.dart';

const settlementTypeLabels = <String, String>{
  'lesson': 'Занятие',
  'trial_lesson': 'Пробный урок',
  'partially_paid_lesson': 'Частичная оплата',
  'free_lesson': 'Бесплатное',
  'paid_miss': 'Оплачиваемый пропуск',
  'partially_paid_miss': 'Частично оплачиваемый пропуск',
  'unpaid_miss': 'Неоплачиваемый пропуск',
  'penalty_lesson': 'Со штрафом',
};

/// Empty selection means no restriction; selected keys are combined with OR.
class SettlementTypeFilter extends StatelessWidget {
  const SettlementTypeFilter({
    super.key,
    required this.selected,
    required this.onChanged,
    this.labels = settlementTypeLabels,
    this.showColors = true,
    this.label = 'Типы списания',
  });
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Map<String, String> labels;
  final bool showColors;
  final String label;

  @override
  Widget build(BuildContext context) => ChoiceDropdown(
    key: ValueKey('financial-filter-$label'),
    labels: labels,
    selected: selected,
    onChanged: onChanged,
    multiple: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    optionWidgets: {
      if (showColors)
        for (final entry in labels.entries)
          entry.key: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: LessonSettlementCorner(
                  settlementTypeKey: entry.key,
                  timeline: true,
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
    },
  );
}
