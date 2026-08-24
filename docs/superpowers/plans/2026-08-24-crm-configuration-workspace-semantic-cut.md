# CRM Configuration Workspace Semantic Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 2,543-line CRM configuration workspace god class with one stateful coordinator, three semantic private UI parts, and one directly tested snapshot-operations library without changing behavior.

**Architecture:** `crm_configuration_workspace.dart` remains the public route and sole owner of providers, mutable state, RBAC, versioning, dirty-form state, and API commands. Schema, commerce, and shell presentation become private widgets in semantic `part` files; pure map migrations, ordering, stable-key, and money conversion move to an imported internal Dart library that is not exported by `client_forms.dart`.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_test`, RepoWise, Sentrux.

**Spec:** `docs/superpowers/specs/2026-08-24-crm-configuration-workspace-semantic-cut-design.md`

## Global Constraints

- Preserve `CrmConfigurationRouteScreen`, `CrmConfigurationWorkspace`, `showCrmConfigurationWorkspace`, the `/crm/configuration` route, and the existing `client_forms.dart` export.
- Preserve every API path, payload key, branch ID, `baseVersion`, `expectedVersion`, publication reason, response mapping, widget key, Russian label, and responsive breakpoint.
- Keep `_dirty` as server-draft state and `DirtyFormExitController` as local-unsaved state; saving a draft leaves `_dirty == true` and marks only the exit controller clean.
- Keep the coordinator as the sole reader of `capabilitySnapshotProvider` and `clientFormsApiProvider`; extracted widgets must not read providers, invoke APIs, or own the canonical snapshot.
- Preserve manager branch-only behavior, school-only structural editing and migration, commerce visibility for Director/system_admin, and edit-plus-publish requirements for commerce mutation.
- Do not create a second provider, controller, repository, service, configuration model, API route, database migration, or compatibility facade.
- Keep one logical task per commit. After every structural task, run focused tests and Sentrux `rescan`, `health`, and `check_rules` before proceeding.
- Original final target: Sentrux `quality_signal >= 4976` (`0.4976` normalized). For this semantic cut only, the owner-approved exception permits `quality_signal >= 4974` when acyclicity raw is `1`, depth is `<= 13`, both rules pass, focused tests and full analysis pass, `_CrmConfigurationWorkspaceState <= 600` NLOC, no method in the changed workspace files exceeds CCN 10, and the recorded Dart duplicate-`build(BuildContext)`-signature effect is the sole quality regression.
- Do not use unrelated cleanup, exclusions, ignored scanner inputs, signature renaming, or any other metric gaming to satisfy the original target or its narrow exception.

## File Structure

- `lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart`: public route plus lifecycle, access, mutable state, API orchestration, and narrow intent handlers.
- `lib/features/crm/presentation/client_forms/crm_configuration_snapshot.dart`: Flutter-independent snapshot copy, migration, key, reorder, catalog, and numeric serialization operations; not exported from the feature barrel.
- `lib/features/crm/presentation/client_forms/crm_configuration_workspace_schema.dart`: private field/category/option-set/settings widgets and editor dialogs.
- `lib/features/crm/presentation/client_forms/crm_configuration_workspace_commerce.dart`: private settlement/compensation widgets and editor dialog.
- `lib/features/crm/presentation/client_forms/crm_configuration_workspace_shell.dart`: private toolbar, responsive shell, navigation, list/property framing, funnel/history widgets, impact dialog, and reason dialog.
- `test/features/settings/crm_configuration_snapshot_test.dart`: direct unit contract for the internal snapshot library.
- `test/features/settings/crm_configuration_workspace_test.dart`: existing end-to-end widget characterization plus one scope-reload regression.

---

### Task 1: Extract directly tested snapshot operations

**Files:**
- Create: `lib/features/crm/presentation/client_forms/crm_configuration_snapshot.dart`
- Create: `test/features/settings/crm_configuration_snapshot_test.dart`
- Modify: `lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart:1-21,175-239,976-1016,1346-1437,1673-1727,2036-2108,2369-2416,2432-2637`

**Interfaces:**
- Consumes: raw `Object?`, `Map<String, dynamic>`, and copied `List<Map<String, dynamic>>` values from the current configuration snapshot.
- Produces: `CrmConfigurationSnapshotOps.deepCopy`, `migrateLegacyFieldCopies`, `migrateInlineFieldOptions`, `optionKey`, `stableOptionKey`, `reorderItems`, `compareCatalogOrder`, `decimalToHundredths`, `hundredthsToDecimal`, `minorToMajor`, and `compensationValueLabel`.

- [ ] **Step 1: Write the failing pure-operation tests**

Create `test/features/settings/crm_configuration_snapshot_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/crm_configuration_snapshot.dart';

void main() {
  test('deep copy isolates nested configuration values', () {
    final source = <String, dynamic>{
      'fields': [
        {'key': 'goal', 'visibility': {'lead': true}},
      ],
    };

    final copy = CrmConfigurationSnapshotOps.deepCopy(source);
    ((copy['fields'] as List).single as Map)['key'] = 'changed';

    expect(((source['fields'] as List).single as Map)['key'], 'goal');
  });

  test('legacy field migration merges copies once and is idempotent', () {
    final snapshot = <String, dynamic>{
      'fields': [
        {
          'entityType': 'lead',
          'key': 'goal',
          'label': 'Цель',
          'valueType': 'text',
          'required': false,
          'active': true,
          'system': false,
          'order': 1,
          'options': <String>[],
        },
        {
          'entityType': 'student',
          'key': 'goal',
          'label': 'Цель',
          'valueType': 'text',
          'required': true,
          'active': true,
          'system': false,
          'order': 0,
          'options': <String>[],
        },
      ],
    };

    expect(CrmConfigurationSnapshotOps.migrateLegacyFieldCopies(snapshot), isTrue);
    final field = (snapshot['fields'] as List).single as Map;
    expect(field['visibility'], {'lead': true, 'student': true});
    expect(field['required'], isTrue);
    expect(field['order'], 0);
    expect(CrmConfigurationSnapshotOps.migrateLegacyFieldCopies(snapshot), isFalse);
  });

  test('legacy field migration rejects incompatible copies', () {
    final snapshot = <String, dynamic>{
      'fields': [
        {'entityType': 'lead', 'key': 'goal', 'valueType': 'text'},
        {'entityType': 'student', 'key': 'goal', 'valueType': 'number'},
      ],
    };

    expect(
      () => CrmConfigurationSnapshotOps.migrateLegacyFieldCopies(snapshot),
      throwsFormatException,
    );
  });

  test('inline option migration is lossless and idempotent', () {
    final snapshot = <String, dynamic>{
      'fields': [
        {
          'key': 'lesson_format',
          'label': 'Формат занятий',
          'valueType': 'select',
          'options': ['Онлайн', 'Офлайн'],
        },
      ],
      'optionSets': <Map<String, dynamic>>[],
    };

    expect(CrmConfigurationSnapshotOps.migrateInlineFieldOptions(snapshot), isTrue);
    final field = (snapshot['fields'] as List).single as Map;
    final optionSet = (snapshot['optionSets'] as List).single as Map;
    expect(field['optionSetKey'], optionSet['key']);
    expect(
      (optionSet['options'] as List).map((value) => (value as Map)['label']),
      ['Онлайн', 'Офлайн'],
    );
    expect(CrmConfigurationSnapshotOps.migrateInlineFieldOptions(snapshot), isFalse);
  });

  test('stable option keys preserve identity and suffix collisions', () {
    final used = <String>{'online_1'};

    expect(
      CrmConfigurationSnapshotOps.optionKey('existing', 'Новое имя', 0, used),
      'existing',
    );
    expect(
      CrmConfigurationSnapshotOps.optionKey(null, 'Online', 0, used),
      'online_1_2',
    );
  });

  test('reorder and numeric serialization remain deterministic', () {
    final items = <Map<String, dynamic>>[
      {'stableKey': 'first', 'order': 0},
      {'stableKey': 'second', 'order': 1},
    ];

    final reordered = CrmConfigurationSnapshotOps.reorderItems(
      items,
      from: 1,
      delta: -1,
    );
    expect(reordered!.map((item) => item['stableKey']), ['second', 'first']);
    expect(reordered.map((item) => item['order']), [0, 1]);
    expect(CrmConfigurationSnapshotOps.reorderItems(items, from: 0, delta: -1), isNull);
    expect(CrmConfigurationSnapshotOps.decimalToHundredths('1500,50'), '150050');
    expect(CrmConfigurationSnapshotOps.hundredthsToDecimal('150050'), '1500.50');
    expect(
      CrmConfigurationSnapshotOps.compensationValueLabel({
        'mode': 'fixed',
        'value': '150050',
      }),
      '1500.50 ₽',
    );
  });
}
```

- [ ] **Step 2: Run the test and verify RED**

```powershell
flutter test test/features/settings/crm_configuration_snapshot_test.dart
```

Expected: FAIL because `crm_configuration_snapshot.dart` and
`CrmConfigurationSnapshotOps` do not exist.

- [ ] **Step 3: Create the internal snapshot library**

Create the non-exported library with this exact surface:

```dart
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
    final nextVisibility = Map<String, dynamic>.from(field['visibility'] as Map);
    current['visibility'] = {
      'lead':
          currentVisibility['lead'] == true || nextVisibility['lead'] == true,
      'student': currentVisibility['student'] == true ||
          nextVisibility['student'] == true,
    };
  }

  void _mergeFlags(
    Map<String, dynamic> current,
    Map<String, dynamic> field,
  ) {
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
```

- [ ] **Step 4: Route every existing call through the class**

Import the new file from `crm_configuration_workspace.dart`, remove
`dart:convert`, and replace the private helper calls with the exact mappings:

```text
_copyMap                         -> CrmConfigurationSnapshotOps.deepCopy
_migrateLegacyFieldCopies       -> CrmConfigurationSnapshotOps.migrateLegacyFieldCopies
_migrateInlineFieldOptions      -> CrmConfigurationSnapshotOps.migrateInlineFieldOptions
_optionKey                      -> CrmConfigurationSnapshotOps.optionKey
_selectionFieldTypes            -> CrmConfigurationSnapshotOps.selectionFieldTypes
_stableOptionKey                -> CrmConfigurationSnapshotOps.stableOptionKey
_byCatalogOrder                 -> CrmConfigurationSnapshotOps.compareCatalogOrder
_decimalToHundredths            -> CrmConfigurationSnapshotOps.decimalToHundredths
_hundredthsToDecimal            -> CrmConfigurationSnapshotOps.hundredthsToDecimal
_minorToMajor                   -> CrmConfigurationSnapshotOps.minorToMajor
_compensationValueLabel         -> CrmConfigurationSnapshotOps.compensationValueLabel
```

Replace both category and commerce reorder loops with `reorderItems`; call
`_replaceItems` only when the result is non-null. Delete the replaced private
helpers from the workspace.

- [ ] **Step 5: Verify snapshot and workspace behavior**

```powershell
dart format lib/features/crm/presentation/client_forms/crm_configuration_snapshot.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart test/features/settings/crm_configuration_snapshot_test.dart
flutter test test/features/settings/crm_configuration_snapshot_test.dart test/features/settings/crm_configuration_workspace_test.dart
git diff --check
```

Expected: both suites PASS; the existing widget suite keeps its current count;
diff check is silent.

- [ ] **Step 6: Run the structural gate and commit**

Call Sentrux `rescan`, `health`, and `check_rules`. Require quality
`quality_signal >= 4976`, acyclicity raw `1`, depth `<= 13`, and both rules passing.

```powershell
git add -- lib/features/crm/presentation/client_forms/crm_configuration_snapshot.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart test/features/settings/crm_configuration_snapshot_test.dart
git commit -m "refactor(crm): extract configuration snapshot operations"
```

---

### Task 2: Extract schema presentation and editors

**Files:**
- Create: `lib/features/crm/presentation/client_forms/crm_configuration_workspace_schema.dart`
- Modify: `lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart:16-21,91-148,601-771,1094-1437,1730-2430`
- Verify: `test/features/settings/crm_configuration_workspace_test.dart`

**Interfaces:**
- Consumes: copied fields, categories, option sets, business settings, selection,
  access booleans, and callbacks owned by the coordinator.
- Produces: private `_CrmFieldList`, `_CrmOptionSetList`,
  `_CrmBusinessSettingsList`, `_CrmFieldPreview`, `_CrmOptionSetPreview`,
  `_CrmBusinessSettingEditor`, `_FieldEditorDialog`, `_CategoryEditorDialog`,
  and `_OptionSetEditorDialog`.

- [ ] **Step 1: Record the schema characterization baseline**

```powershell
flutter test test/features/settings/crm_configuration_workspace_test.dart
```

Expected: all existing workspace tests PASS. Record the test total; Task 2 must
finish with the same total.

- [ ] **Step 2: Declare the private part and move editor ownership**

Add after imports in the main library:

```dart
part 'crm_configuration_workspace_schema.dart';
```

Create the part with:

```dart
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
```

Move `_fieldPlacementLabels`, `_FieldEditorDialog`,
`_FieldEditorDialogState`, `_CategoryEditorDialog`,
`_CategoryEditorDialogState`, `_OptionSetEditorDialog`,
`_OptionSetEditorDialogState`, and `_OptionDraft` into this part without
rewriting their build or validation bodies. Replace option helper references
with `CrmConfigurationSnapshotOps` calls from Task 1.

- [ ] **Step 3: Build passive schema widgets**

Define these exact constructor contracts in the schema part:

```dart
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
}
```

Define preview/editor widgets with these callbacks:

```dart
_CrmFieldPreview(field, canManageStructure, onEdit)
_CrmOptionSetPreview(set, usage, canManageStructure, onEdit)
_CrmBusinessSettingEditor(setting, canEdit, onChanged)
```

Use named constructor parameters in source. `onChanged` has type
`ValueChanged<int>`; `onEdit` is `VoidCallback`. Move the current visual bodies
from `_fieldList`, `_optionSetList`, `_settingList`, `_fieldPreview`,
`_optionSetPreview`, and `_settingEditor` into these widgets. Move the current
label helpers into private top-level functions in the same part.

Keep `_CrmFieldList.build` below CCN 10 by delegating category rendering to
`_CrmCategorySection` and individual field rendering to `_CrmFieldTile`:

```dart
_CrmCategorySection(
  categories: categories,
  canManage: canManageStructure,
  onAdd: onAddCategory,
  onEdit: onEditCategory,
  onReorder: onReorderCategory,
)

for (final field in fields)
  _CrmFieldTile(
    field: field,
    selected: selectedKey == field['key']?.toString(),
    onSelect: onSelect,
  )
```

The section and tile constructors receive only the values shown above. This is
required to remove the current `_fieldList` CCN 13 finding rather than merely
relocate it.

- [ ] **Step 4: Reduce coordinator schema methods to dispatch and intent**

Keep `_editField`, `_editCategory`, `_reorderCategory`, and `_editOptionSet` as
coordinator intent handlers. Add only these narrow handlers:

```dart
void _selectItem(String key) => setState(() => _selectedKey = key);

void _updateBusinessSetting(Map<String, dynamic> setting, int value) {
  final settings = _items('businessSettings');
  final index = settings.indexWhere((item) => item['key'] == setting['key']);
  if (index < 0) return;
  settings[index] = {...settings[index], 'value': value};
  _replaceItems('businessSettings', settings);
}
```

The main file may retain small `_areaContent` and `_editorPane` switch
dispatchers, but neither may contain the extracted widget bodies. Pass copied
lists, immutable booleans, and the handlers above into schema widgets. Do not
pass `WidgetRef`, `ClientFormsApi`, `_snapshot`, or the state object.

Replace the current CCN 11 editor dispatcher with one switch plus focused
selection helpers:

```dart
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
    'commerce' => _commerceCatalogPreview(),
    _ => const SizedBox.shrink(),
  };
}
```

Each `_selected...` helper performs one collection lookup and returns either
its passive widget or `SizedBox.shrink`; the option helper first preserves the
existing `_clientSourcesKey` branch and `ClientSourcesEditor`. This is required
to remove the current editor-dispatch CCN 11 finding.

- [ ] **Step 5: Verify and commit the schema cut**

```powershell
dart format lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace_schema.dart
flutter test test/features/settings/crm_configuration_snapshot_test.dart test/features/settings/crm_configuration_workspace_test.dart
git diff --check
```

Expected: all tests PASS with the Step 1 widget-test count unchanged. Call
Sentrux `rescan`, `health`, and `check_rules`; require the global gates from
Task 1 and no new cycle.

```powershell
git add -- lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace_schema.dart
git commit -m "refactor(crm): split configuration schema workspace"
```

---

### Task 3: Extract commerce presentation and editor

**Files:**
- Create: `lib/features/crm/presentation/client_forms/crm_configuration_workspace_commerce.dart`
- Modify: `lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart:23-45,773-1017,879-1004,1460-1727`
- Verify: `test/features/settings/crm_configuration_workspace_test.dart:591-728`

**Interfaces:**
- Consumes: copied settlement/compensation lists, selection, one manage boolean,
  and coordinator callbacks.
- Produces: private `_CrmCommerceCatalogList`,
  `_CrmCommerceCatalogPreview`, `_CommerceCatalogEditorDialog`, and commerce
  labels local to the part.

- [ ] **Step 1: Run commerce characterization before moving code**

```powershell
flutter test test/features/settings/crm_configuration_workspace_test.dart --plain-name "commerce|catalog|Save Discard Cancel"
```

Expected: the independent settlement/compensation catalog and dirty-back tests
PASS. If Flutter treats the plain name as a literal rather than a regular
expression, run the complete workspace test file instead.

- [ ] **Step 2: Declare the commerce part and move its dialog verbatim**

Add:

```dart
part 'crm_configuration_workspace_commerce.dart';
```

Start the new file with:

```dart
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
```

Move `_settlementContextLabels`, `_compensationModeLabels`,
`_CommerceCatalogEditorDialog`, and `_CommerceCatalogEditorDialogState` into
the part. Preserve all existing controller initialization, disposal,
validation, keys, allowed-context handling, archive switch, and payload keys.
Replace numeric helper calls with `CrmConfigurationSnapshotOps`.

Do not move the current CCN 14 `_submit` unchanged. Split it into identity,
settlement, and compensation payload helpers:

```dart
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
```

Implement the payload helpers as:

```dart
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
```

RepoWise must report each of these four submit-path methods at CCN 10 or lower.

- [ ] **Step 3: Build passive commerce list and preview widgets**

Use these exact boundaries:

```dart
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
}
```

Move the current `_commerceCatalogList`, `_commerceCatalogTile`, and
`_commerceCatalogPreview` rendering into these widgets. Sort only local copied
lists with `CrmConfigurationSnapshotOps.compareCatalogOrder`. Preserve
`add-settlement-type`, `add-compensation-rule`, and
`edit-commerce-catalog-item` keys.

- [ ] **Step 4: Keep commerce mutation in the coordinator**

Retain `_editCommerceCatalog` as the only dialog-to-snapshot mutation handler.
Retain `_reorderCommerceCatalog`, implemented with Task 1 `reorderItems`.
Construct the two commerce widgets from the main dispatchers and pass
`_canManageCommerceCatalogs`; no commerce widget may infer roles or capabilities.

- [ ] **Step 5: Verify and commit the commerce cut**

```powershell
dart format lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace_commerce.dart
flutter test test/features/settings/crm_configuration_snapshot_test.dart test/features/settings/crm_configuration_workspace_test.dart
git diff --check
```

Expected: both suites PASS. Call Sentrux `rescan`, `health`, and `check_rules`;
require `quality_signal >= 4976`, acyclicity raw `1`, depth `<= 13`, both rules
passing, and no new cycle.

```powershell
git add -- lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace_commerce.dart
git commit -m "refactor(crm): split configuration commerce workspace"
```

---

### Task 4: Extract the shell and leave one narrow coordinator

**Files:**
- Create: `lib/features/crm/presentation/client_forms/crm_configuration_workspace_shell.dart`
- Modify: `lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart:91-609,1019-1160,1439-1458`
- Modify: `test/features/settings/crm_configuration_workspace_test.dart:9-75,283-299,755-788`

**Interfaces:**
- Consumes: workspace status, scope, areas, selection, passive content widgets,
  and coordinator callbacks.
- Produces: private `_CrmConfigurationShell`, `_CrmConfigurationListPane`,
  `_CrmConfigurationProperty`, `_CrmConfigurationHistoryList`,
  `_CrmFunnelEntry`, `_showCrmConfigurationImpactDialog`, and
  `_askCrmConfigurationReason`.

- [ ] **Step 1: Add a scope-reload characterization test**

Add to `ConfigurationTestApi`:

```dart
final List<String?> configurationScopeReads = [];
```

At the start of the `/crm/configuration/draft` fake response, add:

```dart
configurationScopeReads.add(queryParameters?['branchId']?.toString());
```

Add the test:

```dart
testWidgets('director changing scope reloads the selected branch draft', (
  tester,
) async {
  final api = ConfigurationTestApi(
    role: 'director',
    capabilities: const [
      'config.crm.read',
      'config.crm.edit',
      'config.crm.publish',
    ],
  );
  await _pump(tester, api);

  await tester.tap(find.byKey(const ValueKey('configuration-scope')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Сокол').last);
  await tester.pumpAndSettle();

  expect(api.configurationScopeReads, [
    null,
    '20000000-0000-4000-8000-000000000001',
  ]);
  expect(find.text('Сокол'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Run the new characterization and verify GREEN**

```powershell
flutter test test/features/settings/crm_configuration_workspace_test.dart --plain-name "director changing scope reloads the selected branch draft"
```

Expected: PASS on the pre-extraction coordinator. A failure means the asserted
scope contract is wrong; correct the test against the observed request before
moving shell code.

- [ ] **Step 3: Declare the shell part and implement its passive contract**

Add:

```dart
part 'crm_configuration_workspace_shell.dart';
```

Create:

```dart
part of 'crm_configuration_workspace.dart';

class _CrmConfigurationShell extends StatelessWidget {
  const _CrmConfigurationShell({
    required this.exitController,
    required this.loading,
    required this.busy,
    required this.error,
    required this.branches,
    required this.branchId,
    required this.isManager,
    required this.areas,
    required this.area,
    required this.selectedKey,
    required this.baseVersion,
    required this.dirty,
    required this.initialSchoolSetup,
    required this.canEdit,
    required this.canPublish,
    required this.listPane,
    required this.editorPane,
    required this.onRetry,
    required this.onScopeChanged,
    required this.onAreaChanged,
    required this.onSaveDraft,
    required this.onPublish,
  });

  final DirtyFormExitController exitController;
  final bool loading;
  final bool busy;
  final String? error;
  final List<Map<String, dynamic>> branches;
  final String? branchId;
  final bool isManager;
  final List<(String, String, IconData)> areas;
  final String area;
  final String? selectedKey;
  final int baseVersion;
  final bool dirty;
  final bool initialSchoolSetup;
  final bool canEdit;
  final bool canPublish;
  final Widget listPane;
  final Widget editorPane;
  final VoidCallback onRetry;
  final ValueChanged<String?> onScopeChanged;
  final ValueChanged<String> onAreaChanged;
  final Future<bool> Function() onSaveDraft;
  final VoidCallback onPublish;
}
```

Move the loading/error view, `DirtyFormExitScope`, toolbar, busy indicator,
900-pixel responsive layout, desktop panes, compact choice chips, and area list
into this widget. Preserve the `configuration-scope` and
`configuration-publish` keys and every enable/disable condition.

Do not move the current CCN 14 toolbar into one build method. Compose it from
three private widgets:

```dart
_CrmConfigurationToolbar(
  scopeSelector: _CrmConfigurationScopeSelector(
    branches: branches,
    branchId: branchId,
    isManager: isManager,
    busy: busy,
    onChanged: onScopeChanged,
  ),
  status: _CrmConfigurationDraftStatus(
    initialSchoolSetup: initialSchoolSetup,
    dirty: dirty,
    baseVersion: baseVersion,
  ),
  busy: busy,
  dirty: dirty,
  initialSchoolSetup: initialSchoolSetup,
  canEdit: canEdit,
  canPublish: canPublish,
  onSaveDraft: onSaveDraft,
  onPublish: onPublish,
)
```

The scope selector owns only the dropdown item construction; the draft-status
widget owns only icon/label selection; the toolbar owns only action visibility
and enablement. Each build method must remain at CCN 10 or lower.

- [ ] **Step 4: Move shared presentation helpers and dialogs**

Move `_listPane` into `_CrmConfigurationListPane`, `_property` into
`_CrmConfigurationProperty`, `_historyList` into
`_CrmConfigurationHistoryList`, and `_funnelEntry` into `_CrmFunnelEntry`.
Their constructor contracts are:

```dart
_CrmConfigurationListPane(title, addLabel, onAdd, children)
_CrmConfigurationProperty(label, value)
_CrmConfigurationHistoryList(revisions, canPublish, onRollback)
_CrmFunnelEntry(onOpen)
```

Use named parameters in production code. `onRollback` is
`ValueChanged<Map<String, dynamic>>`; `onOpen` and nullable `onAdd` are
`VoidCallback`.

Move `_showImpact` and `_askReason` visual bodies into top-level functions:

```dart
Future<String?> _showCrmConfigurationImpactDialog(
  BuildContext context,
  Map<String, dynamic> impact,
);

Future<String?> _askCrmConfigurationReason(
  BuildContext context,
  String title,
);
```

The coordinator calls these functions from `_previewAndPublish` and `_rollback`.
Dialog content, 500-character publication reason, non-empty validation, warning
and blocking-issue rendering, and button labels remain unchanged.

- [ ] **Step 5: Reduce the state class to coordination**

Add two intent handlers:

```dart
void _changeScope(String? branchId) {
  setState(() => _branchId = branchId);
  _load();
}

void _changeArea(String area) {
  setState(() {
    _area = area;
    _selectedKey = null;
  });
}
```

`build` creates `_CrmConfigurationShell` and passes the current list/editor
widgets. Remove `_toolbar`, `_desktop`, `_compact`, `_areaList`, `_listPane`,
`_historyList`, `_funnelEntry`, `_property`, `_showImpact`, and `_askReason`
from the state class. Keep API methods, access getters, `_items`,
`_replaceItems`, edit handlers, `_toast`, and the two small area dispatchers.

- [ ] **Step 6: Run focused, static, and structural verification**

```powershell
dart format lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace_shell.dart test/features/settings/crm_configuration_workspace_test.dart
flutter test test/features/settings/crm_configuration_snapshot_test.dart test/features/settings/crm_configuration_workspace_test.dart
flutter analyze
git diff --check
```

Expected: both test suites and analysis PASS. Confirm the state size and method
complexity from live source and RepoWise after reindexing; do not infer success
only from the main file's physical line count.

Call Sentrux `rescan`, `health`, and `check_rules`. The original quality target
is `quality_signal >= 4976`; the owner-approved exception for this cut permits
`quality_signal >= 4974` only under every condition in Global Constraints.
Require acyclicity raw `1`, depth `<= 13`, both rules passing, and no new cycle.

- [ ] **Step 7: Commit the shell cut**

```powershell
git add -- lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace_shell.dart test/features/settings/crm_configuration_workspace_test.dart
git commit -m "refactor(crm): split configuration workspace shell"
```

---

### Task 5: Run final product, RepoWise, and Sentrux gates

**Files:**
- Modify: `docs/superpowers/specs/2026-08-24-crm-configuration-workspace-semantic-cut-design.md`
- Verify: all files created or changed in Tasks 1-4

**Interfaces:**
- Consumes: the committed semantic cut and the baseline values recorded in the spec.
- Produces: verified metrics, an implementation commit range, and an updated spec status without changing runtime behavior.

- [ ] **Step 1: Run all focused and Flutter gates**

```powershell
flutter test test/features/settings/crm_configuration_snapshot_test.dart test/features/settings/crm_configuration_workspace_test.dart
flutter test
flutter analyze
flutter test integration_test/configuration_settings_device_test.dart -d windows
git diff --check
```

Expected: all unit/widget tests PASS, analysis exits `0`, the Windows device
configuration smoke test PASSes, and diff check is silent. If the device runner
is unavailable, record the exact runner error; do not report that gate as PASS.

- [ ] **Step 2: Prove the dependency and ownership boundaries from source**

```powershell
rg -n "clientFormsApiProvider|capabilitySnapshotProvider" lib/features/crm/presentation/client_forms/crm_configuration_workspace_*.dart
rg -n "part 'crm_configuration_workspace_(schema|commerce|shell)\.dart'|import 'crm_configuration_snapshot\.dart'" lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart
rg -n "crm_configuration_(snapshot|workspace_schema|workspace_commerce|workspace_shell)" lib/features/crm/presentation/client_forms/client_forms.dart
```

Expected: provider reads exist only in the main coordinator; main declares all
three parts and imports the snapshot library; the barrel exports none of the
new internal files.

- [ ] **Step 3: Refresh and inspect RepoWise**

```powershell
repowise update --index-only
```

Call RepoWise `get_health` for the main, snapshot, schema, commerce, and shell
files with `include=["biomarkers","refactoring","trend"]`; call `get_risk` for
all changed production files; call `get_change_risk` for
`a0cfc008..HEAD`. Require `indexed_commit == HEAD`, `index_behind=false`, no
critical god-class finding on `_CrmConfigurationWorkspaceState`, state NLOC
`<= 600`, no changed method CCN above 10, and no missing production caller.

- [ ] **Step 4: Run the final Sentrux session gate**

Call Sentrux `rescan`, `health`, `check_rules`, and `session_end`. Acceptance:

```text
quality_signal >= 4976, or >= 4974 under the owner-approved exception
acyclicity.raw = 1
depth.raw <= 13
rules pass = true
new dependency cycles = 0
```

Record the exact before/after quality, modularity, depth, redundancy, and rule
values. The exception is valid only when focused tests and full analysis pass,
the state is at most 600 NLOC, no changed method exceeds CCN 10, and the
recorded Dart duplicate-`build(BuildContext)`-signature effect is the sole
quality regression. Do not claim a gain that the scanner does not report, and
do not use unrelated cleanup, exclusions, ignored scanner inputs, signature
renaming, or metric gaming.

- [ ] **Step 5: Record verified status and commit documentation**

Change the spec status to `Implemented and verified at <HEAD-before-docs>` and
append a short `Verified outcome` section containing the exact test totals,
Windows device result, state NLOC, maximum CCN, RepoWise health, Sentrux values,
and the four implementation commit hashes.

```powershell
git add -- docs/superpowers/specs/2026-08-24-crm-configuration-workspace-semantic-cut-design.md
git commit -m "docs(crm): record configuration cut verification"
git status --short --branch
```

Expected: the documentation commit succeeds and the working tree is clean.

## Rollback

Revert the shell commit, commerce commit, schema commit, and snapshot commit in
reverse order. The snapshot tests may remain only if their imported library
still exists; otherwise revert their commit with the snapshot implementation.
No rollback step touches an API, migration, database, deployment, or production
data.
