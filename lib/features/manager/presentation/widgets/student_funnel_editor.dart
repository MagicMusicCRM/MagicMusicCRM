import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';

Future<bool?> showClientPipelineEditor(
  BuildContext context, {
  required List<Map<String, dynamic>> branches,
  String? initialBranchId,
  String initialClientType = 'student',
  VoidCallback? onPublished,
}) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Воронки клиентов',
    subtitle: 'Единые правила лидов и учеников для школы и филиалов',
    icon: Icons.view_kanban_outlined,
    builder: (_) => _StudentFunnelEditor(
      branches: branches,
      initialBranchId: initialBranchId,
      initialClientType: initialClientType,
      onPublished: onPublished,
    ),
  );
}

class _StudentFunnelEditor extends ConsumerStatefulWidget {
  const _StudentFunnelEditor({
    required this.branches,
    required this.initialBranchId,
    required this.initialClientType,
    required this.onPublished,
  });

  final List<Map<String, dynamic>> branches;
  final String? initialBranchId;
  final String initialClientType;
  final VoidCallback? onPublished;

  @override
  ConsumerState<_StudentFunnelEditor> createState() =>
      _StudentFunnelEditorState();
}

class _StudentFunnelEditorState extends ConsumerState<_StudentFunnelEditor> {
  static const _styles = <String, String>{
    'cyan': 'Бирюзовый',
    'green': 'Зелёный',
    'amber': 'Янтарный',
    'slate': 'Сланцевый',
    'gray': 'Серый',
    'red': 'Красный',
  };

  final _reason = TextEditingController();
  late String _clientType;
  String? _branchId;
  StudentFunnelConfiguration? _configuration;
  List<StudentFunnelStage> _stages = const [];
  List<Map<String, dynamic>> _revisions = const [];
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  bool _draftDirty = false;

  @override
  void initState() {
    super.initState();
    _clientType = widget.initialClientType;
    _branchId = widget.initialBranchId;
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(magicCrmServiceProvider);
      final result = await Future.wait([
        service.getClientPipeline(clientType: _clientType, branchId: _branchId),
        service.listClientPipelineRevisions(
          clientType: _clientType,
          branchId: _branchId,
        ),
      ]);
      if (!mounted) return;
      final configuration = result[0] as StudentFunnelConfiguration;
      setState(() {
        _configuration = configuration;
        _stages = configuration.stages;
        _revisions = result[1] as List<Map<String, dynamic>>;
        _loading = false;
        _saving = false;
        _draftDirty = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _saving = false;
        _error = 'Не удалось загрузить воронку: $error';
      });
    }
  }

  void _update(int index, StudentFunnelStage stage) {
    setState(() {
      _stages = [..._stages]..[index] = stage;
      _draftDirty = true;
    });
  }

  void _move(int from, int delta) {
    final to = from + delta;
    if (to < 0 || to >= _stages.length) return;
    setState(() {
      final stages = [..._stages];
      final item = stages.removeAt(from);
      stages.insert(to, item);
      _stages = stages;
      _draftDirty = true;
    });
  }

  void _addStage() {
    final key = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _stages = [
        ..._stages,
        StudentFunnelStage(
          key: key,
          label: 'Новый этап',
          style: 'gray',
          active: true,
          terminal: false,
          requiresReason: false,
          allowedTransitions: const [],
        ),
      ];
      _draftDirty = true;
    });
  }

  Future<void> _publish() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Укажите причину изменения.');
      return;
    }
    if (_stages.every((stage) => !stage.active)) {
      setState(() => _error = 'Оставьте хотя бы один активный этап.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = ref.read(magicCrmServiceProvider);
      final preview = await service.previewClientPipeline(
        clientType: _clientType,
        branchId: _branchId,
        expectedVersion: _configuration!.scopeVersion,
        stages: _stages,
      );
      if (!mounted) return;
      if (preview['valid'] != true) {
        setState(() {
          _saving = false;
          _error =
              ((preview['blockingIssues'] as List? ?? const [])
                      .whereType<Map>()
                      .map((issue) => issue['message'])
                      .join('\n'))
                  .trim();
        });
        return;
      }
      final confirmed = await _confirmPreview(preview);
      if (confirmed != true || !mounted) {
        setState(() => _saving = false);
        return;
      }
      await service.publishClientPipeline(
        clientType: _clientType,
        branchId: _branchId,
        expectedVersion: _configuration!.scopeVersion,
        reason: reason,
        stages: _stages,
      );
      if (!mounted) return;
      _changed = true;
      _draftDirty = false;
      widget.onPublished?.call();
      _reason.clear();
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось опубликовать: $error';
      });
    }
  }

  Future<void> _rollback(int targetVersion) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(magicCrmServiceProvider)
          .rollbackClientPipeline(
            clientType: _clientType,
            branchId: _branchId,
            expectedVersion: _configuration!.scopeVersion,
            targetVersion: targetVersion,
            reason: 'Откат к версии $targetVersion',
          );
      if (!mounted) return;
      _changed = true;
      _draftDirty = false;
      widget.onPublished?.call();
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось откатить версию: $error';
      });
    }
  }

  Future<void> _changeScope(String? value) async {
    if (_draftDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Сменить область?'),
          content: const Text(
            'Неопубликованные изменения текущей воронки будут сброшены.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Остаться'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сменить'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    _branchId = value == '__school__' ? null : value;
    await _load();
  }

  Future<void> _changeClientType(String? value) async {
    if (value == null || value == _clientType) return;
    if (_draftDirty && !await _confirmDiscard()) return;
    _clientType = value;
    await _load();
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить изменения?'),
        content: const Text('Неопубликованные изменения будут потеряны.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Остаться'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    return discard == true && mounted;
  }

  Future<bool?> _confirmPreview(Map<String, dynamic> preview) {
    final changes = preview['changes'] as Map? ?? const {};
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Опубликовать воронку?'),
        content: Text(
          'Новых этапов: ${changes['created'] ?? 0} · '
          'изменено: ${changes['updated'] ?? 0} · '
          'архивировано: ${changes['archived'] ?? 0}\n'
          'Затронуто клиентов: ${preview['affectedClients'] ?? 0}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Опубликовать'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestRollback(int targetVersion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Вернуть версию $targetVersion?'),
        content: const Text(
          'Текущая воронка останется в истории, а выбранный вариант будет опубликован как новая версия.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Вернуть'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _rollback(targetVersion);
  }

  Future<void> _handleBlockedClose(bool didPop, bool? result) async {
    if (didPop) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Закрыть без публикации?'),
        content: const Text('Неопубликованные изменения будут потеряны.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Остаться'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop(_changed);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_configuration == null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    return PopScope<bool>(
      canPop: !_draftDirty,
      onPopInvokedWithResult: _handleBlockedClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('pipeline-type-$_clientType'),
            initialValue: _clientType,
            decoration: const InputDecoration(labelText: 'Воронка'),
            items: const [
              DropdownMenuItem(value: 'lead', child: Text('Лиды')),
              DropdownMenuItem(value: 'student', child: Text('Ученики')),
            ],
            onChanged: _saving ? null : _changeClientType,
          ),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<String>(
            key: ValueKey('funnel-scope-${_branchId ?? 'school'}'),
            initialValue: _branchId ?? '__school__',
            decoration: const InputDecoration(labelText: 'Область настройки'),
            items: [
              const DropdownMenuItem(
                value: '__school__',
                child: Text('Вся школа'),
              ),
              ...widget.branches.map(
                (branch) => DropdownMenuItem(
                  value: branch['id']?.toString(),
                  child: Text(branch['name']?.toString() ?? 'Филиал'),
                ),
              ),
            ],
            onChanged: _saving ? null : _changeScope,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            _branchId == null
                ? 'Версия ${_configuration!.schoolVersion}'
                : _configuration!.branchVersion == 0
                ? 'Наследует общешкольную версию ${_configuration!.schoolVersion}'
                : 'Версия филиала ${_configuration!.branchVersion}',
            style: const TextStyle(color: AppColor.text2, fontSize: 12),
          ),
          const SizedBox(height: AppSpace.md),
          for (var index = 0; index < _stages.length; index++)
            _StageEditor(
              key: ValueKey(_stages[index].key),
              stage: _stages[index],
              stages: _stages,
              styles: _styles,
              canMoveUp: index > 0,
              canMoveDown: index < _stages.length - 1,
              onChanged: (stage) => _update(index, stage),
              onMoveUp: () => _move(index, -1),
              onMoveDown: () => _move(index, 1),
            ),
          OutlinedButton.icon(
            onPressed: _saving ? null : _addStage,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить этап'),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey('client-pipeline-reason'),
            controller: _reason,
            enabled: !_saving,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Причина изменения *',
              hintText: 'Например: добавили этап «Заморозка»',
            ),
            onChanged: (_) => _draftDirty = true,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(_error!, style: const TextStyle(color: AppColor.danger)),
          ],
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            key: const ValueKey('client-pipeline-publish'),
            onPressed: _saving ? null : _publish,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish_rounded),
            label: const Text('Опубликовать'),
          ),
          if (_revisions.length > 1) ...[
            const SizedBox(height: AppSpace.xl),
            Text('История', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpace.sm),
            for (final revision in _revisions.skip(1).take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Версия ${revision['version']}'),
                subtitle: Text(revision['reason']?.toString() ?? '—'),
                trailing: TextButton(
                  onPressed: _saving
                      ? null
                      : () => _requestRollback(
                          (revision['version'] as num).toInt(),
                        ),
                  child: const Text('Вернуть'),
                ),
              ),
          ],
          const SizedBox(height: AppSpace.sm),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_changed),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
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
  final bool canMoveUp;
  final bool canMoveDown;
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
                if (value != null) {
                  onChanged(stage.copyWith(style: value));
                }
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(color: AppColor.danger)),
        const SizedBox(height: AppSpace.md),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Повторить'),
        ),
      ],
    );
  }
}
