import { ActorContext } from "../../common/security/actor-context";
import type { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { LessonConstraintPreviewService } from "./lesson-constraint-preview.service";
import { LessonPlannedSettlementCommandService } from "./lesson-planned-settlement-command.service";
import { LessonSettlementCorrectionService } from "./lesson-settlement-correction.service";

describe("LessonConstraintPreviewService", () => {
  it("uses the unified analyzer and preserves the requested lesson interval", async () => {
    const policy = { assertCanWriteCrm: jest.fn() };
    const analysis = {
      valid: false,
      violations: [],
      conflicts: [],
      suggestions: [],
    };
    const constraints = {
      analyze: jest.fn().mockResolvedValue(analysis),
    };
    const service = new LessonConstraintPreviewService(
      policy as never,
      constraints as never,
    );
    const actor = {
      userId: "00000000-0000-4000-8000-000000000001",
      role: "manager",
    } as ActorContext;

    await expect(
      service.previewConstraints(actor, {
        clientRef: {
          type: "student",
          id: "00000000-0000-4000-8000-000000000002",
        },
        teacherId: "00000000-0000-4000-8000-000000000003",
        branchId: "00000000-0000-4000-8000-000000000004",
        roomId: "00000000-0000-4000-8000-000000000005",
        scheduledAt: "2026-08-14T09:00:00.000Z",
        durationMinutes: 45,
        excludeLessonId: "00000000-0000-4000-8000-000000000006",
      }),
    ).resolves.toBe(analysis);

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(constraints.analyze).toHaveBeenCalledWith({
      clientRef: {
        type: "student",
        id: "00000000-0000-4000-8000-000000000002",
      },
      teacherId: "00000000-0000-4000-8000-000000000003",
      branchId: "00000000-0000-4000-8000-000000000004",
      roomId: "00000000-0000-4000-8000-000000000005",
      startAt: new Date("2026-08-14T09:00:00.000Z"),
      endAt: new Date("2026-08-14T09:45:00.000Z"),
      excludeLessonId: "00000000-0000-4000-8000-000000000006",
    });
  });
});

describe("lesson settlement boundary recommendations", () => {
  const actor = { userId: "director-a", role: "director" as const };
  const warnings = [
    "CLIENT_ZERO_DURATION_SETTLEMENT_TYPE_RECOMMENDED",
    "TEACHER_FULL_DURATION_SETTLEMENT_TYPE_RECOMMENDED",
  ];

  it("adds non-blocking warnings to the planned-settlement preview", async () => {
    const database = {
      transaction: jest.fn(async (work) => work({ query: jest.fn() })),
    } as unknown as DatabaseService;
    const service = new LessonPlannedSettlementCommandService(
      database,
      {} as never,
      new CrmPolicy(),
      {} as never,
      {} as never,
      {
        issueLessonTransition: jest.fn().mockReturnValue({
          token: "preview-token",
          expiresAt: "2026-09-03T12:00:00.000Z",
        }),
      } as never,
      {} as never,
      {} as never,
    );
    jest.spyOn(service as never, "calculateSettlementPlanChange" as never)
      .mockResolvedValue({
        fingerprint: "fingerprint",
        financial: {},
        reservations: { before: [], after: [] },
        resourceChange: null,
        warnings,
      } as never);

    await expect(service.previewSettlementPlan(actor, "lesson-a", {
      expectedVersion: 1,
      reasonText: "Проверка границы",
      financialDecision: {
        settlementTypeKey: "partially_paid_lesson",
        teacherCompensationRuleKey: "percent",
      },
    })).resolves.toMatchObject({
      canConfirm: true,
      warnings,
    });
  });

  it("adds non-blocking warnings to the correction preview", async () => {
    const database = {
      transaction: jest.fn(async (work) => work({ query: jest.fn() })),
    } as unknown as DatabaseService;
    const service = new LessonSettlementCorrectionService(
      database,
      {} as never,
      new CrmPolicy(),
      {} as never,
      {
        issueLessonTransition: jest.fn().mockReturnValue({
          token: "preview-token",
          expiresAt: "2026-09-03T12:00:00.000Z",
        }),
      } as never,
      {} as never,
      {} as never,
    );
    jest.spyOn(service as never, "applyCorrection" as never).mockResolvedValue({
      settled: { clientFacts: [], teacherFact: { teacherId: "teacher-a" } },
      resourceChange: null,
      decision: {},
      warnings,
    } as never);

    await expect(service.preview(actor, "lesson-a", {
      expectedVersion: 1,
      reasonText: "Проверка границы",
      financialDecision: {
        settlementTypeKey: "partially_paid_lesson",
        teacherCompensationRuleKey: "percent",
      },
    })).resolves.toMatchObject({
      canConfirm: true,
      warnings,
    });
  });
});
