part of 'crm_configuration_workspace.dart';

const _decisionColorLabels = <String, String>{
  'neutral': 'Серый',
  'success': 'Зелёный',
  'warning': 'Жёлтый',
  'info': 'Голубой',
  'blue': 'Синий',
  'cyan': 'Бирюзовый',
  'violet': 'Сиреневый',
};

const _settlementContextLabels = <String, String>{
  'settle': 'Завершение',
  'reschedule': 'Перенос',
  'cancel': 'Отмена',
};

const _compensationModeLabels = <String, String>{
  'none': 'Не оплачивать',
  'standard': 'Стандартная ставка',
  'percent': 'Процент ставки',
  'fixed': 'Фиксированная сумма',
  'hourly': 'Почасовая сумма',
};

class _CrmCommerceCatalogList extends StatelessWidget {
  const _CrmCommerceCatalogList({
    required this.settlementTypes,
    required this.compensationRules,
    required this.selectedKey,
    required this.canManage,
    required this.onSelect,
    required this.onAdd,
    required this.onReorder,
  });

  final List<Map<String, dynamic>> settlementTypes;
  final List<Map<String, dynamic>> compensationRules;
  final String? selectedKey;
  final bool canManage;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onAdd;
  final void Function(String listKey, String stableKey, int delta) onReorder;

  @override
  Widget build(BuildContext context) {
    final sortedSettlementTypes =
        settlementTypes.map((item) => Map<String, dynamic>.from(item)).toList()
          ..sort(CrmConfigurationSnapshotOps.compareCatalogOrder);
    final sortedCompensationRules =
        compensationRules
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
          ..sort(CrmConfigurationSnapshotOps.compareCatalogOrder);
    final children = <Widget>[
      ListTile(
        title: const Text('Типы списания занятия'),
        subtitle: const Text('Цвет всегда сопровождается названием'),
        trailing: canManage
            ? IconButton(
                key: const ValueKey('add-settlement-type'),
                tooltip: 'Добавить тип списания',
                onPressed: () => onAdd('lessonSettlementTypes'),
                icon: const Icon(Icons.add_rounded),
              )
            : null,
      ),
      for (var index = 0; index < sortedSettlementTypes.length; index++)
        _catalogTile(
          listKey: 'lessonSettlementTypes',
          item: sortedSettlementTypes[index],
          index: index,
          count: sortedSettlementTypes.length,
        ),
      const Divider(),
      ListTile(
        title: const Text('Типы оплаты преподавателю'),
        subtitle: const Text(
          'Сотрудник всегда выбирает тип вручную и независимо от списания',
        ),
        trailing: canManage
            ? IconButton(
                key: const ValueKey('add-compensation-rule'),
                tooltip: 'Добавить тип оплаты преподавателю',
                onPressed: () => onAdd('teacherCompensationRules'),
                icon: const Icon(Icons.add_rounded),
              )
            : null,
      ),
      for (var index = 0; index < sortedCompensationRules.length; index++)
        _catalogTile(
          listKey: 'teacherCompensationRules',
          item: sortedCompensationRules[index],
          index: index,
          count: sortedCompensationRules.length,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Занятия и оплата преподавателю',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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

  Widget _catalogTile({
    required String listKey,
    required Map<String, dynamic> item,
    required int index,
    required int count,
  }) {
    final settlement = listKey == 'lessonSettlementTypes';
    final stableKey = item['stableKey']?.toString() ?? '';
    final selection =
        '${settlement ? 'settlement' : 'compensation'}:$stableKey';
    return ListTile(
      selected: selectedKey == selection,
      leading: Icon(
        settlement ? Icons.sell_outlined : Icons.payments_outlined,
        color: settlement
            ? lessonDecisionColorToken(item['colorToken']?.toString())
            : null,
      ),
      title: Text(item['label']?.toString() ?? stableKey),
      subtitle: Text(
        '${item['active'] == true ? 'Активно' : 'В архиве'} · $stableKey',
      ),
      onTap: () => onSelect(selection),
      trailing: !canManage
          ? null
          : SizedBox(
              width: 80,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Выше',
                    visualDensity: VisualDensity.compact,
                    onPressed: index == 0
                        ? null
                        : () => onReorder(listKey, stableKey, -1),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Ниже',
                    visualDensity: VisualDensity.compact,
                    onPressed: index == count - 1
                        ? null
                        : () => onReorder(listKey, stableKey, 1),
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CrmCommerceCatalogPreview extends StatelessWidget {
  const _CrmCommerceCatalogPreview({
    required this.selection,
    required this.settlementTypes,
    required this.compensationRules,
    required this.canManage,
    required this.onEdit,
  });

  final String? selection;
  final List<Map<String, dynamic>> settlementTypes;
  final List<Map<String, dynamic>> compensationRules;
  final bool canManage;
  final void Function(String listKey, Map<String, dynamic> item) onEdit;

  @override
  Widget build(BuildContext context) {
    final parts = selection?.split(':') ?? const <String>[];
    if (parts.length != 2) {
      return const Center(
        child: Text('Выберите тип списания или оплаты преподавателю'),
      );
    }
    final settlement = parts.first == 'settlement';
    final listKey = settlement
        ? 'lessonSettlementTypes'
        : 'teacherCompensationRules';
    final items =
        (settlement ? settlementTypes : compensationRules)
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
          ..sort(CrmConfigurationSnapshotOps.compareCatalogOrder);
    final item = items
        .where((row) => row['stableKey']?.toString() == parts.last)
        .firstOrNull;
    if (item == null) return const SizedBox.shrink();
    final accent = settlement
        ? lessonDecisionColorToken(item['colorToken']?.toString())
        : Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        Row(
          children: [
            Icon(
              settlement ? Icons.sell_outlined : Icons.payments_outlined,
              color: accent,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                item['label']?.toString() ?? '',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (canManage)
              OutlinedButton.icon(
                key: const ValueKey('edit-commerce-catalog-item'),
                onPressed: () => onEdit(listKey, item),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Изменить'),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        _property('Стабильный ключ', item['stableKey']),
        _property('Состояние', item['active'] == true ? 'Активно' : 'В архиве'),
        if (settlement) ...[
          _property(
            'Цветовая метка',
            _decisionColorLabels[item['colorToken']] ?? item['colorToken'],
          ),
          _property(
            'Доля списания',
            '${((item['hourShareBasisPoints'] as num?) ?? 0) / 100}%',
          ),
          if (item['fixedPenaltyMinor'] != null)
            _property(
              'Дополнительное списание',
              '${CrmConfigurationSnapshotOps.minorToMajor(item['fixedPenaltyMinor'])} ₽',
            ),
          _property(
            'Сценарии',
            (item['allowedContexts'] as List? ?? const [])
                .map((value) => _settlementContextLabels[value] ?? value)
                .join(', '),
          ),
          const SizedBox(height: AppSpace.md),
          Semantics(
            label: 'Предпросмотр: ${item['label']}',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                border: Border.all(color: accent),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: ListTile(
                leading: Icon(Icons.sell_outlined, color: accent),
                title: Text(item['label']?.toString() ?? ''),
                subtitle: const Text('Так метка выглядит в занятии'),
              ),
            ),
          ),
        ] else ...[
          _property(
            'Расчёт',
            _compensationModeLabels[item['mode']] ?? item['mode'],
          ),
          _property(
            'Значение',
            CrmConfigurationSnapshotOps.compensationValueLabel(item),
          ),
          const SizedBox(height: AppSpace.md),
          const Text(
            'Тип выбирается сотрудником вручную для каждого решения по занятию.',
          ),
        ],
      ],
    );
  }
}

class _CommerceCatalogEditorDialog extends StatefulWidget {
  const _CommerceCatalogEditorDialog({
    required this.settlement,
    required this.item,
    required this.nextOrder,
  });

  final bool settlement;
  final Map<String, dynamic>? item;
  final int nextOrder;

  @override
  State<_CommerceCatalogEditorDialog> createState() =>
      _CommerceCatalogEditorDialogState();
}

class _CommerceCatalogEditorDialogState
    extends State<_CommerceCatalogEditorDialog> {
  late final _key = TextEditingController(
    text: widget.item?['stableKey']?.toString() ?? '',
  );
  late final _label = TextEditingController(
    text: widget.item?['label']?.toString() ?? '',
  );
  late final _share = TextEditingController(
    text: CrmConfigurationSnapshotOps.hundredthsToDecimal(
      widget.item?['hourShareBasisPoints'] ?? 10000,
    ),
  );
  late final _penalty = TextEditingController(
    text: widget.item?['fixedPenaltyMinor'] == null
        ? ''
        : CrmConfigurationSnapshotOps.hundredthsToDecimal(
            widget.item!['fixedPenaltyMinor'],
          ),
  );
  late final _value = TextEditingController(
    text: CrmConfigurationSnapshotOps.hundredthsToDecimal(
      widget.item?['value'] ?? '0',
    ),
  );
  late String _color = widget.item?['colorToken']?.toString() ?? 'neutral';
  late String _mode = widget.item?['mode']?.toString() ?? 'none';
  late final Set<String> _contexts = {
    for (final context
        in (widget.item?['allowedContexts'] as List? ?? const ['settle']))
      context.toString(),
  };
  late bool _active = widget.item?['active'] != false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _share.dispose();
    _penalty.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.item == null
          ? widget.settlement
                ? 'Новый тип списания'
                : 'Новый тип оплаты преподавателю'
          : 'Настройка типа',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Название *'),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _key,
              enabled: widget.item == null,
              decoration: const InputDecoration(
                labelText: 'Стабильный ключ *',
                helperText: 'После публикации ключ нельзя переименовать',
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            if (widget.settlement) ...[
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                key: const ValueKey('commerce-settlement-color'),
                initialValue: _color,
                decoration: const InputDecoration(
                  labelText: 'Цвет метки в деталях и истории *',
                ),
                items: [
                  for (final entry in _decisionColorLabels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Row(
                        children: [
                          Icon(
                            Icons.sell_outlined,
                            size: 18,
                            color: lessonDecisionColorToken(entry.key),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Text(entry.value),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _color = value!),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _share,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Доля списания, % *',
                  helperText: 'От 0 до 200%',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _penalty,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Дополнительное фиксированное списание, ₽',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Доступно при',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final entry in _settlementContextLabels.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _contexts.contains(entry.key),
                  title: Text(entry.value),
                  onChanged: (selected) => setState(() {
                    selected == true
                        ? _contexts.add(entry.key)
                        : _contexts.remove(entry.key);
                  }),
                ),
            ] else ...[
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                key: const ValueKey('commerce-compensation-mode'),
                initialValue: _mode,
                decoration: const InputDecoration(labelText: 'Расчёт *'),
                items: [
                  for (final entry in _compensationModeLabels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _mode = value!;
                  if (const {'none', 'standard'}.contains(_mode)) {
                    _value.text = '0';
                  }
                }),
              ),
              if (!const {'none', 'standard'}.contains(_mode)) ...[
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _mode == 'percent'
                        ? 'Процент ставки, % *'
                        : 'Сумма, ₽ *',
                    helperText: _mode == 'percent' ? 'От 0 до 200%' : null,
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.only(top: AppSpace.md),
                child: Text(
                  'Этот тип не связывается автоматически с типом списания.',
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: Text(_active ? 'Активно' : 'В архиве'),
              subtitle: const Text('Архив сохраняет прежние факты и историю'),
              onChanged: (value) => setState(() => _active = value),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColor.danger)),
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

  void _submit() {
    final identity = _validatedIdentity();
    if (identity == null) return;
    final payload = widget.settlement
        ? _settlementPayload(identity)
        : _compensationPayload(identity);
    if (payload != null) Navigator.pop(context, payload);
  }

  ({String key, String label})? _validatedIdentity() {
    final key = _key.text.trim();
    final label = _label.text.trim();
    if (RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(key) &&
        label.isNotEmpty) {
      return (key: key, label: label);
    }
    setState(() {
      _error = 'Заполните название и корректный стабильный ключ.';
    });
    return null;
  }

  Map<String, dynamic>? _settlementPayload(
    ({String key, String label}) identity,
  ) {
    final share = CrmConfigurationSnapshotOps.decimalToHundredths(_share.text);
    final penalty = _penalty.text.trim().isEmpty
        ? null
        : CrmConfigurationSnapshotOps.decimalToHundredths(_penalty.text);
    if (share == null ||
        BigInt.parse(share) > BigInt.from(20000) ||
        (penalty == null && _penalty.text.trim().isNotEmpty) ||
        _contexts.isEmpty) {
      setState(() {
        _error =
            'Укажите долю от 0 до 200%, дополнительное списание и сценарий.';
      });
      return null;
    }
    final contexts = _contexts.toList()..sort();
    return <String, dynamic>{
      'stableKey': identity.key,
      'label': identity.label,
      'colorToken': _color,
      'hourShareBasisPoints': int.parse(share),
      'fixedPenaltyMinor': ?penalty,
      'allowedContexts': contexts,
      'active': _active,
      'order': widget.item?['order'] ?? widget.nextOrder,
    };
  }

  Map<String, dynamic>? _compensationPayload(
    ({String key, String label}) identity,
  ) {
    final rawValue = const {'none', 'standard'}.contains(_mode)
        ? '0'
        : CrmConfigurationSnapshotOps.decimalToHundredths(_value.text);
    if (rawValue == null ||
        (_mode == 'percent' && BigInt.parse(rawValue) > BigInt.from(20000))) {
      setState(() => _error = 'Укажите корректное значение от 0 до 200%.');
      return null;
    }
    return <String, dynamic>{
      'stableKey': identity.key,
      'label': identity.label,
      'mode': _mode,
      'value': rawValue,
      'active': _active,
      'order': widget.item?['order'] ?? widget.nextOrder,
    };
  }
}
