import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'client_forms_api.dart';

class ClientConfigurationButton extends StatelessWidget {
  const ClientConfigurationButton({
    super.key,
    required this.allowed,
    this.onPressed,
  });

  final bool allowed;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!allowed) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const ValueKey('client-configuration-open'),
      onPressed:
          onPressed ??
          () => showDialog<void>(
            context: context,
            builder: (_) => const ClientConfigurationDialog(),
          ),
      icon: const Icon(Icons.tune_rounded, size: 16),
      label: const Text('Источники и поля'),
    );
  }
}

class ClientConfigurationDialog extends ConsumerStatefulWidget {
  const ClientConfigurationDialog({super.key});

  @override
  ConsumerState<ClientConfigurationDialog> createState() =>
      _ClientConfigurationDialogState();
}

class _ClientConfigurationDialogState
    extends ConsumerState<ClientConfigurationDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _sources = const [];
  List<Map<String, dynamic>> _fields = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(clientFormsApiProvider);
      final results = await Future.wait([
        api.listSources(includeArchived: true),
        Future.wait([
          api.listFields(entityType: 'lead', includeArchived: true),
          api.listFields(entityType: 'student', includeArchived: true),
        ]),
      ]);
      if (!mounted) return;
      setState(() {
        _sources = results[0] as List<Map<String, dynamic>>;
        _fields = (results[1] as List<List<Map<String, dynamic>>>)
            .expand((items) => items)
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _configurationError(error);
      });
    }
  }

  Future<void> _mutate(Future<void> Function() mutation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await mutation();
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loading = false;
        _error = _configurationError(error);
      });
    }
  }

  Future<void> _editSource([Map<String, dynamic>? source]) async {
    final draft = await showDialog<_SourceDraft>(
      context: context,
      builder: (_) => _SourceEditor(source: source),
    );
    if (draft == null) return;
    await _mutate(() async {
      final api = ref.read(clientFormsApiProvider);
      if (source == null) {
        await api.createSource(
          canonicalName: draft.canonicalName,
          displayName: draft.displayName,
        );
      } else {
        await api.updateSource(
          source['id'].toString(),
          expectedVersion: _version(source),
          canonicalName: draft.canonicalName,
          displayName: draft.displayName,
        );
      }
    });
  }

  Future<void> _toggleSource(Map<String, dynamic> source) async {
    final active = source['isActive'] == true;
    await _mutate(() async {
      final api = ref.read(clientFormsApiProvider);
      if (active) {
        await api.archiveSource(
          source['id'].toString(),
          expectedVersion: _version(source),
        );
      } else {
        await api.updateSource(
          source['id'].toString(),
          expectedVersion: _version(source),
          isActive: true,
        );
      }
    });
  }

  Future<void> _editField([Map<String, dynamic>? field]) async {
    if (field?['isSystem'] == true) return;
    final draft = await showDialog<_FieldDraft>(
      context: context,
      builder: (_) => _FieldEditor(field: field),
    );
    if (draft == null) return;
    await _mutate(() async {
      final api = ref.read(clientFormsApiProvider);
      if (field == null) {
        await api.createField(
          entityType: draft.entityType,
          key: draft.key,
          label: draft.label,
          valueType: draft.valueType,
          required: draft.required,
          options: draft.options,
        );
      } else {
        await api.updateField(
          field['id'].toString(),
          expectedVersion: _version(field),
          label: draft.label,
          valueType: draft.valueType,
          required: draft.required,
          options: draft.valueType == 'select' ? draft.options : const [],
        );
      }
    });
  }

  Future<void> _toggleField(Map<String, dynamic> field) async {
    if (field['isSystem'] == true) return;
    final active = field['isActive'] == true;
    await _mutate(() async {
      final api = ref.read(clientFormsApiProvider);
      if (active) {
        await api.archiveField(
          field['id'].toString(),
          expectedVersion: _version(field),
        );
      } else {
        await api.updateField(
          field['id'].toString(),
          expectedVersion: _version(field),
          isActive: true,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      key: const ValueKey('client-configuration-dialog'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 480 ? AppSpace.sm : AppSpace.xl,
        vertical: AppSpace.lg,
      ),
      title: const Text('Источники и поля клиентов'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: SizedBox(
          width: width < 480 ? width : 720,
          height: 540,
          child: Column(
            children: [
              TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Источники'),
                  Tab(text: 'Дополнительные поля'),
                ],
              ),
              if (_error != null)
                MaterialBanner(
                  key: const ValueKey('client-configuration-error'),
                  content: Text(_error!),
                  actions: [
                    TextButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _ConfigurationList(
                            emptyText: 'Источники ещё не созданы.',
                            addLabel: 'Добавить источник',
                            onAdd: _busy ? null : () => _editSource(),
                            children: _sources
                                .map(
                                  (source) => _ConfigurationRow(
                                    key: ValueKey(
                                      'client-source-${source['id']}',
                                    ),
                                    title:
                                        source['displayName']?.toString() ??
                                        '—',
                                    subtitle:
                                        source['canonicalName']?.toString() ??
                                        '',
                                    active: source['isActive'] == true,
                                    locked: false,
                                    busy: _busy,
                                    onEdit: () => _editSource(source),
                                    onToggle: () => _toggleSource(source),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                          _ConfigurationList(
                            emptyText: 'Дополнительные поля ещё не созданы.',
                            addLabel: 'Добавить поле',
                            onAdd: _busy ? null : () => _editField(),
                            children: _fields
                                .map(
                                  (field) => _ConfigurationRow(
                                    key: ValueKey(
                                      'client-field-${field['id']}',
                                    ),
                                    title: field['label']?.toString() ?? '—',
                                    subtitle:
                                        '${field['entityType']} · ${field['valueType']}'
                                        '${field['required'] == true ? ' · обязательное' : ''}',
                                    active: field['isActive'] == true,
                                    locked: field['isSystem'] == true,
                                    busy: _busy,
                                    onEdit: () => _editField(field),
                                    onToggle: () => _toggleField(field),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

class _ConfigurationList extends StatelessWidget {
  const _ConfigurationList({
    required this.emptyText,
    required this.addLabel,
    required this.onAdd,
    required this.children,
  });

  final String emptyText;
  final String addLabel;
  final VoidCallback? onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(addLabel),
            ),
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? Center(child: Text(emptyText))
              : ListView(children: children),
        ),
      ],
    );
  }
}

class _ConfigurationRow extends StatelessWidget {
  const _ConfigurationRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.locked,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
  });

  final String title;
  final String subtitle;
  final bool active;
  final bool locked;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(
        '$subtitle${locked ? ' · системное' : ''}${active ? '' : ' · в архиве'}',
      ),
      trailing: Wrap(
        spacing: AppSpace.xs,
        children: [
          IconButton(
            tooltip: 'Изменить',
            onPressed: busy || locked ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: active ? 'Архивировать' : 'Восстановить',
            onPressed: busy || locked ? null : onToggle,
            icon: Icon(
              active ? Icons.archive_outlined : Icons.unarchive_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceDraft {
  const _SourceDraft(this.canonicalName, this.displayName);

  final String canonicalName;
  final String displayName;
}

class _SourceEditor extends StatefulWidget {
  const _SourceEditor({this.source});

  final Map<String, dynamic>? source;

  @override
  State<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<_SourceEditor> {
  late final _canonical = TextEditingController(
    text: widget.source?['canonicalName']?.toString() ?? '',
  );
  late final _display = TextEditingController(
    text: widget.source?['displayName']?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _canonical.dispose();
    _display.dispose();
    super.dispose();
  }

  void _submit() {
    final canonical = _canonical.text.trim();
    final display = _display.text.trim();
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(canonical) ||
        display.isEmpty) {
      setState(() {
        _error = 'Укажите код латиницей и отображаемое название.';
      });
      return;
    }
    Navigator.of(context).pop(_SourceDraft(canonical, display));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.source == null ? 'Новый источник' : 'Источник'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('source-canonical-name'),
            controller: _canonical,
            decoration: const InputDecoration(labelText: 'Код *'),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            key: const ValueKey('source-display-name'),
            controller: _display,
            decoration: InputDecoration(
              labelText: 'Название *',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }
}

class _FieldDraft {
  const _FieldDraft({
    required this.entityType,
    required this.key,
    required this.label,
    required this.valueType,
    required this.required,
    required this.options,
  });

  final String entityType;
  final String key;
  final String label;
  final String valueType;
  final bool required;
  final List<String> options;
}

class _FieldEditor extends StatefulWidget {
  const _FieldEditor({this.field});

  final Map<String, dynamic>? field;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  late String _entityType = widget.field?['entityType']?.toString() ?? 'lead';
  late String _valueType = widget.field?['valueType']?.toString() ?? 'text';
  late bool _required = widget.field?['required'] == true;
  late final _key = TextEditingController(
    text: widget.field?['key']?.toString() ?? '',
  );
  late final _label = TextEditingController(
    text: widget.field?['label']?.toString() ?? '',
  );
  late final _options = TextEditingController(
    text: (widget.field?['options'] as List? ?? const []).join(', '),
  );
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  void _submit() {
    final key = _key.text.trim();
    final label = _label.text.trim();
    final options = _options.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(key) ||
        label.isEmpty ||
        (_valueType == 'select' && options.isEmpty)) {
      setState(() {
        _error = 'Проверьте ключ, название и варианты для поля типа «Список».';
      });
      return;
    }
    Navigator.of(context).pop(
      _FieldDraft(
        entityType: _entityType,
        key: key,
        label: label,
        valueType: _valueType,
        required: _required,
        options: options,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const types = <String, String>{
      'text': 'Текст',
      'number': 'Число',
      'boolean': 'Да/нет',
      'date': 'Дата',
      'select': 'Список',
      'email': 'Email',
      'phone': 'Телефон',
    };
    final editing = widget.field != null;
    return AlertDialog(
      title: Text(editing ? 'Дополнительное поле' : 'Новое поле'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _entityType,
              decoration: const InputDecoration(labelText: 'Карточка'),
              items: const [
                DropdownMenuItem(value: 'lead', child: Text('Лид')),
                DropdownMenuItem(value: 'student', child: Text('Ученик')),
              ],
              onChanged: editing
                  ? null
                  : (value) => setState(() => _entityType = value ?? 'lead'),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              key: const ValueKey('field-key'),
              controller: _key,
              enabled: !editing,
              decoration: const InputDecoration(labelText: 'Ключ *'),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              key: const ValueKey('field-label'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Название *'),
            ),
            const SizedBox(height: AppSpace.sm),
            DropdownButtonFormField<String>(
              initialValue: _valueType,
              decoration: const InputDecoration(labelText: 'Тип'),
              items: types.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) =>
                  setState(() => _valueType = value ?? 'text'),
            ),
            if (_valueType == 'select') ...[
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _options,
                decoration: const InputDecoration(
                  labelText: 'Варианты через запятую *',
                ),
              ),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _required,
              title: const Text('Обязательное'),
              onChanged: (value) => setState(() => _required = value == true),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColor.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }
}

int _version(Map<String, dynamic> row) {
  final value = row['version'];
  return value is num ? value.toInt() : int.tryParse('$value') ?? 1;
}

String _configurationError(Object error) {
  if (error is MagicApiException && error.statusCode == 403) {
    return 'Настройка доступна только Директору и администратору системы.';
  }
  return 'Не удалось сохранить настройки: $error';
}
