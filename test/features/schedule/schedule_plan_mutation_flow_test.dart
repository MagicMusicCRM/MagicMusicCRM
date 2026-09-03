import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
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

  test('schedule-plan payload preserves the complete frozen decision', () {
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
      teacherCreditedDurationMinutes: 45,
      teacherCompensationSource: 'manual',
      clientDecisions: const [
        {
          'clientId': 'student-a',
          'chargeDurationMinutes': 30,
          'chargeType': 'subscription',
          'subscriptionId': 'subscription-a',
        },
      ],
    );

    final rows = SchedulePlanMutationFlow.rowsFromDraft(
      draft,
      canManageTeacherCompensation: false,
    );

    expect(rows.single['financialDecision'], {
      'settlementTypeKey': 'visit',
      'teacherCompensationRuleKey': 'hourly',
      'teacherCreditedDurationMinutes': 45,
      'teacherCompensationSource': 'manual',
      'clientDecisions': [
        {
          'clientId': 'student-a',
          'chargeDurationMinutes': 30,
          'chargeType': 'subscription',
          'subscriptionId': 'subscription-a',
        },
      ],
    });
  });

  test('new individual and group rows seed every current plan client', () {
    final individual = _plan(
      studentId: 'student-a',
      subscriptionId: 'subscription-a',
    );
    final group = _plan(
      kind: 'group',
      groupId: 'group-a',
      participants: const [
        SchedulePlanParticipant(
          id: 'participant-a',
          studentId: 'student-a',
          subscriptionId: 'subscription-a',
          effectiveFrom: '2026-09-01',
          effectiveUntil: null,
          version: 1,
        ),
        SchedulePlanParticipant(
          id: 'participant-b',
          studentId: 'student-b',
          subscriptionId: 'subscription-b',
          effectiveFrom: '2026-09-01',
          effectiveUntil: null,
          version: 1,
        ),
      ],
    );

    expect(SchedulePlanMutationFlow.initialClientDecisionsForPlan(individual), [
      {
        'clientId': 'student-a',
        'chargeType': 'subscription',
        'subscriptionId': 'subscription-a',
      },
    ]);
    expect(SchedulePlanMutationFlow.initialClientDecisionsForPlan(group), [
      {
        'clientId': 'student-a',
        'chargeType': 'subscription',
        'subscriptionId': 'subscription-a',
      },
      {
        'clientId': 'student-b',
        'chargeType': 'subscription',
        'subscriptionId': 'subscription-b',
      },
    ]);
  });
}

SchedulePlan _plan({
  String kind = 'individual',
  String? studentId,
  String? groupId,
  String? subscriptionId,
  List<SchedulePlanParticipant> participants = const [],
}) => SchedulePlan(
  id: 'plan-a',
  kind: kind,
  title: 'План',
  studentId: studentId,
  groupId: groupId,
  subscriptionId: subscriptionId,
  activeFrom: '2026-09-01',
  activeUntil: null,
  status: 'active',
  version: 1,
  endedAt: null,
  endedBy: null,
  endedByName: null,
  endReason: null,
  rows: const [],
  participants: participants,
);
