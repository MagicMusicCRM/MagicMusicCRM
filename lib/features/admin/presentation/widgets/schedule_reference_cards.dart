import 'package:flutter/material.dart';

import 'schedule_reference_controller.dart';
import 'schedule_reference_busy_cards.dart';
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
              onPressed: _whenEnabled(
                canMutate &&
                    !controller.state.loading &&
                    controller.hasBranchHoursChanges,
                onSave,
              ),
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
    final canEdit = controller.canEdit;
    final canMutate =
        _canMutate(canEdit, controller.state.saving) &&
        !controller.state.loading;
    final workingHours = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Рабочие часы по дням недели',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final day in scheduleReferenceDayNames.entries)
          _TeacherRecurringDayEditor(
            weekday: day.key,
            label: day.value,
            controller: controller,
            editable: canMutate,
          ),
      ],
    );
    final absences = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TeacherDateBusySection(controller: controller, editable: canMutate),
        const Divider(height: 28),
        TeacherWeeklyBusySection(controller: controller, editable: canMutate),
      ],
    );
    return ScheduleReferenceCard(
      key: const Key('teacher-availability-editor'),
      title: 'Рабочий график и отсутствия',
      action: canEdit
          ? FilledButton(
              onPressed: canMutate && controller.hasAvailabilityChanges
                  ? onSave
                  : null,
              child: Text(
                controller.state.saving ? 'Сохранение…' : 'Сохранить график',
              ),
            )
          : null,
      children: [
        Text(
          !controller.canEdit
              ? 'Только просмотр. Редактирование выдаёт директор.'
              : controller.hasAvailabilityChanges
              ? 'Есть несохранённые изменения графика'
              : 'Укажите часы работы и периоды отсутствия',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 760
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: workingHours),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: absences),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    workingHours,
                    const SizedBox(height: 16),
                    absences,
                  ],
                ),
        ),
      ],
    );
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
              TeacherRecurringRuleRow(
                rule: rule,
                controller: controller,
                editable: editable,
              ),
        ],
      ),
    );
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
    final toggle = Row(
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
      ],
    );
    final times = [
      _timeButton(context, startKey, '09:00'),
      const Text('—'),
      _timeButton(context, endKey, '21:00'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toggle,
              if (enabled)
                Row(mainAxisAlignment: MainAxisAlignment.end, children: times),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: toggle),
            if (enabled) ...times,
          ],
        );
      },
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

T? _whenEnabled<T>(bool enabled, T callback) => enabled ? callback : null;

bool _canMutate(bool canEdit, bool saving) => canEdit && !saving;
