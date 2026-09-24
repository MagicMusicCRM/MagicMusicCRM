import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'schedule_reference_controller.dart';
import 'schedule_reference_dialogs.dart';
import 'schedule_reference_models.dart';
import 'schedule_reference_recurring_busy_dialog.dart';

class TeacherWeeklyBusySection extends StatelessWidget {
  const TeacherWeeklyBusySection({
    super.key,
    required this.controller,
    required this.editable,
  });

  final ScheduleReferenceController controller;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final rules =
        controller.state.teacherDraft?.unavailableRecurring ??
        const <Map<String, dynamic>>[];
    final canEdit = controller.canEdit && !controller.availabilityLocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Занято каждую неделю',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (canEdit)
              TextButton.icon(
                key: const ValueKey('weekly-unavailable-add'),
                onPressed: editable ? () => _add(context) : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
          ],
        ),
        if (rules.isEmpty) const Text('Повторяющиеся занятые часы не заданы'),
        for (final rule in rules)
          _WeeklyBusyRow(
            rule: rule,
            canEdit: canEdit,
            editable: editable,
            onEdit: () => _edit(context, rule),
            onDelete: () => controller.removeUnavailableRecurringRule(rule),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final rule = await showUnavailableRecurringDialog(
      context,
      timezone: controller.state.branchDraft?.timezone ?? 'Europe/Moscow',
    );
    if (rule != null) controller.addUnavailableRecurringRule(rule);
  }

  Future<void> _edit(BuildContext context, Map<String, dynamic> current) async {
    final rule = await showUnavailableRecurringDialog(
      context,
      timezone:
          current['timezone']?.toString() ??
          controller.state.branchDraft?.timezone ??
          'Europe/Moscow',
      initialRule: current,
    );
    if (rule != null) controller.replaceUnavailableRecurringRule(current, rule);
  }
}

class _WeeklyBusyRow extends StatelessWidget {
  const _WeeklyBusyRow({
    required this.rule,
    required this.canEdit,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> rule;
  final bool canEdit;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(_weeklyLabel(rule)),
    subtitle: Text('${_weeklyDates(rule)}${_reason(rule)}'),
    onTap: editable ? onEdit : null,
    trailing: canEdit
        ? Wrap(
            children: [
              IconButton(
                tooltip: 'Изменить еженедельную занятость',
                onPressed: editable ? onEdit : null,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Удалить еженедельную занятость',
                onPressed: editable ? onDelete : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          )
        : null,
  );
}

class TeacherDateBusySection extends StatelessWidget {
  const TeacherDateBusySection({
    super.key,
    required this.controller,
    required this.editable,
  });

  final ScheduleReferenceController controller;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final rules =
        controller.state.teacherDraft?.intervals ??
        const <Map<String, dynamic>>[];
    final canEdit = controller.canEdit && !controller.availabilityLocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Недоступность по датам',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (canEdit)
              TextButton.icon(
                onPressed: editable ? () => _add(context) : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
          ],
        ),
        for (final rule in rules)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_intervalLabel(rule)),
            subtitle: rule['reason'] == null
                ? null
                : Text(rule['reason'].toString()),
            trailing: canEdit
                ? IconButton(
                    tooltip: 'Удалить период',
                    onPressed: editable
                        ? () => controller.removeUnavailableInterval(rule)
                        : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                  )
                : null,
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final rule = await showUnavailableIntervalDialog(context);
    if (rule != null) controller.addUnavailableInterval(rule);
  }
}

String _weeklyLabel(Map<String, dynamic> rule) {
  final day =
      scheduleReferenceDayNames[(rule['weekday'] as num?)?.toInt()] ??
      'День недели';
  return '$day · ${rule['localStart'] ?? ''}–${rule['localEnd'] ?? ''}';
}

String _weeklyDates(Map<String, dynamic> rule) {
  final from = DateTime.tryParse(rule['validFrom']?.toString() ?? '');
  final until = DateTime.tryParse(rule['validUntil']?.toString() ?? '');
  final format = DateFormat('dd.MM.yyyy');
  return '${from == null ? '' : 'с ${format.format(from)}'} · '
      '${until == null ? 'без даты окончания' : 'до ${format.format(until)}'}';
}

String _intervalLabel(Map<String, dynamic> rule) {
  final start = DateTime.tryParse(
    rule['startsAt']?.toString() ?? '',
  )?.toLocal();
  final end = DateTime.tryParse(rule['endsAt']?.toString() ?? '')?.toLocal();
  if (start == null) return 'Период недоступности';
  final format = DateFormat('dd.MM.yyyy HH:mm');
  return end == null
      ? 'с ${format.format(start)}'
      : '${format.format(start)} - ${format.format(end)}';
}

String _reason(Map<String, dynamic> rule) {
  final reason = rule['reason']?.toString().trim() ?? '';
  return reason.isEmpty ? '' : ' · $reason';
}
