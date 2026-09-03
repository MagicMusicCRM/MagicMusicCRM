import type { PoolClient } from "pg";
import type { DatabaseService } from "../../db/database.service";
import { LessonSettlementService } from "./lesson-settlement.service";

const actor = (role: "admin" | "director") => ({
  actor: { userId: `${role}-a`, role },
  capabilityKey: role === "director"
    ? "config.commerce.manage" as const
    : "schedule.lesson.write" as const,
});

function catalogRow(
  settlementRevisionId = "settlement-revision",
  compensationRevisionId = "compensation-revision",
) {
  return {
    settlement_revision_id: settlementRevisionId,
    compensation_revision_id: compensationRevisionId,
    settlement_types: [
      {
        stableKey: "lesson", label: "Занятие", active: true, order: 0,
        allowedContexts: ["settle"], hourShareBasisPoints: 10_000,
        clientDurationMode: "full", teacherDurationMode: "full",
        defaultTeacherCompensationRuleKey: "standard", colorToken: "blue",
      },
      {
        stableKey: "free_lesson", label: "Бесплатно", active: true, order: 1,
        allowedContexts: ["settle"], hourShareBasisPoints: 0,
        clientDurationMode: "zero", teacherDurationMode: "zero",
        defaultTeacherCompensationRuleKey: "none", colorToken: "neutral",
      },
      {
        stableKey: "partially_paid_lesson", label: "Частично", active: true, order: 2,
        allowedContexts: ["settle"], hourShareBasisPoints: 5_000,
        clientDurationMode: "manual", teacherDurationMode: "manual",
        defaultTeacherCompensationRuleKey: "percent", colorToken: "warning",
      },
    ],
    compensation_rules: [
      { stableKey: "none", label: "Нет", active: true, order: 0, mode: "none", value: "0" },
      { stableKey: "standard", label: "Стандарт", active: true, order: 1, mode: "standard", value: "0" },
      { stableKey: "percent", label: "Процент", active: true, order: 2, mode: "percent", value: "5000" },
      { stableKey: "fixed", label: "Фиксировано", active: true, order: 3, mode: "fixed", value: "100000" },
    ],
  };
}

function catalogClient(): PoolClient {
  return {
    query: jest.fn().mockResolvedValue({
      rows: [catalogRow()],
    }),
  } as unknown as PoolClient;
}

describe("LessonSettlementService.resolvePlannedDecision", () => {
  const service = new LessonSettlementService({} as DatabaseService);

  it.each([30, 45, 60, 90])(
    "normalizes automatic zero and full decisions for %i minutes",
    async (durationMinutes) => {
      const full = await service.resolvePlannedDecision(catalogClient(), {
        branchId: "branch-a",
        durationMinutes,
        decision: {
          settlementTypeKey: "lesson",
          teacherCompensationRuleKey: "standard",
          clientDecisions: [{ clientId: "student-a" }],
        },
        actorUserId: "admin-a",
        authorization: actor("admin"),
      });
      expect(full).toMatchObject({
        teacherCompensationRuleKey: "standard",
        teacherCreditedDurationMinutes: durationMinutes,
        teacherCompensationSource: "automatic",
        clientDecisions: [{ chargeDurationMinutes: durationMinutes }],
      });

      const zero = await service.resolvePlannedDecision(catalogClient(), {
        branchId: "branch-a",
        durationMinutes,
        decision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "standard",
          clientDecisions: [{ clientId: "student-a" }],
        },
        actorUserId: "admin-a",
        authorization: actor("admin"),
      });
      expect(zero).toMatchObject({
        teacherCompensationRuleKey: "none",
        teacherCreditedDurationMinutes: 0,
        teacherCompensationSource: "automatic",
        clientDecisions: [{ chargeDurationMinutes: 0 }],
      });
    },
  );

  it.each([
    [30, 0, 30],
    [45, 45, 0],
    [60, 30, 45],
    [90, 90, 45],
  ])(
    "preserves exact partial boundaries for %i-minute lessons",
    async (durationMinutes, clientMinutes, teacherMinutes) => {
      await expect(service.resolvePlannedDecision(catalogClient(), {
        branchId: "branch-a",
        durationMinutes,
        decision: {
          settlementTypeKey: "partially_paid_lesson",
          teacherCompensationRuleKey: "percent",
          teacherCreditedDurationMinutes: teacherMinutes,
          teacherCompensationSource: "manual",
          clientDecisions: [{
            clientId: "student-a",
            chargeDurationMinutes: clientMinutes,
          }],
        },
        actorUserId: "director-a",
        authorization: actor("director"),
        reasonText: "Согласовано директором",
      })).resolves.toMatchObject({
        teacherCompensationRuleKey: "percent",
        teacherCompensationValueMinor: Math.round(
          teacherMinutes * 10_000 / durationMinutes,
        ).toString(),
        teacherCreditedDurationMinutes: teacherMinutes,
        teacherCompensationSource: "manual",
        clientDecisions: [{ chargeDurationMinutes: clientMinutes }],
      });
    },
  );

  it("recommends a clearer type for an explicit manual teacher boundary override", async () => {
    await expect(service.partialDurationWarnings(catalogClient(), {
      branchId: "branch-a",
      durationMinutes: 60,
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "percent",
        teacherCreditedDurationMinutes: 0,
        teacherCompensationSource: "manual",
      },
    })).resolves.toEqual([
      "TEACHER_ZERO_DURATION_SETTLEMENT_TYPE_RECOMMENDED",
    ]);
  });

  it.each([
    {
      name: "manual source",
      decision: { teacherCompensationSource: "manual" as const },
    },
    {
      name: "changed rule",
      decision: {
        teacherCompensationRuleKey: "fixed",
      },
    },
    {
      name: "changed credited minutes",
      decision: {
        teacherCreditedDurationMinutes: 30,
      },
    },
    {
      name: "changed amount",
      decision: {
        teacherCompensationValueMinor: "5000",
      },
    },
  ])("rejects an unauthorized $name before persistence", async ({ decision }) => {
    await expect(service.resolvePlannedDecision(catalogClient(), {
      branchId: "branch-a",
      durationMinutes: 60,
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        ...decision,
      },
      actorUserId: "admin-a",
      authorization: actor("admin"),
      reasonText: "Попытка изменения",
    })).rejects.toMatchObject({
      status: 403,
      response: { code: "TEACHER_COMPENSATION_PERMISSION_REQUIRED" },
    });
  });

  it("requires a business reason for an authorized manual decision", async () => {
    await expect(service.resolvePlannedDecision(catalogClient(), {
      branchId: "branch-a",
      durationMinutes: 60,
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "fixed",
        teacherCompensationSource: "manual",
      },
      actorUserId: "director-a",
      authorization: actor("director"),
    })).rejects.toMatchObject({
      status: 422,
      response: { code: "TEACHER_COMPENSATION_REASON_REQUIRED" },
    });
  });

  it.each([
    {
      decision: {
        settlementTypeKey: "partially_paid_lesson",
        teacherCompensationRuleKey: "percent",
        teacherCreditedDurationMinutes: 30,
        teacherCompensationSource: "manual" as const,
        clientDecisions: [{ clientId: "student-a" }],
      },
      code: "CLIENT_PARTIAL_DURATION_REQUIRED",
      field: "clientDecisions.student-a.chargeDurationMinutes",
    },
    {
      decision: {
        settlementTypeKey: "partially_paid_lesson",
        teacherCompensationRuleKey: "percent",
        teacherCompensationSource: "manual" as const,
        clientDecisions: [{ clientId: "student-a", chargeDurationMinutes: 30 }],
      },
      code: "TEACHER_PARTIAL_DURATION_REQUIRED",
      field: "teacherCreditedDurationMinutes",
    },
  ])("maps missing partial input to $code", async ({ decision, code, field }) => {
    await expect(service.resolvePlannedDecision(catalogClient(), {
      branchId: "branch-a",
      durationMinutes: 60,
      decision,
      actorUserId: "director-a",
      authorization: actor("director"),
      reasonText: "Частичный расчёт",
    })).rejects.toMatchObject({ status: 422, response: { code, field } });
  });

  it("uses a trusted preserved teacher decision without accepting payload changes", async () => {
    await expect(service.resolvePlannedDecision(catalogClient(), {
      branchId: "branch-a",
      durationMinutes: 60,
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "fixed",
        teacherCompensationValueMinor: "999999",
        teacherCompensationSource: "manual",
      },
      actorUserId: "admin-a",
      authorization: actor("admin"),
      preservedTeacherDecision: {
        teacherCompensationRuleKey: "fixed",
        teacherCompensationValueMinor: "125000",
        teacherCreditedDurationMinutes: 60,
        teacherCompensationSource: "manual",
      },
    })).resolves.toMatchObject({
      teacherCompensationRuleKey: "fixed",
      teacherCompensationValueMinor: "125000",
      teacherCreditedDurationMinutes: 60,
      teacherCompensationSource: "manual",
    });
  });

  it.each([
    {
      name: "missing individual",
      requiredClientIds: ["student-a"],
      clientDecisions: [],
      code: "CLIENT_DECISION_MISSING",
    },
    {
      name: "missing group participant",
      requiredClientIds: ["student-a", "student-b"],
      clientDecisions: [{ clientId: "student-a" }],
      code: "CLIENT_DECISION_MISSING",
    },
    {
      name: "duplicate participant",
      requiredClientIds: ["student-a"],
      clientDecisions: [{ clientId: "student-a" }, { clientId: "student-a" }],
      code: "DUPLICATE_CLIENT_DECISION",
    },
    {
      name: "unrelated participant",
      requiredClientIds: ["student-a"],
      clientDecisions: [{ clientId: "student-a" }, { clientId: "student-b" }],
      code: "UNKNOWN_LESSON_CLIENT",
    },
  ])("rejects $name before resolving a recurring decision", async ({
    requiredClientIds,
    clientDecisions,
    code,
  }) => {
    await expect(service.resolvePlannedDecision(catalogClient(), {
      branchId: "branch-a",
      durationMinutes: 60,
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        clientDecisions,
      },
      requiredClientIds,
      actorUserId: "admin-a",
      authorization: actor("admin"),
    })).rejects.toMatchObject({ status: 422, response: { code } });
  });

  it("rejects an omitted client decision list when clients are required", async () => {
    await expect(service.resolvePlannedDecision(catalogClient(), {
      branchId: "branch-a",
      durationMinutes: 60,
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
      },
      requiredClientIds: ["student-a"],
      actorUserId: "admin-a",
      authorization: actor("admin"),
    })).rejects.toMatchObject({
      status: 422,
      response: {
        code: "CLIENT_DECISION_MISSING",
        field: "clientDecisions",
      },
    });
  });

  it("resolves and freezes revision ids from one catalog load", async () => {
    const client = catalogClient();
    const query = client.query as jest.Mock;
    query
      .mockResolvedValueOnce({ rows: [catalogRow("settlement-a", "compensation-a")] })
      .mockResolvedValue({ rows: [catalogRow("settlement-b", "compensation-b")] });

    const prepared = await service.resolvePlannedPlan(client, {
      branchId: "branch-a",
      durationMinutes: 60,
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        clientDecisions: [{ clientId: "student-a" }],
      },
      requiredClientIds: ["student-a"],
      actorUserId: "admin-a",
      authorization: actor("admin"),
    });

    expect(prepared).toMatchObject({
      settlementRevisionId: "settlement-a",
      compensationRevisionId: "compensation-a",
      decision: {
        clientDecisions: [{
          clientId: "student-a",
          chargeDurationMinutes: 60,
        }],
      },
    });
    expect(query).toHaveBeenCalledTimes(1);
  });

  it.each([
    [0, 60, [
      "CLIENT_ZERO_DURATION_SETTLEMENT_TYPE_RECOMMENDED",
      "TEACHER_FULL_DURATION_SETTLEMENT_TYPE_RECOMMENDED",
    ]],
    [60, 0, [
      "CLIENT_FULL_DURATION_SETTLEMENT_TYPE_RECOMMENDED",
      "TEACHER_ZERO_DURATION_SETTLEMENT_TYPE_RECOMMENDED",
    ]],
    [30, 45, []],
  ] as const)(
    "recommends clearer settlement types for manual boundary %i/%i without rewriting",
    async (clientMinutes, teacherMinutes, expectedWarnings) => {
      const decision = {
        settlementTypeKey: "partially_paid_lesson",
        teacherCompensationRuleKey: "percent",
        teacherCreditedDurationMinutes: teacherMinutes,
        teacherCompensationSource: "manual" as const,
        clientDecisions: [{
          clientId: "student-a",
          chargeDurationMinutes: clientMinutes,
        }],
      };
      const warnings = await (
        service as unknown as {
          partialDurationWarnings(
            client: PoolClient,
            input: {
              branchId: string;
              durationMinutes: number;
              decision: typeof decision;
            },
          ): Promise<string[]>;
        }
      ).partialDurationWarnings(catalogClient(), {
        branchId: "branch-a",
        durationMinutes: 60,
        decision,
      });

      expect(warnings).toEqual(expectedWarnings);
      expect(decision.clientDecisions[0]!.chargeDurationMinutes).toBe(
        clientMinutes,
      );
      expect(decision.teacherCreditedDurationMinutes).toBe(teacherMinutes);
    },
  );

  it.each([
    ["lesson", 60],
    ["free_lesson", 0],
  ] as const)(
    "does not recommend replacing an automatic %s decision",
    async (settlementTypeKey, minutes) => {
      await expect(service.partialDurationWarnings(catalogClient(), {
        branchId: "branch-a",
        durationMinutes: 60,
        decision: {
          settlementTypeKey,
          teacherCompensationRuleKey:
            settlementTypeKey === "lesson" ? "standard" : "none",
          teacherCreditedDurationMinutes: minutes,
          teacherCompensationSource: "automatic",
          clientDecisions: [{
            clientId: "student-a",
            chargeDurationMinutes: minutes,
          }],
        },
      })).resolves.toEqual([]);
    },
  );
});
