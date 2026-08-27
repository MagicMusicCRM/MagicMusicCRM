import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

class SharedTaskEditorView extends StatelessWidget {
  const SharedTaskEditorView({
    super.key,
    required this.controller,
    required this.titleController,
    required this.bodyController,
    required this.audienceOptions,
    required this.embedded,
    required this.onCancel,
    required this.onSubmit,
  });

  final SharedTaskEditorController controller;
  final TextEditingController titleController, bodyController;
  final List<SharedTaskAudienceOption> audienceOptions;
  final bool embedded;
  final VoidCallback onCancel, onSubmit;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final frozen = controller.draftFrozen;
    final options = audienceOptions
        .where((option) => option.type == draft.audienceType)
        .toList();
    final fields = SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('shared-task-title'),
              controller: titleController,
              readOnly: frozen,
              enableInteractiveSelection: !frozen,
              decoration: const InputDecoration(labelText: 'Название'),
              onChanged: controller.setTitle,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: const Key('shared-task-priority'),
              initialValue: draft.priority,
              decoration: const InputDecoration(labelText: 'Приоритет'),
              items: const [
                DropdownMenuItem(value: 'high', child: Text('Высокий')),
                DropdownMenuItem(value: 'medium', child: Text('Обычный')),
                DropdownMenuItem(value: 'low', child: Text('Низкий')),
              ],
              onChanged: frozen ? null : controller.setPriority,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyController,
              readOnly: frozen,
              enableInteractiveSelection: !frozen,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Описание'),
              onChanged: controller.setBody,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('На весь день'),
              value: draft.allDay,
              onChanged: frozen ? null : controller.setAllDay,
            ),
            SharedTaskDateTimeButton(
              label: 'Начало',
              value: draft.start,
              dateOnly: draft.allDay,
              canInteract: () => !controller.draftFrozen,
              onChanged: controller.setStart,
            ),
            if (!draft.allDay)
              SharedTaskDateTimeButton(
                label: 'Окончание',
                value: draft.end ?? draft.start.add(const Duration(hours: 1)),
                canInteract: () => !controller.draftFrozen,
                onChanged: controller.setEnd,
              ),
            if (!draft.hasValidInterval) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                'Окончание должно быть позже начала.',
                key: const Key('shared-task-interval-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Divider(height: 28),
            Text('Кому', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'user', label: Text('Сотрудники')),
                ButtonSegment(value: 'branch', label: Text('Один филиал')),
                ButtonSegment(value: 'allBranches', label: Text('Вся школа')),
              ],
              selected: {draft.audienceType},
              onSelectionChanged: frozen ? null : controller.setAudienceType,
            ),
            if (draft.audienceType != 'allBranches') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                key: const Key('shared-task-audience-target'),
                initialValue: draft.targetId,
                decoration: InputDecoration(
                  labelText: draft.audienceType == 'user'
                      ? 'Сотрудник'
                      : 'Филиал',
                ),
                items: options
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: frozen ? null : controller.setAudienceTarget,
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.canAddAudience
                  ? controller.addAudience
                  : null,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Добавить получателя'),
            ),
            Wrap(
              spacing: 6,
              children: draft.audiences
                  .map(
                    (audience) => InputChip(
                      label: Text(_audienceLabel(audience)),
                      onDeleted: frozen || draft.audiences.length == 1
                          ? null
                          : () => controller.removeAudience(audience),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpace.sm),
            _AudiencePreview(controller: controller),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Напомнить в приложении'),
              subtitle: const Text('Можно выбрать точные дату и время'),
              value: draft.reminder,
              onChanged: frozen ? null : controller.setReminder,
            ),
            if (draft.reminder)
              SharedTaskDateTimeButton(
                key: const Key('shared-task-reminder-at'),
                label: 'Напомнить',
                value: controller.effectiveReminderAt,
                canInteract: () => !controller.draftFrozen,
                onChanged: controller.setReminderAt,
              ),
            if (controller.saveError != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                'Не удалось сохранить задачу. Повторите.',
                key: const Key('shared-task-save-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
    final content = FocusScope(
      canRequestFocus: !frozen,
      child: AbsorbPointer(absorbing: frozen, child: fields),
    );
    final actions = [
      TextButton(
        onPressed: frozen ? null : onCancel,
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: controller.canSubmit ? onSubmit : null,
        child: Text(draft.created ? 'Создать' : 'Сохранить'),
      ),
    ];
    if (!embedded) {
      return AlertDialog(
        title: Text(draft.created ? 'Новая задача' : 'Изменить задачу'),
        content: content,
        actions: actions,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(child: actions.first),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: actions.last),
          ],
        ),
      ],
    );
  }

  String _audienceLabel(Map<String, dynamic> audience) {
    if (audience['type'] == 'allBranches') return 'Вся школа';
    final id = audience['targetId']?.toString();
    for (final option in audienceOptions) {
      if (option.id == id) return option.label;
    }
    return audience['type'] == 'user' ? 'Сотрудник' : 'Филиал';
  }
}

class _AudiencePreview extends StatelessWidget {
  const _AudiencePreview({required this.controller});

  final SharedTaskEditorController controller;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('shared-task-audience-preview'),
    padding: const EdgeInsets.all(AppSpace.md),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Кто получит задачу',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpace.xs),
        if (controller.previewLoading)
          const LinearProgressIndicator(
            key: Key('shared-task-audience-preview-loading'),
          )
        else if (controller.previewError != null) ...[
          const Text(
            'Не удалось проверить получателей. Задача не будет отправлена '
            'без точного расчёта.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: controller.refreshAudiencePreview,
              child: const Text('Повторить расчёт'),
            ),
          ),
        ] else if (controller.preview case final preview?) ...[
          Text(
            'Сейчас получат: ${preview['totalRecipients'] ?? 0}',
            key: const Key('shared-task-recipient-total'),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          for (final selector in controller.previewSelectors)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selector['mode'] == 'fixed'
                        ? Icons.person_outline_rounded
                        : Icons.account_tree_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      '${selector['label'] ?? 'Получатель'}: '
                      '${selector['mode'] == 'fixed' ? 'лично' : 'динамический состав'}; '
                      'сейчас ${selector['currentRecipientCount'] ?? 0}',
                    ),
                  ),
                ],
              ),
            ),
          if (preview['hasDynamicMembership'] == true) ...[
            const SizedBox(height: AppSpace.sm),
            const Text(
              'Для филиала и всей школы состав обновляется автоматически: '
              'задачу увидят сотрудники, которые входят туда на момент работы.',
            ),
          ],
        ],
      ],
    ),
  );
}

class SharedTaskDateTimeButton extends StatelessWidget {
  const SharedTaskDateTimeButton({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.canInteract,
    this.dateOnly = false,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool Function() canInteract;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: canInteract(),
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      DateFormat(dateOnly ? 'dd.MM.yyyy' : 'dd.MM.yyyy HH:mm').format(value),
    ),
    trailing: const Icon(Icons.calendar_month_outlined),
    onTap: !canInteract()
        ? null
        : () async {
            if (!canInteract()) return;
            final date = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
            );
            if (date == null || !context.mounted || !canInteract()) return;
            if (dateOnly) {
              onChanged(DateTime(date.year, date.month, date.day));
              return;
            }
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value),
            );
            if (time == null || !canInteract()) return;
            onChanged(
              DateTime(date.year, date.month, date.day, time.hour, time.minute),
            );
          },
  );
}
