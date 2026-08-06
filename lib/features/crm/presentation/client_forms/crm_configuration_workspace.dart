import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor.dart';

import 'client_forms_api.dart';

const _selectionFieldTypes = {
  'select',
  'radio',
  'multi_select',
  'checkbox_group',
};

typedef _FieldEditorResult = ({
  Map<String, dynamic> field,
  List<Map<String, dynamic>> createdOptionSets,
});

class CrmConfigurationRouteScreen extends ConsumerWidget {
  const CrmConfigurationRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(capabilitySnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Настройки / Конфигурация CRM'),
      ),
      body: access.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Не удалось проверить доступ.')),
        data: (snapshot) => snapshot.allows('config.crm.read')
            ? const CrmConfigurationWorkspace()
            : const Center(
                child: Text('Недостаточно прав для конфигурации CRM.'),
              ),
      ),
    );
  }
}

Future<void> showCrmConfigurationWorkspace(BuildContext context) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const CrmConfigurationRouteScreen()),
  );
}

class CrmConfigurationWorkspace extends ConsumerStatefulWidget {
  const CrmConfigurationWorkspace({super.key});

  @override
  ConsumerState<CrmConfigurationWorkspace> createState() =>
      _CrmConfigurationWorkspaceState();
}

class _CrmConfigurationWorkspaceState
    extends ConsumerState<CrmConfigurationWorkspace> {
  static const _areas = <(String, String, IconData)>[
    ('fields', 'Поля и категории', Icons.dynamic_form_outlined),
    ('options', 'Варианты для полей', Icons.list_alt_outlined),
    ('settings', 'Бизнес-параметры', Icons.tune_rounded),
    ('funnel', 'Воронки клиентов', Icons.view_kanban_outlined),
    ('history', 'История версий', Icons.history_rounded),
  ];
  static const _fieldTypes = <String, String>{
    'text': 'Текст',
    'textarea': 'Многострочный текст',
    'number': 'Число',
    'money': 'Деньги',
    'duration': 'Длительность',
    'boolean': 'Флажок',
    'toggle': 'Переключатель',
    'date': 'Дата',
    'datetime': 'Дата и время',
    'select': 'Один вариант',
    'radio': 'Радиокнопки',
    'multi_select': 'Несколько вариантов',
    'checkbox_group': 'Группа флажков',
    'email': 'Email',
    'phone': 'Телефон',
    'url': 'Ссылка',
  };

  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _revisions = const [];
  Map<String, dynamic>? _snapshot;
  String _area = 'fields';
  String? _branchId;
  String? _selectedKey;
  int _baseVersion = 0;
  bool _dirty = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  CapabilitySnapshot? get _access =>
      ref.read(capabilitySnapshotProvider).asData?.value;
  bool get _canEdit => _access?.allows('config.crm.edit') == true;
  bool get _canPublish => _access?.allows('config.crm.publish') == true;
  bool get _isManager => _access?.role == 'manager';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    try {
      final branches = await ref.read(clientFormsApiProvider).listBranches();
      if (!mounted) return;
      _branches = branches;
      if (_isManager) _branchId = branches.firstOrNull?['id']?.toString();
      await _load();
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(clientFormsApiProvider);
      final results = await Future.wait([
        api.getConfigurationDraft(branchId: _branchId),
        api.listConfigurationRevisions(branchId: _branchId),
      ]);
      final draft = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      final snapshot = _copyMap(draft['snapshot']);
      final migratedInlineOptions =
          _branchId == null && _migrateInlineFieldOptions(snapshot);
      setState(() {
        _baseVersion = (draft['baseVersion'] as num?)?.toInt() ?? 0;
        _snapshot = snapshot;
        _dirty = draft['dirty'] == true || migratedInlineOptions;
        _revisions = results[1] as List<Map<String, dynamic>>;
        _selectedKey = null;
        _loading = false;
        _busy = false;
      });
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _busy = false;
      _error = _message(error);
    });
  }

  List<Map<String, dynamic>> _items(String key) {
    final raw = _snapshot?[key];
    return raw is List
        ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
  }

  void _replaceItems(String key, List<Map<String, dynamic>> items) {
    setState(() {
      _snapshot = {...?_snapshot, key: items};
      _dirty = true;
    });
  }

  Future<void> _saveDraft() async {
    if (_snapshot == null || !_canEdit) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(clientFormsApiProvider)
          .saveConfigurationDraft(
            branchId: _branchId,
            baseVersion: _baseVersion,
            snapshot: _snapshot!,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dirty = true;
      });
      _toast('Черновик сохранён');
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _previewAndPublish() async {
    if (_snapshot == null || !_canPublish) return;
    setState(() => _busy = true);
    try {
      final impact = await ref
          .read(clientFormsApiProvider)
          .previewConfiguration(
            branchId: _branchId,
            baseVersion: _baseVersion,
            snapshot: _snapshot!,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      final reason = await _showImpact(impact);
      if (reason == null || !mounted) return;
      setState(() => _busy = true);
      await ref
          .read(clientFormsApiProvider)
          .publishConfiguration(
            branchId: _branchId,
            baseVersion: _baseVersion,
            reason: reason,
            snapshot: _snapshot!,
          );
      if (!mounted) return;
      _toast('Конфигурация опубликована');
      await _load();
    } catch (error) {
      _fail(error);
    }
  }

  Future<String?> _showImpact(Map<String, dynamic> impact) async {
    var reason = '';
    final valid = impact['valid'] == true;
    final changes = impact['changes'] as Map? ?? const {};
    final screens = (impact['affectedScreens'] as List? ?? const []).join(', ');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          valid ? 'Предпросмотр публикации' : 'Публикация заблокирована',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Новых полей: ${changes['fieldsCreated'] ?? 0} · '
                  'изменено: ${changes['fieldsUpdated'] ?? 0} · '
                  'архивировано: ${changes['fieldsArchived'] ?? 0}',
                ),
                const SizedBox(height: AppSpace.sm),
                Text('Затронутые экраны: ${screens.isEmpty ? 'нет' : screens}'),
                for (final issue
                    in (impact['blockingIssues'] as List? ?? const []))
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.sm),
                    child: Text(
                      '• ${(issue as Map)['message']}',
                      style: const TextStyle(color: AppColor.danger),
                    ),
                  ),
                if (valid) ...[
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    onChanged: (value) => reason = value,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Причина публикации *',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
          if (valid)
            FilledButton(
              onPressed: () {
                final value = reason.trim();
                if (value.isNotEmpty) Navigator.pop(context, value);
              },
              child: const Text('Опубликовать'),
            ),
        ],
      ),
    );
    return result;
  }

  Future<void> _rollback(Map<String, dynamic> revision) async {
    if (!_canPublish) return;
    final reason = await _askReason('Откат к версии ${revision['version']}');
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(clientFormsApiProvider)
          .rollbackConfiguration(
            branchId: _branchId,
            expectedVersion: _baseVersion,
            targetVersion: (revision['version'] as num).toInt(),
            reason: reason,
          );
      if (!mounted) return;
      _toast('Откат опубликован новой версией');
      await _load();
    } catch (error) {
      _fail(error);
    }
  }

  Future<String?> _askReason(String title) async {
    var reason = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          onChanged: (value) => reason = value,
          decoration: const InputDecoration(labelText: 'Причина *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.trim().isNotEmpty) {
                Navigator.pop(context, reason.trim());
              }
            },
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.sm),
            OutlinedButton(
              onPressed: _loadInitial,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        _toolbar(),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >= 900 ? _desktop() : _compact(),
          ),
        ),
      ],
    );
  }

  Widget _toolbar() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 270,
              child: DropdownButtonFormField<String?>(
                key: const ValueKey('configuration-scope'),
                initialValue: _branchId,
                decoration: const InputDecoration(
                  labelText: 'Область действия',
                ),
                items: [
                  if (!_isManager)
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Вся школа'),
                    ),
                  ..._branches.map(
                    (branch) => DropdownMenuItem<String?>(
                      value: branch['id']?.toString(),
                      child: Text(branch['name']?.toString() ?? 'Филиал'),
                    ),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() => _branchId = value);
                        _load();
                      },
              ),
            ),
            Chip(
              avatar: Icon(
                _dirty ? Icons.edit_note_rounded : Icons.verified_outlined,
                size: 18,
              ),
              label: Text(
                '${_dirty ? 'Черновик' : 'Опубликовано'} · версия $_baseVersion',
              ),
            ),
            if (_canEdit)
              OutlinedButton.icon(
                onPressed: _busy || !_dirty ? null : _saveDraft,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Сохранить черновик'),
              ),
            if (_canPublish)
              FilledButton.icon(
                key: const ValueKey('configuration-publish'),
                onPressed: _busy || !_dirty ? null : _previewAndPublish,
                icon: const Icon(Icons.publish_rounded),
                label: const Text('Проверить и опубликовать'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _desktop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 230, child: _areaList()),
        const VerticalDivider(width: 1),
        SizedBox(width: 360, child: _areaContent()),
        const VerticalDivider(width: 1),
        Expanded(child: _editorPane()),
      ],
    );
  }

  Widget _compact() {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            children: [
              for (final area in _areas)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.xs),
                  child: ChoiceChip(
                    label: Text(area.$2),
                    selected: _area == area.$1,
                    onSelected: (_) => setState(() {
                      _area = area.$1;
                      _selectedKey = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _selectedKey == null ? _areaContent() : _editorPane()),
      ],
    );
  }

  Widget _areaList() {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.sm),
      children: [
        for (final area in _areas)
          ListTile(
            selected: _area == area.$1,
            leading: Icon(area.$3),
            title: Text(area.$2),
            onTap: () => setState(() {
              _area = area.$1;
              _selectedKey = null;
            }),
          ),
      ],
    );
  }

  Widget _areaContent() => switch (_area) {
    'fields' => _fieldList(),
    'options' => _optionSetList(),
    'settings' => _settingList(),
    'funnel' => _funnelEntry(),
    'history' => _historyList(),
    _ => const SizedBox.shrink(),
  };

  Widget _fieldList() {
    final fields = _items('fields');
    final categories = _items('categories');
    return _listPane(
      title: 'Поля форм и карточек',
      addLabel: 'Добавить поле',
      onAdd: !_canEdit || _branchId != null ? null : () => _editField(null),
      children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text('Категории · ${categories.length}'),
          trailing: _canEdit && _branchId == null
              ? IconButton(
                  tooltip: 'Добавить категорию',
                  onPressed: _editCategory,
                  icon: const Icon(Icons.create_new_folder_outlined),
                )
              : null,
        ),
        for (final category in categories)
          Padding(
            padding: const EdgeInsets.only(left: AppSpace.lg),
            child: ListTile(
              dense: true,
              title: Text(category['label']?.toString() ?? ''),
              subtitle: Text(category['key']?.toString() ?? ''),
            ),
          ),
        const Divider(),
        ...fields.map((field) {
          final key = '${field['entityType']}:${field['key']}';
          return ListTile(
            selected: _selectedKey == key,
            title: Text(field['label']?.toString() ?? 'Поле'),
            subtitle: Text(
              '${field['entityType'] == 'lead' ? 'Лид' : 'Ученик'} · '
              '${_fieldTypes[field['valueType']] ?? field['valueType']}',
            ),
            trailing: field['system'] == true
                ? const Tooltip(
                    message: 'Системное поле',
                    child: Icon(Icons.lock_outline),
                  )
                : null,
            onTap: () => setState(() => _selectedKey = key),
          );
        }),
      ],
    );
  }

  Widget _optionSetList() {
    final sets = _items('optionSets');
    return _listPane(
      title: 'Наборы вариантов для полей',
      addLabel: 'Добавить набор',
      onAdd: !_canEdit || _branchId != null ? null : () => _editOptionSet(null),
      children: [
        const ListTile(
          leading: Icon(Icons.info_outline_rounded),
          title: Text('Один список — для нескольких полей'),
          subtitle: Text(
            'Например, общий набор «Направления» можно использовать в карточках лида и ученика.',
          ),
        ),
        ...sets.map((set) {
          final key = set['key']?.toString() ?? '';
          return ListTile(
            selected: _selectedKey == key,
            title: Text(set['label']?.toString() ?? key),
            subtitle: Text(
              '${(set['options'] as List? ?? const []).length} вариантов',
            ),
            onTap: () => setState(() => _selectedKey = key),
          );
        }),
      ],
    );
  }

  Widget _settingList() {
    return _listPane(
      title: 'Безопасные бизнес-параметры',
      children: _items('businessSettings').map((setting) {
        final key = setting['key']?.toString() ?? '';
        return ListTile(
          selected: _selectedKey == key,
          title: Text(setting['label']?.toString() ?? key),
          subtitle: Text('${setting['value']} ${setting['unit'] ?? ''}'),
          onTap: () => setState(() => _selectedKey = key),
        );
      }).toList(),
    );
  }

  Widget _funnelEntry() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: FilledButton.icon(
          onPressed: () => showClientPipelineEditor(
            context,
            branches: _branches,
            initialBranchId: _branchId,
          ),
          icon: const Icon(Icons.view_kanban_outlined),
          label: const Text('Настроить воронки лидов и учеников'),
        ),
      ),
    );
  }

  Widget _historyList() {
    return _listPane(
      title: 'Неизменяемые версии',
      children: _revisions
          .map(
            (revision) => ListTile(
              title: Text('Версия ${revision['version']}'),
              subtitle: Text(revision['reason']?.toString() ?? ''),
              trailing: _canPublish && revision['version'] != _baseVersion
                  ? IconButton(
                      tooltip: 'Опубликовать откат к этой версии',
                      onPressed: _busy ? null : () => _rollback(revision),
                      icon: const Icon(Icons.restore_rounded),
                    )
                  : null,
            ),
          )
          .toList(),
    );
  }

  Widget _listPane({
    required String title,
    String? addLabel,
    VoidCallback? onAdd,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (addLabel != null)
                IconButton(
                  tooltip: addLabel,
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                ),
            ],
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? const Center(child: Text('Пока нет элементов'))
              : ListView(children: children),
        ),
      ],
    );
  }

  Widget _editorPane() {
    if (_selectedKey == null) {
      return const Center(
        child: Text('Выберите элемент для просмотра и настройки'),
      );
    }
    if (_area == 'fields') {
      final field = _items('fields')
          .where(
            (item) => '${item['entityType']}:${item['key']}' == _selectedKey,
          )
          .firstOrNull;
      return field == null ? const SizedBox.shrink() : _fieldPreview(field);
    }
    if (_area == 'options') {
      final set = _items(
        'optionSets',
      ).where((item) => item['key']?.toString() == _selectedKey).firstOrNull;
      return set == null ? const SizedBox.shrink() : _optionSetPreview(set);
    }
    if (_area == 'settings') {
      final setting = _items(
        'businessSettings',
      ).where((item) => item['key']?.toString() == _selectedKey).firstOrNull;
      return setting == null
          ? const SizedBox.shrink()
          : _settingEditor(setting);
    }
    return const SizedBox.shrink();
  }

  Widget _fieldPreview(Map<String, dynamic> field) {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                field['label'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (_canEdit && _branchId == null)
              OutlinedButton.icon(
                onPressed: () => _editField(field),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Изменить'),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        _property('Стабильный ключ', field['key']),
        _property('Объект', field['entityType'] == 'lead' ? 'Лид' : 'Ученик'),
        _property('Тип', _fieldTypes[field['valueType']] ?? field['valueType']),
        if (_selectionFieldTypes.contains(field['valueType']))
          _property('Набор вариантов', field['optionSetKey']),
        _property('Категория', field['categoryKey']),
        _property('Ширина', field['width']),
        _property(
          'Размещения',
          (field['placements'] as List? ?? const []).join(', '),
        ),
        _property(
          'Состояние',
          field['active'] == true ? 'Активно' : 'В архиве',
        ),
        const SizedBox(height: AppSpace.lg),
        Text('Предпросмотр', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpace.sm),
        TextFormField(
          enabled: false,
          decoration: InputDecoration(labelText: field['label']?.toString()),
        ),
      ],
    );
  }

  Widget _optionSetPreview(Map<String, dynamic> set) {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                set['label'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (_canEdit && _branchId == null)
              OutlinedButton.icon(
                onPressed: () => _editOptionSet(set),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Изменить'),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        for (final option in (set['options'] as List? ?? const []))
          ListTile(
            leading: const Icon(Icons.drag_indicator_rounded),
            title: Text((option as Map)['label']?.toString() ?? ''),
            subtitle: Text(option['key']?.toString() ?? ''),
            trailing: option['active'] == true
                ? const Icon(
                    Icons.check_circle_outline,
                    color: AppColor.success,
                  )
                : const Icon(Icons.archive_outlined),
          ),
      ],
    );
  }

  Widget _settingEditor(Map<String, dynamic> setting) {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        Text(
          setting['label'],
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          initialValue: setting['value']?.toString(),
          enabled: _canEdit,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Значение, ${setting['unit']}',
            helperText: 'Допустимо ${setting['min']}–${setting['max']}',
          ),
          onChanged: (value) {
            final number = num.tryParse(value);
            if (number == null) return;
            final items = _items('businessSettings');
            final index = items.indexWhere(
              (item) => item['key'] == setting['key'],
            );
            items[index] = {...items[index], 'value': number};
            setState(() {
              _snapshot = {...?_snapshot, 'businessSettings': items};
              _dirty = true;
            });
          },
        ),
        if (_branchId != null)
          const Padding(
            padding: EdgeInsets.only(top: AppSpace.md),
            child: Text(
              'Изменяется только значение филиала; схема наследуется от школы.',
            ),
          ),
      ],
    );
  }

  Future<void> _editField(Map<String, dynamic>? current) async {
    final categories = _items('categories');
    final result = await showDialog<_FieldEditorResult>(
      context: context,
      builder: (_) => _FieldEditorDialog(
        field: current,
        categories: categories,
        optionSets: _items('optionSets'),
        fieldTypes: _fieldTypes,
      ),
    );
    if (result == null) return;
    if (result.createdOptionSets.isNotEmpty) {
      _replaceItems('optionSets', [
        ..._items('optionSets'),
        ...result.createdOptionSets,
      ]);
    }
    final draft = result.field;
    final fields = _items('fields');
    final index = current == null
        ? -1
        : fields.indexWhere(
            (field) =>
                field['entityType'] == current['entityType'] &&
                field['key'] == current['key'],
          );
    if (index < 0) {
      fields.add(draft);
    } else {
      fields[index] = {...?current, ...draft};
    }
    _replaceItems('fields', fields);
    setState(() => _selectedKey = '${draft['entityType']}:${draft['key']}');
  }

  Future<void> _editCategory() async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CategoryEditorDialog(),
    );
    if (draft == null) return;
    final categories = _items('categories');
    categories.add({...draft, 'order': categories.length, 'active': true});
    _replaceItems('categories', categories);
  }

  Future<void> _editOptionSet(Map<String, dynamic>? current) async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _OptionSetEditorDialog(optionSet: current),
    );
    if (draft == null) return;
    final sets = _items('optionSets');
    final index = current == null
        ? -1
        : sets.indexWhere((set) => set['key'] == current['key']);
    if (index < 0) {
      sets.add(draft);
    } else {
      sets[index] = draft;
    }
    _replaceItems('optionSets', sets);
    setState(() => _selectedKey = draft['key']?.toString());
  }

  Widget _property(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: const TextStyle(color: AppColor.text2)),
        ),
        Expanded(child: Text(value?.toString() ?? '—')),
      ],
    ),
  );

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FieldEditorDialog extends StatefulWidget {
  const _FieldEditorDialog({
    required this.field,
    required this.categories,
    required this.optionSets,
    required this.fieldTypes,
  });

  final Map<String, dynamic>? field;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> optionSets;
  final Map<String, String> fieldTypes;

  @override
  State<_FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<_FieldEditorDialog> {
  late final _key = TextEditingController(
    text: widget.field?['key']?.toString() ?? '',
  );
  late final _label = TextEditingController(
    text: widget.field?['label']?.toString() ?? '',
  );
  late final List<Map<String, dynamic>> _optionSets = widget.optionSets
      .map((set) => Map<String, dynamic>.from(set))
      .toList();
  final List<Map<String, dynamic>> _createdOptionSets = [];
  late String _entity = widget.field?['entityType']?.toString() ?? 'lead';
  late String _type = widget.field?['valueType']?.toString() ?? 'text';
  late String _category =
      widget.field?['categoryKey']?.toString() ??
      widget.categories.firstOrNull?['key']?.toString() ??
      'general';
  late String _width = widget.field?['width']?.toString() ?? 'full';
  late bool _required = widget.field?['required'] == true;
  late bool _active = widget.field?['active'] != false;
  late String? _optionSetKey = widget.field?['optionSetKey']?.toString();
  String? _optionSetError;

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final system = widget.field?['system'] == true;
    final selection = _selectionFieldTypes.contains(_type);
    return AlertDialog(
      title: Text(widget.field == null ? 'Новое поле' : 'Настройка поля'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Название *'),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _key,
                enabled: widget.field == null,
                decoration: const InputDecoration(
                  labelText: 'Стабильный ключ *',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _entity,
                      decoration: const InputDecoration(labelText: 'Объект'),
                      items: const [
                        DropdownMenuItem(value: 'lead', child: Text('Лид')),
                        DropdownMenuItem(
                          value: 'student',
                          child: Text('Ученик'),
                        ),
                      ],
                      onChanged: widget.field == null
                          ? (v) => setState(() => _entity = v!)
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Тип'),
                      items: widget.fieldTypes.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: system
                          ? null
                          : (v) => setState(() {
                              _type = v!;
                              if (!_selectionFieldTypes.contains(_type)) {
                                _optionSetKey = null;
                                _optionSetError = null;
                              }
                            }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: const InputDecoration(labelText: 'Категория'),
                      items: widget.categories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category['key']?.toString(),
                              child: Text(category['label']?.toString() ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _width,
                      decoration: const InputDecoration(labelText: 'Ширина'),
                      items: const [
                        DropdownMenuItem(
                          value: 'third',
                          child: Text('Треть строки'),
                        ),
                        DropdownMenuItem(
                          value: 'half',
                          child: Text('Половина'),
                        ),
                        DropdownMenuItem(
                          value: 'full',
                          child: Text('Вся строка'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _width = v!),
                    ),
                  ),
                ],
              ),
              if (selection) ...[
                const SizedBox(height: AppSpace.sm),
                DropdownButtonFormField<String?>(
                  key: ValueKey(_optionSetKey),
                  initialValue: _optionSetKey,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Набор вариантов *',
                    helperText:
                        'Состав набора меняется в разделе «Варианты для полей»',
                    errorText: _optionSetError,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Выберите набор'),
                    ),
                    ..._optionSets.map(
                      (set) => DropdownMenuItem<String?>(
                        value: set['key']?.toString(),
                        child: Text(set['label']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _optionSetKey = value;
                    _optionSetError = null;
                  }),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('field-create-option-set'),
                    onPressed: _createOptionSet,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Создать новый набор'),
                  ),
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _required,
                title: const Text('Обязательное'),
                onChanged: (v) => setState(() => _required = v == true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                title: const Text('Активное'),
                onChanged: system
                    ? null
                    : (v) => setState(() => _active = v == true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }

  void _submit() {
    final key = _key.text.trim();
    final label = _label.text.trim();
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(key) ||
        label.isEmpty) {
      return;
    }
    final selection = _selectionFieldTypes.contains(_type);
    if (selection && _optionSetKey == null) {
      setState(() => _optionSetError = 'Выберите или создайте набор');
      return;
    }
    final optionSet = selection
        ? _optionSets
              .where((set) => set['key']?.toString() == _optionSetKey)
              .firstOrNull
        : null;
    final options =
        (optionSet?['options'] as List? ?? const [])
            .whereType<Map>()
            .where((option) => option['active'] != false)
            .toList()
          ..sort(
            (left, right) => ((left['order'] as num?)?.toInt() ?? 0).compareTo(
              (right['order'] as num?)?.toInt() ?? 0,
            ),
          );
    Navigator.pop<_FieldEditorResult>(context, (
      field: <String, dynamic>{
        'entityType': _entity,
        'key': key,
        'label': label,
        'valueType': _type,
        'required': _required,
        'active': _active,
        'system': widget.field?['system'] == true,
        'categoryKey': _category,
        'order': widget.field?['order'] ?? 0,
        'width': _width,
        'placements': widget.field?['placements'] ?? ['create', 'edit', 'card'],
        'options': options.map((option) => option['label']).toList(),
        'optionSetKey': selection ? _optionSetKey : null,
      },
      createdOptionSets: _createdOptionSets,
    ));
  }

  Future<void> _createOptionSet() async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _OptionSetEditorDialog(optionSet: null),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _optionSets.add(draft);
      _createdOptionSets.add(draft);
      _optionSetKey = draft['key']?.toString();
      _optionSetError = null;
    });
  }
}

class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog();

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  final _key = TextEditingController();
  final _label = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новая категория'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _label,
          decoration: const InputDecoration(labelText: 'Название *'),
        ),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: _key,
          decoration: const InputDecoration(labelText: 'Стабильный ключ *'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          final key = _key.text.trim();
          final label = _label.text.trim();
          if (label.isEmpty ||
              !RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(key)) {
            return;
          }
          Navigator.pop(context, {'key': key, 'label': label});
        },
        child: const Text('Добавить'),
      ),
    ],
  );
}

class _OptionSetEditorDialog extends StatefulWidget {
  const _OptionSetEditorDialog({required this.optionSet});
  final Map<String, dynamic>? optionSet;

  @override
  State<_OptionSetEditorDialog> createState() => _OptionSetEditorDialogState();
}

class _OptionSetEditorDialogState extends State<_OptionSetEditorDialog> {
  late final _key = TextEditingController(
    text: widget.optionSet?['key']?.toString() ?? '',
  );
  late final _label = TextEditingController(
    text: widget.optionSet?['label']?.toString() ?? '',
  );
  late final _options = TextEditingController(
    text: (widget.optionSet?['options'] as List? ?? const [])
        .map((item) => (item as Map)['label'])
        .join(', '),
  );
  late bool _multiple = widget.optionSet?['multiple'] == true;

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.optionSet == null ? 'Новый набор вариантов' : 'Набор вариантов',
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Название *'),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _key,
            enabled: widget.optionSet == null,
            decoration: const InputDecoration(labelText: 'Стабильный ключ *'),
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: _options,
            decoration: const InputDecoration(
              labelText: 'Варианты через запятую *',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _multiple,
            title: const Text('Можно выбрать несколько'),
            onChanged: (v) => setState(() => _multiple = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Сохранить')),
    ],
  );

  void _submit() {
    final key = _key.text.trim();
    final label = _label.text.trim();
    final labels = _options.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(key) ||
        label.isEmpty ||
        labels.isEmpty) {
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'key': key,
      'label': label,
      'multiple': _multiple,
      'options': [
        for (var i = 0; i < labels.length; i++)
          {
            'key': _stableOptionKey(labels[i], i),
            'label': labels[i],
            'order': i,
            'active': true,
          },
      ],
    });
  }
}

Map<String, dynamic> _copyMap(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}

bool _migrateInlineFieldOptions(Map<String, dynamic> snapshot) {
  final fields = (snapshot['fields'] as List? ?? const [])
      .whereType<Map>()
      .map((field) => Map<String, dynamic>.from(field))
      .toList();
  final optionSets = (snapshot['optionSets'] as List? ?? const [])
      .whereType<Map>()
      .map((set) => Map<String, dynamic>.from(set))
      .toList();
  final usedKeys = optionSets
      .map((set) => set['key']?.toString())
      .whereType<String>()
      .toSet();
  var changed = false;
  for (final field in fields) {
    final labels = (field['options'] as List? ?? const [])
        .whereType<String>()
        .where((label) => label.trim().isNotEmpty)
        .toList();
    if (!_selectionFieldTypes.contains(field['valueType']) ||
        field['optionSetKey'] != null ||
        labels.isEmpty) {
      continue;
    }
    final base = '${field['entityType']}_${field['key']}_options';
    var optionSetKey = base.substring(0, base.length.clamp(0, 64));
    for (var suffix = 2; usedKeys.contains(optionSetKey); suffix++) {
      final tail = '_$suffix';
      optionSetKey =
          '${base.substring(0, base.length.clamp(0, 64 - tail.length))}$tail';
    }
    usedKeys.add(optionSetKey);
    final rawLabel = '${field['label']}: варианты';
    optionSets.add({
      'key': optionSetKey,
      'label': rawLabel.substring(0, rawLabel.length.clamp(0, 120)),
      'multiple': const {
        'multi_select',
        'checkbox_group',
      }.contains(field['valueType']),
      'options': [
        for (var index = 0; index < labels.length; index++)
          {
            'key': _stableOptionKey(labels[index], index),
            'label': labels[index],
            'order': index,
            'active': true,
          },
      ],
    });
    field['optionSetKey'] = optionSetKey;
    changed = true;
  }
  if (changed) {
    snapshot['fields'] = fields;
    snapshot['optionSets'] = optionSets;
  }
  return changed;
}

String _stableOptionKey(String label, int index) {
  final normalized = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final suffix = '_${index + 1}';
  final base = normalized.isEmpty ? 'option' : normalized;
  return '${base.substring(0, base.length.clamp(0, 64 - suffix.length))}$suffix';
}

String _message(Object error) {
  if (error is MagicApiException && error.statusCode == 403) {
    return 'Недостаточно делегированных прав или филиал вне области доступа.';
  }
  if (error is MagicApiException && error.statusCode == 409) {
    return 'Конфигурация изменилась в другой вкладке. Обновите данные.';
  }
  return 'Не удалось выполнить операцию: $error';
}
