import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'client_forms_api.dart';

class ClientSourcesEditor extends ConsumerStatefulWidget {
  const ClientSourcesEditor({required this.canEdit, super.key});

  final bool canEdit;

  @override
  ConsumerState<ClientSourcesEditor> createState() =>
      _ClientSourcesEditorState();
}

class _ClientSourcesEditorState extends ConsumerState<ClientSourcesEditor> {
  List<Map<String, dynamic>> _sources = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sources = await ref
          .read(clientFormsApiProvider)
          .listSources(includeArchived: true);
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _sourceError(error);
      });
    }
  }

  Future<void> _edit(Map<String, dynamic>? source) async {
    final input = await showDialog<_SourceInput>(
      context: context,
      builder: (_) => _SourceDialog(source: source),
    );
    if (input == null || !mounted) return;
    await _mutate(() async {
      final api = ref.read(clientFormsApiProvider);
      if (source == null) {
        await api.createSource(
          canonicalName: 'source_${DateTime.now().microsecondsSinceEpoch}',
          displayName: input.displayName,
        );
      } else {
        await api.updateSource(
          source['id'].toString(),
          expectedVersion: (source['version'] as num).toInt(),
          displayName: input.displayName,
        );
      }
    });
  }

  Future<void> _setActive(Map<String, dynamic> source, bool active) async {
    if (!active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Архивировать источник?'),
          content: const Text(
            'Он останется в истории существующих клиентов, но его нельзя будет выбрать для новых карточек.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Архивировать'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _mutate(() {
      final api = ref.read(clientFormsApiProvider);
      final id = source['id'].toString();
      final version = (source['version'] as num).toInt();
      return active
          ? api.updateSource(id, expectedVersion: version, isActive: true)
          : api.archiveSource(id, expectedVersion: version);
    });
  }

  Future<void> _mutate(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _sourceError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Значения источника',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (widget.canEdit)
                IconButton(
                  key: const ValueKey('add-client-source'),
                  tooltip: 'Добавить источник',
                  onPressed: _busy ? null : () => _edit(null),
                  icon: const Icon(Icons.add_rounded),
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              0,
              AppSpace.md,
              AppSpace.sm,
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColor.danger),
            ),
          ),
        Expanded(
          child: _sources.isEmpty
              ? _EmptySources(
                  canEdit: widget.canEdit,
                  onCreate: () => _edit(null),
                )
              : ListView.separated(
                  itemCount: _sources.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final source = _sources[index];
                    final active = source['isActive'] == true;
                    final system = source['isSystem'] == true;
                    return ListTile(
                      key: ValueKey('client-source-${source['id']}'),
                      enabled: !_busy,
                      leading: Icon(
                        system
                            ? Icons.verified_user_outlined
                            : active
                            ? Icons.campaign_outlined
                            : Icons.inventory_2_outlined,
                      ),
                      title: Text(source['displayName']?.toString() ?? '—'),
                      subtitle: Text(
                        system
                            ? 'Системный · назначается клиентам из приложения'
                            : active
                            ? 'Активный источник'
                            : 'В архиве',
                      ),
                      trailing: widget.canEdit && !system
                          ? PopupMenuButton<String>(
                              key: ValueKey(
                                'client-source-menu-${source['id']}',
                              ),
                              enabled: !_busy,
                              onSelected: (action) {
                                if (action == 'edit') _edit(source);
                                if (action == 'archive') {
                                  _setActive(source, false);
                                }
                                if (action == 'restore') {
                                  _setActive(source, true);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Изменить'),
                                ),
                                PopupMenuItem(
                                  value: active ? 'archive' : 'restore',
                                  child: Text(
                                    active ? 'Архивировать' : 'Восстановить',
                                  ),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptySources extends StatelessWidget {
  const _EmptySources({required this.canEdit, required this.onCreate});

  final bool canEdit;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign_outlined, size: 40),
            const SizedBox(height: AppSpace.sm),
            const Text('Источники пока не созданы'),
            const SizedBox(height: AppSpace.xs),
            const Text(
              'Добавьте хотя бы один источник, чтобы создавать лидов и учеников.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColor.text2),
            ),
            if (canEdit) ...[
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                key: const ValueKey('create-first-client-source'),
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Создать первый источник'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceInput {
  const _SourceInput({required this.displayName});

  final String displayName;
}

class _SourceDialog extends StatefulWidget {
  const _SourceDialog({required this.source});

  final Map<String, dynamic>? source;

  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.source?['displayName']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.source != null;
    return AlertDialog(
      title: Text(editing ? 'Изменить источник' : 'Новый источник'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('client-source-name'),
              controller: _name,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Название *'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Укажите название'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('save-client-source'),
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(
              context,
              _SourceInput(displayName: _name.text.trim()),
            );
          },
          child: Text(editing ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}

String _sourceError(Object error) {
  if (error is MagicApiException && error.statusCode == 409) {
    return 'Источник уже изменён в другой вкладке. Обновите список.';
  }
  return 'Не удалось выполнить операцию: $error';
}
