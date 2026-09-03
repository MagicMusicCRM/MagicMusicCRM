part of 'client_card.dart';

extension _ClientCardCustomFieldInputs on _ClientCardState {
  Widget _buildSingleChoiceCustomField(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
    String label,
    Object? rawValue,
  ) {
    final current = rawValue?.toString() ?? '';
    final selectedId = field.options.contains(current) ? current : null;
    if (field.type == 'radio') {
      return _buildRadioCustomField(cs, field, label, selectedId);
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

  Widget _buildRadioCustomField(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
    String label,
    String? selectedId,
  ) {
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
                  if (!selected) return;
                  _updateCustomDataForEntity(field.entity, field.key, option);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBooleanCustomField(
    CrmCustomFieldDefinition field,
    String label,
    Object? rawValue,
  ) {
    final selected = rawValue == true || rawValue?.toString() == 'true';
    if (field.type == 'toggle') {
      return SwitchListTile(
        value: selected,
        activeThumbColor: AppColor.gold,
        onChanged: (value) =>
            _updateCustomDataForEntity(field.entity, field.key, value),
        title: Text(label),
        subtitle: field.hint == null ? null : Text(field.hint!),
        contentPadding: EdgeInsets.zero,
      );
    }
    return CheckboxListTile(
      value: selected,
      onChanged: (value) =>
          _updateCustomDataForEntity(field.entity, field.key, value == true),
      title: Text(label),
      subtitle: field.hint == null ? null : Text(field.hint!),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildMultiChoiceCustomField(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
    String label,
    Object? rawValue,
  ) {
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
          final picked = await showMagicDatePicker(
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
          final date = await showMagicDatePicker(
            context: pickerContext,
            initialDate: current ?? DateTime.now(),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
            initialEntryMode: DatePickerEntryMode.input,
          );
          if (date == null || !pickerContext.mounted) return;
          final time = await showMagicTimePicker(
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
}
