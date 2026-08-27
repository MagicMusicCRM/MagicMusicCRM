import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_models.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_projection.dart';

void main() {
  test(
    'preserves column order and moves an optimistic card without mutation',
    () {
      final raw = <Map<String, dynamic>>[
        {
          'status': 'learning',
          'name': 'Обучаются',
          'style': 'green',
          'allowedTransitions': ['paused'],
          'students': [
            {'id': 'student-1', 'first_name': 'Анна', 'status': 'learning'},
          ],
        },
        {
          'status': 'paused',
          'name': 'Пауза',
          'style': 'amber',
          'allowedTransitions': <String>[],
          'students': <Map<String, dynamic>>[],
        },
      ];

      final projected = projectStudentsBoard(
        raw,
        optimisticStatuses: const {'student-1': 'paused'},
      );

      expect(projected.map((column) => column.name), ['Обучаются', 'Пауза']);
      expect(projected.first.students, isEmpty);
      expect(projected.last.students.single['id'], 'student-1');
      expect((raw.first['students'] as List), hasLength(1));
    },
  );

  test('filters cards locally while retaining every bucket and count', () {
    final projected = projectStudentsBoard([
      {
        'status': 'learning',
        'name': 'Обучаются',
        'style': 'green',
        'allowedTransitions': <String>[],
        'students': [
          {'id': 'student-1', 'first_name': 'Анна', 'phone': '+7001'},
          {'id': 'student-2', 'first_name': 'Борис', 'phone': '+7002'},
        ],
      },
      {
        'status': null,
        'name': 'Требуют сопоставления',
        'style': 'red',
        'allowedTransitions': <String>[],
        'students': <Map<String, dynamic>>[],
      },
    ], query: '+7002');

    expect(projected, hasLength(2));
    expect(projected.first.students.single['id'], 'student-2');
    expect(projected.last.students, isEmpty);
    expect(projected.transitions['learning'], isEmpty);
  });

  test('page and state defensively freeze nested collection inputs', () {
    final pageItem = <String, dynamic>{'id': 'student-1'};
    final pageItems = [pageItem];
    final page = StudentsBoardPageResult(
      items: pageItems,
      nextCursor: 'cursor-2',
    );
    final branch = <String, dynamic>{'id': 'branch-a'};
    final branches = [branch];
    final optimistic = <String, String>{'student-1': 'paused'};
    final pending = <String>{'student-1'};
    final state = StudentsBoardState(
      branches: branches,
      extraStudents: pageItems,
      optimisticStatuses: optimistic,
      pendingStudentIds: pending,
    );

    pageItem['id'] = 'mutated';
    pageItems.add({'id': 'student-2'});
    branch['id'] = 'mutated';
    branches.clear();
    optimistic.clear();
    pending.clear();

    expect(page.items.single['id'], 'student-1');
    expect(state.branches.single['id'], 'branch-a');
    expect(state.extraStudents.single['id'], 'student-1');
    expect(state.optimisticStatuses, {'student-1': 'paused'});
    expect(state.pendingStudentIds, {'student-1'});
    expect(() => page.items.add({'id': 'student-3'}), throwsUnsupportedError);
    expect(() => page.items.single['id'] = 'student-3', throwsUnsupportedError);
    expect(() => state.branches.clear(), throwsUnsupportedError);
    expect(() => state.optimisticStatuses.clear(), throwsUnsupportedError);
    expect(() => state.pendingStudentIds.clear(), throwsUnsupportedError);
  });

  test('projection freezes its result, columns, cards, and transitions', () {
    final projected = projectStudentsBoard([
      {
        'status': 'learning',
        'name': 'Обучаются',
        'style': 'green',
        'allowedTransitions': ['paused'],
        'students': [
          {'id': 'student-1'},
        ],
      },
    ]);
    final transitions = projected.transitions;

    expect(() => projected.add(projected.single), throwsUnsupportedError);
    expect(() => projected.single.students.clear(), throwsUnsupportedError);
    expect(
      () => projected.single.students.single['id'] = 'mutated',
      throwsUnsupportedError,
    );
    expect(
      () => projected.single.allowedTransitions.add('inactive'),
      throwsUnsupportedError,
    );
    expect(() => transitions.clear(), throwsUnsupportedError);
  });

  test(
    'normal view has no controller, service, provider, or shell dependency',
    () {
      const viewFiles = [
        'students_board_widgets.dart',
        'students_board_columns.dart',
        'students_board_card.dart',
        'students_board_drag_feedback.dart',
      ];
      for (final file in viewFiles) {
        final source = File(
          'lib/features/manager/presentation/widgets/$file',
        ).readAsStringSync();
        expect(source, isNot(contains('students_board_widget.dart')));
        expect(source, isNot(contains('students_board_controller.dart')));
        expect(source, isNot(contains('magic_crm_service.dart')));
        expect(source, isNot(contains('flutter_riverpod')));
        expect(source, isNot(contains('Provider')));
      }
    },
  );
}
