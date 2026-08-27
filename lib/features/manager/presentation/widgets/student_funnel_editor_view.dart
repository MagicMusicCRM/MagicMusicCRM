import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor_contract.dart';

class StudentFunnelEditorView extends StatelessWidget {
  const StudentFunnelEditorView({
    required this.contract,
    required this.branches,
    required this.reasonController,
    required this.onClientTypeChanged,
    required this.onScopeChanged,
    required this.onPublish,
    required this.onRollback,
    required this.onRetry,
    required this.onClose,
    required this.onBlockedClose,
    super.key,
  });

  static const _styles = <String, String>{
    'cyan': 'Бирюзовый',
    'green': 'Зелёный',
    'amber': 'Янтарный',
    'slate': 'Сланцевый',
    'gray': 'Серый',
    'red': 'Красный',
  };

  final StudentFunnelEditorViewContract contract;
  final List<Map<String, dynamic>> branches;
  final TextEditingController reasonController;
  final ValueChanged<String?> onClientTypeChanged;
  final ValueChanged<String?> onScopeChanged;
  final VoidCallback onPublish, onRetry, onClose;
  final ValueChanged<int> onRollback;
  final Future<void> Function(bool didPop, bool? result) onBlockedClose;

  @override
  Widget build(BuildContext context) {
    final state = contract.snapshot;
    final Widget body;
    if (state.loading) {
      body = const Padding(
        padding: EdgeInsets.all(AppSpace.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (state.configuration == null) {
      body = _errorState(state.error!);
    } else {
      final configuration = state.configuration!;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._selectors(state, configuration),
          ..._stageEditors(state),
          ..._publishControls(state),
          ..._history(context, state),
          const SizedBox(height: AppSpace.sm),
          TextButton(onPressed: onClose, child: const Text('Закрыть')),
        ],
      );
    }
    return PopScope<bool>(
      canPop: !state.draftDirty,
      onPopInvokedWithResult: onBlockedClose,
      child: body,
    );
  }

  Widget _errorState(String message) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message, style: const TextStyle(color: AppColor.danger)),
      const SizedBox(height: AppSpace.md),
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Повторить'),
      ),
      TextButton(onPressed: onClose, child: const Text('Закрыть')),
    ],
  );

  List<Widget> _selectors(
    StudentFunnelEditorSnapshot state,
    StudentFunnelConfiguration configuration,
  ) => [
    DropdownButtonFormField<String>(
      menuMaxHeight: 256,
      key: ValueKey('pipeline-type-${state.clientType}'),
      initialValue: state.clientType,
      decoration: const InputDecoration(labelText: 'Воронка'),
      items: const [
        DropdownMenuItem(value: 'lead', child: Text('Лиды')),
        DropdownMenuItem(value: 'student', child: Text('Ученики')),
      ],
      onChanged: state.saving ? null : onClientTypeChanged,
    ),
    const SizedBox(height: AppSpace.md),
    DropdownButtonFormField<String>(
      menuMaxHeight: 256,
      key: ValueKey('funnel-scope-${state.branchId ?? 'school'}'),
      initialValue: state.branchId ?? '__school__',
      decoration: const InputDecoration(labelText: 'Область настройки'),
      items: [
        const DropdownMenuItem(value: '__school__', child: Text('Вся школа')),
        ...branches.map(
          (branch) => DropdownMenuItem(
            value: branch['id']?.toString(),
            child: Text(branch['name']?.toString() ?? 'Филиал'),
          ),
        ),
      ],
      onChanged: state.saving ? null : onScopeChanged,
    ),
    const SizedBox(height: AppSpace.md),
    Text(
      state.branchId == null
          ? 'Версия ${configuration.schoolVersion}'
          : configuration.branchVersion == 0
          ? 'Наследует общешкольную версию ${configuration.schoolVersion}'
          : 'Версия филиала ${configuration.branchVersion}',
      style: const TextStyle(color: AppColor.text2, fontSize: 12),
    ),
    const SizedBox(height: AppSpace.md),
  ];

  List<Widget> _stageEditors(StudentFunnelEditorSnapshot state) => [
    if (state.stages.isEmpty) ...[
      const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpace.md),
          child: Text(
            'Воронка ещё не настроена. Добавьте первый этап и опубликуйте начальную версию.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
    ],
    for (var index = 0; index < state.stages.length; index++)
      _StageEditor(
        key: ValueKey(
          '${state.clientType}:${state.branchId ?? 'school'}:'
          '${state.configuration?.scopeVersion ?? 0}:'
          '${state.stages[index].key}',
        ),
        stage: state.stages[index],
        stages: state.stages,
        styles: _styles,
        canMoveUp: index > 0,
        canMoveDown: index < state.stages.length - 1,
        onChanged: (stage) => contract.updateStage(index, stage),
        onMoveUp: () => contract.moveStage(index, -1),
        onMoveDown: () => contract.moveStage(index, 1),
      ),
    OutlinedButton.icon(
      onPressed: state.saving ? null : contract.addStage,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Добавить этап'),
    ),
  ];

  List<Widget> _publishControls(StudentFunnelEditorSnapshot state) => [
    const SizedBox(height: AppSpace.md),
    TextField(
      key: const ValueKey('client-pipeline-reason'),
      controller: reasonController,
      enabled: !state.saving,
      maxLength: 500,
      decoration: const InputDecoration(
        labelText: 'Причина изменения *',
        hintText: 'Например: добавили этап «Заморозка»',
      ),
      onChanged: contract.setReason,
    ),
    if (state.error != null) ...[
      const SizedBox(height: AppSpace.sm),
      Text(state.error!, style: const TextStyle(color: AppColor.danger)),
    ],
    const SizedBox(height: AppSpace.md),
    FilledButton.icon(
      key: const ValueKey('client-pipeline-publish'),
      onPressed: state.saving ? null : onPublish,
      icon: state.saving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.publish_rounded),
      label: const Text('Опубликовать'),
    ),
  ];

  List<Widget> _history(
    BuildContext context,
    StudentFunnelEditorSnapshot state,
  ) => [
    if (state.revisions.length > 1) ...[
      const SizedBox(height: AppSpace.xl),
      Text('История', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpace.sm),
      for (final revision in state.revisions.skip(1).take(5))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Версия ${revision['version']}'),
          subtitle: Text(revision['reason']?.toString() ?? 'Не указано'),
          trailing: TextButton(
            onPressed: state.saving
                ? null
                : () => onRollback((revision['version'] as num).toInt()),
            child: const Text('Вернуть'),
          ),
        ),
    ],
  ];
}

class _StageEditor extends StatelessWidget {
  const _StageEditor({
    required this.stage,
    required this.stages,
    required this.styles,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    super.key,
  });

  final StudentFunnelStage stage;
  final List<StudentFunnelStage> stages;
  final Map<String, String> styles;
  final bool canMoveUp, canMoveDown;
  final ValueChanged<StudentFunnelStage> onChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('client-pipeline-stage-${stage.key}'),
                    initialValue: stage.label,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Название этапа',
                      counterText: '',
                    ),
                    onChanged: (value) =>
                        onChanged(stage.copyWith(label: value)),
                  ),
                ),
                IconButton(
                  tooltip: 'Поднять',
                  onPressed: canMoveUp ? onMoveUp : null,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                IconButton(
                  tooltip: 'Опустить',
                  onPressed: canMoveDown ? onMoveDown : null,
                  icon: const Icon(Icons.arrow_downward_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              initialValue: stage.style,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Цвет'),
              items:
                  {
                        if (!styles.containsKey(stage.style))
                          stage.style: stage.style,
                        ...styles,
                      }.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            entry.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
              onChanged: (value) {
                if (value != null) onChanged(stage.copyWith(style: value));
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Активен'),
              value: stage.active,
              onChanged: (value) => onChanged(stage.copyWith(active: value)),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Финальный этап'),
              value: stage.terminal,
              onChanged: (value) => onChanged(stage.copyWith(terminal: value)),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Требовать причину перехода'),
              value: stage.requiresReason,
              onChanged: (value) =>
                  onChanged(stage.copyWith(requiresReason: value)),
            ),
            const SizedBox(height: AppSpace.sm),
            const Text(
              'Куда можно перенести',
              style: TextStyle(color: AppColor.text2, fontSize: 12),
            ),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final target in stages.where(
                  (target) => target.key != stage.key && target.active,
                ))
                  FilterChip(
                    label: Text(target.label),
                    selected: stage.allowedTransitions.contains(target.key),
                    onSelected: (selected) {
                      final transitions = stage.allowedTransitions.toSet();
                      selected
                          ? transitions.add(target.key)
                          : transitions.remove(target.key);
                      onChanged(
                        stage.copyWith(
                          allowedTransitions: transitions.toList(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
