import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';

class WorkspaceConflictBanner extends StatelessWidget {
  const WorkspaceConflictBanner({
    required this.form,
    required this.onReload,
    required this.onMerge,
    required this.onCancel,
    super.key,
  });

  final WorkspaceFormState form;
  final VoidCallback onReload;
  final VoidCallback onMerge;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final conflict = form.conflict;
    if (conflict == null) return const SizedBox.shrink();
    return MaterialBanner(
      key: ValueKey('workspace-conflict-${form.formKey}'),
      content: Text(
        'Запись изменилась на сервере '
        '(версия ${conflict.serverVersion}). Ваш ввод сохранён.',
      ),
      actions: [
        TextButton(
          key: ValueKey('workspace-conflict-reload-${form.formKey}'),
          onPressed: onReload,
          child: const Text('Загрузить заново'),
        ),
        TextButton(
          key: ValueKey('workspace-conflict-merge-${form.formKey}'),
          onPressed: onMerge,
          child: const Text('Сверить изменения'),
        ),
        TextButton(
          key: ValueKey('workspace-conflict-cancel-${form.formKey}'),
          onPressed: onCancel,
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}
