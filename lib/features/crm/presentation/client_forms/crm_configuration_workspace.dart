import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/forms/dirty_form_exit.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor.dart';

import 'client_forms_api.dart';
import 'client_sources_editor.dart';
import 'crm_configuration_snapshot.dart';

part 'crm_configuration_workspace_schema.dart';
part 'crm_configuration_workspace_commerce.dart';

class CrmConfigurationRouteScreen extends ConsumerWidget {
  const CrmConfigurationRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(capabilitySnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Настройки системы'),
      ),
      body: access.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Не удалось проверить доступ.')),
        data: (snapshot) => snapshot.allows('config.crm.read')
            ? const CrmConfigurationWorkspace()
            : const Center(
                child: Text('Недостаточно прав для изменения настроек.'),
              ),
      ),
    );
  }
}

Future<void> showCrmConfigurationWorkspace(BuildContext context) async {
  await context.push<void>('/crm/configuration');
}

class CrmConfigurationWorkspace extends ConsumerStatefulWidget {
  const CrmConfigurationWorkspace({super.key});

  @override
  ConsumerState<CrmConfigurationWorkspace> createState() =>
      _CrmConfigurationWorkspaceState();
}

class _CrmConfigurationWorkspaceState
    extends ConsumerState<CrmConfigurationWorkspace> {
  static const _commonAreas = <(String, String, IconData)>[
    ('fields', 'Поля и категории', Icons.dynamic_form_outlined),
    ('options', 'Варианты для полей', Icons.list_alt_outlined),
    ('settings', 'Бизнес-параметры', Icons.tune_rounded),
    ('funnel', 'Воронки клиентов', Icons.view_kanban_outlined),
  ];
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
  late final DirtyFormExitController _exitController;

  CapabilitySnapshot? get _access =>
      ref.read(capabilitySnapshotProvider).asData?.value;
  bool get _canEdit => _access?.allows('config.crm.edit') == true;
  bool get _canPublish => _access?.allows('config.crm.publish') == true;
  bool get _isManager => _access?.role == 'manager';
  bool get _canSeeCommerceCatalogs =>
      const {'director', 'system_admin'}.contains(_access?.role) &&
      _access?.allows('config.crm.read') == true;
  bool get _canManageCommerceCatalogs =>
      _canSeeCommerceCatalogs && _canEdit && _canPublish;
  bool get _isInitialSchoolSetup => _branchId == null && _baseVersion == 0;
  List<(String, String, IconData)> get _areas => [
    ..._commonAreas,
    if (_canSeeCommerceCatalogs)
      ('commerce', 'Занятия и оплата', Icons.price_change_outlined),
    ('history', 'История версий', Icons.history_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _exitController = DirtyFormExitController(onSave: _saveDraft);
    _loadInitial();
  }

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
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
      final snapshot = CrmConfigurationSnapshotOps.deepCopy(draft['snapshot']);
      final migratedLegacyFields =
          _branchId == null &&
          CrmConfigurationSnapshotOps.migrateLegacyFieldCopies(snapshot);
      final migratedInlineOptions =
          _branchId == null &&
          CrmConfigurationSnapshotOps.migrateInlineFieldOptions(snapshot);
      final migratedConfiguration =
          migratedLegacyFields || migratedInlineOptions;
      setState(() {
        _baseVersion = (draft['baseVersion'] as num?)?.toInt() ?? 0;
        _snapshot = snapshot;
        _dirty = draft['dirty'] == true || migratedConfiguration;
        _revisions = results[1] as List<Map<String, dynamic>>;
        _selectedKey = null;
        _loading = false;
        _busy = false;
      });
      if (migratedConfiguration) {
        _exitController.markDirty();
      } else {
        _exitController.markClean();
      }
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
    _exitController.markDirty();
  }

  Future<bool> _saveDraft() async {
    if (_snapshot == null || !_canEdit) return false;
    setState(() => _busy = true);
    try {
      await ref
          .read(clientFormsApiProvider)
          .saveConfigurationDraft(
            branchId: _branchId,
            baseVersion: _baseVersion,
            snapshot: _snapshot!,
          );
      if (!mounted) return false;
      setState(() {
        _busy = false;
        _dirty = true;
      });
      _exitController.markClean();
      _toast('Черновик сохранён');
      return true;
    } catch (error) {
      _fail(error);
      return false;
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
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Типов списания изменено: '
                  '${changes['settlementTypesChanged'] ?? 0} · '
                  'типов оплаты преподавателю: '
                  '${changes['compensationRulesChanged'] ?? 0}',
                ),
                const SizedBox(height: AppSpace.sm),
                Text('Затронутые экраны: ${screens.isEmpty ? 'нет' : screens}'),
                for (final warning in (impact['warnings'] as List? ?? const []))
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.sm),
                    child: Text('• $warning'),
                  ),
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
    return DirtyFormExitScope(
      controller: _exitController,
      child: Column(
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
      ),
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
                menuMaxHeight: 256,
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
                _isInitialSchoolSetup
                    ? Icons.rocket_launch_outlined
                    : _dirty
                    ? Icons.edit_note_rounded
                    : Icons.verified_outlined,
                size: 18,
              ),
              label: Text(
                '${_isInitialSchoolSetup
                    ? 'Начальная настройка'
                    : _dirty
                    ? 'Черновик'
                    : 'Опубликовано'} · версия $_baseVersion',
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
                onPressed: _busy || (!_dirty && !_isInitialSchoolSetup)
                    ? null
                    : _previewAndPublish,
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
    'commerce' => _CrmCommerceCatalogList(
      settlementTypes: _items('lessonSettlementTypes'),
      compensationRules: _items('teacherCompensationRules'),
      selectedKey: _selectedKey,
      canManage: _canManageCommerceCatalogs,
      onSelect: _selectItem,
      onAdd: (listKey) => _editCommerceCatalog(listKey, null),
      onReorder: _reorderCommerceCatalog,
    ),
    'history' => _historyList(),
    _ => const SizedBox.shrink(),
  };

  Widget _fieldList() {
    final categories = _items('categories')
      ..sort(
        (left, right) => ((left['order'] as num?)?.toInt() ?? 0).compareTo(
          (right['order'] as num?)?.toInt() ?? 0,
        ),
      );
    return _CrmFieldList(
      fields: _items('fields'),
      categories: categories,
      selectedKey: _selectedKey,
      canManageStructure: _canEdit && _branchId == null,
      onSelect: _selectItem,
      onAddField: () => _editField(null),
      onAddCategory: () => _editCategory(),
      onEditCategory: (category) => _editCategory(category),
      onReorderCategory: _reorderCategory,
    );
  }

  Widget _optionSetList() => _CrmOptionSetList(
    sets: _items('optionSets'),
    fields: _items('fields'),
    selectedKey: _selectedKey,
    canManageStructure: _canEdit && _branchId == null,
    onSelect: _selectItem,
    onAdd: () => _editOptionSet(null),
  );

  Widget _settingList() => _CrmBusinessSettingsList(
    settings: _items('businessSettings'),
    selectedKey: _selectedKey,
    onSelect: _selectItem,
  );
  Future<void> _editCommerceCatalog(
    String listKey,
    Map<String, dynamic>? current,
  ) async {
    if (!_canManageCommerceCatalogs) return;
    final items = _items(listKey)
      ..sort(CrmConfigurationSnapshotOps.compareCatalogOrder);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CommerceCatalogEditorDialog(
        settlement: listKey == 'lessonSettlementTypes',
        item: current,
        nextOrder: items.length,
      ),
    );
    if (result == null) return;
    final index = current == null
        ? -1
        : items.indexWhere((item) => item['stableKey'] == current['stableKey']);
    if (index < 0) {
      items.add(result);
    } else {
      items[index] = result;
    }
    _replaceItems(listKey, items);
    final prefix = listKey == 'lessonSettlementTypes'
        ? 'settlement'
        : 'compensation';
    setState(() => _selectedKey = '$prefix:${result['stableKey']}');
  }

  void _reorderCommerceCatalog(String listKey, String stableKey, int delta) {
    final items = _items(listKey)
      ..sort(CrmConfigurationSnapshotOps.compareCatalogOrder);
    final from = items.indexWhere((item) => item['stableKey'] == stableKey);
    final reordered = CrmConfigurationSnapshotOps.reorderItems(
      items,
      from: from,
      delta: delta,
    );
    if (reordered != null) _replaceItems(listKey, reordered);
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
    return switch (_area) {
      'fields' => _selectedFieldPreview(),
      'options' => _selectedOptionSetPreview(),
      'settings' => _selectedBusinessSettingEditor(),
      'commerce' => _CrmCommerceCatalogPreview(
        selection: _selectedKey,
        settlementTypes: _items('lessonSettlementTypes'),
        compensationRules: _items('teacherCompensationRules'),
        canManage: _canManageCommerceCatalogs,
        onEdit: _editCommerceCatalog,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _selectedFieldPreview() {
    final field = _items(
      'fields',
    ).where((item) => item['key']?.toString() == _selectedKey).firstOrNull;
    return field == null
        ? const SizedBox.shrink()
        : _CrmFieldPreview(
            field: field,
            canManageStructure: _canEdit && _branchId == null,
            onEdit: () => _editField(field),
          );
  }

  Widget _selectedOptionSetPreview() {
    if (_selectedKey == _clientSourcesKey) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Рекламный источник',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Единый список значений для лидов и учеников. Системный источник «Приложение» защищён.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColor.text2),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClientSourcesEditor(canEdit: _canEdit && _branchId == null),
          ),
        ],
      );
    }
    final set = _items(
      'optionSets',
    ).where((item) => item['key']?.toString() == _selectedKey).firstOrNull;
    return set == null
        ? const SizedBox.shrink()
        : _CrmOptionSetPreview(
            set: set,
            usage: _optionSetUsage(
              _items('fields'),
              set['key']?.toString() ?? '',
            ),
            canManageStructure: _canEdit && _branchId == null,
            onEdit: () => _editOptionSet(set),
          );
  }

  Widget _selectedBusinessSettingEditor() {
    final setting = _items(
      'businessSettings',
    ).where((item) => item['key']?.toString() == _selectedKey).firstOrNull;
    return setting == null
        ? const SizedBox.shrink()
        : _CrmBusinessSettingEditor(
            setting: {...setting, 'branchScoped': _branchId != null},
            canEdit: _canEdit,
            onChanged: (value) => _updateBusinessSetting(setting, value),
          );
  }

  void _selectItem(String key) => setState(() => _selectedKey = key);

  void _updateBusinessSetting(Map<String, dynamic> setting, int value) {
    final settings = _items('businessSettings');
    final index = settings.indexWhere((item) => item['key'] == setting['key']);
    if (index < 0) return;
    settings[index] = {...settings[index], 'value': value};
    _replaceItems('businessSettings', settings);
  }

  Future<void> _editField(Map<String, dynamic>? current) async {
    final categories = _items('categories');
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FieldEditorDialog(
        field: current,
        categories: categories,
        optionSets: _items('optionSets'),
        fieldTypes: _fieldTypes,
      ),
    );
    if (draft == null) return;
    final fields = _items('fields');
    final index = current == null
        ? -1
        : fields.indexWhere((field) => field['key'] == current['key']);
    if (index < 0) {
      fields.add(draft);
    } else {
      fields[index] = {...?current, ...draft};
    }
    _replaceItems('fields', fields);
    setState(() => _selectedKey = draft['key']?.toString());
  }

  Future<void> _editCategory([Map<String, dynamic>? current]) async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CategoryEditorDialog(category: current),
    );
    if (draft == null) return;
    final categories = _items('categories');
    final index = current == null
        ? -1
        : categories.indexWhere(
            (category) => category['key'] == current['key'],
          );
    if (draft['active'] == false &&
        _items('fields').any(
          (field) =>
              field['active'] != false && field['categoryKey'] == draft['key'],
        )) {
      _toast('Сначала перенесите активные поля в другую категорию.');
      return;
    }
    if (index < 0) {
      categories.add({...draft, 'order': categories.length, 'active': true});
    } else {
      categories[index] = {
        ...categories[index],
        'label': draft['label'],
        'active': draft['active'],
      };
    }
    _replaceItems('categories', categories);
  }

  void _reorderCategory(int from, int delta) {
    final categories = _items('categories')
      ..sort(
        (left, right) => ((left['order'] as num?)?.toInt() ?? 0).compareTo(
          (right['order'] as num?)?.toInt() ?? 0,
        ),
      );
    final reordered = CrmConfigurationSnapshotOps.reorderItems(
      categories,
      from: from,
      delta: delta,
    );
    if (reordered != null) _replaceItems('categories', reordered);
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

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

String _message(Object error) {
  if (error is MagicApiException && error.statusCode == 403) {
    return 'Недостаточно делегированных прав или филиал вне области доступа.';
  }
  if (error is MagicApiException && error.statusCode == 409) {
    return 'Конфигурация изменилась в другой вкладке. Обновите данные.';
  }
  return userErrorMessage(error);
}
