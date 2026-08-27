import 'package:flutter/material.dart';

import 'reference_catalog_lifecycle_state.dart';

class ReferenceCatalogLifecycleContent extends StatelessWidget {
  const ReferenceCatalogLifecycleContent({
    required this.state,
    required this.nameController,
    required this.reasonController,
    required this.onRename,
    required this.onCommit,
    required this.onClose,
    super.key,
  });

  final ReferenceCatalogLifecycleState state;
  final TextEditingController nameController;
  final TextEditingController reasonController;
  final VoidCallback onRename;
  final VoidCallback onCommit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(state.entityLabel),
    content: SizedBox(width: 640, child: _body(context)),
    actions: _actions(),
  );

  Widget _body(BuildContext context) {
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._nameFields(context),
          _lifecycleDescription(context),
          ..._blockerFields(context),
          ..._impactFields(),
          const SizedBox(height: 16),
          _reasonField(),
          ..._renameFields(),
          ..._historyFields(),
          ..._errorFields(context),
        ],
      ),
    );
  }

  List<Widget> _nameFields(BuildContext context) => state.canRename
      ? [
          TextField(
            key: const ValueKey('reference-name-field'),
            controller: nameController,
            enabled: !state.saving,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          const SizedBox(height: 8),
        ]
      : [
          Text(
            state.entity['name']?.toString() ?? state.entityLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ];

  Widget _lifecycleDescription(BuildContext context) => Text(
    state.archived
        ? 'Запись находится в архиве. Восстановление вернёт её в рабочие списки без потери истории.'
        : state.branchLink
        ? 'Отвязка скроет дисциплину только в этом филиале. Сама дисциплина и история сохранятся.'
        : 'Архивация скроет запись из новых операций. Исторические факты сохранятся.',
    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );

  List<Widget> _blockerFields(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (state.blockers.isEmpty) {
      return [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.verified_outlined, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.archived
                    ? 'Родительские записи активны. Восстановление доступно.'
                    : 'Активных блокирующих связей нет.',
              ),
            ),
          ],
        ),
      ];
    }
    return [
      const SizedBox(height: 16),
      Text(
        'Сначала устраните блокеры',
        style: TextStyle(color: colors.error, fontWeight: FontWeight.w700),
      ),
      for (final blocker in state.blockers)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.error_outline, color: colors.error),
          title: Text('${blocker['label']}: ${blocker['count']}'),
          subtitle: Text(blocker['remediation']?.toString() ?? ''),
        ),
    ];
  }

  List<Widget> _impactFields() => state.impactValues.isEmpty
      ? const []
      : [
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in state.impactValues)
                Chip(label: Text('${entry.key}: ${entry.value}')),
            ],
          ),
        ];

  Widget _reasonField() => TextField(
    key: const ValueKey('reference-reason-field'),
    controller: reasonController,
    enabled: !state.saving,
    minLines: 2,
    maxLines: 4,
    maxLength: 500,
    decoration: const InputDecoration(
      labelText: 'Причина изменения *',
      hintText: 'Причина останется в журнале',
    ),
  );

  List<Widget> _renameFields() => state.canRename
      ? [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('rename-reference-button'),
              onPressed: state.saving ? null : onRename,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Сохранить название'),
            ),
          ),
        ]
      : const [];

  List<Widget> _historyFields() => state.history.isEmpty
      ? const []
      : [
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('История (${state.history.length})'),
            children: [
              for (final item in state.history.take(10))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded),
                  title: Text(state.historyTitle(item)),
                  subtitle: Text(
                    item['reasonText']?.toString() ?? 'Не указано',
                  ),
                ),
            ],
          ),
        ];

  List<Widget> _errorFields(BuildContext context) => state.error == null
      ? const []
      : [
          const SizedBox(height: 8),
          Text(
            state.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ];

  List<Widget> _actions() => [
    TextButton(
      onPressed: state.saving ? null : onClose,
      child: const Text('Закрыть'),
    ),
    FilledButton.icon(
      key: const ValueKey('reference-lifecycle-button'),
      onPressed: state.saving || state.loading || !state.canCommit
          ? null
          : onCommit,
      icon: state.saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              state.archived ? Icons.restore_rounded : Icons.archive_outlined,
            ),
      label: Text(
        state.archived
            ? 'Восстановить'
            : state.branchLink
            ? 'Отвязать'
            : 'В архив',
      ),
    ),
  ];
}
