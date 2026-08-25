part of 'client_card.dart';

extension _ClientCardContactEditors on _ClientCardState {
  // ── KVA-234: мультидисциплины ─────────────────────────────────────────────
  // Массив custom_data['disciplines']; одиночное discipline остаётся для
  // совместимости и пишется первым элементом массива.
  List<String> _disciplinesForEntity(String entity) {
    final customData = _customDataForEntity(entity);
    final raw = customData['disciplines'];
    if (raw is List) {
      return raw
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList();
    }
    final single = customData['discipline']?.toString();
    return single == null || single.isEmpty ? const [] : [single];
  }

  void _toggleDiscipline(String entity, String name) {
    final current = _disciplinesForEntity(entity);
    final next = current.contains(name)
        ? current.where((value) => value != name).toList()
        : [...current, name];
    _updateCustomDataForEntity(entity, 'disciplines', next);
    _updateCustomDataForEntity(
      entity,
      'discipline',
      next.isEmpty ? null : next.first,
    );
  }

  Widget _buildDisciplinesChips(ColorScheme cs, String entity) {
    final selected = _disciplinesForEntity(entity);
    // Справочник — GET /crm/disciplines; при пустом ответе fallback на опции
    // custom-поля discipline из схемы. Выбранные значения всегда видимы.
    final schemaOptions = _customFieldSchema
        .where((field) => field.entity == entity && field.key == 'discipline')
        .expand((field) => field.options);
    final options = <String>{
      for (final row in _disciplineOptions)
        if ((row['name']?.toString() ?? '').isNotEmpty) row['name'].toString(),
      if (_disciplineOptions.isEmpty) ...schemaOptions,
      ...selected,
    }.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: InputDecorator(
        decoration: _inputDecoration(cs, label: 'Направления', isDense: true),
        child: options.isEmpty
            ? Text(
                'Справочник направлений пуст',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              )
            : Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: options.map((name) {
                  return FilterChip(
                    label: Text(name),
                    selected: selected.contains(name),
                    visualDensity: VisualDensity.compact,
                    selectedColor: AppColor.gold.withValues(alpha: 0.22),
                    checkmarkColor: AppColor.gold,
                    onSelected: (_) => _toggleDiscipline(entity, name),
                  );
                }).toList(),
              ),
      ),
    );
  }

  // ── KVA-234: контактные лица ──────────────────────────────────────────────
  // Массив custom_data['contactPersons'] [{name, relation, phone, email}].
  // Миграция на лету: пока массива нет, старые одиночные contactPerson*-поля
  // показываются первым элементом; любое изменение пишет уже массив.
  List<Map<String, dynamic>> _contactPersonsForEntity(String entity) {
    final customData = _customDataForEntity(entity);
    final raw = customData['contactPersons'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    final legacy = <String, dynamic>{
      'name': customData['contactPersonName']?.toString() ?? '',
      'relation': customData['contactPersonRelation']?.toString() ?? '',
      'phone': customData['contactPersonPhone']?.toString() ?? '',
      'email': customData['contactPersonEmail']?.toString() ?? '',
    }..removeWhere((_, value) => (value as String).isEmpty);
    return legacy.isEmpty ? const [] : [legacy];
  }

  void _writeContactPersons(String entity, List<Map<String, dynamic>> persons) {
    _updateCustomDataForEntity(entity, 'contactPersons', persons);
    // Первый элемент зеркалится в старые одиночные поля для совместимости.
    final first = persons.isNotEmpty
        ? persons.first
        : const <String, dynamic>{};
    _updateCustomDataForEntity(entity, 'contactPersonName', first['name']);
    _updateCustomDataForEntity(
      entity,
      'contactPersonRelation',
      first['relation'],
    );
    _updateCustomDataForEntity(entity, 'contactPersonPhone', first['phone']);
    _updateCustomDataForEntity(entity, 'contactPersonEmail', first['email']);
  }

  Future<void> _editContactPerson(String entity, {int? index}) async {
    final persons = _contactPersonsForEntity(entity);
    final existing = index == null ? const <String, dynamic>{} : persons[index];
    final relation = existing['relation']?.toString() ?? '';
    final relationOptions = _customFieldSchema
        .where(
          (field) =>
              field.entity == entity && field.key == 'contactPersonRelation',
        )
        .expand((field) => field.options)
        .toList();
    if (relation.isNotEmpty && !relationOptions.contains(relation)) {
      relationOptions.add(relation);
    }
    final person = await showEditContactPersonDialog(
      context,
      existing: existing,
      relationOptions: relationOptions,
      isNew: index == null,
    );
    if (person == null) return;
    final next = [...persons];
    if (index == null) {
      next.add(person);
    } else {
      next[index] = person;
    }
    _writeContactPersons(entity, next);
  }

  Widget _buildContactPersonsEditor(ColorScheme cs, String entity) {
    final persons = _contactPersonsForEntity(entity);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final addButton = TextButton.icon(
                onPressed: () => _editContactPerson(entity),
                style: TextButton.styleFrom(
                  foregroundColor: AppColor.gold,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('Добавить контактное лицо'),
              );
              const title = Text(
                'Контактные лица',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              );
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, addButton],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  addButton,
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          if (persons.isEmpty)
            Text(
              'Контактные лица не указаны',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            )
          else
            ...List.generate(persons.length, (i) {
              final person = persons[i];
              final name = person['name']?.toString().trim() ?? '';
              final subtitle = [
                person['relation'],
                person['phone'],
                person['email'],
              ].where((v) => v != null && '$v'.isNotEmpty).join(' · ');
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    side: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  title: Text(
                    name.isEmpty ? 'Без имени' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: subtitle.isEmpty
                      ? null
                      : Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        tooltip: 'Изменить',
                        onPressed: () => _editContactPerson(entity, index: i),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: AppTheme.danger,
                        ),
                        tooltip: 'Удалить',
                        onPressed: () => _writeContactPersons(
                          entity,
                          [...persons]..removeAt(i),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
