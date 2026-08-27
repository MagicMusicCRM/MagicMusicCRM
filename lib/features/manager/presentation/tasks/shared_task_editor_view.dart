import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_date_time_button.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_view_contract.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

export 'shared_task_editor_date_time_button.dart';

class SharedTaskEditorView extends StatelessWidget {
  const SharedTaskEditorView({
    super.key,
    required this.contract,
    required this.titleController,
    required this.bodyController,
    required this.audienceOptions,
    required this.embedded,
    required this.onCancel,
    required this.onSubmit,
  });

  final SharedTaskEditorViewContract contract;
  final TextEditingController titleController, bodyController;
  final List<SharedTaskAudienceOption> audienceOptions;
  final bool embedded;
  final VoidCallback onCancel, onSubmit;

  @override
  Widget build(BuildContext context) {
    final snapshot = contract.snapshot;
    final draft = snapshot.draft;
    final frozen = snapshot.draftFrozen;
    final fields = SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._details(draft, frozen),
            ..._schedule(context, draft, frozen),
            ..._audience(context, snapshot, draft, frozen),
            ..._reminderAndFeedback(context, snapshot, draft, frozen),
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
        onPressed: snapshot.canSubmit ? onSubmit : null,
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

  List<Widget> _details(SharedTaskEditorDraft draft, bool frozen) => [
    TextField(
      key: const Key('shared-task-title'),
      controller: titleController,
      readOnly: frozen,
      enableInteractiveSelection: !frozen,
      decoration: const InputDecoration(labelText: 'Название'),
      onChanged: contract.setTitle,
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
      onChanged: frozen ? null : contract.setPriority,
    ),
    const SizedBox(height: 10),
    TextField(
      controller: bodyController,
      readOnly: frozen,
      enableInteractiveSelection: !frozen,
      minLines: 2,
      maxLines: 4,
      decoration: const InputDecoration(labelText: 'Описание'),
      onChanged: contract.setBody,
    ),
  ];

  List<Widget> _schedule(
    BuildContext context,
    SharedTaskEditorDraft draft,
    bool frozen,
  ) => [
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('На весь день'),
      value: draft.allDay,
      onChanged: frozen ? null : contract.setAllDay,
    ),
    SharedTaskDateTimeButton(
      label: 'Начало',
      value: draft.start,
      dateOnly: draft.allDay,
      canInteract: () => !contract.snapshot.draftFrozen,
      onChanged: contract.setStart,
    ),
    if (!draft.allDay)
      SharedTaskDateTimeButton(
        label: 'Окончание',
        value: draft.end ?? draft.start.add(const Duration(hours: 1)),
        canInteract: () => !contract.snapshot.draftFrozen,
        onChanged: contract.setEnd,
      ),
    if (!draft.hasValidInterval) ...[
      const SizedBox(height: AppSpace.xs),
      Text(
        'Окончание должно быть позже начала.',
        key: const Key('shared-task-interval-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ],
  ];

  List<Widget> _audience(
    BuildContext context,
    SharedTaskEditorViewSnapshot snapshot,
    SharedTaskEditorDraft draft,
    bool frozen,
  ) {
    final options = audienceOptions.where(
      (option) => option.type == draft.audienceType,
    );
    return [
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
        onSelectionChanged: frozen ? null : contract.setAudienceType,
      ),
      if (draft.audienceType != 'allBranches') ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          menuMaxHeight: 256,
          key: const Key('shared-task-audience-target'),
          initialValue: draft.targetId,
          decoration: InputDecoration(
            labelText: draft.audienceType == 'user' ? 'Сотрудник' : 'Филиал',
          ),
          items: [
            for (final option in options)
              DropdownMenuItem(value: option.id, child: Text(option.label)),
          ],
          onChanged: frozen ? null : contract.setAudienceTarget,
        ),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: snapshot.canAddAudience ? contract.addAudience : null,
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('Добавить получателя'),
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final audience in draft.audiences)
            InputChip(
              label: Text(_audienceLabel(audience)),
              onDeleted: frozen || draft.audiences.length == 1
                  ? null
                  : () => contract.removeAudience(audience),
            ),
        ],
      ),
      const SizedBox(height: AppSpace.sm),
      _AudiencePreview(contract: contract),
    ];
  }

  List<Widget> _reminderAndFeedback(
    BuildContext context,
    SharedTaskEditorViewSnapshot snapshot,
    SharedTaskEditorDraft draft,
    bool frozen,
  ) => [
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Напомнить в приложении'),
      subtitle: const Text('Можно выбрать точные дату и время'),
      value: draft.reminder,
      onChanged: frozen ? null : contract.setReminder,
    ),
    if (draft.reminder)
      SharedTaskDateTimeButton(
        key: const Key('shared-task-reminder-at'),
        label: 'Напомнить',
        value: snapshot.effectiveReminderAt,
        canInteract: () => !contract.snapshot.draftFrozen,
        onChanged: contract.setReminderAt,
      ),
    if (snapshot.saveError != null) ...[
      const SizedBox(height: AppSpace.sm),
      Text(
        'Не удалось сохранить задачу. Повторите.',
        key: const Key('shared-task-save-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ],
  ];

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
  const _AudiencePreview({required this.contract});

  final SharedTaskEditorViewContract contract;

  @override
  Widget build(BuildContext context) {
    final snapshot = contract.snapshot;
    return Container(
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
          if (snapshot.previewLoading)
            const LinearProgressIndicator(
              key: Key('shared-task-audience-preview-loading'),
            )
          else if (snapshot.previewError != null) ...[
            const Text(
              'Не удалось проверить получателей. Задача не будет отправлена '
              'без точного расчёта.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: contract.refreshAudiencePreview,
                child: const Text('Повторить расчёт'),
              ),
            ),
          ] else if (snapshot.preview case final preview?) ...[
            Text(
              'Сейчас получат: ${preview['totalRecipients'] ?? 0}',
              key: const Key('shared-task-recipient-total'),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            for (final selector in snapshot.previewSelectors)
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
}
