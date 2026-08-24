import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/crm_configuration_snapshot.dart';

void main() {
  test('deep copy isolates nested configuration values', () {
    final source = <String, dynamic>{
      'fields': [
        {
          'key': 'goal',
          'visibility': {'lead': true},
        },
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

    expect(
      CrmConfigurationSnapshotOps.migrateLegacyFieldCopies(snapshot),
      isTrue,
    );
    final field = (snapshot['fields'] as List).single as Map;
    expect(field['visibility'], {'lead': true, 'student': true});
    expect(field['required'], isTrue);
    expect(field['order'], 0);
    expect(
      CrmConfigurationSnapshotOps.migrateLegacyFieldCopies(snapshot),
      isFalse,
    );
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

    expect(
      CrmConfigurationSnapshotOps.migrateInlineFieldOptions(snapshot),
      isTrue,
    );
    final field = (snapshot['fields'] as List).single as Map;
    final optionSet = (snapshot['optionSets'] as List).single as Map;
    expect(field['optionSetKey'], optionSet['key']);
    expect(
      (optionSet['options'] as List).map((value) => (value as Map)['label']),
      ['Онлайн', 'Офлайн'],
    );
    expect(
      CrmConfigurationSnapshotOps.migrateInlineFieldOptions(snapshot),
      isFalse,
    );
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
    expect(
      CrmConfigurationSnapshotOps.reorderItems(items, from: 0, delta: -1),
      isNull,
    );
    expect(
      CrmConfigurationSnapshotOps.decimalToHundredths('1500,50'),
      '150050',
    );
    expect(
      CrmConfigurationSnapshotOps.hundredthsToDecimal('150050'),
      '1500.50',
    );
    expect(
      CrmConfigurationSnapshotOps.compensationValueLabel({
        'mode': 'fixed',
        'value': '150050',
      }),
      '1500.50 ₽',
    );
  });
}
