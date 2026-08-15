import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class ReferenceCatalogLifecycleDialog extends ConsumerStatefulWidget {
  const ReferenceCatalogLifecycleDialog({
    super.key,
    required this.entityType,
    required this.item,
  });

  final String entityType;
  final Map<String, dynamic> item;

  @override
  ConsumerState<ReferenceCatalogLifecycleDialog> createState() =>
      _ReferenceCatalogLifecycleDialogState();
}

class _ReferenceCatalogLifecycleDialogState
    extends ConsumerState<ReferenceCatalogLifecycleDialog> {
  final _name = TextEditingController();
  final _reason = TextEditingController();
  Map<String, dynamic>? _preview;
  List<Map<String, dynamic>> _history = const [];
  String? _error;
  bool _loading = true;
  bool _saving = false;

  String get _id => widget.item['id']?.toString() ?? '';
  Map<String, dynamic> get _entity {
    final raw = _preview?['entity'];
    return raw is Map ? Map<String, dynamic>.from(raw) : widget.item;
  }

  bool get _archived =>
      (_entity['lifecycleState'] ?? _entity['lifecycle_state']) == 'archived';
  int get _version {
    final raw = _entity['version'];
    return raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1;
  }

  bool get _branchLink => widget.entityType == 'branch_discipline';
  bool get _canRename => _preview?['canRename'] == true && !_branchLink;
  bool get _canCommit => _archived
      ? (_preview?['canRestore'] == true)
      : (_preview?['canArchive'] == true);

  List<Map<String, dynamic>> get _blockers {
    final raw = _preview?['blockers'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  @override
  void initState() {
    super.initState();
    _name.text = widget.item['name']?.toString() ?? '';
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load({String? errorAfterLoad}) async {
    if (_id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final values = await Future.wait([
        crm.previewReferenceCatalogLifecycle(
          entityType: widget.entityType,
          id: _id,
        ),
        crm.listReferenceCatalogHistory(entityType: widget.entityType, id: _id),
      ]);
      if (!mounted) return;
      final preview = values[0] as Map<String, dynamic>;
      final entity = preview['entity'];
      setState(() {
        _preview = preview;
        _history = values[1] as List<Map<String, dynamic>>;
        if (entity is Map && entity['name'] != null) {
          _name.text = entity['name'].toString();
        }
        _error = errorAfterLoad;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось проверить запись.',
        );
        _loading = false;
      });
    }
  }

  String? _validateReason() {
    final value = _reason.text.trim();
    if (value.length < 3) {
      setState(() => _error = 'Укажите понятную причину (минимум 3 символа).');
      return null;
    }
    return value;
  }

  Future<void> _renameItem() async {
    final reason = _validateReason();
    if (reason == null) return;
    final name = _name.text.trim();
    if (name.isEmpty || name == _entity['name']?.toString()) {
      setState(() => _error = 'Укажите новое название.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(magicCrmServiceProvider)
          .renameReferenceCatalogItem(
            entityType: widget.entityType,
            id: _id,
            name: name,
            expectedVersion: _version,
            reasonText: reason,
          );
      if (!mounted) return;
      _reason.clear();
      setState(() => _saving = false);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось изменить запись.',
        );
      });
      await _load(
        errorAfterLoad: userErrorMessage(
          error,
          fallback: 'Не удалось изменить запись.',
        ),
      );
    }
  }

  Future<void> _commitLifecycle() async {
    final reason = _validateReason();
    if (reason == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      if (_archived) {
        await crm.restoreReferenceCatalogItem(
          entityType: widget.entityType,
          id: _id,
          expectedVersion: _version,
          reasonText: reason,
        );
      } else {
        await crm.archiveReferenceCatalogItem(
          entityType: widget.entityType,
          id: _id,
          expectedVersion: _version,
          reasonText: reason,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить историю.',
        );
      });
      await _load(
        errorAfterLoad: userErrorMessage(
          error,
          fallback: 'Не удалось изменить запись.',
        ),
      );
    }
  }

  String get _entityLabel => switch (widget.entityType) {
    'discipline' => 'Дисциплина',
    'loss_reason' => 'Причина отказа',
    _ => 'Дисциплина филиала',
  };

  String _historyTitle(Map<String, dynamic> item) =>
      switch (item['operation']) {
        'rename' => 'Название изменено',
        'restore' => 'Запись восстановлена',
        'unassign' => 'Дисциплина отвязана',
        _ => 'Запись архивирована',
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final impact = _preview?['impact'];
    final impactValues = impact is Map
        ? impact.entries
              .where((entry) => entry.value is num && (entry.value as num) > 0)
              .toList()
        : const <MapEntry<dynamic, dynamic>>[];
    return AlertDialog(
      title: Text(_entityLabel),
      content: SizedBox(
        width: 640,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_canRename) ...[
                      TextField(
                        key: const ValueKey('reference-name-field'),
                        controller: _name,
                        enabled: !_saving,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: 'Название',
                        ),
                      ),
                      const SizedBox(height: 8),
                    ] else
                      Text(
                        _entity['name']?.toString() ?? _entityLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    Text(
                      _archived
                          ? 'Запись находится в архиве. Восстановление вернёт её в рабочие списки без потери истории.'
                          : _branchLink
                          ? 'Отвязка скроет дисциплину только в этом филиале. Сама дисциплина и история сохранятся.'
                          : 'Архивация скроет запись из новых операций. Исторические факты сохранятся.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    if (_blockers.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Сначала устраните блокеры',
                        style: TextStyle(
                          color: colors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      for (final blocker in _blockers)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.error_outline,
                            color: colors.error,
                          ),
                          title: Text(
                            '${blocker['label']}: ${blocker['count']}',
                          ),
                          subtitle: Text(
                            blocker['remediation']?.toString() ?? '',
                          ),
                        ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.verified_outlined, color: colors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _archived
                                  ? 'Родительские записи активны. Восстановление доступно.'
                                  : 'Активных блокирующих связей нет.',
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (impactValues.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in impactValues)
                            Chip(label: Text('${entry.key}: ${entry.value}')),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('reference-reason-field'),
                      controller: _reason,
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Причина изменения *',
                        hintText: 'Причина останется в журнале',
                      ),
                    ),
                    if (_canRename)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const ValueKey('rename-reference-button'),
                          onPressed: _saving ? null : _renameItem,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Сохранить название'),
                        ),
                      ),
                    if (_history.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('История (${_history.length})'),
                        children: [
                          for (final item in _history.take(10))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.history_rounded),
                              title: Text(_historyTitle(item)),
                              subtitle: Text(
                                item['reasonText']?.toString() ?? 'Не указано',
                              ),
                            ),
                        ],
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: colors.error)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        FilledButton.icon(
          key: const ValueKey('reference-lifecycle-button'),
          onPressed: _saving || _loading || !_canCommit
              ? null
              : _commitLifecycle,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _archived ? Icons.restore_rounded : Icons.archive_outlined,
                ),
          label: Text(
            _archived
                ? 'Восстановить'
                : _branchLink
                ? 'Отвязать'
                : 'В архив',
          ),
        ),
      ],
    );
  }
}
