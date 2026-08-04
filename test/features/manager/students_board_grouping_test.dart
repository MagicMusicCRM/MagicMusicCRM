import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/students_board_providers.dart';

void main() {
  group('groupStudentsByStatus', () {
    const stages = [
      StudentFunnelStage(
        key: 'consultation',
        label: 'Консультация',
        style: 'cyan',
        active: true,
        allowedTransitions: ['learning'],
      ),
      StudentFunnelStage(
        key: 'learning',
        label: 'Обучается',
        style: 'green',
        active: true,
        allowedTransitions: [],
      ),
    ];

    test('uses configured stages and order without built-in status names', () {
      final columns = groupStudentsByStatus([
        {'id': 's1', 'status': 'learning'},
        {'id': 's2', 'status': 'consultation'},
      ], stages);

      expect(columns.map((column) => column['name']), [
        'Консультация',
        'Обучается',
      ]);
      expect(columns.first['allowedTransitions'], ['learning']);
      expect((columns.first['students'] as List).single['id'], 's2');
    });

    test('keeps unknown legacy values in the remediation bucket', () {
      final columns = groupStudentsByStatus([
        {'id': 's3', 'status': 'legacy_pause'},
        {'id': 's4'},
      ], stages);

      expect(columns.last['status'], isNull);
      expect(columns.last['name'], 'Требуют сопоставления');
      expect((columns.last['students'] as List).map((item) => item['id']), [
        's3',
        's4',
      ]);
    });
  });

  group('groupStudentsByDiscipline', () {
    final disciplines = [
      {'discipline_id': 'd1', 'name': 'Вокал', 'sort_order': 0},
      {'discipline_id': 'd2', 'name': 'Гитара', 'sort_order': 1},
    ];

    test('groups students into discipline columns by name, case-insensitive', () {
      final students = [
        {'id': 's1', 'first_name': 'Аня', 'custom_data': {'discipline': 'Вокал'}},
        {'id': 's2', 'first_name': 'Боря', 'custom_data': {'discipline': 'гитара'}},
        {'id': 's3', 'first_name': 'Вера', 'custom_data': {'discipline': 'Вокал'}},
      ];

      final columns = groupStudentsByDiscipline(disciplines, students);

      expect(columns.map((c) => c['name']), ['Вокал', 'Гитара', 'Без направления']);
      expect((columns[0]['students'] as List).map((s) => s['id']), ['s1', 's3']);
      expect((columns[1]['students'] as List).single['id'], 's2');
      expect((columns[2]['students'] as List), isEmpty);
    });

    test('puts unmatched/empty-discipline students in the trailing column', () {
      final students = [
        {'id': 's4', 'first_name': 'Гена', 'custom_data': {'discipline': 'Фортепиано'}},
        {'id': 's5', 'first_name': 'Дина', 'custom_data': {}},
        {'id': 's6', 'first_name': 'Женя'},
      ];

      final columns = groupStudentsByDiscipline(disciplines, students);

      final fallback = columns.last;
      expect(fallback['name'], 'Без направления');
      expect((fallback['students'] as List).map((s) => s['id']), ['s4', 's5', 's6']);
    });

    test('buckets by the relational disciplines list (multi-discipline → multiple columns)', () {
      final students = [
        {
          'id': 's7',
          'first_name': 'Зоя',
          'disciplines': [
            {'id': 'd1', 'name': 'Вокал'},
            {'id': 'd2', 'name': 'Гитара'},
          ],
        },
        {
          'id': 's8',
          'first_name': 'Иван',
          'disciplines': [
            {'id': 'd2', 'name': 'гитара'},
          ],
          // custom_data fallback must be ignored when disciplines are present.
          'custom_data': {'discipline': 'Вокал'},
        },
      ];

      final columns = groupStudentsByDiscipline(disciplines, students);

      expect((columns[0]['students'] as List).map((s) => s['id']), ['s7']);
      expect((columns[1]['students'] as List).map((s) => s['id']), ['s7', 's8']);
      expect((columns[2]['students'] as List), isEmpty);
    });

    test('keeps discipline column order by sort_order', () {
      final unordered = [
        {'discipline_id': 'd2', 'name': 'Гитара', 'sort_order': 1},
        {'discipline_id': 'd1', 'name': 'Вокал', 'sort_order': 0},
      ];

      final columns = groupStudentsByDiscipline(unordered, const []);

      expect(columns.map((c) => c['name']), ['Вокал', 'Гитара', 'Без направления']);
    });
  });
}
