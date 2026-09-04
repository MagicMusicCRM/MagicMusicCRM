import { ForbiddenException, UnprocessableEntityException } from "@nestjs/common";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { ActorContext } from "../../common/security/actor-context";
import type { DatabaseService } from "../../db/database.service";
import type { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import { SchedulePlanMutationService } from "./schedule-plan-mutation.service";
import { LessonSettlementCorrectionService } from "./lesson-settlement-correction.service";
import { LessonPlannedSettlementCommandService } from "./lesson-planned-settlement-command.service";
import { LessonTransitionPreviewService } from "./lesson-transition-preview.service";
import type { LessonTransitionPreparationService } from "./lesson-transition-preparation.service";
import { LessonWriteCommandService } from "./lesson-write-command.service";

const roles = [
  "system_admin",
  "director",
  "manager",
  "admin",
  "teacher",
  "client",
] as const;

const actor = (role: (typeof roles)[number]): ActorContext => ({
  userId: `user-${role}`,
  role,
});

const financialDecision = {
  settlementTypeKey: "free_lesson",
  teacherCompensationRuleKey: "fixed",
  teacherCompensationValueMinor: "125000",
};

describe("lesson compensation service RBAC", () => {
  it("keeps every human compensation commit on the canonical current-role authorization", () => {
    for (const file of [
      "lesson-write-command.service.ts",
      "schedule-plan-mutation.service.ts",
      "lesson-transition-command.service.ts",
      "lesson-bulk-transition.service.ts",
      "lesson-planned-settlement-command.service.ts",
      "lesson-settlement-correction.service.ts",
    ]) {
      expect(readFileSync(resolve(__dirname, file), "utf8")).toContain(
        "teacherCompensationMutationAuthorization(actor)",
      );
    }
  });

  describe("central planned-decision rejection order", () => {
    const rejection = () => new UnprocessableEntityException({
      code: "TEACHER_PARTIAL_DURATION_REQUIRED",
      field: "teacherCreditedDurationMinutes",
    });

    it("rejects create before lesson, snapshot, or plan persistence", async () => {
      const client = { query: jest.fn() };
      const settlement = {
        resolvePlannedDecision: jest.fn(() => {
          throw new Error("legacy decision-only resolver used");
        }),
        resolvePlannedPlan: jest.fn().mockRejectedValue(rejection()),
        assignPreparedPlan: jest.fn(),
      };
      const repository = {
        insertLesson: jest.fn(),
        response: jest.fn(),
      };
      const lifecycle = { createSnapshot: jest.fn() };
      const platform = {
        executeVersionedMutation: jest.fn(async (input) => input.mutate(client)),
      };
      const service = new LessonWriteCommandService(
        platform as never,
        new CrmPolicy(),
        { resolve: jest.fn().mockResolvedValue({ tombstone: false }) } as never,
        {
          create: jest.fn().mockReturnValue({
            clientRef: { type: "student", id: "student-a" },
            teacherId: "teacher-a",
            branchId: "branch-a",
            roomId: "room-a",
            scheduledAt: "2026-09-04T10:00:00.000Z",
            endAt: "2026-09-04T11:00:00.000Z",
            durationMinutes: 60,
          }),
        } as never,
        {} as never,
        lifecycle as never,
        {} as never,
        settlement as never,
        repository as never,
      );

      await expect(service.create(actor("director"), {
        financialDecision: {
          settlementTypeKey: "partially_paid_lesson",
          teacherCompensationRuleKey: "percent",
        },
      }, {
        idempotencyKey: "central-resolver-create-001",
        requestId: "central-resolver-create-request-001",
      })).rejects.toMatchObject({
        status: 422,
        response: { code: "TEACHER_PARTIAL_DURATION_REQUIRED" },
      });
      expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
        client,
        expect.objectContaining({ requiredClientIds: ["student-a"] }),
      );
      expect(repository.insertLesson).not.toHaveBeenCalled();
      expect(lifecycle.createSnapshot).not.toHaveBeenCalled();
      expect(settlement.assignPreparedPlan).not.toHaveBeenCalled();
    });

    it("rejects planned edit before plan preparation or reservation mutation", async () => {
      const client = {
        query: jest.fn(async (sql: string) => {
          if (sql.includes("select lesson.teacher_id")) {
            return { rows: [{
              teacher_id: "teacher-a",
              branch_id: "branch-a",
              room_id: "room-a",
              scheduled_at: "2026-09-04T10:00:00.000Z",
              duration_minutes: 60,
              teacher_rate_snapshot: null,
            }] };
          }
          if (sql.includes("select duration_minutes")) {
            return { rows: [{ duration_minutes: 60 }] };
          }
          if (sql.includes("from app.lesson_snapshots")) {
            return { rows: [{ type: "student", id: "student-a" }, {
              type: "student", id: "student-b",
            }] };
          }
          return { rows: [] };
        }),
      };
      const settlement = {
        loadPlan: jest.fn().mockResolvedValue({
          version: 1,
          state: "planned",
          decision: {
            settlementTypeKey: "lesson",
            teacherCompensationRuleKey: "standard",
          },
        }),
        plannedSubscriptionAllocations: jest.fn().mockResolvedValue([]),
        resolvePlannedDecision: jest.fn(() => {
          throw new Error("legacy decision-only resolver used");
        }),
        resolvePlannedPlan: jest.fn().mockRejectedValue(rejection()),
        replacePlan: jest.fn(),
      };
      const reservations = {
        releaseForLessons: jest.fn(),
        allocate: jest.fn(),
      };
      const repository = {
        loadSettlementSource: jest.fn().mockResolvedValue({
          version: 1,
          lifecycle_state: "scheduled",
        }),
        listReservedAllocations: jest.fn().mockResolvedValue([]),
      };
      const service = new LessonPlannedSettlementCommandService(
        {} as never,
        {} as never,
        new CrmPolicy(),
        reservations as never,
        settlement as never,
        {} as never,
        repository as never,
        {} as never,
      );

      await expect((service as unknown as {
        calculateSettlementPlanChange(
          client: unknown,
          actor: ActorContext,
          lessonId: string,
          dto: unknown,
        ): Promise<unknown>;
      }).calculateSettlementPlanChange(
        client,
        actor("director"),
        "lesson-a",
        {
          expectedVersion: 1,
          reasonText: "Частичный расчёт",
          financialDecision: {
            settlementTypeKey: "partially_paid_lesson",
            teacherCompensationRuleKey: "percent",
            clientDecisions: [{ clientId: "student-a" }],
          },
        },
      )).rejects.toMatchObject({
        status: 422,
        response: { code: "TEACHER_PARTIAL_DURATION_REQUIRED" },
      });
      expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
        client,
        expect.objectContaining({
          requiredClientIds: ["student-a", "student-b"],
        }),
      );
      expect(settlement.replacePlan).not.toHaveBeenCalled();
      expect(reservations.releaseForLessons).not.toHaveBeenCalled();
    });

    it("rejects correction before correction history or facts persistence", async () => {
      const query = jest.fn(async (sql: string) => {
        if (sql.includes("select version, lifecycle_state")) {
          return { rows: [{
            version: 3,
            lifecycle_state: "successfully_completed",
            branch_id: "branch-a",
            duration_minutes: 60,
          }] };
        }
        if (sql.includes("select lesson.teacher_id")) {
          return { rows: [{
            teacher_id: "teacher-a",
            branch_id: "branch-a",
            room_id: "room-a",
            scheduled_at: "2026-09-04T10:00:00.000Z",
            duration_minutes: 60,
            teacher_rate_snapshot: null,
          }] };
        }
        if (sql.includes("from app.lesson_snapshots")) {
          return { rows: [{ type: "student", id: "student-a" }, {
            type: "student", id: "student-b",
          }] };
        }
        return { rows: [] };
      });
      const settlement = {
        resolvePlannedDecision: jest.fn(() => {
          throw new Error("legacy decision-only resolver used");
        }),
        resolvePlannedPlan: jest.fn().mockRejectedValue(rejection()),
        settle: jest.fn(),
      };
      const service = new LessonSettlementCorrectionService(
        {} as never,
        {} as never,
        new CrmPolicy(),
        settlement as never,
        {} as never,
        {} as never,
        {} as never,
      );

      await expect((service as unknown as {
        applyCorrection(
          client: unknown,
          actor: ActorContext,
          lessonId: string,
          dto: unknown,
          correctionId: string,
          lock: boolean,
        ): Promise<unknown>;
      }).applyCorrection(
        { query },
        actor("director"),
        "lesson-a",
        {
          expectedVersion: 3,
          reasonText: "Частичный расчёт",
          financialDecision: {
            settlementTypeKey: "partially_paid_lesson",
            teacherCompensationRuleKey: "percent",
            clientDecisions: [{ clientId: "student-a" }],
          },
        },
        "correction-a",
        true,
      )).rejects.toMatchObject({
        status: 422,
        response: { code: "TEACHER_PARTIAL_DURATION_REQUIRED" },
      });
      expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
        { query },
        expect.objectContaining({
          requiredClientIds: ["student-a", "student-b"],
        }),
      );
      expect(settlement.settle).not.toHaveBeenCalled();
      expect(query.mock.calls.some(([sql]) =>
        sql.includes("insert into app.lesson_settlement_corrections"),
      )).toBe(false);
    });

    it("assigns create from the one prepared plan returned by central resolution", async () => {
      const client = { query: jest.fn().mockResolvedValue({ rows: [] }) };
      const decision = {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        clientDecisions: [{ clientId: "student-a" }],
      };
      const prepared = {
        decision,
        settlementRevisionId: "settlement-revision-a",
        compensationRevisionId: "compensation-revision-a",
      };
      const settlement = {
        resolvePlannedPlan: jest.fn().mockResolvedValue(prepared),
        resolvePlannedDecision: jest.fn(() => {
          throw new Error("legacy decision-only resolver used");
        }),
        assignPlan: jest.fn(() => {
          throw new Error("catalog-reloading assignment used");
        }),
        assignPreparedPlan: jest.fn().mockResolvedValue(prepared),
        plannedSubscriptionAllocations: jest.fn().mockResolvedValue([]),
      };
      const repository = {
        insertLesson: jest.fn().mockResolvedValue(undefined),
        response: jest.fn().mockReturnValue({ id: "lesson-a", version: 1 }),
      };
      const service = new LessonWriteCommandService(
        {
          executeVersionedMutation: jest.fn(async (input) => ({
            resultRef: await input.mutate(client),
            version: 1,
            replayed: false,
          })),
        } as never,
        new CrmPolicy(),
        { resolve: jest.fn().mockResolvedValue({ tombstone: false }) } as never,
        {
          create: jest.fn().mockReturnValue({
            clientRef: { type: "student", id: "student-a" },
            teacherId: "teacher-a",
            branchId: "branch-a",
            roomId: "room-a",
            scheduledAt: "2026-09-04T10:00:00.000Z",
            endAt: "2026-09-04T11:00:00.000Z",
            durationMinutes: 60,
          }),
        } as never,
        { validate: jest.fn().mockResolvedValue({ valid: true }) } as never,
        { createSnapshot: jest.fn().mockResolvedValue(undefined) } as never,
        {} as never,
        settlement as never,
        repository as never,
      );

      await service.create(actor("director"), {
        financialDecision: decision,
      }, {
        idempotencyKey: "prepared-create-001",
        requestId: "prepared-create-request-001",
      });

      expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
        client,
        expect.objectContaining({ requiredClientIds: ["student-a"] }),
      );
      expect(settlement.assignPreparedPlan).toHaveBeenCalledWith(client, {
        lessonId: expect.any(String),
        selectedBy: "user-director",
        reasonText: undefined,
        ...prepared,
      });
      expect(settlement.resolvePlannedDecision).not.toHaveBeenCalled();
      expect(settlement.assignPlan).not.toHaveBeenCalled();
    });

    it("previews a planned edit from the one prepared revision pair", async () => {
      const client = {
        query: jest.fn(async (sql: string) => {
          if (sql.includes("select lesson.teacher_id")) {
            return { rows: [{
              teacher_id: "teacher-a",
              branch_id: "branch-a",
              room_id: "room-a",
              scheduled_at: "2026-09-04T10:00:00.000Z",
              duration_minutes: 60,
              teacher_rate_snapshot: null,
            }] };
          }
          if (sql.includes("from app.lesson_snapshots")) {
            return { rows: [{ type: "student", id: "student-a" }] };
          }
          if (sql.includes("select duration_minutes")) {
            return { rows: [{ duration_minutes: 60 }] };
          }
          return { rows: [] };
        }),
      };
      const decision = {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        clientDecisions: [{ clientId: "student-a" }],
      };
      const prepared = {
        decision,
        settlementRevisionId: "settlement-revision-a",
        compensationRevisionId: "compensation-revision-a",
      };
      const settlement = {
        loadPlan: jest.fn().mockResolvedValue({
          ...prepared,
          version: 1,
          state: "planned",
        }),
        plannedSubscriptionAllocations: jest.fn().mockResolvedValue([]),
        resolvePlannedPlan: jest.fn().mockResolvedValue(prepared),
        resolvePlannedDecision: jest.fn(() => {
          throw new Error("legacy decision-only resolver used");
        }),
        preparePlan: jest.fn().mockResolvedValue({
          decision,
          settlementRevisionId: "settlement-revision-b",
          compensationRevisionId: "compensation-revision-b",
        }),
        partialDurationWarnings: jest.fn().mockResolvedValue([]),
        preview: jest.fn().mockResolvedValue({
          clientFacts: [],
          teacherFact: {},
        }),
      };
      const service = new LessonPlannedSettlementCommandService(
        {} as never,
        {} as never,
        new CrmPolicy(),
        {} as never,
        settlement as never,
        {} as never,
        {
          loadSettlementSource: jest.fn().mockResolvedValue({
            version: 1,
            lifecycle_state: "scheduled",
          }),
          listReservedAllocations: jest.fn().mockResolvedValue([]),
          markCompletedForFinancialPreview: jest.fn().mockResolvedValue(undefined),
        } as never,
        {} as never,
      );

      const result = await (service as unknown as {
        calculateSettlementPlanChange(
          client: unknown,
          targetActor: ActorContext,
          lessonId: string,
          dto: unknown,
        ): Promise<{ prepared: typeof prepared }>;
      }).calculateSettlementPlanChange(client, actor("director"), "lesson-a", {
        expectedVersion: 1,
        reasonText: "Изменено правило расчёта",
        financialDecision: decision,
      });

      expect(result.prepared).toEqual(prepared);
      expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
        client,
        expect.objectContaining({ requiredClientIds: ["student-a"] }),
      );
      expect(settlement.resolvePlannedDecision).not.toHaveBeenCalled();
      expect(settlement.preparePlan).not.toHaveBeenCalled();
    });
  });

  it.each(roles)(
    "keeps lesson creation available without granting rate changes for %s",
    async (role) => {
      const reachedAuthorizedWork = new Error("AUTHORIZED_WORK");
      const service = new LessonWriteCommandService(
        {} as never,
        new CrmPolicy(),
        {} as never,
        {
          create: jest.fn(() => {
            throw reachedAuthorizedWork;
          }),
        } as never,
        {} as never,
        {} as never,
        {} as never,
        {} as never,
        {} as never,
      );
      const request = service.create(
        actor(role),
        {
          teacherRate: 1250,
          teacherCompensationType: "hourly",
          teacherCompensationValue: 1250,
          financialDecision,
        },
        {
          idempotencyKey: "lesson-compensation-rbac-001",
          requestId: "lesson-compensation-rbac-request-001",
        },
      );

      if (["director", "system_admin", "manager", "admin"].includes(role)) {
        await expect(request).rejects.toBe(reachedAuthorizedWork);
      } else {
        await expect(request).rejects.toBeInstanceOf(ForbiddenException);
      }
    },
  );

  it.each(roles)(
    "keeps settlement correction available without granting rate changes for %s",
    async (role) => {
      const reachedAuthorizedWork = new Error("AUTHORIZED_WORK");
      const database = {
        transaction: jest.fn().mockRejectedValue(reachedAuthorizedWork),
      } as unknown as DatabaseService;
      const service = new LessonSettlementCorrectionService(
        database,
        {} as PlatformIntegrityService,
        new CrmPolicy(),
        {} as never,
        {} as never,
        {} as never,
        {} as never,
      );
      const request = service.preview(actor(role), "lesson-1", {
        expectedVersion: 3,
        reasonText: "Исправление расчёта",
        financialDecision,
      });

      if (["director", "system_admin", "manager", "admin"].includes(role)) {
        await expect(request).rejects.toBe(reachedAuthorizedWork);
        expect(database.transaction).toHaveBeenCalledTimes(1);
      } else {
        await expect(request).rejects.toBeInstanceOf(ForbiddenException);
        expect(database.transaction).not.toHaveBeenCalled();
      }
    },
  );

  it.each(["manager", "admin", "director", "system_admin"] as const)(
    "applies the effective teacher compensation policy while %s corrects settlement",
    async (role) => {
      const baseDecision = {
        settlementTypeKey: "paid_lesson",
        clientDecisions: [
          {
            clientId: "11111111-1111-4111-8111-111111111111",
            settlementTypeKey: "paid_lesson",
          },
        ],
      };
      const canOverride = role === "director" || role === "system_admin";
      const requestedDecision = canOverride
        ? {
            ...baseDecision,
            teacherCompensationRuleKey: "fixed",
            teacherCompensationValueMinor: "999999",
          }
        : baseDecision as never;
      const effectiveDecision = canOverride
        ? requestedDecision
        : {
            ...requestedDecision,
            teacherCompensationRuleKey: "fixed",
            teacherCompensationValueMinor: "125000",
          };
      const query = jest.fn(async (sql: string, _params?: unknown[]) => {
        if (sql.includes("select lesson.teacher_id")) {
          return { rows: [{ teacher_id: "teacher-1", branch_id: "branch-1", room_id: "room-1" }] };
        }
        if (sql.includes("from app.lesson_snapshots")) {
          return { rows: [{
            type: "student",
            id: "11111111-1111-4111-8111-111111111111",
          }] };
        }
        if (sql.includes("select version, lifecycle_state")) {
          return {
            rows: [
              {
                version: 3,
                lifecycle_state: "successfully_completed",
                branch_id: "branch-1",
                duration_minutes: 60,
              },
            ],
          };
        }
        return { rows: [] };
      });
      const client = { query };
      const settlement = {
        reuseStoredTeacherCompensation: jest
          .fn()
          .mockResolvedValue(effectiveDecision),
        resolvePlannedDecision: jest.fn().mockResolvedValue(effectiveDecision),
        preparePlan: jest.fn().mockResolvedValue({
          decision: effectiveDecision,
          settlementRevisionId: "settlement-revision-b",
          compensationRevisionId: "compensation-revision-b",
        }),
        resolvePlannedPlan: jest.fn().mockResolvedValue({
          decision: effectiveDecision,
          settlementRevisionId: "settlement-revision-a",
          compensationRevisionId: "compensation-revision-a",
        }),
        partialDurationWarnings: jest.fn().mockResolvedValue([]),
        settle: jest.fn().mockResolvedValue({
          clientFacts: [],
          teacherFact: { id: "teacher-fact-1" },
        }),
      };
      const service = new LessonSettlementCorrectionService(
        {} as DatabaseService,
        {} as PlatformIntegrityService,
        new CrmPolicy(),
        settlement as never,
        {} as never,
        {} as never,
        {} as never,
      );

      const result = await (
        service as unknown as {
          applyCorrection(
            client: unknown,
            targetActor: ActorContext,
            lessonId: string,
            dto: unknown,
            correctionId: string,
            lock: boolean,
          ): Promise<{ settled: { teacherFact: { id: string } } }>;
        }
      ).applyCorrection(
        client,
        actor(role),
        "lesson-1",
        {
          expectedVersion: 3,
          reasonText: "Исправление оплаты клиента",
          financialDecision: requestedDecision,
        },
        "correction-1",
        true,
      );

      const historyInsert = query.mock.calls.find(([sql]) =>
        sql.includes("insert into app.lesson_settlement_corrections"),
      );
      expect(historyInsert).toBeDefined();
      expect(JSON.parse(String(historyInsert?.[1]?.[4]))).toEqual(
        effectiveDecision,
      );
      expect(historyInsert?.[1]?.[5]).toBe("settlement-revision-a");
      expect(historyInsert?.[1]?.[6]).toBe("compensation-revision-a");
      expect(settlement.settle).toHaveBeenCalledWith(
        client,
        "lesson-1",
        expect.objectContaining({
          decision: effectiveDecision,
          configurationRevisionIds: {
            settlementRevisionId: "settlement-revision-a",
            compensationRevisionId: "compensation-revision-a",
          },
        }),
      );
      expect(settlement.resolvePlannedDecision).not.toHaveBeenCalled();
      expect(settlement.preparePlan).not.toHaveBeenCalled();
      expect(settlement.reuseStoredTeacherCompensation).toHaveBeenCalledTimes(
        canOverride ? 0 : 1,
      );
      expect(result.settled.teacherFact.id).toBe("teacher-fact-1");
    },
  );

  it.each(["reschedule", "cancel", "settle"] as const)(
    "keeps legacy %s payload compatible without granting rate changes",
    async (operation) => {
      for (const role of roles) {
        const reachedAuthorizedWork = new Error("AUTHORIZED_WORK");
        const database = {
          transaction: jest.fn().mockRejectedValue(reachedAuthorizedWork),
        } as unknown as DatabaseService;
        const service = new LessonTransitionPreviewService(
          database,
          new CrmPolicy(),
          {} as LessonTransitionPreparationService,
          {} as never,
        );
        const dto = {
          expectedVersion: 3,
          reasonText: "Решение по занятию",
          financialDecision,
          ...(operation === "reschedule" ? { successor: {} } : {}),
        };
        const request =
          operation === "reschedule"
            ? service.previewReschedule(actor(role), "lesson-1", dto as never)
            : operation === "cancel"
              ? service.previewCancel(actor(role), "lesson-1", dto as never)
              : service.previewSettle(actor(role), "lesson-1", dto as never);

        if (["director", "system_admin", "manager", "admin"].includes(role)) {
          await expect(request).rejects.toBe(reachedAuthorizedWork);
          expect(database.transaction).toHaveBeenCalledTimes(1);
        } else {
          await expect(request).rejects.toBeInstanceOf(ForbiddenException);
          expect(database.transaction).not.toHaveBeenCalled();
        }
      }
    },
  );

  it.each(["manager", "admin"] as const)(
    "keeps operational %s transitions available when teacher fields are omitted",
    async (role) => {
      const reachedAuthorizedWork = new Error("AUTHORIZED_WORK");
      const database = {
        transaction: jest.fn().mockRejectedValue(reachedAuthorizedWork),
      } as unknown as DatabaseService;
      const service = new LessonTransitionPreviewService(
        database,
        new CrmPolicy(),
        {} as LessonTransitionPreparationService,
        {} as never,
      );

      await expect(
        service.previewCancel(actor(role), "lesson-1", {
          expectedVersion: 3,
          reasonText: "Отмена занятия",
          financialDecision: { settlementTypeKey: "free_lesson" } as never,
        }),
      ).rejects.toBe(reachedAuthorizedWork);
    },
  );

  it.each(roles)(
    "keeps authorized and sparse schedule-plan payloads compatible for %s",
    async (role) => {
      const reachedAuthorizedWork = new Error("AUTHORIZED_WORK");
      const service = new SchedulePlanMutationService(
        {} as PlatformIntegrityService,
        new CrmPolicy(),
        {} as never,
        {} as never,
        {} as never,
        {
          normalizeCreate: jest.fn(() => {
            throw reachedAuthorizedWork;
          }),
        } as never,
        {} as never,
      );
      const request = service.create(
        actor(role),
        {
          kind: "individual",
          title: "Plan",
          studentId: "student-1",
          subscriptionId: "subscription-1",
          activeFrom: "2026-09-01",
          rows: [
            {
              teacherId: "teacher-1",
              roomId: "room-1",
              branchId: "branch-1",
              weekday: 1,
              beginTime: "10:00",
              financialDecision:
                role === "director" || role === "system_admin"
                  ? financialDecision
                  : { settlementTypeKey: "free_lesson" } as never,
            },
          ],
        },
        {
          idempotencyKey: "schedule-plan-compensation-001",
          requestId: "schedule-plan-compensation-request-001",
        },
      );

      if (["director", "system_admin", "manager", "admin"].includes(role)) {
        await expect(request).rejects.toBe(reachedAuthorizedWork);
      } else {
        await expect(request).rejects.toBeInstanceOf(ForbiddenException);
      }
    },
  );

  it.each(["manager", "admin"] as const)(
    "keeps operational %s schedule-plan creation available when compensation is omitted",
    async (role) => {
      const reachedAuthorizedWork = new Error("AUTHORIZED_WORK");
      const service = new SchedulePlanMutationService(
        {} as PlatformIntegrityService,
        new CrmPolicy(),
        {} as never,
        {} as never,
        {} as never,
        {
          normalizeCreate: jest.fn(() => {
            throw reachedAuthorizedWork;
          }),
        } as never,
        {} as never,
      );

      await expect(
        service.create(
          actor(role),
          {
            kind: "individual",
            title: "Plan",
            studentId: "student-1",
            subscriptionId: "subscription-1",
            activeFrom: "2026-09-01",
            rows: [
              {
                teacherId: "teacher-1",
                roomId: "room-1",
                branchId: "branch-1",
                weekday: 1,
                beginTime: "10:00",
                financialDecision: {
                  settlementTypeKey: "free_lesson",
                } as never,
              },
            ],
          },
          {
            idempotencyKey: "schedule-plan-compensation-omitted-001",
            requestId: "schedule-plan-compensation-omitted-request-001",
          },
        ),
      ).rejects.toBe(reachedAuthorizedWork);
    },
  );
});
