import 'dart:convert';

abstract final class CrmConfigurationSnapshotOps {
  static const selectionFieldTypes = <String>{
    'select',
    'radio',
    'multi_select',
    'checkbox_group',
  };

  static Map<String, dynamic> deepCopy(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  static List<Map<String, dynamic>>? reorderItems(
    List<Map<String, dynamic>> items, {
    required int from,
    required int delta,
  }) {
    final to = from + delta;
    if (from < 0 || from >= items.length || to < 0 || to >= items.length) {
      return null;
    }
    final reordered = items.map(Map<String, dynamic>.from).toList();
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);
    return [
      for (var index = 0; index < reordered.length; index++)
        {...reordered[index], 'order': index},
    ];
  }

  static bool migrateLegacyFieldCopies(Map<String, dynamic> snapshot) {
    final migration = _LegacyFieldMigration();
    for (final raw in (snapshot['fields'] as List? ?? const [])) {
      if (raw is Map) migration.add(Map<String, dynamic>.from(raw));
    }
    if (migration.changed) snapshot['fields'] = migration.fields;
    return migration.changed;
  }

  static bool migrateInlineFieldOptions(Map<String, dynamic> snapshot) {
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
      if (!selectionFieldTypes.contains(field['valueType']) ||
          field['optionSetKey'] != null ||
          labels.isEmpty) {
        continue;
      }
      final base = '${field['key']}_options';
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
              'key': stableOptionKey(labels[index], index),
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
      final referencedSets = fields
          .map((field) => field['optionSetKey']?.toString())
          .whereType<String>()
          .toSet();
      optionSets.removeWhere((set) {
        final key = set['key']?.toString() ?? '';
        return !referencedSets.contains(key) &&
            RegExp(r'^(lead|student)_.+_options$').hasMatch(key);
      });
      snapshot['fields'] = fields;
      snapshot['optionSets'] = optionSets;
    }
    return changed;
  }

  static String optionKey(
    String? existing,
    String label,
    int index,
    Set<String> usedKeys,
  ) {
    if (existing != null && existing.isNotEmpty) {
      usedKeys.add(existing);
      return existing;
    }
    final base = stableOptionKey(label, index);
    var candidate = base;
    for (var suffix = 2; usedKeys.contains(candidate); suffix++) {
      final tail = '_$suffix';
      candidate =
          '${base.substring(0, base.length.clamp(0, 64 - tail.length))}$tail';
    }
    usedKeys.add(candidate);
    return candidate;
  }

  static String stableOptionKey(String label, int index) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final suffix = '_${index + 1}';
    final base = normalized.isEmpty ? 'option' : normalized;
    return '${base.substring(0, base.length.clamp(0, 64 - suffix.length))}$suffix';
  }

  static int compareCatalogOrder(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final order = ((left['order'] as num?)?.toInt() ?? 0).compareTo(
      (right['order'] as num?)?.toInt() ?? 0,
    );
    return order != 0
        ? order
        : (left['stableKey']?.toString() ?? '').compareTo(
            right['stableKey']?.toString() ?? '',
          );
  }

  static String? decimalToHundredths(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final whole = BigInt.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return (whole * BigInt.from(100) + BigInt.parse(fraction)).toString();
  }

  static String hundredthsToDecimal(Object? raw) {
    final value = BigInt.tryParse(raw?.toString() ?? '') ?? BigInt.zero;
    final whole = value ~/ BigInt.from(100);
    final fraction = value
        .remainder(BigInt.from(100))
        .abs()
        .toString()
        .padLeft(2, '0');
    return fraction == '00' ? '$whole' : '$whole.$fraction';
  }

  static String minorToMajor(Object? raw) => hundredthsToDecimal(raw);

  static String compensationValueLabel(Map<String, dynamic> item) =>
      switch (item['mode']?.toString()) {
        'percent' => '${hundredthsToDecimal(item['value'])}%',
        'fixed' || 'hourly' => '${hundredthsToDecimal(item['value'])} ₽',
        _ => 'Не требуется',
      };
}

final class _LegacyFieldMigration {
  final _merged = <String, Map<String, dynamic>>{};
  bool changed = false;

  List<Map<String, dynamic>> get fields => _merged.values.toList();

  void add(Map<String, dynamic> field) {
    final legacyEntity = field.remove('entityType')?.toString();
    final hadVisibility = field['visibility'] is Map;
    field['visibility'] = _visibility(field['visibility'], legacyEntity);
    if (legacyEntity != null || !hadVisibility) changed = true;

    final key = field['key']?.toString();
    if (key == null || key.isEmpty) return;
    final current = _merged[key];
    if (current == null) {
      _merged[key] = field;
      return;
    }
    _merge(key, current, field);
  }

  Map<String, dynamic> _visibility(Object? raw, String? legacyEntity) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {
      'lead': legacyEntity == null || legacyEntity == 'lead',
      'student': legacyEntity == null || legacyEntity == 'student',
    };
  }

  void _merge(
    String key,
    Map<String, dynamic> current,
    Map<String, dynamic> field,
  ) {
    if (current['valueType'] != field['valueType']) {
      throw FormatException(
        'Поле «$key» имеет несовместимые типы в карточках лида и ученика.',
      );
    }
    changed = true;
    _mergeVisibility(current, field);
    _mergeFlags(current, field);
    _mergeOrderAndOptions(current, field);
    _mergeOptionSet(current, field);
  }

  void _mergeVisibility(
    Map<String, dynamic> current,
    Map<String, dynamic> field,
  ) {
    final currentVisibility = Map<String, dynamic>.from(
      current['visibility'] as Map,
    );
    final nextVisibility = Map<String, dynamic>.from(
      field['visibility'] as Map,
    );
    current['visibility'] = {
      'lead':
          currentVisibility['lead'] == true || nextVisibility['lead'] == true,
      'student':
          currentVisibility['student'] == true ||
          nextVisibility['student'] == true,
    };
  }

  void _mergeFlags(Map<String, dynamic> current, Map<String, dynamic> field) {
    current['required'] =
        current['required'] == true || field['required'] == true;
    current['active'] = current['active'] == true || field['active'] == true;
    current['system'] = current['system'] == true || field['system'] == true;
  }

  void _mergeOrderAndOptions(
    Map<String, dynamic> current,
    Map<String, dynamic> field,
  ) {
    current['order'] = [
      (current['order'] as num?)?.toInt() ?? 0,
      (field['order'] as num?)?.toInt() ?? 0,
    ].reduce((left, right) => left < right ? left : right);
    current['options'] = {
      ...(current['options'] as List? ?? const []).whereType<String>(),
      ...(field['options'] as List? ?? const []).whereType<String>(),
    }.toList();
  }

  void _mergeOptionSet(
    Map<String, dynamic> current,
    Map<String, dynamic> field,
  ) {
    final currentSet = current['optionSetKey']?.toString();
    final nextSet = field['optionSetKey']?.toString();
    if (currentSet != null && nextSet != null && currentSet != nextSet) {
      current.remove('optionSetKey');
    } else if (currentSet == null && nextSet != null) {
      current['optionSetKey'] = nextSet;
    }
  }
}
