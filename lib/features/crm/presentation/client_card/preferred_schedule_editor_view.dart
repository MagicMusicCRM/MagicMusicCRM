import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

import 'preferred_schedule_editor_controller.dart';

class PreferredScheduleEditorView extends StatelessWidget {
  const PreferredScheduleEditorView({
    required this.state,
    required this.branches,
    required this.subscriptionOptions,
    required this.teachers,
    required this.rooms,
    required this.decisionCatalog,
    required this.titleController,
    required this.notesController,
    required this.isEdit,
    required this.planMode,
    required this.requireFinancialDecision,
    required this.requireSubscription,
    required this.allowOpenEnded,
    required this.showPeriod,
    required this.onTextChanged,
    required this.onBranchChanged,
    required this.onWeekdayChanged,
    required this.onPickTime,
    required this.onDurationChanged,
    required this.onLessonsPerDayChanged,
    required this.onTeacherChanged,
    required this.onRoomChanged,
    required this.onSubscriptionChanged,
    required this.onSettlementTypeChanged,
    required this.onCompensationRuleChanged,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onOpenEndedChanged,
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  static const _weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  final PreferredScheduleEditorState state;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> subscriptionOptions;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> rooms;
  final LessonDecisionCatalog? decisionCatalog;
  final TextEditingController titleController;
  final TextEditingController notesController;
  final bool isEdit;
  final bool planMode;
  final bool requireFinancialDecision;
  final bool requireSubscription;
  final bool allowOpenEnded;
  final bool showPeriod;
  final VoidCallback onTextChanged;
  final ValueChanged<String> onBranchChanged;
  final void Function(int day, bool selected) onWeekdayChanged;
  final VoidCallback onPickTime;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<int> onLessonsPerDayChanged;
  final ValueChanged<String?> onTeacherChanged;
  final ValueChanged<String?> onRoomChanged;
  final ValueChanged<String?> onSubscriptionChanged;
  final ValueChanged<String?> onSettlementTypeChanged;
  final ValueChanged<String?> onCompensationRuleChanged;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final ValueChanged<bool> onOpenEndedChanged;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      ..._planFields(),
      _branchField(),
      const SizedBox(height: AppSpace.md),
      _weekdayFields(),
      const SizedBox(height: AppSpace.md),
      _timingFields(),
      const SizedBox(height: AppSpace.md),
      _ResourceFields(
        state: state,
        teachers: teachers,
        rooms: rooms,
        onTeacherChanged: onTeacherChanged,
        onRoomChanged: onRoomChanged,
      ),
      if (planMode) ...[
        const SizedBox(height: AppSpace.md),
        _DecisionFields(
          state: state,
          catalog: decisionCatalog,
          onSettlementChanged: onSettlementTypeChanged,
          onCompensationChanged: onCompensationRuleChanged,
        ),
      ],
      ..._periodFields(),
      const SizedBox(height: AppSpace.md),
      _notesField(),
      ..._errorFields(context),
      const SizedBox(height: AppSpace.lg),
      _actions(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields,
    );
  }

  List<Widget> _planFields() {
    if (!planMode && !requireFinancialDecision) return const [];
    return [
      TextField(
        key: const ValueKey('schedule-plan-title'),
        controller: titleController,
        maxLength: 160,
        decoration: const InputDecoration(labelText: 'Название'),
        onChanged: (_) => onTextChanged(),
      ),
      if (requireSubscription) ...[
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<String>(
          menuMaxHeight: 256,
          key: const ValueKey('schedule-plan-subscription'),
          initialValue: state.subscriptionId,
          decoration: const InputDecoration(labelText: 'Абонемент'),
          items: [
            for (final option in subscriptionOptions)
              DropdownMenuItem(
                value: option['id']?.toString(),
                child: Text(option['label']?.toString() ?? 'Абонемент'),
              ),
          ],
          onChanged: onSubscriptionChanged,
        ),
      ],
      const SizedBox(height: AppSpace.md),
    ];
  }

  Widget _branchField() => DropdownButtonFormField<String>(
    menuMaxHeight: 256,
    key: const ValueKey('preferred-schedule-branch'),
    initialValue: state.branchId.isEmpty ? null : state.branchId,
    decoration: const InputDecoration(
      labelText: 'Филиал *',
      helperText: 'Постоянная серия всегда привязана к филиалу',
    ),
    items: [
      for (final branch in branches)
        DropdownMenuItem(
          value: branch['id']?.toString(),
          child: Text(branch['name']?.toString() ?? 'Филиал'),
        ),
    ],
    onChanged: isEdit
        ? null
        : (value) {
            if (value != null) onBranchChanged(value);
          },
  );

  Widget _weekdayFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Дни недели',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: AppSpace.sm),
      Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [
          for (var day = 1; day <= 7; day++)
            FilterChip(
              key: ValueKey('preferred-schedule-weekday-$day'),
              label: Text(_weekdayLabels[day - 1]),
              selected: state.weekdays.contains(day),
              onSelected: isEdit
                  ? null
                  : (selected) => onWeekdayChanged(day, selected),
            ),
        ],
      ),
    ],
  );

  Widget _timingFields() => _ResponsiveFields(
    fields: [
      InkWell(
        key: const ValueKey('preferred-schedule-time'),
        onTap: onPickTime,
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Время'),
          child: Text(state.beginTime),
        ),
      ),
      _intDropdown(
        key: const ValueKey('preferred-schedule-duration'),
        label: 'Длительность',
        value: state.durationMinutes,
        values: const [30, 45, 60, 90, 120],
        itemLabel: (value) => '$value мин',
        onChanged: onDurationChanged,
      ),
      _intDropdown(
        key: const ValueKey('preferred-schedule-lessons-per-day'),
        label: 'Занятий в день',
        helperText: 'Идут подряд',
        value: state.lessonsPerDay,
        values: const [1, 2, 3, 4],
        itemLabel: (value) => '$value',
        onChanged: isEdit ? null : onLessonsPerDayChanged,
      ),
    ],
  );

  Widget _intDropdown({
    required Key key,
    required String label,
    required int value,
    required List<int> values,
    required String Function(int) itemLabel,
    required ValueChanged<int>? onChanged,
    String? helperText,
  }) => DropdownButtonFormField<int>(
    menuMaxHeight: 256,
    key: key,
    initialValue: value,
    decoration: InputDecoration(labelText: label, helperText: helperText),
    items: [
      for (final item in values)
        DropdownMenuItem(value: item, child: Text(itemLabel(item))),
    ],
    onChanged: (selected) {
      if (selected != null) onChanged?.call(selected);
    },
  );

  List<Widget> _periodFields() => [
    if (showPeriod) ...[
      const SizedBox(height: AppSpace.md),
      _ResponsiveFields(
        fields: [
          _dateField(
            key: const ValueKey('preferred-schedule-start'),
            label: isEdit ? 'Применить с даты' : 'Дата начала',
            value: state.validFrom,
            onTap: onPickStartDate,
          ),
          if (!state.openEnded)
            _dateField(
              key: const ValueKey('preferred-schedule-end'),
              label: 'Дата окончания',
              value: state.validUntil,
              onTap: onPickEndDate,
            ),
        ],
      ),
    ],
    if (showPeriod && allowOpenEnded) ...[
      const SizedBox(height: AppSpace.sm),
      SwitchListTile.adaptive(
        key: const ValueKey('schedule-plan-open-ended'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Без даты окончания'),
        value: state.openEnded,
        onChanged: onOpenEndedChanged,
      ),
    ],
  ];

  Widget _dateField({
    required Key key,
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) => InkWell(
    key: key,
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Text(DateFormat('dd.MM.yyyy').format(value)),
    ),
  );

  Widget _notesField() => TextField(
    key: const ValueKey('preferred-schedule-notes'),
    controller: notesController,
    minLines: 2,
    maxLines: 4,
    maxLength: 500,
    decoration: const InputDecoration(
      labelText: 'Описание',
      hintText: 'Пожелания клиента и важные условия',
    ),
    onChanged: (_) => onTextChanged(),
  );

  List<Widget> _errorFields(BuildContext context) => [
    if (state.validationError != null) ...[
      const SizedBox(height: AppSpace.sm),
      Text(
        state.validationError!,
        key: const ValueKey('preferred-schedule-error'),
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 13,
        ),
      ),
    ],
  ];

  Widget _actions() => Row(
    children: [
      Expanded(
        child: OutlinedButton(onPressed: onCancel, child: const Text('Отмена')),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: FilledButton(
          key: const ValueKey('preferred-schedule-save'),
          onPressed: onSubmit,
          child: Text(isEdit ? 'Применить' : 'Создать'),
        ),
      ),
    ],
  );
}

class _ResourceFields extends StatelessWidget {
  const _ResourceFields({
    required this.state,
    required this.teachers,
    required this.rooms,
    required this.onTeacherChanged,
    required this.onRoomChanged,
  });

  final PreferredScheduleEditorState state;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> rooms;
  final ValueChanged<String?> onTeacherChanged;
  final ValueChanged<String?> onRoomChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SearchablePickerField(
        key: const ValueKey('preferred-schedule-teacher'),
        label: 'Педагог *',
        placeholder: teachers.isEmpty
            ? 'Нет назначенных в этот филиал педагогов'
            : 'Выберите педагога',
        enabled: teachers.isNotEmpty,
        selectedId: state.teacherId,
        items: [
          for (final teacher in teachers)
            SearchableSelectItem(
              id: teacher['id'].toString(),
              label:
                  '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'
                      .trim(),
            ),
        ],
        onSelected: (item) => onTeacherChanged(item?.id),
      ),
      const SizedBox(height: AppSpace.md),
      SearchablePickerField(
        key: const ValueKey('preferred-schedule-room'),
        label: 'Аудитория *',
        placeholder: rooms.isEmpty
            ? 'В филиале нет доступных аудиторий'
            : 'Выберите аудиторию',
        selectedId: state.roomId,
        items: [
          for (final room in rooms)
            SearchableSelectItem(
              id: room['id'].toString(),
              label: room['name']?.toString() ?? 'Аудитория',
            ),
        ],
        onSelected: (item) => onRoomChanged(item?.id),
      ),
    ],
  );
}

class _DecisionFields extends StatelessWidget {
  const _DecisionFields({
    required this.state,
    required this.catalog,
    required this.onSettlementChanged,
    required this.onCompensationChanged,
  });

  final PreferredScheduleEditorState state;
  final LessonDecisionCatalog? catalog;
  final ValueChanged<String?> onSettlementChanged;
  final ValueChanged<String?> onCompensationChanged;

  @override
  Widget build(BuildContext context) => _ResponsiveFields(
    fields: [
      _dropdown(
        key: const ValueKey('schedule-plan-settlement-type'),
        label: 'Тип списания *',
        helperText: 'Применится после окончания занятия',
        value: state.settlementTypeKey,
        items: catalog?.settlementTypes ?? const [],
        onChanged: onSettlementChanged,
      ),
      _dropdown(
        key: const ValueKey('schedule-plan-compensation-rule'),
        label: 'Оплата преподавателю *',
        helperText: 'Сотрудник выбирает правило явно',
        value: state.teacherCompensationRuleKey,
        items: catalog?.compensationRules ?? const [],
        onChanged: onCompensationChanged,
      ),
    ],
  );

  Widget _dropdown({
    required Key key,
    required String label,
    required String helperText,
    required String? value,
    required List<LessonDecisionCatalogItem> items,
    required ValueChanged<String?> onChanged,
  }) => DropdownButtonFormField<String>(
    menuMaxHeight: 256,
    key: key,
    initialValue: value,
    decoration: InputDecoration(labelText: label, helperText: helperText),
    items: [
      for (final item in items)
        DropdownMenuItem(value: item.key, child: Text(item.label)),
    ],
    onChanged: onChanged,
  );
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.fields});

  final List<Widget> fields;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 520) {
        return Column(
          children: [
            for (var index = 0; index < fields.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpace.md),
              fields[index],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < fields.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpace.sm),
            Expanded(child: fields[index]),
          ],
        ],
      );
    },
  );
}
