part of 'crm_configuration_workspace.dart';

const _clientSourcesKey = '__client_sources__';
const _fieldTypes = <String, String>{
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
  'email': 'Почта',
  'phone': 'Телефон',
  'url': 'Ссылка',
};

const _fieldPlacementLabels = <String, String>{
  'create': 'Создание',
  'edit': 'Редактирование',
  'card': 'Карточка',
  'table': 'Таблица',
};

class _CrmFieldList extends StatelessWidget {
  const _CrmFieldList({
    required this.fields,
    required this.categories,
    required this.selectedKey,
    required this.canManageStructure,
    required this.onSelect,
    required this.onAddField,
    required this.onAddCategory,
    required this.onEditCategory,
    required this.onReorderCategory,
  });

  final List<Map<String, dynamic>> fields;
  final List<Map<String, dynamic>> categories;
  final String? selectedKey;
  final bool canManageStructure;
  final ValueChanged<String> onSelect;
  final VoidCallback onAddField;
  final VoidCallback onAddCategory;
  final ValueChanged<Map<String, dynamic>> onEditCategory;
  final void Function(int from, int delta) onReorderCategory;

  @override
  Widget build(BuildContext context) => _CrmConfigurationListPane(
    title: 'Поля форм и карточек',
    addLabel: 'Добавить поле',
    onAdd: canManageStructure ? onAddField : null,
    children: [
      const ListTile(
        leading: Icon(Icons.info_outline_rounded),
        title: Text('Структура и видимость полей'),
        subtitle: Text(
          'Название, тип, категория и показ в карточках лида или ученика. Значения списков меняются только в разделе «Варианты для полей».',
        ),
      ),
      _CrmCategorySection(
        categories: categories,
        canManage: canManageStructure,
        onAdd: onAddCategory,
        onEdit: onEditCategory,
        onReorder: onReorderCategory,
      ),
      const Divider(),
      for (final field in fields)
        _CrmFieldTile(
          field: field,
          selected: selectedKey == field['key']?.toString(),
          onSelect: onSelect,
        ),
    ],
  );
}

class _CrmCategorySection extends StatelessWidget {
  const _CrmCategorySection({
    required this.categories,
    required this.canManage,
    required this.onAdd,
    required this.onEdit,
    required this.onReorder,
  });

  final List<Map<String, dynamic>> categories;
  final bool canManage;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final void Function(int from, int delta) onReorder;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text('Категории · ${categories.length}'),
        trailing: canManage
            ? IconButton(
                tooltip: 'Добавить категорию',
                onPressed: onAdd,
                icon: const Icon(Icons.create_new_folder_outlined),
              )
            : null,
      ),
      for (var index = 0; index < categories.length; index++)
        Padding(
          padding: const EdgeInsets.only(left: AppSpace.lg),
          child: ListTile(
            dense: true,
            title: Text(categories[index]['label']?.toString() ?? ''),
            subtitle: Text(
              '${categories[index]['key'] ?? ''} · '
              '${categories[index]['active'] == false ? 'в архиве' : 'активна'}',
            ),
            leading: categories[index]['active'] == false
                ? const Icon(Icons.archive_outlined, size: 18)
                : const Icon(Icons.folder_outlined, size: 18),
            trailing: canManage
                ? SizedBox(
                    width: 120,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Выше',
                          visualDensity: VisualDensity.compact,
                          onPressed: index == 0
                              ? null
                              : () => onReorder(index, -1),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ниже',
                          visualDensity: VisualDensity.compact,
                          onPressed: index == categories.length - 1
                              ? null
                              : () => onReorder(index, 1),
                          icon: const Icon(
                            Icons.arrow_downward_rounded,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Изменить категорию',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onEdit(categories[index]),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
        ),
    ],
  );
}

class _CrmFieldTile extends StatelessWidget {
  const _CrmFieldTile({
    required this.field,
    required this.selected,
    required this.onSelect,
  });

  final Map<String, dynamic> field;
  final bool selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final key = field['key']?.toString() ?? '';
    return ListTile(
      selected: selected,
      title: Text(field['label']?.toString() ?? 'Поле'),
      subtitle: Text(
        '${_fieldVisibilityLabel(field)} · '
        '${_fieldTypes[field['valueType']] ?? field['valueType']}',
      ),
      trailing: field['system'] == true
          ? const Tooltip(
              message: 'Системное поле',
              child: Icon(Icons.lock_outline),
            )
          : null,
      onTap: () => onSelect(key),
    );
  }
}

class _CrmOptionSetList extends StatelessWidget {
  const _CrmOptionSetList({
    required this.sets,
    required this.fields,
    required this.selectedKey,
    required this.canManageStructure,
    required this.onSelect,
    required this.onAdd,
  });

  final List<Map<String, dynamic>> sets;
  final List<Map<String, dynamic>> fields;
  final String? selectedKey;
  final bool canManageStructure;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => _CrmConfigurationListPane(
    title: 'Наборы вариантов для полей',
    addLabel: 'Добавить набор',
    onAdd: canManageStructure ? onAdd : null,
    children: [
      const ListTile(
        leading: Icon(Icons.info_outline_rounded),
        title: Text('Значения списков и справочников'),
        subtitle: Text(
          'Один набор используется обеими карточками. Здесь же настраивается системный рекламный источник.',
        ),
      ),
      ListTile(
        selected: selectedKey == _clientSourcesKey,
        leading: const Icon(Icons.campaign_outlined),
        title: const Text('Рекламный источник'),
        subtitle: const Text('Лид и ученик · системный справочник'),
        trailing: const Icon(Icons.lock_outline),
        onTap: () => onSelect(_clientSourcesKey),
      ),
      for (final set in sets)
        ListTile(
          selected: selectedKey == set['key']?.toString(),
          title: Text(set['label']?.toString() ?? set['key']?.toString() ?? ''),
          subtitle: Text(
            '${_optionSetUsageLabel(_optionSetUsage(fields, set['key']?.toString() ?? ''))} · '
            '${_optionCountLabel((set['options'] as List? ?? const []).length)}',
          ),
          onTap: () => onSelect(set['key']?.toString() ?? ''),
        ),
    ],
  );

  String _optionCountLabel(int count) {
    final lastTwo = count % 100;
    final last = count % 10;
    final noun = lastTwo >= 11 && lastTwo <= 14
        ? 'вариантов'
        : last == 1
        ? 'вариант'
        : last >= 2 && last <= 4
        ? 'варианта'
        : 'вариантов';
    return '$count $noun';
  }
}

class _CrmBusinessSettingsList extends StatelessWidget {
  const _CrmBusinessSettingsList({
    required this.settings,
    required this.selectedKey,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> settings;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => _CrmConfigurationListPane(
    title: 'Безопасные бизнес-параметры',
    children: [
      for (final setting in settings)
        ListTile(
          selected: selectedKey == setting['key']?.toString(),
          title: Text(
            setting['label']?.toString() ?? setting['key']?.toString() ?? '',
          ),
          subtitle: Text('${setting['value']} ${setting['unit'] ?? ''}'),
          onTap: () => onSelect(setting['key']?.toString() ?? ''),
        ),
    ],
  );
}

class _CrmFieldPreview extends StatelessWidget {
  const _CrmFieldPreview({
    required this.field,
    required this.canManageStructure,
    required this.onEdit,
  });

  final Map<String, dynamic> field;
  final bool canManageStructure;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ListView(
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
          if (canManageStructure && field['system'] != true)
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Изменить'),
            ),
        ],
      ),
      const SizedBox(height: AppSpace.lg),
      _CrmConfigurationProperty(label: 'Стабильный ключ', value: field['key']),
      _CrmConfigurationProperty(
        label: 'Видимость',
        value: _fieldVisibilityLabel(field),
      ),
      _CrmConfigurationProperty(
        label: 'Тип',
        value: _fieldTypes[field['valueType']] ?? field['valueType'],
      ),
      if (CrmConfigurationSnapshotOps.selectionFieldTypes.contains(
        field['valueType'],
      ))
        _CrmConfigurationProperty(
          label: 'Набор вариантов',
          value: field['key'] == 'sourceId'
              ? 'Рекламный источник · раздел «Варианты для полей»'
              : field['optionSetKey'],
        ),
      _CrmConfigurationProperty(
        label: 'Категория',
        value: field['categoryKey'],
      ),
      _CrmConfigurationProperty(label: 'Ширина', value: field['width']),
      _CrmConfigurationProperty(
        label: 'Размещения',
        value: (field['placements'] as List? ?? const []).join(', '),
      ),
      _CrmConfigurationProperty(
        label: 'Состояние',
        value: field['active'] == true ? 'Активно' : 'В архиве',
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

class _CrmOptionSetPreview extends StatelessWidget {
  const _CrmOptionSetPreview({
    required this.set,
    required this.usage,
    required this.canManageStructure,
    required this.onEdit,
  });

  final Map<String, dynamic> set;
  final List<Map<String, dynamic>> usage;
  final bool canManageStructure;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ListView(
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
          if (canManageStructure)
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Изменить'),
            ),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      _CrmConfigurationProperty(
        label: 'Используется в',
        value: _optionSetUsageLabel(usage),
      ),
      if (usage.isNotEmpty)
        _CrmConfigurationProperty(
          label: 'Поля',
          value: usage
              .map((field) => field['label']?.toString() ?? 'Поле')
              .toSet()
              .join(', '),
        ),
      const SizedBox(height: AppSpace.sm),
      for (final option in (set['options'] as List? ?? const []))
        ListTile(
          leading: const Icon(Icons.drag_indicator_rounded),
          title: Text((option as Map)['label']?.toString() ?? ''),
          subtitle: Text(option['key']?.toString() ?? ''),
          trailing: option['active'] == true
              ? const Icon(Icons.check_circle_outline, color: AppColor.success)
              : const Icon(Icons.archive_outlined),
        ),
    ],
  );
}

class _CrmBusinessSettingEditor extends StatelessWidget {
  const _CrmBusinessSettingEditor({
    required this.setting,
    required this.canEdit,
    required this.onChanged,
  });

  final Map<String, dynamic> setting;
  final bool canEdit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpace.lg),
    children: [
      Text(setting['label'], style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: AppSpace.md),
      TextFormField(
        initialValue: setting['value']?.toString(),
        enabled: canEdit,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Значение, ${setting['unit']}',
          helperText: 'Допустимо: ${setting['min']}-${setting['max']}',
        ),
        onChanged: (value) {
          final number = int.tryParse(value);
          if (number != null) onChanged(number);
        },
      ),
      if (setting['branchScoped'] == true)
        const Padding(
          padding: EdgeInsets.only(top: AppSpace.md),
          child: Text(
            'Изменяется только значение филиала; схема наследуется от школы.',
          ),
        ),
    ],
  );
}

List<Map<String, dynamic>> _optionSetUsage(
  List<Map<String, dynamic>> fields,
  String optionSetKey,
) => fields
    .where((field) => field['optionSetKey']?.toString() == optionSetKey)
    .toList(growable: false);

String _optionSetUsageLabel(List<Map<String, dynamic>> fields) {
  final lead = fields.any(
    (field) => (field['visibility'] as Map?)?['lead'] == true,
  );
  final student = fields.any(
    (field) => (field['visibility'] as Map?)?['student'] == true,
  );
  if (lead && student) return 'Карточки лида и ученика';
  if (lead) return 'Карточка лида';
  if (student) return 'Карточка ученика';
  return 'Не используется в карточках';
}

String _fieldVisibilityLabel(Map<String, dynamic> field) {
  final visibility = field['visibility'] as Map?;
  final lead = visibility?['lead'] == true;
  final student = visibility?['student'] == true;
  if (lead && student) return 'Лид и ученик';
  if (lead) return 'Только лид';
  if (student) return 'Только ученик';
  return 'Скрыто';
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
  late String _type = widget.field?['valueType']?.toString() ?? 'text';
  late bool _visibleOnLead =
      (widget.field?['visibility'] as Map?)?['lead'] != false;
  late bool _visibleOnStudent =
      (widget.field?['visibility'] as Map?)?['student'] != false;
  late String _category =
      widget.field?['categoryKey']?.toString() ??
      widget.categories.firstOrNull?['key']?.toString() ??
      'general';
  late String _width = widget.field?['width']?.toString() ?? 'full';
  late final Set<String> _placements = {
    for (final placement
        in (widget.field?['placements'] as List? ??
            const ['create', 'edit', 'card']))
      placement.toString(),
  };
  late bool _required = widget.field?['required'] == true;
  late bool _active = widget.field?['active'] != false;
  late String? _optionSetKey = widget.field?['optionSetKey']?.toString();
  String? _optionSetError;
  String? _placementsError;
  String? _visibilityError;

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final system = widget.field?['system'] == true;
    final selection = CrmConfigurationSnapshotOps.selectionFieldTypes.contains(
      _type,
    );
    final compatibleOptionSets = _optionSets
        .where(
          (set) =>
              set['key']?.toString() == _optionSetKey ||
              _optionSetMatchesCurrentType(set),
        )
        .toList(growable: false);
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
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                key: const ValueKey('field-type'),
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
                        if (!CrmConfigurationSnapshotOps.selectionFieldTypes
                                .contains(_type) ||
                            !_optionSetMatchesType(_optionSetKey)) {
                          _optionSetKey = null;
                          _optionSetError = null;
                        }
                      }),
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Показывать в карточках',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                children: [
                  FilterChip(
                    key: const ValueKey('field-visible-lead'),
                    label: const Text('Лид'),
                    selected: _visibleOnLead,
                    onSelected: system
                        ? null
                        : (value) => setState(() {
                            _visibleOnLead = value;
                            _visibilityError = null;
                          }),
                  ),
                  FilterChip(
                    key: const ValueKey('field-visible-student'),
                    label: const Text('Ученик'),
                    selected: _visibleOnStudent,
                    onSelected: system
                        ? null
                        : (value) => setState(() {
                            _visibleOnStudent = value;
                            _visibilityError = null;
                          }),
                  ),
                ],
              ),
              if (_visibilityError != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _visibilityError!,
                    style: const TextStyle(color: AppColor.danger),
                  ),
                ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      menuMaxHeight: 256,
                      initialValue: _category,
                      decoration: const InputDecoration(labelText: 'Категория'),
                      items: widget.categories
                          .where(
                            (category) =>
                                category['active'] != false ||
                                category['key']?.toString() == _category,
                          )
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
                      menuMaxHeight: 256,
                      key: const ValueKey('field-width'),
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
                  menuMaxHeight: 256,
                  key: ValueKey(_optionSetKey),
                  initialValue: _optionSetKey,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Набор вариантов *',
                    helperText: compatibleOptionSets.isEmpty
                        ? 'Сначала добавьте подходящий набор в разделе «Варианты для полей»'
                        : 'Состав набора меняется только в разделе «Варианты для полей»',
                    errorText: _optionSetError,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Выберите набор'),
                    ),
                    ...compatibleOptionSets.map(
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
              const SizedBox(height: AppSpace.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Показывать поле в',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final entry in _fieldPlacementLabels.entries)
                    FilterChip(
                      key: ValueKey('field-placement-${entry.key}'),
                      label: Text(entry.value),
                      selected: _placements.contains(entry.key),
                      onSelected: (selected) => setState(() {
                        selected
                            ? _placements.add(entry.key)
                            : _placements.remove(entry.key);
                        _placementsError = null;
                      }),
                    ),
                ],
              ),
              if (_placementsError != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text(
                      _placementsError!,
                      style: const TextStyle(color: AppColor.danger),
                    ),
                  ),
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
    final selection = CrmConfigurationSnapshotOps.selectionFieldTypes.contains(
      _type,
    );
    if (selection && _optionSetKey == null) {
      setState(
        () => _optionSetError =
            'Сначала создайте подходящий набор в разделе «Варианты для полей»',
      );
      return;
    }
    if (!_visibleOnLead && !_visibleOnStudent) {
      setState(() => _visibilityError = 'Выберите хотя бы один тип карточки');
      return;
    }
    if (_placements.isEmpty) {
      setState(() => _placementsError = 'Выберите хотя бы одно размещение');
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
    Navigator.pop<Map<String, dynamic>>(context, <String, dynamic>{
      'key': key,
      'label': label,
      'valueType': _type,
      'required': _required,
      'active': _active,
      'system': widget.field?['system'] == true,
      'categoryKey': _category,
      'order': widget.field?['order'] ?? 0,
      'width': _width,
      'placements': [
        for (final key in _fieldPlacementLabels.keys)
          if (_placements.contains(key)) key,
      ],
      'options': options.map((option) => option['label']).toList(),
      'optionSetKey': selection ? _optionSetKey : null,
      'visibility': {'lead': _visibleOnLead, 'student': _visibleOnStudent},
    });
  }

  bool _optionSetMatchesCurrentType(Map<String, dynamic> set) {
    final expectsMultiple = const {
      'multi_select',
      'checkbox_group',
    }.contains(_type);
    return (set['multiple'] == true) == expectsMultiple;
  }

  bool _optionSetMatchesType(String? key) {
    if (key == null) return true;
    final set = _optionSets
        .where((candidate) => candidate['key']?.toString() == key)
        .firstOrNull;
    return set == null || _optionSetMatchesCurrentType(set);
  }
}

class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog({required this.category});

  final Map<String, dynamic>? category;

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final _key = TextEditingController(
    text: widget.category?['key']?.toString() ?? '',
  );
  late final _label = TextEditingController(
    text: widget.category?['label']?.toString() ?? '',
  );
  late bool _active = widget.category?['active'] != false;

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.category == null ? 'Новая категория' : 'Категория'),
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
          enabled: widget.category == null,
          decoration: const InputDecoration(labelText: 'Стабильный ключ *'),
        ),
        if (widget.category != null)
          SwitchListTile(
            key: const ValueKey('category-active'),
            contentPadding: EdgeInsets.zero,
            value: _active,
            title: Text(_active ? 'Активна' : 'В архиве'),
            subtitle: const Text(
              'Архивировать можно только категорию без активных полей',
            ),
            onChanged: (value) => setState(() => _active = value),
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
          Navigator.pop(context, {
            'key': key,
            'label': label,
            'active': _active,
          });
        },
        child: Text(widget.category == null ? 'Добавить' : 'Сохранить'),
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
  late final List<_OptionDraft> _options;
  late bool _multiple = widget.optionSet?['multiple'] == true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final raw =
        (widget.optionSet?['options'] as List? ?? const [])
            .whereType<Map>()
            .map((option) => Map<String, dynamic>.from(option))
            .toList()
          ..sort(
            (left, right) => ((left['order'] as num?)?.toInt() ?? 0).compareTo(
              (right['order'] as num?)?.toInt() ?? 0,
            ),
          );
    _options = [
      for (final option in raw)
        _OptionDraft(
          key: option['key']?.toString(),
          label: option['label']?.toString() ?? '',
          active: option['active'] != false,
        ),
    ];
    if (_options.isEmpty) _options.add(_OptionDraft());
  }

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.optionSet == null ? 'Новый набор вариантов' : 'Набор вариантов',
    ),
    content: SizedBox(
      width: 560,
      height: 520,
      child: Column(
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _multiple,
            title: const Text('Можно выбрать несколько'),
            onChanged: (v) => setState(() => _multiple = v),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Варианты',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                key: const ValueKey('option-set-add-option'),
                onPressed: () => setState(() {
                  _options.add(_OptionDraft());
                  _error = null;
                }),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _options.length,
              itemBuilder: (context, index) {
                final option = _options[index];
                return Padding(
                  key: option.identity,
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: option.label,
                          decoration: InputDecoration(
                            labelText: 'Вариант ${index + 1} *',
                            helperText: option.active ? null : 'В архиве',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Выше',
                        onPressed: index == 0
                            ? null
                            : () => _moveOption(index, -1),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                      IconButton(
                        tooltip: 'Ниже',
                        onPressed: index == _options.length - 1
                            ? null
                            : () => _moveOption(index, 1),
                        icon: const Icon(Icons.arrow_downward_rounded),
                      ),
                      IconButton(
                        tooltip: option.active
                            ? 'Архивировать вариант'
                            : 'Вернуть вариант',
                        onPressed: () => setState(() {
                          option.active = !option.active;
                          _error = null;
                        }),
                        icon: Icon(
                          option.active
                              ? Icons.archive_outlined
                              : Icons.unarchive_outlined,
                        ),
                      ),
                      if (option.key == null)
                        IconButton(
                          tooltip: 'Удалить новый вариант',
                          onPressed: () => _removeNewOption(index),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: const TextStyle(color: AppColor.danger),
              ),
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
    final labels = _options.map((option) => option.label.text.trim()).toList();
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(key) ||
        label.isEmpty ||
        labels.isEmpty ||
        labels.any((value) => value.isEmpty) ||
        !_options.any((option) => option.active)) {
      setState(() {
        _error = 'Заполните все варианты и оставьте хотя бы один активным.';
      });
      return;
    }
    final usedKeys = <String>{};
    Navigator.pop(context, <String, dynamic>{
      'key': key,
      'label': label,
      'multiple': _multiple,
      'options': [
        for (var i = 0; i < labels.length; i++)
          {
            'key': CrmConfigurationSnapshotOps.optionKey(
              _options[i].key,
              labels[i],
              i,
              usedKeys,
            ),
            'label': labels[i],
            'order': i,
            'active': _options[i].active,
          },
      ],
    });
  }

  void _moveOption(int from, int delta) {
    final to = from + delta;
    if (to < 0 || to >= _options.length) return;
    setState(() {
      final moved = _options.removeAt(from);
      _options.insert(to, moved);
    });
  }

  void _removeNewOption(int index) {
    setState(() {
      final removed = _options.removeAt(index);
      removed.dispose();
      if (_options.isEmpty) _options.add(_OptionDraft());
      _error = null;
    });
  }
}

class _OptionDraft {
  _OptionDraft({this.key, String label = '', this.active = true})
    : label = TextEditingController(text: label),
      identity = UniqueKey();

  final String? key;
  final TextEditingController label;
  final Key identity;
  bool active;

  void dispose() => label.dispose();
}
