part of 'client_card.dart';

extension _ClientCardCustomFields on _ClientCardState {
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
}
