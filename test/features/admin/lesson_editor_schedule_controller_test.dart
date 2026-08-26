import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_schedule_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_save_flow.dart';

void main() {
  const policy = LessonEditorDecisionPolicy();

  test(
    'builds Moscow preview request and excludes the edited lesson',
    () async {
      late LessonEditorScheduleRequest captured;
      const analysis = LessonScheduleAnalysis(
        valid: true,
        violations: [],
        suggestions: [],
      );
      final controller = LessonEditorScheduleController(
        policy: policy,
        analyze: (request) async {
          captured = request;
          return analysis;
        },
      );
      final draft = _draft();

      expect(
        await controller.analyze(session: _editSession(draft), draft: draft),
        same(analysis),
      );
      expect(captured.clientType, 'student');
      expect(captured.clientId, 'student-a');
      expect(captured.teacherId, 'teacher-a');
      expect(captured.branchId, 'branch-a');
      expect(captured.roomId, 'room-a');
      expect(captured.scheduledAt, '2026-08-26T10:00:00.000Z');
      expect(captured.durationMinutes, 60);
      expect(captured.excludeLessonId, 'lesson-a');
    },
  );

  test('rejects an incomplete request before schedule analysis', () async {
    var analyzeCalls = 0;
    final controller = LessonEditorScheduleController(
      policy: policy,
      analyze: (_) async {
        analyzeCalls++;
        return const LessonScheduleAnalysis(
          valid: true,
          violations: [],
          suggestions: [],
        );
      },
    );
    final draft = _draft().copyWith(roomId: null);

    expect(
      () => controller.analyze(session: _createSession(draft), draft: draft),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Lesson schedule request is incomplete',
        ),
      ),
    );
    expect(analyzeCalls, 0);
  });

  test('applies only non-null teacher, room, and start suggestions', () {
    final controller = LessonEditorScheduleController(
      policy: policy,
      analyze: (_) async => const LessonScheduleAnalysis(
        valid: true,
        violations: [],
        suggestions: [],
      ),
    );
    final draft = _draft();
    final start = DateTime(2026, 8, 27, 15, 30);

    final teacherOnly = controller.applySuggestion(
      draft,
      const ScheduleSuggestion(
        kind: 'SAME_SPECIALIZATION_TEACHER',
        rank: 1,
        score: 90,
        teacherId: 'teacher-b',
      ),
    );
    final roomAndStart = controller.applySuggestion(
      teacherOnly,
      ScheduleSuggestion(
        kind: 'COMBINED',
        rank: 2,
        score: 80,
        roomId: 'room-b',
        startAt: start,
      ),
    );

    expect(teacherOnly.teacherId, 'teacher-b');
    expect(teacherOnly.roomId, 'room-a');
    expect(teacherOnly.localStart, DateTime(2026, 8, 26, 13));
    expect(roomAndStart.teacherId, 'teacher-b');
    expect(roomAndStart.roomId, 'room-b');
    expect(roomAndStart.localStart, start);
  });
}

LessonEditorDraft _draft() => LessonEditorDraft(
  localStart: DateTime(2026, 8, 26, 13),
  durationMinutes: 60,
  isTrial: false,
  completionType: 'standard',
  clientChargeType: 'personal_account',
  client: const LessonClientRef(
    type: 'student',
    id: 'student-a',
    label: 'Анна',
  ),
  teacherId: 'teacher-a',
  branchId: 'branch-a',
  roomId: 'room-a',
);

LessonEditorSession _createSession(LessonEditorDraft draft) =>
    LessonEditorSession(
      draft: draft,
      snapshot: null,
      seededClient: draft.client,
    );

LessonEditorSession _editSession(LessonEditorDraft draft) =>
    LessonEditorSession(
      draft: draft,
      snapshot: const LessonEditorSnapshot(
        lessonId: 'lesson-a',
        expectedVersion: 4,
        rawLesson: {'id': 'lesson-a', 'version': 4},
        clientLocked: true,
        initialSchedulePayload: {},
        initialCompensationRuleKey: null,
        initialCompensationValueMinor: null,
      ),
      seededClient: draft.client,
    );
