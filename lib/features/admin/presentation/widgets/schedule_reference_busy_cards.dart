import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'schedule_reference_dialogs.dart';

import 'schedule_reference_controller.dart';
import 'schedule_reference_interval_busy_dialog.dart';
import 'schedule_reference_models.dart';
import 'schedule_reference_recurring_busy_dialog.dart';
import 'schedule_reference_timezone.dart';

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
    final canEdit = controller.canEdit;
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
    final extraAvailability =
        controller.state.teacherDraft?.availableIntervals ??
        const <Map<String, dynamic>>[];
    final canEdit = controller.canEdit;
    final timezone = controller.state.branchDraft?.timezone ?? 'Europe/Moscow';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Отсутствия по датам',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (canEdit)
              TextButton.icon(
                key: const ValueKey('interval-unavailable-add'),
                onPressed: editable ? () => _add(context) : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
          ],
        ),
        if (rules.isEmpty) const Text('Отсутствия не добавлены'),
        for (final rule in rules)
          _DateBusyRow(
            rule: rule,
            timezone: timezone,
            canEdit: canEdit,
            editable: editable,
            onEdit: () => _edit(context, rule),
            onDelete: () => controller.removeUnavailableInterval(rule),
          ),
        if (extraAvailability.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Дополнительная доступность по датам',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final rule in extraAvailability)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_intervalLabel(rule, timezone)),
              subtitle: rule['reason'] == null
                  ? null
                  : Text(rule['reason'].toString()),
            ),
        ],
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final rule = await showUnavailableIntervalDialog(
      context,
      timezone: controller.state.branchDraft?.timezone ?? 'Europe/Moscow',
    );
    if (rule != null) controller.addUnavailableInterval(rule);
  }

  Future<void> _edit(BuildContext context, Map<String, dynamic> current) async {
    final rule = await showUnavailableIntervalDialog(
      context,
      timezone:
          current['timezone']?.toString() ??
          controller.state.branchDraft?.timezone ??
          'Europe/Moscow',
      initialRule: current,
    );
    if (rule != null) controller.replaceUnavailableInterval(current, rule);
  }
}

class _DateBusyRow extends StatelessWidget {
  const _DateBusyRow({
    required this.rule,
    required this.timezone,
    required this.canEdit,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> rule;
  final String timezone;
  final bool canEdit;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(_intervalLabel(rule, timezone)),
    subtitle: rule['reason'] == null ? null : Text(rule['reason'].toString()),
    onTap: editable ? onEdit : null,
    trailing: canEdit
        ? Wrap(
            children: [
              IconButton(
                tooltip: 'Изменить занятый период',
                onPressed: editable ? onEdit : null,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Удалить период',
                onPressed: editable ? onDelete : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          )
        : null,
  );
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

String _intervalLabel(Map<String, dynamic> rule, String timezone) {
  final zone = rule['timezone']?.toString() ?? timezone;
  final startUtc = DateTime.tryParse(rule['startsAt']?.toString() ?? '');
  final endUtc = DateTime.tryParse(rule['endsAt']?.toString() ?? '');
  final start = startUtc == null ? null : scheduleUtcToLocal(startUtc, zone);
  final end = endUtc == null ? null : scheduleUtcToLocal(endUtc, zone);
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

class TeacherRecurringRuleRow extends StatelessWidget {
  const TeacherRecurringRuleRow({
    super.key,
    required this.rule,
    required this.controller,
    required this.editable,
  });

  final Map<String, dynamic> rule;
  final ScheduleReferenceController controller;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final start = rule['localStart']?.toString() ?? '09:00';
    final end = rule['localEnd']?.toString() ?? '21:00';
    final validFrom = DateTime.tryParse(rule['validFrom']?.toString() ?? '');
    final validUntil = DateTime.tryParse(rule['validUntil']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: editable
                ? () => _pickTime(context, 'localStart', start)
                : null,
            icon: const Icon(Icons.schedule_rounded, size: 16),
            label: Text(start),
          ),
          const Text('—'),
          TextButton(
            onPressed: editable
                ? () => _pickTime(context, 'localEnd', end)
                : null,
            child: Text(end),
          ),
          TextButton.icon(
            onPressed: editable
                ? () => _pickDate(context, 'validFrom', validFrom)
                : null,
            icon: const Icon(Icons.event_available_outlined, size: 16),
            label: Text(
              'с ${validFrom == null ? 'сегодня' : DateFormat('dd.MM.yyyy').format(validFrom)}',
            ),
          ),
          TextButton.icon(
            onPressed: editable
                ? () => _pickDate(context, 'validUntil', validUntil)
                : null,
            icon: const Icon(Icons.event_busy_outlined, size: 16),
            label: Text(
              validUntil == null
                  ? 'без срока'
                  : 'до ${DateFormat('dd.MM.yyyy').format(validUntil)}',
            ),
          ),
          if (validUntil != null)
            IconButton(
              tooltip: 'Убрать дату окончания',
              onPressed: editable
                  ? () =>
                        controller.updateRecurringRule(rule, 'validUntil', null)
                  : null,
              icon: const Icon(Icons.event_busy_rounded, size: 18),
            ),
          IconButton(
            tooltip: 'Удалить рабочий интервал',
            onPressed: editable
                ? () => controller.removeRecurringRule(rule)
                : null,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    String field,
    String current,
  ) async {
    final next = await pickScheduleTime(context, current);
    if (next != null) controller.updateRecurringRule(rule, field, next);
  }

  Future<void> _pickDate(
    BuildContext context,
    String field,
    DateTime? current,
  ) async {
    final now = DateUtils.dateOnly(DateTime.now());
    final next = await showMagicDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (next != null) {
      controller.updateRecurringRule(
        rule,
        field,
        DateFormat('yyyy-MM-dd').format(next),
      );
    }
  }
}
