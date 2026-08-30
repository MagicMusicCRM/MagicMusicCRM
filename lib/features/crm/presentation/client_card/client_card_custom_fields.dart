part of 'client_card.dart';

extension _ClientCardCustomFields on _ClientCardState {
  Widget _buildClientTextField(
    ColorScheme cs,
    String label,
    String? value,
    ValueChanged<String?> onChanged, {
    TextInputType? keyboard,
    String? errorText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: TextFormField(
        // Keyed on the data epoch, NOT the live value: a value-derived key
        // recreated the field on every keystroke, dropping cursor/IME state.
        key: ValueKey('$label-$_editorEpoch'),
        initialValue: value ?? '',
        decoration: _inputDecoration(
          cs,
          label: label,
          isDense: true,
        ).copyWith(errorText: errorText),
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
              !field.isSystem &&
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
  static const Set<String> _booleanCustomFieldTypes = {'boolean', 'toggle'};
  static const Set<String> _multiCustomFieldTypes = {
    'multi_select',
    'checkbox_group',
  };
  static const Map<String, String> _customFieldValueSuffixes = {
    'money': ' ₽',
    'duration': ' мин.',
  };

  Widget _buildCustomFieldControl(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
  ) {
    if (!field.placements.contains('edit')) {
      return _buildReadOnlyCustomField(cs, field);
    }
    final rawValue = _customFieldRawValue(field);
    final label = field.required ? '${field.label} *' : field.label;
    return switch (field.type) {
      'select' ||
      'radio' => _buildSingleChoiceCustomField(cs, field, label, rawValue),
      'boolean' || 'toggle' => _buildBooleanCustomField(field, label, rawValue),
      'date' => _buildDateCustomField(cs, field, rawValue?.toString()),
      'datetime' => _buildDateTimeCustomField(cs, field, rawValue?.toString()),
      'multi_select' || 'checkbox_group' => _buildMultiChoiceCustomField(
        cs,
        field,
        label,
        rawValue,
      ),
      _ => _buildCustomTextField(
        cs,
        label,
        field,
        rawValue?.toString(),
        keyboard: _keyboardForCustomField(field.type),
      ),
    };
  }

  Object? _customFieldRawValue(CrmCustomFieldDefinition field) {
    final customData = _customDataForEntity(field.entity);
    final alias = _customFieldReadAliases[field.key];
    return customData[field.key] ?? (alias == null ? null : customData[alias]);
  }

  Widget _buildReadOnlyCustomField(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
  ) {
    final rawValue = _customFieldRawValue(field);
    final value = _readOnlyCustomFieldValue(field.type, rawValue);
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

  String _readOnlyCustomFieldValue(String type, Object? rawValue) {
    if (type == 'date' || type == 'datetime') {
      return _formatCustomDate(rawValue, withTime: type == 'datetime');
    }
    if (_booleanCustomFieldTypes.contains(type)) {
      return rawValue == true ? 'Да' : 'Нет';
    }
    if (_multiCustomFieldTypes.contains(type)) {
      return _formatMultiCustomFieldValue(rawValue);
    }
    if (rawValue == null) return '';
    return '${rawValue.toString()}${_customFieldValueSuffixes[type] ?? ''}';
  }

  String _formatMultiCustomFieldValue(Object? rawValue) {
    if (rawValue is! Iterable) return rawValue?.toString() ?? '';
    return rawValue.map((item) => item.toString()).join(', ');
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
