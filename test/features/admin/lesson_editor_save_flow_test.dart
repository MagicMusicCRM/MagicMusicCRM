import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/lesson_schedule_analysis.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_save_flow.dart';

void main() {
  test(
    'preview transport failure still reaches authoritative create',
    () async {
      var createCalls = 0;
      final flow = LessonEditorSaveFlow.forTesting(
        preview: (_) async => throw StateError('preview unavailable'),
        create: (_) async {
          createCalls++;
          return {'id': 'lesson-a'};
        },
      );

      final result = await flow.save(_createCommand());

      expect(result, isA<LessonSaveCreated>());
      expect((result as LessonSaveCreated).lesson, {'id': 'lesson-a'});
      expect(createCalls, 1);
    },
  );

  test('preview constraint violations block authoritative create', () async {
    var createCalls = 0;
    final violation = LessonConstraintViolation.fromJson(
      _violationJson('ROOM_OVERLAP'),
    );
    final flow = LessonEditorSaveFlow.forTesting(
      preview: (_) async => LessonScheduleAnalysis.fromViolations([violation]),
      create: (_) async {
        createCalls++;
        return {'id': 'lesson-a'};
      },
    );

    final result = await flow.save(_createCommand());

    expect(result, isA<LessonSaveViolations>());
    expect(
      (result as LessonSaveViolations).violations.single.code,
      'ROOM_OVERLAP',
    );
    expect(createCalls, 0);
  });

  test('authoritative 422 returns violations and keeps the draft', () async {
    final flow = LessonEditorSaveFlow.forTesting(
      preview: (_) async => _validAnalysis,
      create: (_) async => throw MagicApiException(
        statusCode: 422,
        message: 'conflict',
        details: {
          'violations': [_violationJson('ROOM_OVERLAP')],
        },
      ),
    );

    final result = await flow.save(_createCommand());

    expect(result, isA<LessonSaveViolations>());
    expect(
      (result as LessonSaveViolations).violations.single.code,
      'ROOM_OVERLAP',
    );
  });

  test('invalid authoritative 422 details remain failures', () async {
    const cases = <({String label, Object? details})>[
      (label: 'null details', details: null),
      (label: 'empty violations', details: {'violations': <Object>[]}),
      (
        label: 'non-map violation',
        details: {
          'violations': ['not-a-map'],
        },
      ),
    ];

    for (final (:label, :details) in cases) {
      var createCalls = 0;
      final error = MagicApiException(
        statusCode: 422,
        message: 'invalid constraint details',
        details: details,
      );
      final flow = LessonEditorSaveFlow.forTesting(
        preview: (_) async => _validAnalysis,
        create: (_) async {
          createCalls++;
          throw error;
        },
      );

      final result = await flow.save(_createCommand());

      expect(result, isA<LessonSaveFailure>(), reason: label);
      expect((result as LessonSaveFailure).error, same(error), reason: label);
      expect(createCalls, 1, reason: label);
    }
  });

  test('non-constraint create failures return a typed failure', () async {
    final error = MagicApiException(
      statusCode: 500,
      message: 'create unavailable',
    );
    final flow = LessonEditorSaveFlow.forTesting(
      preview: (_) async => _validAnalysis,
      create: (_) async => throw error,
    );

    final result = await flow.save(_createCommand());

    expect(result, isA<LessonSaveFailure>());
    expect((result as LessonSaveFailure).error, same(error));
    expect(result.stackTrace, isNotNull);
  });

  test(
    'non-422 errors with violation-shaped details remain failures',
    () async {
      final flow = LessonEditorSaveFlow.forTesting(
        preview: (_) async => _validAnalysis,
        create: (_) async => throw MagicApiException(
          statusCode: 400,
          message: 'bad request',
          details: {
            'violations': [_violationJson('ROOM_OVERLAP')],
          },
        ),
      );

      expect(await flow.save(_createCommand()), isA<LessonSaveFailure>());
    },
  );

  test('coalesces a double submit into one create call', () async {
    final completer = Completer<Map<String, dynamic>>();
    var createCalls = 0;
    final flow = LessonEditorSaveFlow.forTesting(
      preview: (_) async => _validAnalysis,
      create: (_) {
        createCalls++;
        return completer.future;
      },
    );

    final first = flow.save(_createCommand());
    await _waitFor(() => createCalls == 1);
    expect(await flow.save(_createCommand()), isA<LessonSaveBusy>());
    completer.complete({'id': 'lesson-a'});
    expect(await first, isA<LessonSaveCreated>());
    expect(createCalls, 1);
  });

  test('edit decision bypasses preview and create', () async {
    var previewCalls = 0;
    var createCalls = 0;
    const decision = LessonDecisionRequest(
      operation: LessonDecisionOperation.reschedule,
      lesson: {'id': 'lesson-a'},
      successor: {'scheduledAt': '2026-08-26T11:00:00.000Z'},
    );
    final flow = LessonEditorSaveFlow.forTesting(
      preview: (_) async {
        previewCalls++;
        return _validAnalysis;
      },
      create: (_) async {
        createCalls++;
        return {'id': 'lesson-a'};
      },
    );

    final result = await flow.save(
      LessonEditorSaveCommand(
        scheduleRequest: _scheduleRequest,
        payload: const {},
        decisionRequest: decision,
      ),
    );

    expect(result, isA<LessonSaveDecision>());
    expect((result as LessonSaveDecision).request, same(decision));
    expect(previewCalls, 0);
    expect(createCalls, 0);
  });

  test('note update chains its returned version into the transition', () async {
    final flow = LessonEditorSaveFlow.forTesting(
      preview: (_) async => _validAnalysis,
      create: (_) async => {'id': 'unused'},
      updateNotes: (update) async {
        expect(update.lessonId, 'lesson-a');
        expect(update.expectedVersion, 4);
        expect(update.notes, '');
        return {'lessonId': 'lesson-a', 'version': 5};
      },
    );

    final result = await flow.save(
      const LessonEditorSaveCommand(
        scheduleRequest: _scheduleRequest,
        payload: {},
        noteUpdate: LessonNoteUpdate(
          lessonId: 'lesson-a',
          expectedVersion: 4,
          notes: '',
        ),
        decisionRequest: LessonDecisionRequest(
          operation: LessonDecisionOperation.reschedule,
          lesson: {'id': 'lesson-a', 'version': 4},
        ),
      ),
    );

    expect(result, isA<LessonSaveDecision>());
    expect((result as LessonSaveDecision).request.lesson['version'], 5);
  });
}

const _validAnalysis = LessonScheduleAnalysis(
  valid: true,
  violations: [],
  suggestions: [],
);

const _scheduleRequest = LessonEditorScheduleRequest(
  clientType: 'student',
  clientId: 'student-a',
  teacherId: 'teacher-a',
  branchId: 'branch-a',
  roomId: 'room-a',
  scheduledAt: '2026-08-26T10:00:00.000Z',
  durationMinutes: 60,
);

LessonEditorSaveCommand _createCommand() => const LessonEditorSaveCommand(
  scheduleRequest: _scheduleRequest,
  payload: {
    'clientRef': {'type': 'student', 'id': 'student-a'},
    'teacherId': 'teacher-a',
    'branchId': 'branch-a',
    'roomId': 'room-a',
    'scheduledAt': '2026-08-26T10:00:00.000Z',
    'durationMinutes': 60,
  },
);

Map<String, dynamic> _violationJson(String code) => {
  'code': code,
  'resource': {'type': 'room', 'id': 'room-a'},
  'conflictingLessonIds': ['lesson-existing'],
  'ruleIds': ['room-overlap'],
};

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}
