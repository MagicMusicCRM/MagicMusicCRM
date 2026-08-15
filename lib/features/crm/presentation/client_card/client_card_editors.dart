part of 'client_card.dart';

extension _ClientCardEditors on _ClientCardState {
  Widget _buildClientTextField(
    ColorScheme cs,
    String label,
    String? value,
    ValueChanged<String?> onChanged, {
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: TextFormField(
        // Keyed on the data epoch, NOT the live value: a value-derived key
        // recreated the field on every keystroke, dropping cursor/IME state.
        key: ValueKey('$label-$_editorEpoch'),
        initialValue: value ?? '',
        decoration: _inputDecoration(cs, label: label, isDense: true),
        keyboardType: keyboard,
        onChanged: (v) => onChanged(v.trim().isEmpty ? null : v),
      ),
    );
  }

  List<Widget> _buildCustomFieldControls(
    ColorScheme cs,
    String entity, {
    Set<String>? includeKeys,
    Set<String> excludedKeys = const {},
  }) {
    final fields = _customFieldSchema
        .where(
          (field) =>
              field.entity == entity &&
              (field.placements.contains('edit') ||
                  field.placements.contains('card')) &&
              !_isSystemOnlyCustomField(field.key) &&
              (includeKeys == null || includeKeys.contains(field.key)) &&
              !excludedKeys.contains(field.key),
        )
        .toList();
    if (fields.isEmpty) {
      return [
        Text(
          'Дополнительные поля не настроены',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      ];
    }
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final useSingleColumn = available < 520;
          double fieldWidth(CrmCustomFieldDefinition field) {
            if (useSingleColumn) return available;
            return switch (field.width) {
              'third' => (available - AppSpace.sm * 2) / 3,
              'half' => (available - AppSpace.sm) / 2,
              _ => available,
            };
          }

          return Wrap(
            spacing: AppSpace.sm,
            runSpacing: 0,
            children: [
              for (final field in fields)
                SizedBox(
                  key: ValueKey('custom-field-layout-${field.key}'),
                  width: fieldWidth(field),
                  child: _buildCustomFieldControl(cs, field),
                ),
            ],
          );
        },
      ),
    ];
  }

  /// #9: чтение-алиасы для полей, чьи настоящие данные выгрузка HolliHop
  /// положила под другим ключом. Показ подхватывает легаси-ключ, запись всегда
  /// идёт в канонический (алиас остаётся нетронутым фолбэком).
  static const Map<String, String> _customFieldReadAliases = {
    'requestType': 'addressType',
    'responsible': 'responsibleName',
  };

  Widget _buildCustomFieldControl(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
  ) {
    if (!field.placements.contains('edit')) {
      return _buildReadOnlyCustomField(cs, field);
    }
    final customData = _customDataForEntity(field.entity);
    final alias = _customFieldReadAliases[field.key];
    final rawValue =
        customData[field.key] ?? (alias == null ? null : customData[alias]);
    final label = field.required ? '${field.label} *' : field.label;

    if (field.type == 'select' || field.type == 'radio') {
      final current = rawValue?.toString() ?? '';
      final selectedId = field.options.contains(current) ? current : null;
      if (field.type == 'radio') {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: InputDecorator(
            decoration: _inputDecoration(cs, label: label, isDense: true),
            child: Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final option in field.options)
                  ChoiceChip(
                    label: Text(option),
                    selected: selectedId == option,
                    onSelected: (selected) {
                      if (selected) {
                        _updateCustomDataForEntity(
                          field.entity,
                          field.key,
                          option,
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: SearchablePickerField(
          label: label,
          selectedId: selectedId,
          placeholder: 'Выберите значение',
          hintText: field.hint ?? 'Введите значение для поиска',
          items: [
            for (final option in field.options)
              SearchableSelectItem(id: option, label: option),
          ],
          onSelected: (item) =>
              _updateCustomDataForEntity(field.entity, field.key, item?.id),
        ),
      );
    }

    if (field.type == 'boolean' || field.type == 'toggle') {
      final control = SwitchListTile(
        value: rawValue == true || rawValue?.toString() == 'true',
        activeThumbColor: AppColor.gold,
        onChanged: (value) =>
            _updateCustomDataForEntity(field.entity, field.key, value),
        title: Text(label),
        subtitle: field.hint == null ? null : Text(field.hint!),
        contentPadding: EdgeInsets.zero,
      );
      if (field.type == 'toggle') return control;
      return CheckboxListTile(
        value: rawValue == true || rawValue?.toString() == 'true',
        onChanged: (value) =>
            _updateCustomDataForEntity(field.entity, field.key, value == true),
        title: Text(label),
        subtitle: field.hint == null ? null : Text(field.hint!),
        contentPadding: EdgeInsets.zero,
      );
    }

    if (field.type == 'date') {
      return _buildDateCustomField(cs, field, rawValue?.toString());
    }

    if (field.type == 'datetime') {
      return _buildDateTimeCustomField(cs, field, rawValue?.toString());
    }

    if (field.type == 'multi_select' || field.type == 'checkbox_group') {
      final selected = (rawValue as List? ?? const [])
          .map((value) => value.toString())
          .toSet();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: InputDecorator(
          decoration: _inputDecoration(cs, label: label, isDense: true),
          child: Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final option in field.options)
                FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (checked) {
                    final next = {...selected};
                    checked ? next.add(option) : next.remove(option);
                    _updateCustomDataForEntity(
                      field.entity,
                      field.key,
                      next.toList(growable: false),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    }

    return _buildCustomTextField(
      cs,
      label,
      field,
      rawValue?.toString(),
      keyboard: _keyboardForCustomField(field.type),
    );
  }

  Widget _buildReadOnlyCustomField(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
  ) {
    final customData = _customDataForEntity(field.entity);
    final alias = _customFieldReadAliases[field.key];
    final rawValue =
        customData[field.key] ?? (alias == null ? null : customData[alias]);
    final value = switch (field.type) {
      'boolean' || 'toggle' => rawValue == true ? 'Да' : 'Нет',
      'multi_select' || 'checkbox_group' when rawValue is Iterable =>
        rawValue.map((item) => item.toString()).join(', '),
      'date' => _formatCustomDate(rawValue, withTime: false),
      'datetime' => _formatCustomDate(rawValue, withTime: true),
      'money' when rawValue != null => '$rawValue ₽',
      'duration' when rawValue != null => '$rawValue мин.',
      _ => rawValue?.toString() ?? '',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: InputDecorator(
        key: ValueKey('custom-field-readonly-${field.key}'),
        decoration: _inputDecoration(cs, label: field.label, isDense: true),
        child: Text(
          value.trim().isEmpty ? 'Не указано' : value,
          style: TextStyle(
            color: value.trim().isEmpty ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ),
      ),
    );
  }

  String _formatCustomDate(Object? rawValue, {required bool withTime}) {
    final parsed = DateTime.tryParse(rawValue?.toString() ?? '')?.toLocal();
    if (parsed == null) return rawValue?.toString() ?? '';
    return DateFormat(
      withTime ? 'dd.MM.yyyy HH:mm' : 'dd.MM.yyyy',
    ).format(parsed);
  }

  bool _isSystemOnlyCustomField(String key) => _ClientCardState
      ._systemOnlyCustomFieldKeys
      .contains(_normalizedCustomKey(key));

  String _normalizedCustomKey(String key) =>
      key.trim().replaceAll('-', '_').toLowerCase();

  Map<String, dynamic> _customDataForEntity(String entity) {
    if (entity == 'students' && _student != null) {
      return Map<String, dynamic>.from(_student!['custom_data'] as Map? ?? {});
    }
    return Map<String, dynamic>.from(_leadData['custom_data'] as Map? ?? {});
  }

  Widget _buildCustomTextField(
    ColorScheme cs,
    String label,
    CrmCustomFieldDefinition field,
    String? value, {
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: TextFormField(
        // Epoch key, not value key — see _buildClientTextField.
        key: ValueKey('${field.entity}-${field.key}-$_editorEpoch'),
        initialValue: value ?? '',
        maxLines: field.type == 'textarea' ? 4 : 1,
        decoration: _inputDecoration(
          cs,
          label: label,
          helperText: field.hint,
          isDense: true,
        ),
        keyboardType: keyboard,
        onChanged: (v) {
          final trimmed = v.trim();
          final numeric = const {
            'number',
            'money',
            'duration',
          }.contains(field.type);
          _updateCustomDataForEntity(
            field.entity,
            field.key,
            trimmed.isEmpty
                ? null
                : numeric
                ? num.tryParse(trimmed.replaceAll(',', '.'))
                : v,
          );
        },
      ),
    );
  }

  Widget _buildDateCustomField(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
    String? value,
  ) {
    final dt = value == null ? null : DateTime.tryParse(value);
    final display = dt != null
        ? DateFormat('dd.MM.yyyy', 'ru').format(dt)
        : 'Не выбрано';
    final label = field.required ? '${field.label} *' : field.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: dt ?? DateTime.now(),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
            // Dates here are often far away (birthdates) — allow typing.
            initialEntryMode: DatePickerEntryMode.input,
          );
          if (picked != null) {
            _updateCustomDataForEntity(
              field.entity,
              field.key,
              DateFormat('yyyy-MM-dd').format(picked),
            );
          }
        },
        child: InputDecorator(
          decoration: _inputDecoration(
            cs,
            label: label,
            helperText: field.hint,
            isDense: true,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(display),
              const Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: AppColor.gold,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimeCustomField(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
    String? value,
  ) {
    final current = value == null ? null : DateTime.tryParse(value)?.toLocal();
    final label = field.required ? '${field.label} *' : field.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () async {
          final pickerContext = context;
          final date = await showDatePicker(
            context: pickerContext,
            initialDate: current ?? DateTime.now(),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
            initialEntryMode: DatePickerEntryMode.input,
          );
          if (date == null || !pickerContext.mounted) return;
          final time = await showTimePicker(
            context: pickerContext,
            initialTime: current == null
                ? TimeOfDay.now()
                : TimeOfDay.fromDateTime(current),
          );
          if (time == null) return;
          _updateCustomDataForEntity(
            field.entity,
            field.key,
            DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            ).toIso8601String(),
          );
        },
        child: InputDecorator(
          decoration: _inputDecoration(
            cs,
            label: label,
            helperText: field.hint,
            isDense: true,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                current == null
                    ? 'Не выбрано'
                    : DateFormat('dd.MM.yyyy HH:mm', 'ru').format(current),
              ),
              const Icon(Icons.event_rounded, size: 16, color: AppColor.gold),
            ],
          ),
        ),
      ),
    );
  }

  /// Переключатель чёрного списка.
  ///
  /// ✔ Решение владельца 17.07: это бан — клиенту закрываются чаты школы и
  /// администрации. Поэтому не обычный тумблер:
  ///  - при постановке спрашиваем причину: через месяц «почему он в чёрном
  ///    списке» больше спросить будет не у кого;
  ///  - применяется сразу своим запросом, а не копится до «Сохранить» вместе с
  ///    остальными полями. Бан — не правка карточки, и уехать заодно с ней он
  ///    не должен.
  Widget _buildBlacklistToggle(ColorScheme cs) {
    final banned = _isBlacklisted;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: SwitchListTile(
        value: banned,
        activeThumbColor: AppTheme.danger,
        contentPadding: EdgeInsets.zero,
        title: const Text('Чёрный список'),
        subtitle: Text(
          banned
              ? (_blacklistReason ?? 'Причина не указана')
              : 'Клиент не сможет писать в чаты школы и администрации',
          style: TextStyle(
            fontSize: 12,
            color: banned ? AppTheme.danger : cs.onSurfaceVariant,
          ),
        ),
        onChanged: _blacklistBusy ? null : (value) => _toggleBlacklist(value),
      ),
    );
  }

  Future<void> _toggleBlacklist(bool value) async {
    String? reason;
    if (value) {
      reason = await _askBlacklistReason();
      // Отмена диалога — это отмена бана, а не бан без причины.
      if (reason == null) return;
    }

    _emitState(() => _blacklistBusy = true);
    try {
      // Банится та половина карточки, которая есть: аккаунт клиента цепляется
      // к любой из них, и бан только на ученике оставил бы лиду открытый чат.
      final service = ref.read(magicCrmServiceProvider);
      if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
        await service.setClientBlacklist(
          entity: 'students',
          id: _studentId,
          blacklisted: value,
          reason: reason,
        );
      }
      if (_mode.hasLeadHalf && _leadId.isNotEmpty) {
        await service.setClientBlacklist(
          entity: 'leads',
          id: _leadId,
          blacklisted: value,
          reason: reason,
        );
      }
      // Перечитываем ту половину, которая открыта: флаг едет в её DTO.
      if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
        await _fetchStudentData();
      } else {
        await _fetchCard();
      }
      unawaited(_reloadOperationalHistory());
      if (mounted) {
        MagicToast.show(
          context,
          value ? 'Клиент в чёрном списке' : 'Клиент убран из чёрного списка',
          type: value ? MagicToastType.danger : MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось изменить чёрный список',
          detail: userErrorMessage(e),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _blacklistBusy = false);
    }
  }

  Future<String?> _askBlacklistReason() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('В чёрный список'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Клиент не сможет писать в чаты школы и администрации. '
              'Отменить это может любой администратор или управляющий.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Причина',
                hintText: 'Например: оскорблял администратора в чате',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('В чёрный список'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    // Причину не требуем: заставлять сочинять текст ради галочки — верный
    // способ получить «...» в каждой второй карточке. Пустая строка честнее.
    return controller.text.trim();
  }

  /// Редактор возраста.
  ///
  /// ✔ Решение владельца 17.07: возраст можно вписать руками, а можно поставить
  /// дату рождения — и тогда он считается сам. Отсюда два вида этого поля:
  ///
  ///  - дата рождения стоит → возраст **только показываем**. Считает его сервер
  ///    (`age.ts`), и он сам меняется с годами. Поле для ввода здесь было бы
  ///    обманом: вписанное в него число не читается никем;
  ///  - даты рождения нет → обычное числовое поле.
  ///
  /// Условие — наличие даты рождения, а не повторение правила расчёта: сам
  /// возраст здесь не вычисляется, иначе правило разъехалось бы с сервером.
  Widget _buildAgeCustomField(ColorScheme cs, String entity) {
    final matches = _customFieldSchema.where(
      (f) => f.entity == entity && f.key == 'age',
    );
    if (matches.isEmpty) return const SizedBox.shrink();
    final field = matches.first;

    final customData = _customDataForEntity(entity);
    final hasBirthday =
        (customData['birthday']?.toString().trim() ?? '').isNotEmpty;

    if (!hasBirthday) {
      return _buildCustomTextField(
        cs,
        field.label,
        field,
        customData['age']?.toString(),
        keyboard: TextInputType.number,
      );
    }

    final label = _ageLabel();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: InputDecorator(
        decoration: _inputDecoration(
          cs,
          label: field.label,
          helperText: 'Считается по дате рождения',
          isDense: true,
        ),
        child: Row(
          children: [
            const Icon(Icons.cake_outlined, size: 16, color: AppColor.gold),
            const SizedBox(width: AppSpace.sm),
            Text(label ?? 'Не удалось разобрать дату рождения'),
          ],
        ),
      ),
    );
  }

  TextInputType? _keyboardForCustomField(String type) {
    return switch (type) {
      'number' ||
      'money' ||
      'duration' => const TextInputType.numberWithOptions(decimal: true),
      'phone' => TextInputType.phone,
      'email' => TextInputType.emailAddress,
      'url' => TextInputType.url,
      _ => null,
    };
  }

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

  Widget _buildBranchDropdown(ColorScheme cs, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: SearchablePickerField(
        label: label,
        selectedId: _clientBranchId,
        placeholder: 'Выберите филиал',
        hintText: 'Введите название филиала',
        isNullable: false,
        items: _branches
            .map(
              (branch) => SearchableSelectItem(
                id: branch['id'].toString(),
                label: branch['name']?.toString() ?? 'Не указано',
              ),
            )
            .toList(growable: false),
        onSelected: (item) => _updateClientCore('branchId', item?.id),
      ),
    );
  }

  Widget _buildSourceDropdown(ColorScheme cs) {
    final current = _clientSourceId;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: SearchablePickerField(
        key: ValueKey('client-source-$_editorEpoch'),
        label: 'Рекламный источник *',
        selectedId: current,
        placeholder: 'Выберите источник',
        hintText: 'Введите название источника',
        isNullable: false,
        items: _sources
            .where(
              (source) =>
                  source['isActive'] == true ||
                  source['id']?.toString() == current,
            )
            .map((source) {
              final id = source['id']?.toString() ?? '';
              final active = source['isActive'] == true;
              return SearchableSelectItem(
                id: id,
                label:
                    '${active ? '' : 'Архив · '}${source['displayName'] ?? 'Не указано'}',
              );
            })
            .toList(growable: false),
        onSelected: (item) => _updateClientCore('sourceId', item?.id),
      ),
    );
  }

  // ── #7: пикер «Ответственный» ─────────────────────────────────────────────
  // Заменяет свободный текст выбором сотрудника из GET /api/admin/staff.
  // Пишет custom_data.responsible (имя — обратная совместимость с бэкфиллом
  // HolliHop) и custom_data.responsibleUserId (uuid). Показ подхватывает и
  // легаси responsibleName, у которого id нет.

  String? _responsibleDisplayValue(String entity) {
    if (entity == 'leads') {
      final assignedName = _leadData['assigned_name']?.toString().trim();
      if (assignedName != null && assignedName.isNotEmpty) return assignedName;
    }
    final customData = _customDataForEntity(entity);
    for (final key in const ['responsible', 'responsibleName']) {
      final v = customData[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    // Кросс-половинный легаси-фолбэк (responsibleName другой половины или
    // FullName первого assignee из выгрузки HolliHop).
    return _responsibleLabel();
  }

  void _setResponsible(String entity, {String? name, String? userId}) {
    final normalizedId = userId?.trim();
    final isClear = normalizedId == null || normalizedId.isEmpty;
    final mirrorConverted = _mode == ClientMode.converted;
    final updateLead = entity == 'leads' || mirrorConverted;
    final updateStudent = entity == 'students' || mirrorConverted;

    _emitState(() {
      if (updateLead) {
        _leadResponsibleChanged = true;
        if (isClear) {
          _leadData.remove('assigned_to');
          _leadData.remove('assigned_name');
          final customData =
              Map<String, dynamic>.from(_leadData['custom_data'] as Map? ?? {})
                ..removeWhere(
                  (key, _) => const {
                    'responsible',
                    'responsibleUserId',
                    'responsibleName',
                  }.contains(key),
                );
          _leadData['custom_data'] = customData;
        } else {
          _leadData['assigned_to'] = normalizedId;
          _leadData['assigned_name'] = name;
        }
      }

      if (updateStudent) {
        _studentResponsibleChanged = true;
        final student = _student;
        if (student != null) {
          final customData = Map<String, dynamic>.from(
            student['custom_data'] as Map? ?? {},
          );
          if (isClear) {
            customData.remove('responsible');
            customData.remove('responsibleUserId');
            customData.remove('responsibleName');
          } else {
            customData['responsible'] = name;
            customData['responsibleUserId'] = normalizedId;
            customData.remove('responsibleName');
          }
          student['custom_data'] = customData;
        }
      }
      _edited = true;
    });
  }

  Future<void> _pickResponsible(String entity) async {
    final crm = ref.read(magicCrmServiceProvider);

    Future<List<SearchableSelectItem>> search(String query) async {
      final rows = await crm.listResponsibleStaff(search: query);
      return rows.map((row) {
        return SearchableSelectItem(
          id: row['id'].toString(),
          label: row['name']?.toString() ?? 'Без имени',
          subtitle: _staffRoleLabel(row['role']),
        );
      }).toList();
    }

    SearchableSelect.show(
      context: context,
      title: 'Ответственный',
      hintText: 'Имя сотрудника…',
      items: const [],
      isNullable: true,
      onSearch: search,
      onSelected: (item) {
        if (item == null) {
          _setResponsible(entity, name: null, userId: null);
          return;
        }
        _setResponsible(entity, name: item.label, userId: item.id);
      },
    );
  }

  String? _staffRoleLabel(Object? role) {
    return switch (role?.toString()) {
      'admin' => 'Администратор',
      'manager' => 'Управляющий',
      'director' => 'Директор',
      'system_admin' => 'Администратор системы',
      final v when v != null && v.isNotEmpty => v,
      _ => null,
    };
  }

  Widget _buildResponsiblePicker(ColorScheme cs, String entity) {
    final value = _responsibleDisplayValue(entity);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () => _pickResponsible(entity),
        child: InputDecorator(
          decoration: _inputDecoration(
            cs,
            label: 'Ответственный',
            isDense: true,
            suffixIcon: value == null
                ? const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: AppColor.gold,
                  )
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () =>
                        _setResponsible(entity, name: null, userId: null),
                  ),
          ),
          child: Text(
            value ?? 'Не выбран',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: value == null ? TextStyle(color: cs.onSurfaceVariant) : null,
          ),
        ),
      ),
    );
  }

  /// Staff может выбрать поток комментария; педагог всегда пишет teacher_note.
  bool get _canPickCommentKind {
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    final isStaff =
        role == 'admin' ||
        role == 'manager' ||
        role == 'director' ||
        role == 'system_admin';
    final targetIsStudent = _isConverted || widget.entityType == 'student';
    return isStaff && targetIsStudent;
  }

  Widget _buildCommentInput(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_canPickCommentKind) ...[
          Wrap(
            spacing: AppSpace.sm,
            children: [
              for (final (kind, label) in const [
                ('admin_comment', 'Комментарий админа'),
                ('teacher_note', 'Для педагога'),
              ])
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: _commentKind == kind,
                  // #11: галочка + подпись ниже — чтобы выбор потока читался
                  // как выбор, а не как кнопка, которая «ничего не делает».
                  showCheckmark: true,
                  checkmarkColor: AppColor.gold,
                  selectedColor: AppColor.goldSoft,
                  onSelected: (_) => _emitState(() => _commentKind = kind),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            _commentKind == 'teacher_note'
                ? 'Комментарий увидит и педагог'
                : 'Комментарий виден только админам',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                decoration: _inputDecoration(
                  cs,
                  hint: 'Написать комментарий...',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Tooltip(
              message: 'Отправить комментарий',
              child: Material(
                color: AppColor.gold,
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: _addComment,
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpace.md),
                    child: Icon(
                      Icons.send_rounded,
                      color: AppColor.onGold,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAggregateCard(ColorScheme cs, {bool includeTasks = true}) {
    return _aggregateCard(
      cs,
      loadingCard: _loadingCard,
      card: _leadCard,
      duplicateCount: _duplicateCandidates
          .where(_isCurrentLeadDuplicateCandidate)
          .length,
      loadingDuplicates: _loadingDuplicates,
      includeTasks: includeTasks,
    );
  }

  // Reads the family id out of either the existing `_family` payload or the
  // raw `createFamily` response (which nests the record under `family`).
  String? _familyIdFrom(Map<String, dynamic>? source) {
    if (source == null) return null;
    final direct = source['id']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = source['family'];
    if (nested is Map) {
      final id = nested['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> _openAddFamilyMemberSheet() async {
    final selfId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    final input = await showAddFamilyMemberSheet(
      context,
      isStudent: _isStudent,
      // Default the linked record to this card's own entity (lead or student).
      defaultEntityType: widget.entityType,
      defaultEntityId: selfId,
      defaultEntityLabel: _clientPresentationLabel,
    );
    if (input == null) return;
    final role = input.role;
    final entityType = input.entityType;
    final entityId = input.entityId;
    final isPrimaryContact = input.isPrimaryContact;
    if (entityId.isEmpty) {
      if (mounted) {
        MagicToast.show(
          context,
          'Выберите запись',
          type: MagicToastType.danger,
        );
      }
      return;
    }

    _emitState(() => _familyBusy = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);
      var familyId = _familyIdFrom(_family?['family'] as Map<String, dynamic>?);
      if (familyId == null) {
        final branchId = _leadData['branch_id']?.toString();
        final created = await crm.createFamily({
          if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
        });
        familyId = _familyIdFrom(created);
        if (familyId == null) {
          throw StateError('Не удалось получить идентификатор семьи');
        }
      }
      await crm.addFamilyMember(
        familyId,
        entityType: entityType,
        entityId: entityId,
        role: role,
        isPrimaryContact: isPrimaryContact ? true : null,
      );
      await _fetchFamily();
      if (mounted) {
        MagicToast.show(
          context,
          'Участник добавлен',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка добавления',
          detail: userErrorMessage(e),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _familyBusy = false);
    }
  }

  Future<void> _removeFamilyMember(FamilyMember member) async {
    final memberId = member.id;
    if (memberId.isEmpty) return;
    final name = member.name.trim().isNotEmpty ? member.name : 'участника';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('Связь "$name" с семьёй будет удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    _emitState(() => _familyBusy = true);
    try {
      await ref.read(magicCrmServiceProvider).removeFamilyMember(memberId);
      await _fetchFamily();
      if (mounted) {
        MagicToast.show(
          context,
          'Участник удалён',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка удаления',
          detail: userErrorMessage(e),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _familyBusy = false);
    }
  }

  Future<void> _setFamilyPrimaryPayer(FamilyMember member) async {
    final familyRecord = _family?['family'];
    final familyId = familyRecord is Map
        ? familyRecord['id']?.toString()
        : null;
    if (familyId == null || familyId.isEmpty || member.id.isEmpty) return;
    _emitState(() => _familyBusy = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .setFamilyPrimaryPayer(familyId, member.id);
      await _fetchFamily();
      if (mounted) {
        MagicToast.show(
          context,
          'Основной плательщик назначен',
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось назначить плательщика',
          detail: userErrorMessage(error),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _familyBusy = false);
    }
  }

  void _openFamilyMember(BuildContext sourceContext, FamilyMember member) {
    final entityType = member.entityType;
    final entityId = member.entityId;
    if (entityId == null || entityId.isEmpty) return;
    if (entityType != 'lead' && entityType != 'student') return;
    _openLinkedRecord(
      sourceContext,
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: entityId,
        variant: entityType,
        presentation: EntityPresentationReference(primary: member.name),
      ),
      EntityOpenTarget.current,
    );
  }

  Future<void> _linkClientUser(Map<String, dynamic> candidate) async {
    final userId =
        candidate['userId']?.toString() ?? candidate['user_id']?.toString();
    if (userId == null || userId.isEmpty) return;
    _emitState(() => _clientAccessBusy = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .linkUserToClient(widget.entityType, _entityId, userId);
      await _fetchClientAccess();
      if (mounted) {
        MagicToast.show(
          context,
          'Аккаунт связан с карточкой',
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось связать аккаунт',
          detail: userErrorMessage(error),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _clientAccessBusy = false);
    }
  }

  Future<void> _inviteClientToApp() async {
    final studentId = _studentId;
    if (studentId.isEmpty) return;
    _emitState(() => _clientAccessBusy = true);
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .inviteStudent(studentId);
      if (mounted) {
        MagicToast.show(
          context,
          'Приглашение отправлено',
          detail: result['email']?.toString(),
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось отправить приглашение',
          detail: userErrorMessage(error),
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) _emitState(() => _clientAccessBusy = false);
    }
  }

  bool _isCurrentLeadDuplicateCandidate(Map<String, dynamic> candidate) {
    final leadId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    if (leadId == null || leadId.isEmpty) return false;
    return (candidate['entity_type_a'] == 'lead' &&
            candidate['entity_id_a'] == leadId &&
            candidate['entity_type_b'] == 'student') ||
        (candidate['entity_type_b'] == 'lead' &&
            candidate['entity_id_b'] == leadId &&
            candidate['entity_type_a'] == 'student');
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    // New comments target the card's primary half: the student side for a
    // converted client (where most activity lives), otherwise the open entity.
    final targetType = _isConverted ? 'student' : widget.entityType;
    final targetId = _isConverted ? _studentId : _entityId;
    if (targetId.isEmpty) return;
    // kind существует только у entity_comments (ученик): staff выбирает поток,
    // педагог всегда пишет teacher_note (admin_comment ему запрещён RBAC'ом).
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    final kind = targetType != 'student'
        ? null
        : _canPickCommentKind
        ? _commentKind
        : role == 'teacher'
        ? 'teacher_note'
        : null;
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: targetType,
            entityId: targetId,
            body: text,
            kind: kind,
          );
      _commentCtrl.clear();
      if (mounted) {
        // #11: видимая обратная связь — что комментарий создан и в какой
        // поток он ушёл; выбор потока возвращается к безопасному дефолту.
        MagicToast.show(
          context,
          kind == 'teacher_note'
              ? 'Комментарий добавлен (для педагога)'
              : 'Комментарий добавлен',
          type: MagicToastType.success,
        );
        _emitState(() {
          _commentsRefreshKey++;
          _commentKind = 'admin_comment';
        });
        if (_mode.hasStudentHalf) {
          _fetchStudentData();
        }
        if (_mode.hasLeadHalf) {
          _fetchCard();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить изменение.'),
            ),
          ),
        );
      }
    }
  }
}
