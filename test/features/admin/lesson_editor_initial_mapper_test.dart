import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_initial_mapper.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart';

void main() {
  const mapper = LessonEditorInitialMapper();

  test('normalizes a frozen group edit from legacy aliases', () {
    final session = mapper.map(
      const LessonEditorInitialInput(
        initialDate: null,
        initialDurationMinutes: null,
        initialRoomId: null,
        initialBranchId: null,
        initialIsTrial: false,
        lesson: {
          'id': 'lesson-a',
          'version': 4,
          'groupId': 'group-a',
          'groupName': 'Ансамбль',
          'teacher_id': 'teacher-a',
          'branch_id': 'branch-a',
          'room_id': 'room-a',
          'scheduled_at': '2026-08-26T10:00:00.000Z',
          'duration_minutes': 90,
          'is_trial': true,
          'completion_type': 'standard.success',
          'client_charge_type': 'subscription',
          'subscription_id': 'subscription-a',
          'settlementTypeKey': 'lesson',
          'teacherCompensationRuleKey': 'teacher-hourly',
          'teacherCompensationValueMinor': '12500',
        },
      ),
    );

    expect(session.isEdit, isTrue);
    expect(
      session.draft.client,
      const LessonClientRef(type: 'group', id: 'group-a', label: 'Ансамбль'),
    );
    expect(session.draft.localStart, DateTime(2026, 8, 26, 13));
    expect(session.draft.durationMinutes, 90);
    expect(session.draft.isTrial, isTrue);
    expect(session.draft.completionType, 'standard.success');
    expect(session.draft.clientChargeType, 'subscription');
    expect(session.draft.subscriptionId, 'subscription-a');
    expect(session.draft.settlementTypeKey, 'lesson');
    expect(session.draft.compensationRuleKey, 'teacher-hourly');
    expect(session.draft.compensationValueMinor, '12500');
    expect(session.snapshot?.expectedVersion, 4);
    expect(session.snapshot?.clientLocked, isTrue);
    expect(session.snapshot?.initialCompensationRuleKey, 'teacher-hourly');
    expect(session.snapshot?.initialCompensationValueMinor, '12500');
  });

  test('keeps lead trial creation independent from funding', () {
    final session = mapper.map(
      const LessonEditorInitialInput(
        initialDate: null,
        initialDurationMinutes: 45,
        initialRoomId: null,
        initialBranchId: 'branch-a',
        initialIsTrial: true,
        lesson: null,
        leadId: 'lead-a',
        leadName: 'Анна',
      ),
    );

    expect(session.draft.client?.type, 'lead');
    expect(session.draft.client?.id, 'lead-a');
    expect(session.leadNoteSource, 'Анна');
    expect(session.draft.isTrial, isTrue);
    expect(session.draft.clientChargeType, 'none');
    expect(session.draft.durationMinutes, 45);
    expect(session.snapshot, isNull);
  });

  test(
    'keeps fallback lead display separate from the nullable note source',
    () {
      const cases = {
        'Лид без имени': LessonEditorInitialInput(
          initialDate: null,
          initialDurationMinutes: null,
          initialRoomId: null,
          initialBranchId: null,
          initialIsTrial: false,
          lesson: null,
          leadId: 'lead-a',
        ),
        'Клиент без имени': LessonEditorInitialInput(
          initialDate: null,
          initialDurationMinutes: null,
          initialRoomId: null,
          initialBranchId: null,
          initialIsTrial: false,
          lesson: null,
          clientType: 'lead',
          clientId: 'lead-b',
        ),
      };

      for (final entry in cases.entries) {
        final session = mapper.map(entry.value);

        expect(session.draft.client?.label, entry.key);
        expect(session.leadNoteSource, isNull, reason: entry.key);
      }
    },
  );

  test('prefers an explicit client seed over a lead seed', () {
    final session = mapper.map(
      const LessonEditorInitialInput(
        initialDate: null,
        initialDurationMinutes: null,
        initialRoomId: null,
        initialBranchId: 'branch-a',
        initialIsTrial: false,
        lesson: null,
        clientType: 'student',
        clientId: 'student-seed',
        clientName: 'Ирина',
        leadId: 'lead-seed',
        leadName: 'Анна',
      ),
    );

    expect(
      session.seededClient,
      const LessonClientRef(
        type: 'student',
        id: 'student-seed',
        label: 'Ирина',
      ),
    );
    expect(session.draft.client, session.seededClient);
  });

  test(
    'uses edit lead identity over constructor seeds and preserves old dates',
    () {
      final session = mapper.map(
        const LessonEditorInitialInput(
          initialDate: null,
          initialDurationMinutes: 45,
          initialRoomId: 'room-seed',
          initialBranchId: 'branch-seed',
          initialIsTrial: false,
          clientType: 'student',
          clientId: 'student-seed',
          clientName: 'Ирина',
          leadId: 'lead-seed',
          leadName: 'Анна',
          lesson: {
            'id': 'lesson-old',
            'version': '7',
            'lead_id': 'lead-edit',
            'lead_name': 'Мария',
            'teacher_id': 'teacher-edit',
            'branch_id': 'branch-edit',
            'room_id': 'room-edit',
            'scheduled_at': '2024-01-15T08:30:00.000Z',
            'duration_minutes': 60,
            'snapshot_trial': false,
          },
        ),
      );

      expect(
        session.draft.client,
        const LessonClientRef(type: 'lead', id: 'lead-edit', label: 'Мария'),
      );
      expect(session.seededClient, session.draft.client);
      expect(session.draft.localStart, DateTime(2024, 1, 15, 11, 30));
      expect(session.draft.teacherId, 'teacher-edit');
      expect(session.draft.branchId, 'branch-edit');
      expect(session.draft.roomId, 'room-edit');
      expect(session.snapshot?.expectedVersion, 7);
    },
  );

  test('uses student identity when an edit has no lead or group', () {
    final session = mapper.map(
      const LessonEditorInitialInput(
        initialDate: null,
        initialDurationMinutes: null,
        initialRoomId: null,
        initialBranchId: null,
        initialIsTrial: false,
        lesson: {
          'id': 'lesson-student',
          'student_id': 'student-a',
          'student_name': 'Павел',
        },
      ),
    );

    expect(
      session.draft.client,
      const LessonClientRef(type: 'student', id: 'student-a', label: 'Павел'),
    );
  });

  test('copyWith can explicitly clear nullable draft identities', () {
    final draft = LessonEditorDraft(
      localStart: DateTime(2026, 8, 26, 13),
      durationMinutes: 60,
      isTrial: false,
      completionType: 'standard.success',
      clientChargeType: 'subscription',
      client: const LessonClientRef(
        type: 'student',
        id: 'student-a',
        label: 'Павел',
      ),
      teacherId: 'teacher-a',
      branchId: 'branch-a',
      roomId: 'room-a',
      subscriptionId: 'subscription-a',
      settlementTypeKey: 'lesson',
      compensationRuleKey: 'teacher-hourly',
      compensationValueMinor: '12500',
    );

    final cleared = draft.copyWith(
      client: null,
      teacherId: null,
      branchId: null,
      roomId: null,
      subscriptionId: null,
      settlementTypeKey: null,
      compensationRuleKey: null,
      compensationValueMinor: null,
    );

    expect(cleared.client, isNull);
    expect(cleared.teacherId, isNull);
    expect(cleared.branchId, isNull);
    expect(cleared.roomId, isNull);
    expect(cleared.subscriptionId, isNull);
    expect(cleared.settlementTypeKey, isNull);
    expect(cleared.compensationRuleKey, isNull);
    expect(cleared.compensationValueMinor, isNull);
  });
}
