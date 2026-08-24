import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_editor.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/schedule_plan_constraint_interpreter.dart';

void main() {
  PreferredScheduleDraft draft({
    required Set<int> weekdays,
    int lessonsPerDay = 1,
  }) => PreferredScheduleDraft(
    branchId: 'branch-a',
    weekdays: weekdays,
    beginTime: '10:00',
    durationMinutes: 60,
    lessonsPerDay: lessonsPerDay,
    validFrom: DateTime(2026, 8, 25),
    validUntil: DateTime(2026, 9, 25),
    teacherId: 'teacher-a',
    roomId: 'room-a',
    notes: '',
  );

  group('SchedulePlanConstraintInterpreter', () {
    test('groups analyzer conflict scopes and maps affected draft rows', () {
      final interpreter = SchedulePlanConstraintInterpreter(
        rows: [
          draft(weekdays: {1, 2}),
          draft(weekdays: {3}),
        ],
        participantLabels: const {'student-a': 'Анна', 'student-b': 'Борис'},
      );

      final issues = interpreter.issues({
        'conflicts': [
          {
            'code': 'CLIENT_OVERLAP',
            'fingerprint': 'client-overlap:shared',
            'scopes': [
              {
                'rowIndex': 0,
                'localDate': '2026-08-26',
                'studentId': 'student-a',
              },
              {
                'rowIndex': 2,
                'localDate': '2026-08-27',
                'studentId': 'student-b',
              },
            ],
            'conflictingLessonIds': ['lesson-a', 'lesson-b'],
          },
        ],
      });

      expect(issues, hasLength(1));
      expect(issues.single.analyzerGrouped, isTrue);
      expect(issues.single.fingerprint, 'client-overlap:shared');
      expect(issues.single.rowLabel, 'Строки 1, 3');
      expect(issues.single.affectedDraftIndexes, {0, 1});
      expect(issues.single.participantLabels, {'Анна', 'Борис'});
      expect(issues.single.dates, {'2026-08-26', '2026-08-27'});
      expect(issues.single.lessonIds, {'lesson-a', 'lesson-b'});
    });

    test('groups legacy failures by row code and resource', () {
      final interpreter = SchedulePlanConstraintInterpreter(
        rows: [
          draft(weekdays: {1}),
        ],
        participantLabels: const {'student-a': 'Анна'},
      );

      final issues = interpreter.issues({
        'rows': [
          {
            'index': 0,
            'failures': [
              for (final date in ['2026-08-26', '2026-09-02'])
                {
                  'studentId': 'student-a',
                  'occurrence': {'localDate': date},
                  'violations': [
                    {
                      'code': 'CLIENT_OVERLAP',
                      'resource': {'id': 'student-a'},
                      'conflictingLessonIds': ['lesson-a'],
                      'conflictingRowIndexes': [1],
                    },
                  ],
                },
            ],
          },
        ],
      });

      expect(issues, hasLength(1));
      expect(issues.single.label, 'у клиента уже есть занятие');
      expect(issues.single.participantLabel, 'Анна');
      expect(issues.single.dates, {'2026-08-26', '2026-09-02'});
      expect(issues.single.lessonIds, {'lesson-a'});
      expect(issues.single.rowIndexes, {1});
    });

    test('sorts suggestions by score and maps preview rows to drafts', () {
      final interpreter = SchedulePlanConstraintInterpreter(
        rows: [
          draft(weekdays: {1}, lessonsPerDay: 2),
          draft(weekdays: {2}),
        ],
      );
      final suggestions = interpreter.suggestions({
        'rows': [
          for (var index = 0; index < 10; index++)
            {
              'index': index == 9 ? 2 : 0,
              'suggestions': [
                {
                  'kind': 'NEAREST_TIME',
                  'rank': index + 1,
                  'score': index,
                  'changes': {'startOffsetMinutes': index + 5},
                },
              ],
            },
        ],
      });

      expect(suggestions, hasLength(8));
      expect(suggestions.first.suggestion.score, 9);
      expect(suggestions.last.suggestion.score, 2);
      expect(suggestions.first.previewRowIndex, 2);
      expect(suggestions.first.draftIndex, 1);
      expect(
        suggestions
            .where((item) => item.previewRowIndex == 0)
            .every((item) => item.draftIndex == 0),
        isTrue,
      );
    });

    test('offsets time across both sides of midnight', () {
      expect(
        SchedulePlanConstraintInterpreter.offsetTime('23:50', 20),
        '00:10',
      );
      expect(
        SchedulePlanConstraintInterpreter.offsetTime('00:10', -20),
        '23:50',
      );
    });

    test('formats a suggestion with resource names and offset', () {
      final interpreter = SchedulePlanConstraintInterpreter(
        rows: [
          draft(weekdays: {1}),
        ],
      );
      final item = interpreter.suggestions({
        'rows': [
          {
            'index': 0,
            'suggestions': [
              {
                'kind': 'COMBINED',
                'rank': 1,
                'score': 100,
                'changes': {
                  'roomName': 'Зал 1',
                  'teacherName': 'Анна Петрова',
                  'startOffsetMinutes': 15,
                },
              },
            ],
          },
        ],
      }).single;

      expect(
        SchedulePlanConstraintInterpreter.suggestionLabel(item),
        'Строка 1 · №1 · Комбинированный вариант · Зал 1 · Анна Петрова · +15 мин',
      );
    });
  });
}
