import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/schedule_plan_mutation_flow.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_draft.dart';

void main() {
  test('mutation flow exposes typed outcome and deterministic slot times', () {
    expect(
      SchedulePlanMutationFlow.slotTime(
        beginTime: '09:15',
        durationMinutes: 45,
        slot: 2,
      ),
      '10:45',
    );
    expect(
      SchedulePlanMutationResult.values,
      containsAll([
        SchedulePlanMutationResult.committed,
        SchedulePlanMutationResult.cancelled,
      ]),
    );
  });

  test('operational schedule-plan payload omits teacher compensation', () {
    final draft = PreferredScheduleDraft(
      branchId: 'branch-a',
      weekdays: const {1},
      beginTime: '10:00',
      durationMinutes: 60,
      lessonsPerDay: 1,
      validFrom: DateTime(2026, 9, 1),
      validUntil: DateTime(2026, 12, 1),
      teacherId: 'teacher-a',
      roomId: 'room-a',
      notes: '',
      settlementTypeKey: 'visit',
      teacherCompensationRuleKey: 'hourly',
    );

    final rows = SchedulePlanMutationFlow.rowsFromDraft(
      draft,
      canManageTeacherCompensation: false,
    );

    expect(rows.single['financialDecision'], {'settlementTypeKey': 'visit'});
  });
}
