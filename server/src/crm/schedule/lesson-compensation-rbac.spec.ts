import { ForbiddenException } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import type { DatabaseService } from "../../db/database.service";
import type { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import { SchedulePlanMutationService } from "./schedule-plan-mutation.service";
import { LessonSettlementCorrectionService } from "./lesson-settlement-correction.service";
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
      const requestedDecision = {
        settlementTypeKey: "paid_lesson",
        teacherCompensationRuleKey: "fixed",
        teacherCompensationValueMinor: "999999",
        clientDecisions: [
          {
            clientId: "11111111-1111-4111-8111-111111111111",
            settlementTypeKey: "paid_lesson",
          },
        ],
      };
      const canOverride = role === "director" || role === "system_admin";
      const effectiveDecision = canOverride
        ? requestedDecision
        : {
            ...requestedDecision,
            teacherCompensationRuleKey: "fixed",
            teacherCompensationValueMinor: "125000",
          };
      const query = jest.fn(async (sql: string, _params?: unknown[]) => {
        if (sql.includes("select version, lifecycle_state")) {
          return {
            rows: [
              {
                version: 3,
                lifecycle_state: "successfully_completed",
                branch_id: "branch-1",
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
        preparePlan: jest.fn().mockResolvedValue({
          settlementRevisionId: "settlement-revision-1",
          compensationRevisionId: "compensation-revision-1",
        }),
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
      expect(settlement.settle).toHaveBeenCalledWith(
        client,
        "lesson-1",
        expect.objectContaining({ decision: effectiveDecision }),
      );
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
    "keeps legacy schedule-plan payload compatible for %s",
    async (role) => {
      const reachedAuthorizedWork = new Error("AUTHORIZED_WORK");
      const service = new SchedulePlanMutationService(
        {} as PlatformIntegrityService,
        new CrmPolicy(),
        {} as never,
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
              financialDecision,
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
