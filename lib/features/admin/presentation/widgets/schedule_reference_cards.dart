import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
            editable: controller.canEdit,
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
                onPressed: () => _addException(context),
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
                    onPressed: () => controller.removeBranchException(
                      row['date']?.toString() ?? '',
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
            onChanged: !controller.canEdit
                ? null
                : (selected) => controller.setAssignment(
                    branch['id'].toString(),
                    selected == true,
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
    return ScheduleReferenceCard(
      title: 'Доступность преподавателя',
      action: canEdit
          ? FilledButton(
              onPressed: controller.state.saving ? null : onSave,
              child: const Text('Сохранить'),
            )
          : null,
      children: [
        if (controller.availabilityLocked)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline_rounded),
            title: Text('Сложная схема доступности'),
            subtitle: Text(
              'На один день задано несколько правил. '
              'Редактор не изменяет их, чтобы не потерять данные.',
            ),
          ),
        for (final day in scheduleReferenceDayNames.entries)
          ScheduleTimeRow(
            label: day.value,
            value: draft?.recurring[day.key],
            editable: canEdit,
            startKey: 'localStart',
            endKey: 'localEnd',
            onEnabled: (enabled) =>
                controller.setRecurringEnabled(day.key, enabled),
            onTime: (field, value) =>
                controller.setRecurringTime(day.key, field, value),
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
                onPressed: () => _addInterval(context),
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
                    onPressed: () => controller.removeUnavailableInterval(row),
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
