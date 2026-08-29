import {
  assertSchedulePlanBackdateShape,
  schedulePlanBusinessShapeMatches,
} from "./schedule-plan-backdate";

const plan = {
  id: "00000000-0000-4000-8000-000000000001",
  kind: "individual" as const,
  title: "План",
  student_id: "00000000-0000-4000-8000-000000000002",
  group_id: null,
  subscription_id: "00000000-0000-4000-8000-000000000003",
  active_from: "2026-08-20",
  active_until: "2026-09-24",
  status: "active" as const,
  version: 1,
};

describe("schedule Plan backdate shape", () => {
  it("fails closed when a legacy active series has no financial decision snapshot", () => {
    const input = {
      plan,
      dto: {
        expectedVersion: 1,
        effectiveFrom: "2026-08-01",
        activeUntil: plan.active_until,
        subscriptionId: plan.subscription_id,
        rows: [
          {
            seriesId: "00000000-0000-4000-8000-000000000004",
            teacherId: "00000000-0000-4000-8000-000000000005",
            roomId: "00000000-0000-4000-8000-000000000006",
            branchId: "00000000-0000-4000-8000-000000000007",
            weekday: 4,
            beginTime: "18:00",
            durationMinutes: 60,
            financialDecision: {
              settlementTypeKey: "lesson",
              teacherCompensationRuleKey: "fixed",
            },
          },
        ],
      },
      subscriptionId: plan.subscription_id,
      activeUntil: plan.active_until,
      participants: [],
      participantsAtOldStart: [],
      activeSeries: [
        {
          id: "00000000-0000-4000-8000-000000000004",
          valid_from: plan.active_from,
          teacher_id: "00000000-0000-4000-8000-000000000005",
          room_id: "00000000-0000-4000-8000-000000000006",
          branch_id: "00000000-0000-4000-8000-000000000007",
          weekday: 4,
          begin_time: "18:00",
          duration_minutes: 60,
          notes: null,
          planned_financial_decision: null,
        },
      ],
    };
    expect(schedulePlanBusinessShapeMatches(input)).toBe(false);
    expect(() => assertSchedulePlanBackdateShape(input)).toThrow(
      expect.objectContaining({
        response: expect.objectContaining({
          code: "SCHEDULE_PLAN_BACKDATE_SHAPE_CHANGE",
        }),
      }),
    );
  });
});
