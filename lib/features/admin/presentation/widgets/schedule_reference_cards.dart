import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/widgets/magic_picker.dart';

import 'schedule_reference_controller.dart';
import 'schedule_reference_dialogs.dart';
import 'schedule_reference_models.dart';

class BranchHoursCard extends StatelessWidget {
  const BranchHoursCard({
    super.key,
    required this.controller,
    required this.onSave,
  });

  final ScheduleReferenceController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final draft = controller.state.branchDraft;
    final canMutate = _canMutate(controller.canEdit, controller.state.saving);
    return ScheduleReferenceCard(
      title: 'Рабочие часы филиала',
      action: controller.canEdit
          ? FilledButton(
              onPressed:
                  controller.state.saving || draft?.weekly.isEmpty != false
                  ? null
                  : onSave,
              child: const Text('Сохранить'),
            )
          : null,
      children: [
        for (final day in scheduleReferenceDayNames.entries)
          ScheduleTimeRow(
            label: day.value,
            value: draft?.weekly[day.key],
            editable: canMutate,
            onEnabled: (enabled) =>
                controller.setBranchDayEnabled(day.key, enabled),
            onTime: (field, value) =>
                controller.setBranchTime(day.key, field, value),
          ),
        const Divider(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Исключения',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (controller.canEdit)
              TextButton.icon(
                onPressed: _whenEnabled(
                  canMutate,
                  () => _addException(context),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
          ],
        ),
        for (final row in draft?.exceptions ?? const <Map<String, dynamic>>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row['date']?.toString() ?? ''),
            subtitle: Text(
              row['closed'] == true
                  ? 'Закрыто${_reason(row)}'
                  : '${row['open']}-${row['close']}${_reason(row)}',
            ),
            trailing: controller.canEdit
                ? IconButton(
                    tooltip: 'Удалить исключение',
                    onPressed: _whenEnabled(
                      canMutate,
                      () => controller.removeBranchException(
                        row['date']?.toString() ?? '',
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  )
                : null,
          ),
      ],
    );
  }

  Future<void> _addException(BuildContext context) async {
    final row = await showBranchExceptionDialog(context);
    if (row != null) controller.replaceBranchException(row);
  }
}

class TeacherAssignmentsCard extends StatelessWidget {
  const TeacherAssignmentsCard({
    super.key,
    required this.controller,
    required this.onSave,
  });

  final ScheduleReferenceController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final assignments = controller.state.teacherDraft?.assignments;
    final canMutate = _canMutate(controller.canEdit, controller.state.saving);
    return ScheduleReferenceCard(
      title: 'Филиалы преподавателя',
      action: controller.canEdit
          ? FilledButton(
              onPressed:
                  controller.state.saving || assignments?.isEmpty != false
                  ? null
                  : onSave,
              child: const Text('Сохранить'),
            )
          : null,
      children: [
        for (final branch in controller.state.branches)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: assignments?.containsKey(branch['id']?.toString()) ?? false,
            title: Text(branch['name']?.toString() ?? 'Филиал'),
            onChanged: _whenEnabled<ValueChanged<bool?>>(
              canMutate,
              (selected) => controller.setAssignment(
                branch['id'].toString(),
                selected == true,
              ),
            ),
          ),
      ],
    );
  }
}

class TeacherAvailabilityCard extends StatelessWidget {
  const TeacherAvailabilityCard({
    super.key,
    required this.controller,
    required this.onSave,
  });

  final ScheduleReferenceController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final draft = controller.state.teacherDraft;
    final canEdit = controller.canEdit && !controller.availabilityLocked;
    final canMutate = _canMutate(canEdit, controller.state.saving);
    return ScheduleReferenceCard(
      title: 'Доступность преподавателя',
      action: canEdit
          ? FilledButton(
              onPressed: controller.state.saving ? null : onSave,
              child: const Text('Сохранить'),
            )
          : null,
      children: [
        const Text(
          'Для каждого дня можно задать несколько рабочих интервалов и срок действия. '
          'Разовые занятые периоды добавляются ниже.',
        ),
        const SizedBox(height: 12),
        for (final day in scheduleReferenceDayNames.entries)
          _TeacherRecurringDayEditor(
            weekday: day.key,
            label: day.value,
            controller: controller,
            editable: canMutate,
          ),
        const Divider(height: 28),
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
                onPressed: _whenEnabled(canMutate, () => _addInterval(context)),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
          ],
        ),
        for (final row in draft?.intervals ?? const <Map<String, dynamic>>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_intervalLabel(row)),
            subtitle: row['reason'] == null
                ? null
                : Text(row['reason'].toString()),
            trailing: canEdit
                ? IconButton(
                    tooltip: 'Удалить период',
                    onPressed: _whenEnabled(
                      canMutate,
                      () => controller.removeUnavailableInterval(row),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  )
                : null,
          ),
      ],
    );
  }

  Future<void> _addInterval(BuildContext context) async {
    final interval = await showUnavailableIntervalDialog(context);
    if (interval != null) controller.addUnavailableInterval(interval);
  }
}

class _TeacherRecurringDayEditor extends StatelessWidget {
  const _TeacherRecurringDayEditor({
    required this.weekday,
    required this.label,
    required this.controller,
    required this.editable,
  });

  final int weekday;
  final String label;
  final ScheduleReferenceController controller;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final rules = controller.recurringRulesFor(weekday);
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('teacher-availability-day-$weekday'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                key: ValueKey('teacher-availability-add-$weekday'),
                onPressed: editable
                    ? () => controller.addRecurringRule(weekday)
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Интервал'),
              ),
            ],
          ),
          if (rules.isEmpty)
            Text(
              'Рабочие интервалы не заданы',
              style: TextStyle(color: colors.onSurfaceVariant),
            )
          else
            for (final rule in rules)
              _TeacherRecurringRuleRow(
                rule: rule,
                controller: controller,
                editable: editable,
              ),
        ],
      ),
    );
  }
}

class _TeacherRecurringRuleRow extends StatelessWidget {
  const _TeacherRecurringRuleRow({
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

class ScheduleTimeRow extends StatelessWidget {
  const ScheduleTimeRow({
    super.key,
    required this.label,
    required this.value,
    required this.editable,
    required this.onEnabled,
    required this.onTime,
    this.startKey = 'open',
    this.endKey = 'close',
  });

  final String label;
  final Map<String, dynamic>? value;
  final bool editable;
  final ValueChanged<bool> onEnabled;
  final void Function(String field, String value) onTime;
  final String startKey;
  final String endKey;

  @override
  Widget build(BuildContext context) {
    final enabled = value != null;
    return Row(
      children: [
        Semantics(
          label: '$label: ${enabled ? 'включено' : 'выключено'}',
          toggled: enabled,
          child: ExcludeSemantics(
            child: Switch(
              value: enabled,
              onChanged: editable ? onEnabled : null,
            ),
          ),
        ),
        Expanded(child: Text(label)),
        if (enabled) ...[
          _timeButton(context, startKey, '09:00'),
          const Text('Не указано'),
          _timeButton(context, endKey, '21:00'),
        ],
      ],
    );
  }

  Widget _timeButton(BuildContext context, String field, String fallback) {
    final current = value?[field]?.toString() ?? fallback;
    return TextButton(
      onPressed: !editable
          ? null
          : () async {
              final next = await pickScheduleTime(context, current);
              if (next != null) onTime(field, next);
            },
      child: Text(current),
    );
  }
}

class ScheduleReferenceCard extends StatelessWidget {
  const ScheduleReferenceCard({
    super.key,
    required this.title,
    required this.children,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

String _reason(Map<String, dynamic> row) {
  final value = row['reason']?.toString().trim() ?? '';
  return value.isEmpty ? '' : ' · $value';
}

String _intervalLabel(Map<String, dynamic> row) {
  final start = DateTime.tryParse(row['startsAt']?.toString() ?? '')?.toLocal();
  final end = DateTime.tryParse(row['endsAt']?.toString() ?? '')?.toLocal();
  if (start == null) return 'Период недоступности';
  final format = DateFormat('dd.MM.yyyy HH:mm');
  return end == null
      ? 'с ${format.format(start)}'
      : '${format.format(start)} - ${format.format(end)}';
}

T? _whenEnabled<T>(bool enabled, T callback) => enabled ? callback : null;

bool _canMutate(bool canEdit, bool saving) => canEdit && !saving;
