import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart';

enum _ReferenceCatalogView { disciplines, lossReasons }

class ReferenceCatalogSettings extends ConsumerStatefulWidget {
  const ReferenceCatalogSettings({super.key, required this.canEdit});

  final bool canEdit;

  @override
  ConsumerState<ReferenceCatalogSettings> createState() =>
      _ReferenceCatalogSettingsState();
}

class _ReferenceCatalogSettingsState
    extends ConsumerState<ReferenceCatalogSettings> {
  final _search = TextEditingController();
  _ReferenceCatalogView _view = _ReferenceCatalogView.disciplines;
  List<Map<String, dynamic>> _disciplines = const [];
  List<Map<String, dynamic>> _lossReasons = const [];
  bool _showArchived = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final values = await Future.wait([
        crm.listDisciplines(includeArchived: _showArchived),
        crm.listLossReasons(includeArchived: _showArchived),
      ]);
      if (!mounted) return;
      setState(() {
        _disciplines = values[0];
        _lossReasons = values[1];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить записи.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final result = await showDialog<({String name, String kind})>(
      context: context,
      builder: (_) => _CreateReferenceDialog(
        lossReason: _view == _ReferenceCatalogView.lossReasons,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final crm = ref.read(magicCrmServiceProvider);
      if (_view == _ReferenceCatalogView.disciplines) {
        await crm.createDiscipline(result.name);
      } else {
        await crm.createLossReason(name: result.name, kind: result.kind);
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(error, fallback: 'Не удалось создать запись.'),
          ),
        ),
      );
    }
  }

  Future<void> _openLifecycle(Map<String, dynamic> item) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ReferenceCatalogLifecycleDialog(
        entityType: _view == _ReferenceCatalogView.disciplines
            ? 'discipline'
            : 'loss_reason',
        item: item,
      ),
    );
    if (changed == true) await _load();
  }

  List<Map<String, dynamic>> get _visibleItems {
    final source = _view == _ReferenceCatalogView.disciplines
        ? _disciplines
        : _lossReasons;
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source
        .where(
          (item) =>
              (item['name']?.toString().toLowerCase() ?? '').contains(query),
        )
        .toList();
  }

  String _subtitle(Map<String, dynamic> item) {
    final archived =
        (item['lifecycle_state'] ?? item['lifecycleState']) == 'archived';
    if (archived) {
      final reason = item['archive_reason'] ?? item['archiveReason'];
      return 'В архиве${reason == null ? '' : ' • $reason'}';
    }
    if (_view == _ReferenceCatalogView.lossReasons) {
      final kind = item['kind'] == 'paused' ? 'пауза' : 'отказ';
      final uses = item['historicalUses'];
      return '$kind${uses is num && uses > 0 ? ' • использовано: $uses' : ''}';
    }
    final usage = item['active_usage'];
    if (usage is! Map) return 'Активна';
    final total = usage.values.whereType<num>().fold<int>(
      0,
      (sum, value) => sum + value.toInt(),
    );
    return total == 0 ? 'Нет активных связей' : 'Активных связей: $total';
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_ReferenceCatalogView>(
                segments: const [
                  ButtonSegment(
                    value: _ReferenceCatalogView.disciplines,
                    label: Text('Дисциплины'),
                    icon: Icon(Icons.school_outlined),
                  ),
                  ButtonSegment(
                    value: _ReferenceCatalogView.lossReasons,
                    label: Text('Причины отказа'),
                    icon: Icon(Icons.rule_folder_outlined),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (value) =>
                    setState(() => _view = value.first),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Поиск по справочнику',
                  ),
                ),
              ),
              FilterChip(
                selected: _showArchived,
                onSelected: widget.canEdit
                    ? (value) {
                        setState(() => _showArchived = value);
                        _load();
                      }
                    : null,
                avatar: const Icon(Icons.archive_outlined, size: 18),
                label: const Text('Показать архив'),
              ),
              if (widget.canEdit)
                FilledButton.icon(
                  key: const ValueKey('create-reference-button'),
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    _view == _ReferenceCatalogView.disciplines
                        ? 'Новая дисциплина'
                        : 'Новая причина',
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Не удалось загрузить справочники.'),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : items.isEmpty
              ? const Center(child: Text('В справочнике пока нет записей.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final archived =
                          (item['lifecycle_state'] ?? item['lifecycleState']) ==
                          'archived';
                      return ListTile(
                        key: ValueKey('reference-${item['id']}'),
                        leading: Icon(
                          archived
                              ? Icons.inventory_2_outlined
                              : _view == _ReferenceCatalogView.disciplines
                              ? Icons.school_outlined
                              : Icons.rule_folder_outlined,
                        ),
                        title: Text(item['name']?.toString() ?? 'Без названия'),
                        subtitle: Text(_subtitle(item)),
                        trailing: widget.canEdit
                            ? IconButton(
                                tooltip: archived
                                    ? 'Восстановить или переименовать'
                                    : 'Изменить или архивировать',
                                onPressed: () => _openLifecycle(item),
                                icon: Icon(
                                  archived
                                      ? Icons.restore_rounded
                                      : Icons.more_horiz_rounded,
                                ),
                              )
                            : null,
                        onTap: widget.canEdit
                            ? () => _openLifecycle(item)
                            : null,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _CreateReferenceDialog extends StatefulWidget {
  const _CreateReferenceDialog({required this.lossReason});

  final bool lossReason;

  @override
  State<_CreateReferenceDialog> createState() => _CreateReferenceDialogState();
}

class _CreateReferenceDialogState extends State<_CreateReferenceDialog> {
  final _name = TextEditingController();
  String _kind = 'lost';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название.');
      return;
    }
    Navigator.pop(context, (name: name, kind: _kind));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.lossReason ? 'Новая причина' : 'Новая дисциплина'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('new-reference-name-field'),
              controller: _name,
              autofocus: true,
              maxLength: 120,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Название *'),
            ),
            if (widget.lossReason) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Тип'),
                items: const [
                  DropdownMenuItem(value: 'lost', child: Text('Отказ')),
                  DropdownMenuItem(value: 'paused', child: Text('Пауза')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _kind = value);
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('submit-reference-button'),
          onPressed: _submit,
          child: const Text('Создать'),
        ),
      ],
    );
  }
}
