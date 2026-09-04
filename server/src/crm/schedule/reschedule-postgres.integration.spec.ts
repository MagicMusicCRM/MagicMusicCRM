import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { AuditService } from "../../audit/audit.service";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { NotificationTokenCrypto } from "../../notifications/notification-token-crypto.service";
import { NotificationWorker } from "../../notifications/notification-worker.service";
import { NotificationsPolicy } from "../../notifications/notifications.policy";
import { NotificationsService } from "../../notifications/notifications.service";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { ClientArchiveService } from "../clients/client-archive.service";
import { lessonSettlementLockKey } from "../commerce/lesson-settlement-locks";
import { LessonSettlementPort } from "../commerce/lesson-settlement.port";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import { AvailabilityRepository } from "./availability.repository";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { LessonCompletionWorkerRepository } from "./completion-worker.repository";
import { LessonCompletionService } from "./lesson-completion.service";
import { LessonCompletionWorker } from "./lesson-completion.worker";
import { LessonActionableChainService } from "./lesson-actionable-chain.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonCommandRepository } from "./lesson-command.repository";
import { LessonPlannedSettlementCommandService } from "./lesson-planned-settlement-command.service";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
import { LessonBulkTransitionService } from "./lesson-bulk-transition.service";
import { LessonTransitionCommandService } from "./lesson-transition-command.service";
import { LessonTransitionCommitService } from "./lesson-transition-commit.service";
import { LessonTransitionFinancialService } from "./lesson-transition-financial.service";
import { LessonTransitionPreparationService } from "./lesson-transition-preparation.service";
import { LessonTransitionPreviewService } from "./lesson-transition-preview.service";
import { stableTransitionId } from "./lesson-transition.rules";
import { LessonTransitionService } from "./lesson-transition.service";
import { LessonSettlementCorrectionService } from "./lesson-settlement-correction.service";

const url =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (!["127.0.0.1", "localhost", "[::1]"].includes(new URL(url).hostname)) {
  throw new Error("Lesson transition tests require local PostgreSQL.");
}
const previewSecret = "lesson-transition-preview-secret-for-tests-2026";
jest.setTimeout(60_000);

describe("Atomic lesson reschedule/cancel/settle (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let service: LessonTransitionService;
  let failingService: LessonTransitionService;
  let settlement: LessonSettlementService;
  let completionWorker: LessonCompletionWorker;
  let corrections: LessonSettlementCorrectionService;
  let archives: ClientArchiveService;
  let tokens: SubscriptionPreviewTokenService;
  let plannedSettlements: LessonPlannedSettlementCommandService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: url });
    await new MigrationRunner(pool).up();
    const config = {
      getOrThrow: () => url,
      get: (key: string, fallback: string) =>
        key === "COMMERCE_PREVIEW_SECRET" ? previewSecret : fallback,
    } as unknown as ConfigService;
    database = new DatabaseService(config);
    const constraints = new ScheduleConstraintEngine(
      new ConstraintEngineRepository(
        database,
        new AvailabilityRepository(database),
      ),
    );
    const lifecycle = new LessonLifecycleRepository(database);
    const actionableChains = new LessonActionableChainService(lifecycle);
    const reservations = new SubscriptionReservationService(database, {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    } as unknown as RealtimeBus);
    tokens = new SubscriptionPreviewTokenService(config);
    const platform = new PlatformIntegrityService(
      database,
      new PlatformIntegrityRepository(),
    );
    const policy = new CrmPolicy();
    archives = new ClientArchiveService(
      database,
      platform,
      policy,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );
    const validator = new LessonRequiredFieldValidator();
    settlement = new LessonSettlementService(database);
    plannedSettlements = new LessonPlannedSettlementCommandService(
      database,
      platform,
      policy,
      reservations,
      settlement,
      tokens,
      new LessonCommandRepository(database),
      constraints,
    );
    corrections = new LessonSettlementCorrectionService(database, platform, policy,
      settlement, tokens, reservations, constraints);
    const buildTransitionGraph = (settlementPort: LessonSettlementPort) => {
      const financial = new LessonTransitionFinancialService(
        settlementPort,
        reservations,
      );
      const preparation = new LessonTransitionPreparationService(
        database,
        policy,
        validator,
        constraints,
        settlementPort,
        reservations,
        financial,
        new LessonCommandRepository(database),
      );
      const commits = new LessonTransitionCommitService(
        preparation,
        financial,
        settlementPort,
        reservations,
        lifecycle,
      );
      const previews = new LessonTransitionPreviewService(
        database,
        policy,
        preparation,
        tokens,
        actionableChains,
      );
      const commands = new LessonTransitionCommandService(
        platform,
        policy,
        tokens,
        commits,
        reservations,
        actionableChains,
      );
      const bulkTransitions = new LessonBulkTransitionService(
        database,
        platform,
        policy,
        tokens,
        preparation,
        commits,
        reservations,
      );
      return new LessonTransitionService(previews, commands, bulkTransitions);
    };
    service = buildTransitionGraph(settlement);
    failingService = buildTransitionGraph({
      settle: async (
        ...args: Parameters<LessonSettlementService["settle"]>
      ) => {
        await settlement.settle(...args);
        throw new Error("injected commerce failure");
      },
      preparePlan: settlement.preparePlan.bind(settlement),
      assignPlan: settlement.assignPlan.bind(settlement),
      assignPreparedPlan: settlement.assignPreparedPlan.bind(settlement),
      clonePlan: settlement.clonePlan.bind(settlement),
      loadPlan: settlement.loadPlan.bind(settlement),
      markPlanState: settlement.markPlanState.bind(settlement),
      plannedSubscriptionAllocations:
        settlement.plannedSubscriptionAllocations.bind(settlement),
      resolvePlannedPlan: settlement.resolvePlannedPlan.bind(settlement),
    } satisfies LessonSettlementPort);
    const completionRepository = new LessonCompletionWorkerRepository(database);
    completionWorker = new LessonCompletionWorker(
      completionRepository,
      new LessonCompletionService(
        platform,
        completionRepository,
        settlement,
        reservations,
        lifecycle,
      ),
    );
  });

  it("atomically reverses a completed subscription lesson and completes its successor exactly once", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const paidDecision = {
      settlementTypeKey: "paid_miss",
      teacherCompensationRuleKey: "standard",
      clientDecisions: [{ clientId: fixture.studentId }],
    };
    const metadata = (label: string) => ({
      idempotencyKey: `${label}-${randomUUID()}`,
      requestId: `request-${label}-${randomUUID()}`,
    });
    const sourceLessonId = fixture.capacityId;
    try {
      await database.transaction((client) =>
        settlement.assignPlan(client, {
          lessonId: sourceLessonId,
          branchId: fixture.branchId,
          decision: paidDecision,
          selectedBy: fixture.managerId,
          reasonText: "Исходный план расчёта",
        }),
      );
      await expect(
        service.previewSettle(actor, sourceLessonId, {
          expectedVersion: 1,
          financialDecision: paidDecision,
        }),
      ).rejects.toMatchObject({
        status: 409,
        response: { code: "LESSON_SETTLEMENT_REVIEW_NOT_REQUIRED" },
      });
      await database.transaction(async (client) => {
        await settlement.markPlanState(
          client,
          sourceLessonId,
          "review_required",
          "ConflictException",
        );
        await client.query(
          "update app.lessons set lifecycle_state = 'settlement_pending' where id = $1",
          [sourceLessonId],
        );
      });
      const completionPreview = await service.previewSettle(
        actor,
        sourceLessonId,
        { expectedVersion: 2, financialDecision: paidDecision },
      );
      await service.settle(
        actor,
        sourceLessonId,
        {
          expectedVersion: 2,
          financialDecision: paidDecision,
          previewToken: completionPreview.previewToken!,
          confirm: true,
        },
        metadata("complete-before-reschedule"),
      );

      const completedEvidence = async () => {
        const result = await pool.query(
          `select source.lifecycle_state, source.version,
             (select count(*)::int from app.lessons
               where predecessor_id = source.id) as successors,
             (select count(*)::int from app.lesson_settlement_plans plan
               where plan.lesson_id = source.id
                  or plan.lesson_id in (
                    select id from app.lessons where predecessor_id = source.id
                  )) as plans,
             (select count(*)::int from app.lesson_settlement_corrections
               where lesson_id = source.id) as corrections,
             (select count(*)::int from app.lesson_transitions
               where lesson_id = source.id) as transitions,
             (select count(*)::int from app.lesson_client_charge_facts
               where lesson_id = source.id) as client_facts,
             (select count(*)::int from app.lesson_teacher_compensation_facts
               where lesson_id = source.id) as teacher_facts,
             (select state::text from app.lesson_reservations
               where lesson_id = source.id limit 1) as reservation_state,
             (select units::text from app.lesson_reservations
               where lesson_id = source.id limit 1) as reservation_units,
             (select count(*)::int from app.audit_events
               where entity_type = 'lesson'
                 and entity_id = source.id::text) as audits,
             (select count(*)::int from app.platform_outbox_events
               where aggregate_type = 'schedule:lesson'
                 and aggregate_id = source.id::text) as outbox,
             (select count(*)::int from app.idempotency_records
               where actor_key = $2) as idempotency
           from app.lessons source where source.id = $1`,
          [sourceLessonId, `user:${fixture.managerId}`],
        );
        return result.rows[0];
      };
      const beforeUnauthorized = await completedEvidence();
      const reversalRequestDecision = {
        settlementTypeKey: "paid_miss",
        clientDecisions: [{ clientId: fixture.studentId }],
      } as never;
      const forbiddenTeacherDecision = {
        settlementTypeKey: "paid_miss",
        teacherCompensationRuleKey: "fixed",
        teacherCompensationValueMinor: "70000",
        teacherCreditedDurationMinutes: 60,
        teacherCompensationSource: "manual" as const,
        clientDecisions: [{ clientId: fixture.studentId }],
      };
      const completedReschedule = {
        expectedVersion: 3,
        reasonCode: "business.error",
        reasonText: "Исправление ошибочно завершённого занятия",
        successor: { scheduledAt: "2026-08-03T08:00:00.000Z" },
      };
      await expect(
        service.previewReschedule(actor, sourceLessonId, {
          ...completedReschedule,
          financialDecision: forbiddenTeacherDecision,
        }),
      ).rejects.toMatchObject({
        status: 403,
        response: { code: "TEACHER_COMPENSATION_PERMISSION_REQUIRED" },
      });
      expect(await completedEvidence()).toEqual(beforeUnauthorized);

      const reschedulePreview = await service.previewReschedule(
        actor,
        sourceLessonId,
        {
          ...completedReschedule,
          financialDecision: reversalRequestDecision,
        },
      );
      expect(reschedulePreview).toMatchObject({
        canConfirm: true,
        sourceFinancialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
        successorFinancialDecision: {
          settlementTypeKey: "paid_miss",
          teacherCompensationRuleKey: "standard",
        },
        warnings: ["COMPLETED_LESSON_EFFECTS_WILL_BE_REVERSED"],
      });
      const rescheduleCommand = {
        ...completedReschedule,
        financialDecision: reversalRequestDecision,
        previewToken: reschedulePreview.previewToken!,
        confirm: true as const,
      };
      await expect(
        service.reschedule(
          actor,
          sourceLessonId,
          { ...rescheduleCommand, financialDecision: forbiddenTeacherDecision },
          metadata("completed-reschedule-unauthorized"),
        ),
      ).rejects.toMatchObject({
        status: 403,
        response: { code: "TEACHER_COMPENSATION_PERMISSION_REQUIRED" },
      });
      expect(await completedEvidence()).toEqual(beforeUnauthorized);
      await expect(
        failingService.reschedule(
          actor,
          sourceLessonId,
          rescheduleCommand,
          metadata("completed-reschedule-rollback"),
        ),
      ).rejects.toThrow("injected commerce failure");
      const rollbackEvidence = await pool.query<{
        lifecycle_state: string;
        version: number | string;
        successors: number;
        corrections: number;
        client_facts: number;
        teacher_facts: number;
      }>(
        `select source.lifecycle_state, source.version,
           (select count(*)::int from app.lessons
             where predecessor_id = source.id) as successors,
           (select count(*)::int from app.lesson_settlement_corrections
             where lesson_id = source.id) as corrections,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = source.id) as client_facts,
           (select count(*)::int from app.lesson_teacher_compensation_facts
             where lesson_id = source.id) as teacher_facts
         from app.lessons source where source.id = $1`,
        [sourceLessonId],
      );
      expect(rollbackEvidence.rows[0]).toEqual({
        lifecycle_state: "successfully_completed",
        version: "3",
        successors: 0,
        corrections: 0,
        client_facts: 1,
        teacher_facts: 1,
      });
      await expect(
        effectiveSubscriptionUnits(pool, fixture.subscriptionId),
      ).resolves.toBe("1.00");

      await pool.query("update app.users set role = 'director' where id = $1", [
        fixture.managerId,
      ]);
      const director = {
        userId: fixture.managerId,
        role: "director" as const,
      };
      const authorizedPreview = await service.previewReschedule(
        director,
        sourceLessonId,
        {
          ...completedReschedule,
          financialDecision: forbiddenTeacherDecision,
        },
      );
      expect(authorizedPreview).toMatchObject({
        sourceFinancialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
          teacherCompensationSource: "automatic",
        },
        successorFinancialDecision: {
          settlementTypeKey: "paid_miss",
          teacherCompensationRuleKey: "fixed",
          teacherCompensationValueMinor: "70000",
          teacherCompensationSource: "manual",
        },
      });
      const moved = await service.reschedule(
        director,
        sourceLessonId,
        {
          ...completedReschedule,
          financialDecision: forbiddenTeacherDecision,
          previewToken: authorizedPreview.previewToken!,
          confirm: true,
        },
        metadata("completed-reschedule"),
      );
      expect(moved).toMatchObject({
        sourceFinancialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
          teacherCompensationSource: "automatic",
        },
        successorFinancialDecision: {
          settlementTypeKey: "paid_miss",
          teacherCompensationRuleKey: "fixed",
          teacherCompensationValueMinor: "70000",
          teacherCompensationSource: "manual",
        },
        financialDecision: {
          settlementTypeKey: "paid_miss",
          teacherCompensationRuleKey: "fixed",
          teacherCompensationValueMinor: "70000",
          teacherCompensationSource: "manual",
        },
      });
      const successorId = moved.successor!.id;
      const state = await pool.query<{
        lifecycle_state: string;
        correction_count: number;
        transition_count: number;
        teacher_amount_minor: string;
        successor_state: string;
        successor_plan_key: string;
      }>(
        `select source.lifecycle_state,
           (select count(*)::int from app.lesson_settlement_corrections
             where lesson_id = source.id) as correction_count,
           (select count(*)::int from app.lesson_transitions
             where lesson_id = source.id) as transition_count,
           (select amount_minor::text
             from app.lesson_teacher_compensation_facts_effective
             where lesson_id = source.id) as teacher_amount_minor,
           successor.lifecycle_state as successor_state,
           plan.decision->>'settlementTypeKey' as successor_plan_key
         from app.lessons source
         join app.lessons successor on successor.id = source.successor_id
         join app.lesson_settlement_plans plan on plan.lesson_id = successor.id
         where source.id = $1`,
        [sourceLessonId],
      );
      expect(moved).toMatchObject({
        source: { state: "rescheduled", version: 4 },
        successor: { state: "scheduled", version: 1 },
      });
      expect(state.rows[0]).toEqual({
        lifecycle_state: "rescheduled",
        correction_count: 1,
        transition_count: 2,
        teacher_amount_minor: "0",
        successor_state: "scheduled",
        successor_plan_key: "paid_miss",
      });

      const clientHistory = await pool.query<{
        id: string;
        correction_id: string | null;
        supersedes_fact_id: string | null;
        units: string;
      }>(
        `select id, correction_id, supersedes_fact_id, units::text
         from app.lesson_client_charge_facts
         where lesson_id = $1
         order by (correction_id is not null), created_at, id`,
        [sourceLessonId],
      );
      const teacherHistory = await pool.query<{
        id: string;
        correction_id: string | null;
        supersedes_fact_id: string | null;
        amount_minor: string;
      }>(
        `select id, correction_id, supersedes_fact_id, amount_minor::text
         from app.lesson_teacher_compensation_facts
         where lesson_id = $1
         order by (correction_id is not null), created_at, id`,
        [sourceLessonId],
      );
      expect(clientHistory.rows).toHaveLength(2);
      expect(clientHistory.rows[0]).toMatchObject({
        correction_id: null,
        supersedes_fact_id: null,
        units: "1.00",
      });
      expect(clientHistory.rows[1]).toMatchObject({
        correction_id: expect.any(String),
        supersedes_fact_id: clientHistory.rows[0]!.id,
        units: "0.00",
      });
      expect(teacherHistory.rows).toHaveLength(2);
      expect(Number(teacherHistory.rows[0]!.amount_minor)).toBeGreaterThan(0);
      expect(teacherHistory.rows[1]).toMatchObject({
        correction_id: expect.any(String),
        supersedes_fact_id: teacherHistory.rows[0]!.id,
        amount_minor: "0",
      });

      const reservationsAfterMove = await pool.query<{
        lesson_id: string;
        state: string;
        financial_fact_id: string | null;
        financial_fact_effective: boolean;
      }>(
        `select reservation.lesson_id, reservation.state,
           reservation.financial_fact_id,
           exists (
             select 1 from app.lesson_client_charge_facts_effective fact
             where fact.id = reservation.financial_fact_id
           ) as financial_fact_effective
         from app.lesson_reservations reservation
         where reservation.lesson_id = any($1::uuid[])
         order by reservation.lesson_id = $2`,
        [[sourceLessonId, successorId], sourceLessonId],
      );
      expect(reservationsAfterMove.rows).toEqual([
        {
          lesson_id: successorId,
          state: "reserved",
          financial_fact_id: null,
          financial_fact_effective: false,
        },
        {
          lesson_id: sourceLessonId,
          state: "consumed",
          financial_fact_id: clientHistory.rows[0]!.id,
          financial_fact_effective: false,
        },
      ]);
      await expect(
        effectiveSubscriptionUnits(pool, fixture.subscriptionId),
      ).resolves.toBe("0.00");

      await expect(
        completionWorker.runOnce({
          workerId: `completed-reschedule-${randomUUID()}`,
          limit: 10,
        }),
      ).resolves.toMatchObject({ claimed: 1, completed: 1 });
      await expect(
        completionWorker.runOnce({
          workerId: `completed-reschedule-replay-${randomUUID()}`,
          limit: 10,
        }),
      ).resolves.toMatchObject({ claimed: 0, completed: 0 });

      const successorEvidence = await pool.query<{
        lifecycle_state: string;
        plan_state: string;
        work_state: string;
        attempts: number;
        transition_count: number;
        client_fact_count: number;
        teacher_fact_count: number;
        reservation_state: string;
        reservation_fact_effective: boolean;
      }>(
        `select successor.lifecycle_state, plan.state as plan_state,
           work.state as work_state, work.attempts,
           (select count(*)::int from app.lesson_transitions
             where lesson_id = successor.id) as transition_count,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = successor.id) as client_fact_count,
           (select count(*)::int from app.lesson_teacher_compensation_facts
             where lesson_id = successor.id) as teacher_fact_count,
           reservation.state as reservation_state,
           exists (
             select 1 from app.lesson_client_charge_facts_effective fact
             where fact.id = reservation.financial_fact_id
           ) as reservation_fact_effective
         from app.lessons successor
         join app.lesson_settlement_plans plan on plan.lesson_id = successor.id
         join app.lesson_completion_work work on work.lesson_id = successor.id
         join app.lesson_reservations reservation on reservation.lesson_id = successor.id
         where successor.id = $1`,
        [successorId],
      );
      expect(successorEvidence.rows[0]).toEqual({
        lifecycle_state: "successfully_completed",
        plan_state: "settled",
        work_state: "completed",
        attempts: 1,
        transition_count: 1,
        client_fact_count: 1,
        teacher_fact_count: 1,
        reservation_state: "consumed",
        reservation_fact_effective: true,
      });
      await expect(
        effectiveSubscriptionUnits(pool, fixture.subscriptionId),
      ).resolves.toBe("1.00");
    } finally {
      await cleanup(pool, fixture);
    }
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("dry-runs the exact facts and atomically commits every transition kind", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const metadata = (label: string) => ({
      idempotencyKey: `${label}-${randomUUID()}`,
      requestId: `request-${label}-${randomUUID()}`,
    });
    const freeDecision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [{ clientId: fixture.studentId }],
    };
    const paidMissDecision = {
      settlementTypeKey: "paid_miss",
      teacherCompensationRuleKey: "standard",
      clientDecisions: [{ clientId: fixture.studentId }],
    };
    try {
      const conflicting = await service.previewReschedule(
        actor,
        fixture.sourceId,
        {
          expectedVersion: 1,
          reasonCode: "client.requested",
          reasonText: "Клиент попросил другое время",
          financialDecision: freeDecision,
          successor: { scheduledAt: "2026-07-27T09:00:00.000Z" },
        },
      );
      expect(conflicting).toMatchObject({
        canConfirm: false,
        confirmRequired: true,
        violations: expect.arrayContaining([
          expect.objectContaining({ code: "TEACHER_OVERLAP" }),
          expect.objectContaining({ code: "CLIENT_OVERLAP" }),
          expect.objectContaining({ code: "ROOM_OVERLAP" }),
        ]),
      });
      expect(conflicting).not.toHaveProperty("previewToken");

      const preview = await service.previewReschedule(actor, fixture.sourceId, {
        expectedVersion: 1,
        reasonCode: "client.requested",
        reasonText: "Клиент попросил другое время",
        financialDecision: freeDecision,
        successor: { scheduledAt: "2026-07-27T11:00:00.000Z" },
      });
      expect(preview).toMatchObject({
        requestedLessonId: fixture.sourceId,
        actionableLessonId: fixture.sourceId,
        redirected: false,
        canConfirm: true,
        sourceFinancialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
        successorFinancialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
        sourceFinancialPreview: {
          clientFacts: [
            expect.objectContaining({
              settlementTypeKey: "free_lesson",
              amountMinor: "0",
              units: "0.00",
            }),
          ],
          teacherFact: expect.objectContaining({
            compensationRuleKey: "none",
            amountMinor: "0",
          }),
        },
        successorPlannedSettlementPreview: {
          financialDecision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "none",
          },
        },
      });
      expect(preview.previewToken).toBeTruthy();
      await expect(
        failingService.reschedule(
          actor,
          fixture.sourceId,
          {
            expectedVersion: 1,
            reasonCode: "client.requested",
            reasonText: "Клиент попросил другое время",
            financialDecision: freeDecision,
            successor: { scheduledAt: "2026-07-27T11:00:00.000Z" },
            previewToken: preview.previewToken!,
            confirm: true,
          },
          metadata("failure"),
        ),
      ).rejects.toThrow("injected commerce failure");
      await expectSourceUnchanged(pool, fixture.sourceId);

      const command = {
        expectedVersion: 1,
        reasonCode: "client.requested",
        reasonText: "Клиент попросил другое время",
        financialDecision: freeDecision,
        successor: { scheduledAt: "2026-07-27T11:00:00.000Z" },
        previewToken: preview.previewToken!,
        confirm: true as const,
      };
      const idempotency = metadata("reschedule-success");
      const result = await service.reschedule(
        actor,
        fixture.sourceId,
        command,
        idempotency,
      );
      expect(result).toMatchObject({
        source: { id: fixture.sourceId, state: "rescheduled", version: 2 },
        successor: { state: "scheduled", version: 1 },
        replayed: false,
      });
      const redirectedPreview = await service.previewReschedule(
        actor,
        fixture.sourceId,
        {
          expectedVersion: 1,
          reasonCode: "client.requested",
          reasonText: "Повторный перенос из исходной карточки",
          financialDecision: freeDecision,
          successor: { scheduledAt: "2026-07-27T14:00:00.000Z" },
        },
      );
      expect(redirectedPreview).toMatchObject({
        requestedLessonId: fixture.sourceId,
        actionableLessonId: result.successor!.id,
        redirected: true,
        source: { id: result.successor!.id, version: 1 },
      });
      const replay = await service.reschedule(
        actor,
        fixture.sourceId,
        command,
        idempotency,
      );
      expect(replay).toMatchObject({
        transitionId: result.transitionId,
        replayed: true,
      });

      await database.transaction((client) => settlement.assignPlan(client, {
        lessonId: fixture.cancelId,
        branchId: fixture.branchId,
        decision: {
          ...paidMissDecision,
          teacherCompensationSource: "automatic",
        },
        selectedBy: fixture.managerId,
        reasonText: "Автоматический план для проверки отмены",
      }));
      const cancelPreview = await service.previewCancel(
        actor,
        fixture.cancelId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText: "Отмена по решению школы",
          financialDecision: paidMissDecision,
        },
      );
      expect(cancelPreview).toMatchObject({
        canConfirm: true,
        financialPreview: {
          clientFacts: [
            expect.objectContaining({
              settlementTypeKey: "paid_miss",
              settlementLabel: "Оплачиваемый пропуск",
              settlementColorToken: "blue",
              hourShareBasisPoints: 10_000,
              units: "1.00",
              amountMinor: "100000",
            }),
          ],
          teacherFact: expect.objectContaining({
            compensationRuleKey: "standard",
          }),
        },
      });
      const cancelled = await service.cancel(
        actor,
        fixture.cancelId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText: "Отмена по решению школы",
          financialDecision: paidMissDecision,
          previewToken: cancelPreview.previewToken!,
          confirm: true,
        },
        metadata("cancel"),
      );
      expect(cancelled.source).toEqual({
        id: fixture.cancelId,
        state: "cancelled",
        version: 2,
      });

      const settleDecision = {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        clientDecisions: [{ clientId: fixture.studentId }],
      };
      await database.transaction(async (client) => {
        await settlement.assignPlan(client, {
          lessonId: fixture.settleId,
          branchId: fixture.branchId,
          decision: { ...settleDecision, settlementTypeKey: "free_lesson" },
          selectedBy: fixture.managerId,
          reasonText: "Автоматический расчёт требует проверки",
        });
        await settlement.markPlanState(
          client,
          fixture.settleId,
          "review_required",
          "ConflictException",
        );
        await client.query(
          "update app.lessons set lifecycle_state = 'settlement_pending' where id = $1",
          [fixture.settleId],
        );
      });
      const plannedHistory = await corrections.history(actor, fixture.settleId);
      expect(plannedHistory.items.filter((item) => item.effective)).toEqual([
        expect.objectContaining({ kind: "planned",
          settlementTypeLabel: "Бесплатное занятие",
          decision: expect.objectContaining({ settlementTypeKey: "free_lesson" }) }),
      ]);
      const beforeSettle = await pool.query<{ count: number }>(
        `
          select (
            select count(*)::int from app.lesson_client_charge_facts
            where lesson_id = $1
          ) + (
            select count(*)::int from app.lesson_teacher_compensation_facts
            where lesson_id = $1
          ) as count
        `,
        [fixture.settleId],
      );
      expect(beforeSettle.rows[0]!.count).toBe(0);
      const settlePreview = await service.previewSettle(
        actor,
        fixture.settleId,
        {
          expectedVersion: 2,
          reasonCode: "attendance.confirmed",
          financialDecision: settleDecision,
        },
      );
      const settled = await service.settle(
        actor,
        fixture.settleId,
        {
          expectedVersion: 2,
          reasonCode: "attendance.confirmed",
          financialDecision: settleDecision,
          previewToken: settlePreview.previewToken!,
          confirm: true,
        },
        metadata("settle"),
      );
      expect(settled.source).toEqual({
        id: fixture.settleId,
        state: "successfully_completed",
        version: 3,
      });

      const settledHistory = await corrections.history(actor, fixture.settleId);
      expect(settledHistory.items).toHaveLength(2);
      expect(settledHistory.items.filter((item) => item.effective)).toEqual([
        expect.objectContaining({ kind: "transition",
          settlementTypeLabel: expect.stringMatching(/[А-Яа-я]/),
          teacherCompensationRuleLabel: expect.stringMatching(/[А-Яа-я]/),
          decision: expect.objectContaining({ settlementTypeKey: "lesson" }) }),
      ]);
      expect(settledHistory.items.find((item) => item.kind === "planned"))
        .toMatchObject({ effective: false, settlementTypeLabel: "Бесплатное занятие" });
      // New catalog labels must not change the meaning of old history entries.
      await pool.query(
        `insert into app.crm_configuration_revisions
           (branch_id, version, patch, effective_snapshot, reason)
         select $1, 1,
           jsonb_build_object('lessonSettlementTypes', '[{"stableKey":"lesson","label":"Новое название"}]'::jsonb),
           jsonb_set(effective_snapshot, '{lessonSettlementTypes}',
             '[{"stableKey":"lesson","label":"Новое название"}]'::jsonb),
           'History label regression'
         from app.crm_configuration_revisions where branch_id is null
         order by version desc limit 1`, [fixture.branchId],
      );
      expect((await corrections.history(actor, fixture.settleId)).items)
        .toEqual(settledHistory.items);

      const persisted = await pool.query<{
        transitions: number;
        client_facts: number;
        teacher_facts: number;
        successors: number;
        reason_text: string;
        settlement_plan_state: string;
        settlement_failure_code: string | null;
      }>(
        `
          select
            (select count(*)::int from app.lesson_transitions
              where lesson_id = any($1::uuid[])) as transitions,
            (select count(*)::int from app.lesson_client_charge_facts
              where lesson_id = any($1::uuid[])) as client_facts,
            (select count(*)::int from app.lesson_teacher_compensation_facts
              where lesson_id = any($1::uuid[])) as teacher_facts,
            (select count(*)::int from app.lessons
              where predecessor_id = $2) as successors,
            (select reason_text from app.lesson_transitions
              where lesson_id = $2) as reason_text,
            (select state from app.lesson_settlement_plans
              where lesson_id = $3) as settlement_plan_state,
            (select failure_code from app.lesson_settlement_plans
              where lesson_id = $3) as settlement_failure_code
        `,
        [
          [fixture.sourceId, fixture.cancelId, fixture.settleId],
          fixture.sourceId,
          fixture.settleId,
        ],
      );
      expect(persisted.rows[0]).toEqual({
        transitions: 3,
        client_facts: 3,
        teacher_facts: 3,
        successors: 1,
        reason_text: "Клиент попросил другое время",
        settlement_plan_state: "settled",
        settlement_failure_code: null,
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("resolves transition teacher provenance before preview and commit", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const manager = { userId: fixture.managerId, role: "manager" as const };
    const director = { userId: fixture.managerId, role: "director" as const };
    const metadata = (label: string) => ({
      idempotencyKey: `${label}-${randomUUID()}`,
      requestId: `request-${label}-${randomUUID()}`,
    });
    const manuallySourced = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "fixed",
      teacherCompensationValueMinor: "70000",
      teacherCompensationSource: "manual" as const,
      clientDecisions: [{ clientId: fixture.studentId }],
    };
    try {
      await expect(
        service.previewCancel(manager, fixture.cancelId, {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText: "Ручная оплата запрещена менеджеру",
          financialDecision: manuallySourced,
        }),
      ).rejects.toMatchObject({
        status: 403,
        response: { code: "TEACHER_COMPENSATION_PERMISSION_REQUIRED" },
      });
      await expect(transitionCounts(pool, fixture.cancelId)).resolves.toEqual({
        lifecycle_state: "scheduled",
        version: 1,
        successors: 0,
        transitions: 0,
        client_facts: 0,
        teacher_facts: 0,
      });

      const legacyManual = {
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "fixed",
        teacherCompensationValueMinor: "70000",
        clientDecisions: [{ clientId: fixture.studentId }],
      };
      await pool.query("update app.users set role = 'director' where id = $1", [
        fixture.managerId,
      ]);
      const manualPreview = await service.previewCancel(
        director,
        fixture.cancelId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText: "Та же сумма выбрана вручную директором",
          financialDecision: legacyManual,
        },
      );
      expect(manualPreview.financialDecision).toMatchObject({
        teacherCompensationRuleKey: "fixed",
        teacherCompensationValueMinor: "70000",
        teacherCompensationSource: "manual",
      });
      const manualCommit = await service.cancel(
        director,
        fixture.cancelId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText: "Та же сумма выбрана вручную директором",
          financialDecision: legacyManual,
          previewToken: manualPreview.previewToken!,
          confirm: true,
        },
        metadata("manual-provenance"),
      );
      expect(manualCommit.financialDecision).toEqual(
        manualPreview.financialDecision,
      );
      await expect(
        pool.query<{ compensation_source: string }>(
          `select compensation_source
           from app.lesson_teacher_compensation_facts_effective
           where lesson_id = $1`,
          [fixture.cancelId],
        ),
      ).resolves.toMatchObject({ rows: [{ compensation_source: "manual" }] });

      await pool.query("update app.users set role = 'manager' where id = $1", [
        fixture.managerId,
      ]);

      const legacyAutomatic = {
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "none",
        clientDecisions: [{ clientId: fixture.studentId }],
      };
      await database.transaction((client) => settlement.assignPlan(client, {
        lessonId: fixture.sourceId,
        branchId: fixture.branchId,
        decision: {
          ...legacyAutomatic,
          teacherCompensationSource: "automatic",
        },
        selectedBy: fixture.managerId,
        reasonText: "Автоматический план для проверки provenance",
      }));
      const automaticPreview = await service.previewCancel(
        manager,
        fixture.sourceId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText: "Старый автоматический payload",
          financialDecision: legacyAutomatic,
        },
      );
      expect(automaticPreview.financialDecision).toMatchObject({
        teacherCompensationSource: "automatic",
      });
      const automaticCommit = await service.cancel(
        manager,
        fixture.sourceId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText: "Старый автоматический payload",
          financialDecision: legacyAutomatic,
          previewToken: automaticPreview.previewToken!,
          confirm: true,
        },
        metadata("automatic-provenance"),
      );
      expect(automaticCommit.financialDecision).toEqual(
        automaticPreview.financialDecision,
      );
      await expect(
        pool.query<{ compensation_source: string }>(
          `select compensation_source
           from app.lesson_teacher_compensation_facts_effective
           where lesson_id = $1`,
          [fixture.sourceId],
        ),
      ).resolves.toMatchObject({
        rows: [{ compensation_source: "automatic" }],
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("plans a partial personal-account successor from its new teacher date and replays once", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "director" as const };
    const successorDecision = {
      settlementTypeKey: "partially_paid_lesson",
      clientDecisions: [{
        clientId: fixture.studentId,
        chargeType: "personal_account" as const,
        basePriceMinor: "180000",
        chargeDurationMinutes: 30,
      }],
      teacherCompensationRuleKey: "standard",
      teacherCreditedDurationMinutes: 45,
    };
    try {
      await pool.query("update app.users set role = 'director' where id = $1", [
        fixture.managerId,
      ]);
      await pool.query(
        `insert into app.teacher_rates (teacher_id, rate, effective_from) values
           ($1, 700, '2026-01-01'),
           ($2, 900, '2026-01-01'),
           ($2, 1200, '2026-08-01')`,
        [fixture.teacherId, fixture.replacementTeacherId],
      );
      const draft = {
        scheduledAt: "2026-08-03T08:00:00.000Z",
        teacherId: fixture.replacementTeacherId,
        roomId: fixture.replacementRoomId,
      };
      const preview = await service.previewReschedule(
        actor,
        fixture.cancelId,
        {
          expectedVersion: 1,
          reasonCode: "client.requested",
          reasonText: "Частичный перенос на нового преподавателя",
          successor: draft,
          successorFinancialDecision: successorDecision,
        },
      );

      expect(preview).toMatchObject({
        canConfirm: true,
        sourceFinancialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
        successorFinancialDecision: {
          ...successorDecision,
          teacherCompensationRuleKey: "percent",
          teacherRateSnapshot: { type: "hourly", value: "1200" },
          teacherCompensationSource: "manual",
        },
      });

      const command = {
        expectedVersion: 1,
        reasonCode: "client.requested",
        reasonText: "Частичный перенос на нового преподавателя",
        successor: draft,
        successorFinancialDecision: successorDecision,
        previewToken: preview.previewToken!,
        confirm: true as const,
      };
      const metadata = {
        idempotencyKey: `partial-personal-move-${randomUUID()}`,
        requestId: `partial-personal-request-${randomUUID()}`,
      };
      const moved = await service.reschedule(
        actor,
        fixture.cancelId,
        command,
        metadata,
      );
      const replay = await service.reschedule(
        actor,
        fixture.cancelId,
        command,
        metadata,
      );
      expect(replay).toMatchObject({
        successor: { id: moved.successor!.id },
        transitionId: moved.transitionId,
        replayed: true,
      });

      const persisted = await pool.query<{
        source_client_amount: string;
        source_client_share: number;
        source_teacher_amount: string;
        source_teacher_type: string;
        successor_teacher_id: string;
        successor_teacher_rate: string;
        successor_snapshot_rate: string;
        successor_decision: typeof successorDecision & {
          teacherRateSnapshot: { type: string; value: string };
          teacherCompensationSource: string;
        };
        successor_plan_revisions: number;
        successor_client_facts: number;
        successor_teacher_facts: number;
      }>(
        `select
           source_client.amount_minor::text as source_client_amount,
           source_client.hour_share_basis_points as source_client_share,
           source_teacher.amount_minor::text as source_teacher_amount,
           source_teacher.compensation_type as source_teacher_type,
           successor.teacher_id as successor_teacher_id,
           successor.teacher_rate::text as successor_teacher_rate,
           successor_snapshot.teacher_compensation_value::text as successor_snapshot_rate,
           successor_plan.decision as successor_decision,
           (select count(*)::int from app.lesson_settlement_plan_revisions
             where lesson_id = successor.id) as successor_plan_revisions,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = successor.id) as successor_client_facts,
           (select count(*)::int from app.lesson_teacher_compensation_facts
             where lesson_id = successor.id) as successor_teacher_facts
         from app.lessons source
         join app.lessons successor on successor.id = source.successor_id
         join app.lesson_client_charge_facts_effective source_client
           on source_client.lesson_id = source.id
         join app.lesson_teacher_compensation_facts_effective source_teacher
           on source_teacher.lesson_id = source.id
         join app.lesson_snapshots successor_snapshot
           on successor_snapshot.lesson_id = successor.id
         join app.lesson_settlement_plans successor_plan
           on successor_plan.lesson_id = successor.id
         where source.id = $1`,
        [fixture.cancelId],
      );
      expect(persisted.rows[0]).toEqual({
        source_client_amount: "0",
        source_client_share: 0,
        source_teacher_amount: "0",
        source_teacher_type: "none",
        successor_teacher_id: fixture.replacementTeacherId,
        successor_teacher_rate: "1200.00",
        successor_snapshot_rate: "1200.00",
        successor_decision: expect.objectContaining({
          ...successorDecision,
          teacherCompensationRuleKey: "percent",
          teacherRateSnapshot: { type: "hourly", value: "1200" },
          teacherCompensationSource: "manual",
        }),
        successor_plan_revisions: 1,
        successor_client_facts: 0,
        successor_teacher_facts: 0,
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("moves the active subscription reservation to the successor exactly once", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const successorDecision = {
      settlementTypeKey: "lesson",
      teacherCompensationRuleKey: "standard",
      clientDecisions: [{
        clientId: fixture.studentId,
        chargeType: "subscription" as const,
        subscriptionId: fixture.subscriptionId,
      }],
    };
    try {
      const before = await pool.query<{ id: string }>(
        `select id from app.lesson_reservations
         where lesson_id = $1 and state = 'reserved'`,
        [fixture.capacityId],
      );
      const preview = await service.previewReschedule(
        actor,
        fixture.capacityId,
        {
          expectedVersion: 1,
          reasonCode: "client.requested",
          reasonText: "Перенос брони абонемента",
          successor: { scheduledAt: "2026-08-03T08:00:00.000Z" },
          successorFinancialDecision: successorDecision,
        },
      );
      const command = {
        expectedVersion: 1,
        reasonCode: "client.requested",
        reasonText: "Перенос брони абонемента",
        successor: { scheduledAt: "2026-08-03T08:00:00.000Z" },
        successorFinancialDecision: successorDecision,
        previewToken: preview.previewToken!,
        confirm: true as const,
      };
      const metadata = {
        idempotencyKey: `subscription-move-${randomUUID()}`,
        requestId: `subscription-move-request-${randomUUID()}`,
      };
      const moved = await service.reschedule(
        actor,
        fixture.capacityId,
        command,
        metadata,
      );
      const replay = await service.reschedule(
        actor,
        fixture.capacityId,
        command,
        metadata,
      );

      const reservations = await pool.query<{
        id: string;
        lesson_id: string;
        state: string;
        units: string;
      }>(
        `select id, lesson_id, state, units::text
         from app.lesson_reservations
         where lesson_id = any($1::uuid[])
         order by id`,
        [[fixture.capacityId, moved.successor!.id]],
      );
      expect(reservations.rows).toEqual([{
        id: before.rows[0]!.id,
        lesson_id: moved.successor!.id,
        state: "reserved",
        units: "1.00",
      }]);
      expect(replay).toMatchObject({
        successor: { id: moved.successor!.id },
        replayed: true,
      });
      const integrity = await pool.query<{
        source_state: string;
        source_version: string;
        source_successor_id: string;
        successor_version: string;
        successor_predecessor_id: string;
        transitions: number;
        plan_revisions: number;
        audits: number;
        outbox: number;
        outbox_successor_id: string;
        idempotency: number;
      }>(
        `select
           source.lifecycle_state as source_state,
           source.version::text as source_version,
           source.successor_id as source_successor_id,
           successor.version::text as successor_version,
           successor.predecessor_id as successor_predecessor_id,
           (select count(*)::int from app.lesson_transitions
             where lesson_id = source.id) as transitions,
           (select count(*)::int from app.lesson_settlement_plan_revisions
             where lesson_id = successor.id) as plan_revisions,
           (select count(*)::int from app.audit_events
             where request_id = $2) as audits,
           (select count(*)::int from app.platform_outbox_events
             where request_id = $2) as outbox,
           (select payload->>'successorId' from app.platform_outbox_events
             where request_id = $2 limit 1) as outbox_successor_id,
           (select count(*)::int from app.idempotency_records
             where actor_key = $3 and operation = 'schedule.lesson.reschedule'
               and idempotency_key = $4) as idempotency
         from app.lessons source
         join app.lessons successor on successor.id = source.successor_id
         where source.id = $1`,
        [
          fixture.capacityId,
          metadata.requestId,
          `user:${fixture.managerId}`,
          metadata.idempotencyKey,
        ],
      );
      expect(integrity.rows[0]).toEqual({
        source_state: "rescheduled",
        source_version: "2",
        source_successor_id: moved.successor!.id,
        successor_version: "1",
        successor_predecessor_id: fixture.capacityId,
        transitions: 1,
        plan_revisions: 1,
        audits: 1,
        outbox: 1,
        outbox_successor_id: moved.successor!.id,
        idempotency: 1,
      });
      await expect(
        effectiveSubscriptionUnits(pool, fixture.subscriptionId),
      ).resolves.toBe("0.00");
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("cancels every automatic catalog policy with exact financial and reservation history", async () => {
    const lifecycle = new LessonLifecycleRepository(database);
    const fixture = await createFixture(pool, lifecycle);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const cases = [
      {
        key: "free_lesson",
        label: "Бесплатное занятие",
        color: "warning",
        share: 0,
        units: "0.00",
        reservationState: "released",
        reservationUnits: "1.00",
        availableUnits: "1.00",
        teacherRule: "none",
        teacherAmount: "0",
      },
      {
        key: "paid_miss",
        label: "Оплачиваемый пропуск",
        color: "blue",
        share: 10_000,
        units: "1.00",
        reservationState: "consumed",
        reservationUnits: "1.00",
        availableUnits: "0.00",
        teacherRule: "standard",
        teacherAmount: "70000",
      },
      {
        key: "unpaid_miss",
        label: "Неоплачиваемый пропуск",
        color: "neutral",
        share: 0,
        units: "0.00",
        reservationState: "released",
        reservationUnits: "1.00",
        availableUnits: "1.00",
        teacherRule: "none",
        teacherAmount: "0",
      },
    ] as const;
    try {
      for (const [index, item] of cases.entries()) {
        const subscription = await pool.query<{ id: string }>(
          `insert into app.subscriptions (
             student_id, lessons_total, lessons_used, status
           ) values ($1, 1, 0, 'active') returning id`,
          [fixture.studentId],
        );
        const subscriptionId = subscription.rows[0]!.id;
        const lesson = await pool.query<{ id: string }>(
          `insert into app.lessons (
             student_id, teacher_id, branch_id, room_id, scheduled_at,
             duration_minutes, created_by
           ) values ($1, $2, $3, $4, $5::timestamptz, 60, $6) returning id`,
          [
            fixture.studentId,
            fixture.teacherId,
            fixture.branchId,
            fixture.roomId,
            `2026-08-${String(10 + index).padStart(2, "0")}T07:00:00Z`,
            fixture.managerId,
          ],
        );
        const lessonId = lesson.rows[0]!.id;
        await database.transaction(async (client) => {
          await lifecycle.createSnapshot(client, {
            lessonId,
            clientType: "student",
            clientId: fixture.studentId,
            completionType: "standard.success",
            clientChargeType: "subscription",
            clientChargeValue: 1,
            teacherCompensationType: "fixed",
            teacherCompensationValue: 700,
            subscriptionId,
            trial: false,
          });
          await lifecycle.createReservation(client, {
            lessonId,
            subscriptionId,
            units: 1,
          });
        });

        if (index === 0) {
          for (const forbiddenKey of ["lesson"]) {
            await expect(
              service.previewCancel(actor, lessonId, {
                expectedVersion: 1,
                reasonCode: "school.cancelled",
                reasonText: "Проверка недоступного типа отмены",
                financialDecision: {
                  settlementTypeKey: forbiddenKey,
                  teacherCompensationRuleKey: "standard",
                  clientDecisions: [{
                    clientId: fixture.studentId,
                    chargeDurationMinutes: 60,
                  }],
                },
              }),
            ).rejects.toMatchObject({
              status: 422,
              response: { code: "SETTLEMENT_TYPE_NOT_ALLOWED" },
            });
          }
        }

        const financialDecision = {
          settlementTypeKey: item.key,
          teacherCompensationRuleKey: item.teacherRule,
          clientDecisions: [{
            clientId: fixture.studentId,
          }],
        };
        await database.transaction((client) => settlement.assignPlan(client, {
          lessonId,
          branchId: fixture.branchId,
          decision: {
            ...financialDecision,
            teacherCompensationSource: "automatic",
          },
          selectedBy: fixture.managerId,
          reasonText: `Автоматический план: ${item.label}`,
        }));
        const reasonText = `Отмена: ${item.label}`;
        const preview = await service.previewCancel(actor, lessonId, {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText,
          financialDecision,
        });
        expect(preview).toMatchObject({
          canConfirm: true,
          confirmRequired: true,
          source: { id: lessonId, state: "scheduled", version: 1 },
          financialPreview: {
            clientFacts: [
              expect.objectContaining({
                settlementTypeKey: item.key,
                settlementLabel: item.label,
                settlementColorToken: item.color,
                hourShareBasisPoints: item.share,
                units: item.units,
                amountMinor: "0",
                configurationRevisionId: expect.any(String),
              }),
            ],
            teacherFact: expect.objectContaining({
              compensationRuleKey: item.teacherRule,
              amountMinor: item.teacherAmount,
              configurationRevisionId: expect.any(String),
            }),
          },
        });
        expect(preview.previewToken).toEqual(expect.any(String));

        const command = {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText,
          financialDecision,
          previewToken: preview.previewToken!,
          confirm: true as const,
        };
        const commandMetadata = {
          idempotencyKey: `cancel-${item.key}-${randomUUID()}`,
          requestId: `request-cancel-${item.key}-${randomUUID()}`,
        };
        const cancelled = await service.cancel(
          actor,
          lessonId,
          command,
          commandMetadata,
        );
        const replay = await service.cancel(
          actor,
          lessonId,
          command,
          commandMetadata,
        );
        expect(cancelled).toMatchObject({
          source: { id: lessonId, state: "cancelled", version: 2 },
          financialDecision: expect.objectContaining({
            settlementTypeKey: item.key,
            teacherCompensationRuleKey: item.teacherRule,
          }),
          replayed: false,
        });
        expect(replay).toMatchObject({
          transitionId: cancelled.transitionId,
          clientFinancialFactIds: cancelled.clientFinancialFactIds,
          teacherFinancialFactId: cancelled.teacherFinancialFactId,
          replayed: true,
        });

        const persisted = await pool.query<{
          lifecycle_state: string;
          version: string;
          reservation_state: string;
          reservation_units: string;
          available_units: string;
          settlement_type_key: string;
          settlement_label: string;
          settlement_color_token: string;
          hour_share_basis_points: number;
          fact_units: string;
          amount_minor: string;
          client_revision_id: string | null;
          teacher_amount_minor: string;
          teacher_revision_id: string | null;
          reason_code: string;
          reason_text: string;
          decision_key: string;
          transition_count: number;
          client_fact_count: number;
          teacher_fact_count: number;
          audit_count: number;
          outbox_count: number;
          idempotency_count: number;
        }>(
          `select lesson.lifecycle_state::text, lesson.version,
                  reservation.state::text as reservation_state,
                  reservation.units::text as reservation_units,
                  (
                    subscription.lessons_total - subscription.lessons_used
                    - coalesce((
                      select sum(fact.units)
                      from app.lesson_client_charge_facts_effective fact
                      where fact.subscription_id = subscription.id
                        and fact.charge_type = 'subscription'
                    ), 0)
                    - coalesce((
                      select sum(active.units)
                      from app.lesson_reservations active
                      where active.subscription_id = subscription.id
                        and active.state = 'reserved'
                    ), 0)
                  )::text as available_units,
                  client_fact.settlement_type_key,
                  client_fact.settlement_label,
                  client_fact.settlement_color_token,
                  client_fact.hour_share_basis_points,
                  client_fact.units::text as fact_units,
                  client_fact.amount_minor::text,
                  client_fact.configuration_revision_id::text as client_revision_id,
                  teacher_fact.amount_minor::text as teacher_amount_minor,
                  teacher_fact.configuration_revision_id::text as teacher_revision_id,
                  transition.reason_code,
                  transition.reason_text,
                  transition.financial_decision->>'settlementTypeKey' as decision_key,
                  (select count(*)::int from app.lesson_transitions
                    where lesson_id = lesson.id) as transition_count,
                  (select count(*)::int from app.lesson_client_charge_facts
                    where lesson_id = lesson.id) as client_fact_count,
                  (select count(*)::int from app.lesson_teacher_compensation_facts
                    where lesson_id = lesson.id) as teacher_fact_count,
                  (select count(*)::int from app.audit_events
                    where entity_type = 'lesson' and entity_id = lesson.id::text
                      and action = 'crm.lesson_cancelled') as audit_count,
                  (select count(*)::int from app.platform_outbox_events
                    where aggregate_type = 'schedule:lesson'
                      and aggregate_id = lesson.id::text) as outbox_count,
                  (select count(*)::int from app.idempotency_records
                    where actor_key = $3 and idempotency_key = $4) as idempotency_count
             from app.lessons lesson
             join app.lesson_reservations reservation on reservation.lesson_id = lesson.id
             join app.subscriptions subscription on subscription.id = reservation.subscription_id
             join app.lesson_client_charge_facts client_fact on client_fact.lesson_id = lesson.id
             join app.lesson_teacher_compensation_facts teacher_fact on teacher_fact.lesson_id = lesson.id
             join app.lesson_transitions transition on transition.lesson_id = lesson.id
            where lesson.id = $1 and subscription.id = $2`,
          [
            lessonId,
            subscriptionId,
            `user:${fixture.managerId}`,
            commandMetadata.idempotencyKey,
          ],
        );
        expect(persisted.rows[0]).toMatchObject({
          lifecycle_state: "cancelled",
          version: "2",
          reservation_state: item.reservationState,
          reservation_units: item.reservationUnits,
          available_units: item.availableUnits,
          settlement_type_key: item.key,
          settlement_label: item.label,
          settlement_color_token: item.color,
          hour_share_basis_points: item.share,
          fact_units: item.units,
          amount_minor: "0",
          client_revision_id: expect.any(String),
          teacher_amount_minor: item.teacherAmount,
          teacher_revision_id: expect.any(String),
          reason_code: "school.cancelled",
          reason_text: reasonText,
          decision_key: item.key,
          transition_count: 1,
          client_fact_count: 1,
          teacher_fact_count: 1,
          audit_count: 1,
          outbox_count: 1,
          idempotency_count: 1,
        });
      }
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("substitutes an allowed teacher and room only after a conflict-free signed preview", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const financialDecision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [{ clientId: fixture.studentId }],
    };
    const successor = {
      teacherId: fixture.replacementTeacherId,
      branchId: fixture.branchId,
      roomId: fixture.replacementRoomId,
      scheduledAt: "2026-07-27T12:00:00.000Z",
    };
    try {
      const blocked = await service.previewReschedule(actor, fixture.sourceId, {
        expectedVersion: 1,
        reasonCode: "school.substitution",
        reasonText: "Проверка занятой подмены",
        financialDecision,
        successor,
      });
      expect(blocked).toMatchObject({
        canConfirm: false,
        violations: expect.arrayContaining([
          expect.objectContaining({ code: "TEACHER_OVERLAP" }),
          expect.objectContaining({ code: "ROOM_OVERLAP" }),
        ]),
      });
      expect(blocked).not.toHaveProperty("previewToken");

      const availableSuccessor = {
        ...successor,
        scheduledAt: "2026-07-27T11:00:00.000Z",
      };
      const preview = await service.previewReschedule(actor, fixture.sourceId, {
        expectedVersion: 1,
        reasonCode: "school.substitution",
        reasonText: "Согласованная подмена",
        financialDecision,
        successor: availableSuccessor,
      });
      expect(preview).toMatchObject({ canConfirm: true, violations: [] });
      expect(preview.previewToken).toBeTruthy();

      const command = {
        expectedVersion: 1,
        reasonCode: "school.substitution",
        reasonText: "Согласованная подмена",
        financialDecision,
        successor: availableSuccessor,
        previewToken: preview.previewToken!,
        confirm: true as const,
      };
      const metadata = {
        idempotencyKey: `replacement-${randomUUID()}`,
        requestId: `request-replacement-${randomUUID()}`,
      };
      const moved = await service.reschedule(
        actor,
        fixture.sourceId,
        command,
        metadata,
      );
      const replay = await service.reschedule(
        actor,
        fixture.sourceId,
        command,
        metadata,
      );
      expect(replay).toMatchObject({
        transitionId: moved.transitionId,
        replayed: true,
      });

      const persisted = await pool.query<{
        source_state: string;
        teacher_id: string;
        branch_id: string;
        room_id: string;
        transition_count: number;
      }>(
        `select source.lifecycle_state::text as source_state,
                successor.teacher_id,
                successor.branch_id,
                successor.room_id,
                (select count(*)::int from app.lesson_transitions
                 where lesson_id = source.id) as transition_count
           from app.lessons source
           join app.lessons successor on successor.id = source.successor_id
          where source.id = $1`,
        [fixture.sourceId],
      );
      expect(persisted.rows[0]).toEqual({
        source_state: "rescheduled",
        teacher_id: fixture.replacementTeacherId,
        branch_id: fixture.branchId,
        room_id: fixture.replacementRoomId,
        transition_count: 1,
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("reschedules a frozen group through the same signed form contract", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const decision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [fixture.studentId, fixture.secondStudentId]
        .map((clientId) => ({ clientId })),
    };
    const previewDto = {
      expectedVersion: 1,
      reasonCode: "client.requested",
      reasonText: "Участники попросили перенести групповое занятие",
      financialDecision: decision,
      successor: { scheduledAt: "2026-08-03T09:00:00.000Z" },
    };
    try {
      const preview = await service.previewReschedule(
        actor,
        fixture.groupSourceId,
        previewDto,
      );
      expect(preview).toMatchObject({
        canConfirm: true,
        source: { state: "scheduled" },
        sourceFinancialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
        successorFinancialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
        successor: {
          subject: { type: "group", id: fixture.groupId },
          startAt: "2026-08-03T09:00:00.000Z",
        },
        sourceFinancialPreview: {
          clientFacts: expect.arrayContaining([
            expect.objectContaining({
              clientId: fixture.studentId,
              settlementTypeKey: "free_lesson",
              amountMinor: "0",
              units: "0.00",
            }),
            expect.objectContaining({
              clientId: fixture.secondStudentId,
              settlementTypeKey: "free_lesson",
              amountMinor: "0",
              units: "0.00",
            }),
          ]),
          teacherFact: expect.objectContaining({
            compensationRuleKey: "none",
            amountMinor: "0",
          }),
        },
        successorPlannedSettlementPreview: {
          financialDecision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "none",
          },
        },
      });
      const command = {
        ...previewDto,
        previewToken: preview.previewToken!,
        confirm: true as const,
      };
      const metadata = {
        idempotencyKey: `group-reschedule-${randomUUID()}`,
        requestId: `group-reschedule-${randomUUID()}`,
      };
      const moved = await service.reschedule(
        actor,
        fixture.groupSourceId,
        command,
        metadata,
      );
      expect(moved).toMatchObject({
        source: { state: "rescheduled", version: 2 },
        successor: { state: "scheduled", version: 1 },
        clientFinancialFactIds: [expect.any(String), expect.any(String)],
        teacherFinancialFactId: expect.any(String),
        replayed: false,
      });
      await expect(
        service.reschedule(actor, fixture.groupSourceId, command, metadata),
      ).resolves.toMatchObject({
        transitionId: moved.transitionId,
        replayed: true,
      });

      const persisted = await pool.query<{
        source_state: string;
        source_version: number;
        successor_state: string;
        successor_group_id: string;
        successor_scheduled_at: Date | string;
        successor_participants: number;
        source_client_facts: number;
        source_teacher_facts: number;
        transitions: number;
        successor_plan_state: string;
        reason_text: string;
      }>(
        `select
           source.lifecycle_state as source_state,
           source.version::int as source_version,
           successor.lifecycle_state as successor_state,
           successor.group_id as successor_group_id,
           successor.scheduled_at as successor_scheduled_at,
           (select count(*)::int from app.lesson_snapshot_participants
             where lesson_id = successor.id) as successor_participants,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = source.id) as source_client_facts,
           (select count(*)::int from app.lesson_teacher_compensation_facts
             where lesson_id = source.id) as source_teacher_facts,
           (select count(*)::int from app.lesson_transitions
             where lesson_id = source.id) as transitions,
           plan.state as successor_plan_state,
           transition.reason_text
         from app.lessons source
         join app.lessons successor on successor.predecessor_id = source.id
         join app.lesson_settlement_plans plan on plan.lesson_id = successor.id
         join app.lesson_transitions transition on transition.lesson_id = source.id
         where source.id = $1`,
        [fixture.groupSourceId],
      );
      expect(persisted.rows[0]).toMatchObject({
        source_state: "rescheduled",
        source_version: 2,
        successor_state: "scheduled",
        successor_group_id: fixture.groupId,
        successor_participants: 2,
        source_client_facts: 2,
        source_teacher_facts: 1,
        transitions: 1,
        successor_plan_state: "planned",
        reason_text: "Участники попросили перенести групповое занятие",
      });
      expect(
        new Date(persisted.rows[0]!.successor_scheduled_at).toISOString(),
      ).toBe("2026-08-03T09:00:00.000Z");
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("rejects inexact frozen-group rows before durable writes and honors exclusions", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const exactDecision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [{ clientId: fixture.studentId }],
    };
    try {
      await pool.query(
        `insert into app.lesson_participant_exclusions (
           lesson_id, student_id, reason_code, actor_user_id
         ) values ($1, $2, 'test.exact-transition', $3)`,
        [fixture.groupSourceId, fixture.secondStudentId, fixture.managerId],
      );
      const previewDto = {
        expectedVersion: 1,
        reasonCode: "school.cancelled",
        reasonText: "Проверка точного списка участников",
        financialDecision: exactDecision,
      };
      const validPreview = await service.previewCancel(
        actor,
        fixture.groupSourceId,
        previewDto,
      );
      expect(validPreview.financialPreview).toMatchObject({
        clientFacts: [expect.objectContaining({ clientId: fixture.studentId })],
      });

      const invalidCases = [
        {
          code: "CLIENT_DECISION_MISSING",
          clientDecisions: [],
        },
        {
          code: "DUPLICATE_CLIENT_DECISION",
          clientDecisions: [
            { clientId: fixture.studentId },
            { clientId: fixture.studentId },
          ],
        },
        {
          code: "UNKNOWN_LESSON_CLIENT",
          clientDecisions: [
            { clientId: fixture.studentId },
            { clientId: fixture.secondStudentId },
          ],
        },
      ];
      const idempotencyKeys: string[] = [];
      for (const invalid of invalidCases) {
        const financialDecision = {
          ...exactDecision,
          clientDecisions: invalid.clientDecisions,
        };
        await expect(service.previewCancel(actor, fixture.groupSourceId, {
          ...previewDto,
          financialDecision,
        })).rejects.toMatchObject({
          status: 422,
          response: { code: invalid.code },
        });
        const idempotencyKey = `exact-group-${invalid.code}-${randomUUID()}`;
        idempotencyKeys.push(idempotencyKey);
        await expect(service.cancel(actor, fixture.groupSourceId, {
          ...previewDto,
          financialDecision,
          previewToken: validPreview.previewToken!,
          confirm: true,
        }, {
          idempotencyKey,
          requestId: `request-${idempotencyKey}`,
        })).rejects.toMatchObject({
          status: 422,
          response: { code: invalid.code },
        });
      }

      expect(await transitionCounts(pool, fixture.groupSourceId)).toEqual({
        lifecycle_state: "scheduled",
        version: 1,
        successors: 0,
        transitions: 0,
        client_facts: 0,
        teacher_facts: 0,
      });
      const writes = await pool.query<{
        audits: number;
        outbox: number;
        idempotency: number;
      }>(
        `select
           (select count(*)::int from app.audit_events
             where entity_id = $1) as audits,
           (select count(*)::int from app.platform_outbox_events
             where aggregate_id = $1) as outbox,
           (select count(*)::int from app.idempotency_records
             where idempotency_key = any($2::text[])) as idempotency`,
        [fixture.groupSourceId, idempotencyKeys],
      );
      expect(writes.rows[0]).toEqual({ audits: 0, outbox: 0, idempotency: 0 });

      await expect(service.cancel(actor, fixture.groupSourceId, {
        ...previewDto,
        previewToken: validPreview.previewToken!,
        confirm: true,
      }, {
        idempotencyKey: `exact-group-valid-${randomUUID()}`,
        requestId: `exact-group-valid-${randomUUID()}`,
      })).resolves.toMatchObject({
        source: { state: "cancelled", version: 2 },
        clientFinancialFactIds: [expect.any(String)],
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("serializes partial group archive and transition commits in both lock orders", async () => {
    const lifecycle = new LessonLifecycleRepository(database);
    const run = async (first: "archive" | "transition") => {
      const fixture = await createFixture(pool, lifecycle);
      const actor = { userId: fixture.managerId, role: "director" as const };
      const staleDecision = {
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "none",
        clientDecisions: [fixture.studentId, fixture.secondStudentId]
          .map((clientId) => ({ clientId })),
      };
      const previewDto = {
        expectedVersion: 1,
        reasonCode: "school.cancelled",
        reasonText: "Конкурентная проверка архива и перехода",
        financialDecision: staleDecision,
      };
      const archiveDto = {
        type: "student" as const,
        id: fixture.secondStudentId,
        expectedVersion: 1,
        reason: `test.transition-race.${first}`,
        confirm: true as const,
      };
      const blocker = await pool.connect();
      let archivePromise: Promise<unknown> | undefined;
      let transitionPromise: Promise<unknown> | undefined;
      try {
        await pool.query("update app.users set role = 'director' where id = $1", [
          fixture.managerId,
        ]);
        const scheduled = await pool.query<{ version: number | string }>(
          "update app.lessons set scheduled_at = now() + interval '1 day' where id = $1 returning version",
          [fixture.groupSourceId],
        );
        previewDto.expectedVersion = Number(scheduled.rows[0]!.version);
        const signedPreview = await service.previewCancel(
          actor,
          fixture.groupSourceId,
          previewDto,
        );
        const transition = () => service.cancel(actor, fixture.groupSourceId, {
          ...previewDto,
          previewToken: signedPreview.previewToken!,
          confirm: true,
        }, {
          idempotencyKey: `transition-race-${first}-${randomUUID()}`,
          requestId: `transition-race-${first}-${randomUUID()}`,
        });
        await blocker.query("begin");
        if (first === "archive") {
          await blocker.query(
            "select id from app.students where id = $1 for update",
            [fixture.secondStudentId],
          );
          archivePromise = archives.archive(actor, archiveDto);
          const archivePid = await waitForBlockedQuery(
            pool,
            "insert into app.lesson_participant_exclusions",
          );
          expect(await sessionHoldsAdvisoryLock(pool, archivePid)).toBe(true);
          transitionPromise = transition();
          await waitForBlockedQuery(pool, "pg_advisory_xact_lock");
          await blocker.query("commit");
          await archivePromise;
          await expect(transitionPromise).rejects.toMatchObject({
            status: 422,
            response: { code: "UNKNOWN_LESSON_CLIENT" },
          });
        } else {
          await blocker.query(
            "select id from app.lessons where id = $1 for update",
            [fixture.groupSourceId],
          );
          transitionPromise = transition();
          const transitionPid = await waitForBlockedQuery(
            pool,
            "select lesson.id",
          );
          expect(await sessionHoldsAdvisoryLock(pool, transitionPid)).toBe(true);
          archivePromise = archives.archive(actor, archiveDto);
          await waitForBlockedQuery(pool, "pg_advisory_xact_lock");
          await blocker.query("commit");
          await expect(transitionPromise).resolves.toMatchObject({
            source: { state: "cancelled" },
            clientFinancialFactIds: [expect.any(String), expect.any(String)],
          });
          await archivePromise;
        }
        const evidence = await pool.query<{
          exclusions: number;
          facts: number;
          transitions: number;
        }>(
          `select
             (select count(*)::int from app.lesson_participant_exclusions
               where lesson_id = $1 and student_id = $2) as exclusions,
             (select count(*)::int from app.lesson_client_charge_facts
               where lesson_id = $1) as facts,
             (select count(*)::int from app.lesson_transitions
               where lesson_id = $1) as transitions`,
          [fixture.groupSourceId, fixture.secondStudentId],
        );
        expect(evidence.rows[0]).toEqual(first === "archive"
          ? { exclusions: 1, facts: 0, transitions: 0 }
          : { exclusions: 0, facts: 2, transitions: 1 });
      } finally {
        await blocker.query("rollback").catch(() => undefined);
        blocker.release();
        await Promise.allSettled([
          archivePromise ?? Promise.resolve(),
          transitionPromise ?? Promise.resolve(),
        ]);
        await cleanup(pool, fixture);
      }
    };

    await run("archive");
    await run("transition");
  });

  it("re-discovers and locks a reschedule successor before archive exclusions", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "director" as const };
    const decision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [fixture.studentId, fixture.secondStudentId]
        .map((clientId) => ({ clientId })),
    };
    const sourceBlocker = await pool.connect();
    const successorBlocker = await pool.connect();
    let archivePromise: Promise<unknown> | undefined;
    let reschedulePromise: Promise<unknown> | undefined;
    let successorPreviewPromise: Promise<Awaited<ReturnType<typeof service.previewCancel>>> | undefined;
    let successorTransition: Promise<unknown> | undefined;
    try {
      await pool.query("update app.users set role = 'director' where id = $1", [
        fixture.managerId,
      ]);
      const scheduled = await pool.query<{ version: number | string }>(
        "update app.lessons set scheduled_at = now() + interval '1 day' where id = $1 returning version",
        [fixture.groupSourceId],
      );
      const successorSchedule = await pool.query<{ scheduled_at: Date | string }>(
        `select ((date_trunc('week', now() at time zone 'Europe/Moscow')
          + interval '1 week 12 hours') at time zone 'Europe/Moscow') as scheduled_at`,
      );
      const expectedVersion = Number(scheduled.rows[0]!.version);
      const rescheduleDto = {
        expectedVersion,
        reasonCode: "client.requested",
        reasonText: "Проверка successor во время архива",
        financialDecision: decision,
        successor: {
          scheduledAt: new Date(successorSchedule.rows[0]!.scheduled_at).toISOString(),
        },
      };
      const preview = await service.previewReschedule(
        actor,
        fixture.groupSourceId,
        rescheduleDto,
      );
      const idempotencyKey = `archive-successor-${randomUUID()}`;
      const successorId = stableTransitionId(
        `schedule.lesson.reschedule\0${fixture.groupSourceId}\0${actor.userId}\0${idempotencyKey}`,
      );
      await sourceBlocker.query("begin");
      await sourceBlocker.query(
        "select id from app.lessons where id = $1 for update",
        [fixture.groupSourceId],
      );
      await successorBlocker.query("begin");
      await successorBlocker.query(
        "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
        [lessonSettlementLockKey(successorId)],
      );
      reschedulePromise = service.reschedule(actor, fixture.groupSourceId, {
        ...rescheduleDto,
        previewToken: preview.previewToken!,
        confirm: true,
      }, {
        idempotencyKey,
        requestId: `archive-successor-${randomUUID()}`,
      });
      await waitForBlockedQuery(pool, "select lesson.id");
      archivePromise = archives.archive(actor, {
        type: "student",
        id: fixture.secondStudentId,
        expectedVersion: 1,
        reason: "test.reschedule-successor-race",
        confirm: true,
      });
      await waitForBlockedQuery(pool, "pg_advisory_xact_lock");
      await sourceBlocker.query("commit");
      await expect(reschedulePromise).resolves.toMatchObject({
        successor: { id: successorId, state: "scheduled" },
      });
      const archivePid = await waitForBlockedQuery(
        pool,
        "pg_advisory_xact_lock",
      );
      expect(await sessionHoldsAdvisoryLock(pool, archivePid)).toBe(true);
      const cancelDto = {
        expectedVersion: 1,
        reasonCode: "school.cancelled",
        reasonText: "Параллельная отмена successor",
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
          clientDecisions: [{ clientId: fixture.studentId }],
        },
      };
      successorPreviewPromise = service.previewCancel(actor, successorId, cancelDto);
      await successorBlocker.query("commit");
      await archivePromise;
      const cancelPreview = await successorPreviewPromise;
      expect(cancelPreview.financialPreview).toMatchObject({
        clientFacts: [expect.objectContaining({ clientId: fixture.studentId })],
      });
      successorTransition = service.cancel(actor, successorId, {
        ...cancelDto,
        previewToken: cancelPreview.previewToken!,
        confirm: true,
      }, {
        idempotencyKey: `archive-successor-cancel-${randomUUID()}`,
        requestId: `archive-successor-cancel-${randomUUID()}`,
      });
      await expect(successorTransition).resolves.toMatchObject({
        source: { state: "cancelled" },
        clientFinancialFactIds: [expect.any(String)],
      });
      const evidence = await pool.query<{
        exclusions: number;
        facts: number;
        archived_facts: number;
        transitions: number;
        state: string;
      }>(
        `select lesson.lifecycle_state as state,
           (select count(*)::int from app.lesson_participant_exclusions
             where lesson_id = lesson.id and student_id = $2) as exclusions,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = lesson.id) as facts,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = lesson.id and client_id = $2) as archived_facts,
           (select count(*)::int from app.lesson_transitions
             where lesson_id = lesson.id) as transitions
         from app.lessons lesson where lesson.id = $1`,
        [successorId, fixture.secondStudentId],
      );
      expect(evidence.rows[0]).toEqual({
        state: "cancelled",
        exclusions: 1,
        facts: 1,
        archived_facts: 0,
        transitions: 1,
      });
    } finally {
      await sourceBlocker.query("rollback").catch(() => undefined);
      await successorBlocker.query("rollback").catch(() => undefined);
      sourceBlocker.release();
      successorBlocker.release();
      await Promise.allSettled([
        archivePromise ?? Promise.resolve(),
        reschedulePromise ?? Promise.resolve(),
        successorPreviewPromise ?? Promise.resolve(),
        successorTransition ?? Promise.resolve(),
      ]);
      await cleanup(pool, fixture);
    }
  });

  it("previews and commits an exact frozen lead row", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const financialDecision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [{ clientId: fixture.leadId }],
    };
    try {
      const previewDto = {
        expectedVersion: 1,
        reasonCode: "school.cancelled",
        reasonText: "Отмена пробного занятия лида",
        financialDecision,
      };
      const preview = await service.previewCancel(
        actor,
        fixture.leadLessonId,
        previewDto,
      );
      expect(preview.financialPreview).toMatchObject({
        clientFacts: [expect.objectContaining({
          clientType: "lead",
          clientId: fixture.leadId,
        })],
      });
      await expect(service.cancel(actor, fixture.leadLessonId, {
        ...previewDto,
        previewToken: preview.previewToken!,
        confirm: true,
      }, {
        idempotencyKey: `exact-lead-${randomUUID()}`,
        requestId: `exact-lead-${randomUUID()}`,
      })).resolves.toMatchObject({
        source: { state: "cancelled", version: 2 },
        clientFinancialFactIds: [expect.any(String)],
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("rejects stale/tampered previews and allows one parallel winner", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const decision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [{ clientId: fixture.studentId }],
    };
    const preview = (scheduledAt: string) =>
      service.previewReschedule(actor, fixture.sourceId, {
        expectedVersion: 1,
        reasonCode: "schedule.concurrent",
        reasonText: "Проверка конкурентного переноса",
        financialDecision: decision,
        successor: { scheduledAt },
      });
    const metadata = (label: string) => ({
      idempotencyKey: `race-${label}-${randomUUID()}`,
      requestId: `race-request-${label}-${randomUUID()}`,
    });
    try {
      const left = await preview("2026-07-27T11:00:00.000Z");
      const right = await preview("2026-07-27T14:00:00.000Z");
      await expect(
        service.reschedule(
          actor,
          fixture.sourceId,
          {
            expectedVersion: 1,
            reasonCode: "schedule.concurrent",
            reasonText: "Изменённое после предпросмотра объяснение",
            financialDecision: decision,
            successor: { scheduledAt: "2026-07-27T11:00:00.000Z" },
            previewToken: left.previewToken!,
            confirm: true,
          },
          metadata("stale"),
        ),
      ).rejects.toMatchObject({ status: 422 });
      await expectSourceUnchanged(pool, fixture.sourceId);

      const capacityDecision = {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        clientDecisions: [{ clientId: fixture.studentId }],
      };
      await database.transaction(async (client) => {
        await settlement.assignPlan(client, {
          lessonId: fixture.capacityId,
          branchId: fixture.branchId,
          decision: capacityDecision,
          selectedBy: fixture.managerId,
          reasonText: "Автоматический расчёт требует проверки",
        });
        await settlement.markPlanState(
          client,
          fixture.capacityId,
          "review_required",
          "ConflictException",
        );
        await client.query(
          "update app.lessons set lifecycle_state = 'settlement_pending' where id = $1",
          [fixture.capacityId],
        );
      });
      const capacityPreview = await service.previewSettle(
        actor,
        fixture.capacityId,
        {
          expectedVersion: 2,
          reasonCode: "attendance.confirmed",
          financialDecision: capacityDecision,
        },
      );
      await pool.query(
        `insert into app.lesson_reservations (
          lesson_id, subscription_id, units
        ) values ($1, $2, 1)`,
        [fixture.blockerId, fixture.subscriptionId],
      );
      await expect(
        service.settle(
          actor,
          fixture.capacityId,
          {
            expectedVersion: 2,
            reasonCode: "attendance.confirmed",
            financialDecision: capacityDecision,
            previewToken: capacityPreview.previewToken!,
            confirm: true,
          },
          metadata("insufficient-capacity"),
        ),
      ).rejects.toMatchObject({ status: 422 });
      const capacityState = await pool.query<{
        lifecycle_state: string;
        version: number;
        plan_state: string;
        facts: number;
      }>(
        `select lesson.lifecycle_state, lesson.version::int as version,
           plan.state as plan_state,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = lesson.id) +
           (select count(*)::int from app.lesson_teacher_compensation_facts
             where lesson_id = lesson.id) as facts
         from app.lessons lesson
         join app.lesson_settlement_plans plan on plan.lesson_id = lesson.id
         where lesson.id = $1`,
        [fixture.capacityId],
      );
      expect(capacityState.rows[0]).toEqual({
        lifecycle_state: "settlement_pending",
        version: 2,
        plan_state: "review_required",
        facts: 0,
      });
      const results = await Promise.allSettled([
        service.reschedule(
          actor,
          fixture.sourceId,
          {
            expectedVersion: 1,
            reasonCode: "schedule.concurrent",
            reasonText: "Проверка конкурентного переноса",
            financialDecision: decision,
            successor: { scheduledAt: "2026-07-27T11:00:00.000Z" },
            previewToken: left.previewToken!,
            confirm: true,
          },
          metadata("left"),
        ),
        service.reschedule(
          actor,
          fixture.sourceId,
          {
            expectedVersion: 1,
            reasonCode: "schedule.concurrent",
            reasonText: "Проверка конкурентного переноса",
            financialDecision: decision,
            successor: { scheduledAt: "2026-07-27T14:00:00.000Z" },
            previewToken: right.previewToken!,
            confirm: true,
          },
          metadata("right"),
        ),
      ]);
      expect(
        results.filter((result) => result.status === "fulfilled"),
      ).toHaveLength(1);
      expect(
        results.filter((result) => result.status === "rejected"),
      ).toHaveLength(1);
      const loser = results.find((result) => result.status === "rejected");
      expect(loser).toMatchObject({
        status: "rejected",
        reason: {
          status: 409,
          response: {
            code: expect.stringMatching(
              /^LESSON_(VERSION_STALE|ALREADY_RESCHEDULED)$/,
            ),
          },
        },
      });
      const counts = await transitionCounts(pool, fixture.sourceId);
      expect(counts).toEqual({
        lifecycle_state: "rescheduled",
        version: 2,
        successors: 1,
        transitions: 1,
        client_facts: 1,
        teacher_facts: 1,
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("commits a signed bulk transition once and rolls the whole batch back on stale input", async () => {
    const actorFor = (managerId: string) => ({
      userId: managerId,
      role: "manager" as const,
    });
    const decisionFor = (studentId: string) => ({
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [{ clientId: studentId }],
    });
    const prepareReview = async (
      fixture: Awaited<ReturnType<typeof createFixture>>,
      lessonIds: string[],
    ) =>
      database.transaction(async (client) => {
        for (const lessonId of lessonIds) {
          await settlement.assignPlan(client, {
            lessonId,
            branchId: fixture.branchId,
            decision: decisionFor(fixture.studentId),
            selectedBy: fixture.managerId,
            reasonText: "Массовая проверка автоматического расчёта",
          });
          await settlement.markPlanState(
            client,
            lessonId,
            "review_required",
            "ConflictException",
          );
        }
        await client.query(
          `update app.lessons
         set lifecycle_state = 'settlement_pending'
         where id = any($1::uuid[])`,
          [lessonIds],
        );
      });
    const lifecycle = new LessonLifecycleRepository(database);
    const successFixture = await createFixture(pool, lifecycle);
    try {
      const actor = actorFor(successFixture.managerId);
      await prepareReview(successFixture, [
        successFixture.cancelId,
        successFixture.settleId,
      ]);
      const previewDto = {
        reasonCode: "attendance.bulk",
        reasonText: "Массовая проверка занятий",
        items: [successFixture.cancelId, successFixture.settleId].map(
          (lessonId) => ({
            lessonId,
            operation: "settle" as const,
            expectedVersion: 2,
            financialDecision: decisionFor(successFixture.studentId),
          }),
        ),
      };
      const preview = await service.previewBulk(actor, previewDto);
      expect(preview).toMatchObject({
        canConfirm: true,
        confirmRequired: true,
        items: [{ canConfirm: true }, { canConfirm: true }],
      });
      const command = {
        ...previewDto,
        previewToken: preview.previewToken!,
        confirm: true as const,
      };
      const metadata = {
        idempotencyKey: `bulk-success-${randomUUID()}`,
        requestId: `bulk-success-${randomUUID()}`,
      };
      const committed = await service.bulk(actor, command, metadata);
      expect(committed).toMatchObject({ replayed: false });
      expect(committed.items).toHaveLength(2);
      await expect(
        service.bulk(actor, command, metadata),
      ).resolves.toMatchObject({
        bulkId: committed.bulkId,
        replayed: true,
      });
      const counts = await pool.query<{
        completed: number;
        transitions: number;
        client_facts: number;
        teacher_facts: number;
      }>(
        `
          select
            (select count(*)::int from app.lessons
              where id = any($1::uuid[])
                and lifecycle_state = 'successfully_completed') as completed,
            (select count(*)::int from app.lesson_transitions
              where lesson_id = any($1::uuid[])) as transitions,
            (select count(*)::int from app.lesson_client_charge_facts
              where lesson_id = any($1::uuid[])) as client_facts,
            (select count(*)::int from app.lesson_teacher_compensation_facts
              where lesson_id = any($1::uuid[])) as teacher_facts
        `,
        [[successFixture.cancelId, successFixture.settleId]],
      );
      expect(counts.rows[0]).toEqual({
        completed: 2,
        transitions: 2,
        client_facts: 2,
        teacher_facts: 2,
      });
    } finally {
      await cleanup(pool, successFixture);
    }

    const rollbackFixture = await createFixture(pool, lifecycle);
    try {
      const actor = actorFor(rollbackFixture.managerId);
      const ordered = [
        rollbackFixture.cancelId,
        rollbackFixture.settleId,
      ].sort();
      await prepareReview(rollbackFixture, ordered);
      const previewDto = {
        reasonCode: "attendance.bulk",
        reasonText: "Проверка полного отката",
        items: ordered.map((lessonId) => ({
          lessonId,
          operation: "settle" as const,
          expectedVersion: 2,
          financialDecision: decisionFor(rollbackFixture.studentId),
        })),
      };
      const preview = await service.previewBulk(actor, previewDto);
      await pool.query("update app.lessons set notes = 'stale' where id = $1", [
        ordered[1],
      ]);
      await expect(
        service.bulk(
          actor,
          {
            ...previewDto,
            previewToken: preview.previewToken!,
            confirm: true,
          },
          {
            idempotencyKey: `bulk-rollback-${randomUUID()}`,
            requestId: `bulk-rollback-${randomUUID()}`,
          },
        ),
      ).rejects.toMatchObject({ status: 409 });
      expect(await transitionCounts(pool, ordered[0]!)).toEqual({
        lifecycle_state: "settlement_pending",
        version: 2,
        successors: 0,
        transitions: 0,
        client_facts: 0,
        teacher_facts: 0,
      });
      expect(await transitionCounts(pool, ordered[1]!)).toEqual({
        lifecycle_state: "settlement_pending",
        version: 3,
        successors: 0,
        transitions: 0,
        client_facts: 0,
        teacher_facts: 0,
      });
    } finally {
      await cleanup(pool, rollbackFixture);
    }
  });

  it("serializes archive fixed-point discovery with bulk lesson locks", async () => {
    const lifecycle = new LessonLifecycleRepository(database);
    const fixture = await createFixture(pool, lifecycle);
    const actor = { userId: fixture.managerId, role: "director" as const };
    let lessonA = stableTransitionId("archive-bulk-lock-order-a");
    for (let index = 0; lessonA.localeCompare(fixture.groupSourceId) >= 0; index += 1) {
      lessonA = stableTransitionId(`archive-bulk-lock-order-a-${index}`);
    }
    const lessonB = fixture.groupSourceId;
    const creator = await pool.connect();
    let archivePromise: Promise<unknown> | undefined;
    let bulkPromise: Promise<unknown> | undefined;
    try {
      expect(lessonA.localeCompare(lessonB)).toBeLessThan(0);
      await pool.query("update app.users set role = 'director' where id = $1", [
        fixture.managerId,
      ]);
      const scheduledB = await pool.query<{ version: number | string }>(
        "update app.lessons set scheduled_at = now() + interval '1 day' where id = $1 returning version",
        [lessonB],
      );
      await pool.query(
        `insert into app.lessons (
           id, group_id, teacher_id, branch_id, room_id, scheduled_at,
           duration_minutes, status, is_trial, created_by
         ) select $1, group_id, teacher_id, branch_id, room_id,
           now() + interval '2 days', duration_minutes, status, is_trial, created_by
         from app.lessons where id = $2`,
        [lessonA, lessonB],
      );
      await database.transaction((client) => lifecycle.createGroupSnapshot(client, {
        lessonId: lessonA,
        groupId: fixture.groupId,
        completionType: "standard.success",
        teacherCompensationType: "fixed",
        teacherCompensationValue: 700,
        trial: false,
        participants: [{
          studentId: fixture.studentId,
          chargeType: "personal_account",
          chargeValue: 800,
        }],
      }));
      const decision = (clientIds: string[]) => ({
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "none",
        clientDecisions: clientIds.map((clientId) => ({ clientId })),
      });
      const previewDto = {
        reasonCode: "school.cancelled",
        reasonText: "Проверка общего multi-lesson gate",
        items: [
          {
            lessonId: lessonB,
            operation: "cancel" as const,
            expectedVersion: Number(scheduledB.rows[0]!.version),
            financialDecision: decision([
              fixture.studentId,
              fixture.secondStudentId,
            ]),
          },
          {
            lessonId: lessonA,
            operation: "cancel" as const,
            expectedVersion: 1,
            financialDecision: decision([fixture.studentId]),
          },
        ],
      };
      const preview = await service.previewBulk(actor, previewDto);
      expect(preview.canConfirm).toBe(true);
      await creator.query("begin");
      await creator.query(
        "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
        [`client:student:${fixture.secondStudentId}`],
      );
      await creator.query(
        `insert into app.lesson_snapshot_participants (
           lesson_id, student_id, charge_type, charge_value
         ) values ($1, $2, 'none', 0)`,
        [lessonA, fixture.secondStudentId],
      );
      archivePromise = archives.archive(actor, {
        type: "student",
        id: fixture.secondStudentId,
        expectedVersion: 1,
        reason: "test.bulk-fixed-point-lock-order",
        confirm: true,
      });
      await waitForBlockedQuery(pool, "pg_advisory_xact_lock");
      bulkPromise = service.bulk(actor, {
        ...previewDto,
        previewToken: preview.previewToken!,
        confirm: true,
      }, {
        idempotencyKey: `bulk-fixed-point-${randomUUID()}`,
        requestId: `bulk-fixed-point-${randomUUID()}`,
      });
      await waitForBlockedSessionCount(pool, 2);
      const lessonAWasFree = await advisoryLockIsAvailable(
        pool,
        lessonSettlementLockKey(lessonA),
      );
      await creator.query("commit");
      const [archiveResult, bulkResult] = await Promise.allSettled([
        archivePromise,
        bulkPromise,
      ]);
      expect(lessonAWasFree).toBe(true);
      expect(archiveResult.status).toBe("fulfilled");
      expect(bulkResult).toMatchObject({
        status: "rejected",
        reason: {
          status: 422,
          response: { code: "UNKNOWN_LESSON_CLIENT" },
        },
      });
      const evidence = await pool.query<{
        exclusions: number;
        facts: number;
        transitions: number;
      }>(
        `select
           (select count(*)::int from app.lesson_participant_exclusions
             where lesson_id = any($1::uuid[]) and student_id = $2) as exclusions,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = any($1::uuid[])) as facts,
           (select count(*)::int from app.lesson_transitions
             where lesson_id = any($1::uuid[])) as transitions`,
        [[lessonA, lessonB], fixture.secondStudentId],
      );
      expect(evidence.rows[0]).toEqual({
        exclusions: 2,
        facts: 0,
        transitions: 0,
      });
    } finally {
      await creator.query("rollback").catch(() => undefined);
      creator.release();
      await Promise.allSettled([
        archivePromise ?? Promise.resolve(),
        bulkPromise ?? Promise.resolve(),
      ]);
      await cleanup(pool, fixture);
    }
  });

  it("gates a single reschedule before archive fixed-point lesson locks", async () => {
    const lifecycle = new LessonLifecycleRepository(database);
    const fixture = await createFixture(pool, lifecycle);
    const archiveActor = {
      userId: fixture.managerId,
      role: "director" as const,
    };
    const rescheduleActor = {
      userId: fixture.teacherUserId,
      role: "director" as const,
    };
    const lessonA = stableTransitionId(`archive-single-reschedule-${randomUUID()}`);
    const creator = await pool.connect();
    const lessonBlocker = await pool.connect();
    let archivePromise: Promise<unknown> | undefined;
    let reschedulePromise: Promise<unknown> | undefined;
    try {
      await pool.query(
        "update app.users set role = 'director' where id = any($1::uuid[])",
        [[fixture.managerId, fixture.teacherUserId]],
      );
      await pool.query(
        "update app.lessons set scheduled_at = now() + interval '1 day' where id = $1",
        [fixture.groupSourceId],
      );
      const successorSchedule = await pool.query<{ scheduled_at: Date | string }>(
        `select ((date_trunc('week', now() at time zone 'Europe/Moscow')
          + interval '1 week 12 hours') at time zone 'Europe/Moscow') as scheduled_at`,
      );
      await lessonBlocker.query("begin");
      await lessonBlocker.query(
        "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
        [lessonSettlementLockKey(lessonA)],
      );
      await pool.query(
        `insert into app.aggregate_versions (
           aggregate_type, aggregate_id, version
         ) values ('schedule:lesson', $1, 1)`,
        [lessonA],
      );
      await creator.query("begin");
      await creator.query(
        "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
        [`client:student:${fixture.secondStudentId}`],
      );
      await creator.query(
        `insert into app.lessons (
           id, group_id, teacher_id, branch_id, room_id, scheduled_at,
           duration_minutes, status, is_trial, created_by
         ) select $1, group_id, teacher_id, branch_id, room_id,
           now() + interval '2 days', duration_minutes, status, is_trial, created_by
         from app.lessons where id = $2`,
        [lessonA, fixture.groupSourceId],
      );
      await lifecycle.createGroupSnapshot(creator, {
        lessonId: lessonA,
        groupId: fixture.groupId,
        completionType: "standard.success",
        teacherCompensationType: "fixed",
        teacherCompensationValue: 700,
        trial: false,
        participants: [fixture.studentId, fixture.secondStudentId].map(
          (studentId) => ({
            studentId,
            chargeType: "personal_account" as const,
            chargeValue: 800,
          }),
        ),
      });
      archivePromise = archives.archive(archiveActor, {
        type: "student",
        id: fixture.secondStudentId,
        expectedVersion: 1,
        reason: "test.single-reschedule-fixed-point-lock-order",
        confirm: true,
      });
      const archivePid = await waitForBlockedQuery(
        pool,
        "pg_advisory_xact_lock",
      );
      const previewToken = tokens.issueLessonTransition({
        kind: "lesson.transition",
        operation: "reschedule",
        actorUserId: rescheduleActor.userId,
        lessonId: lessonA,
        expectedVersion: 1,
        transitionFingerprint: "a".repeat(64),
      }).token;
      const rescheduleIdempotencyKey =
        `single-reschedule-gate-${randomUUID()}`;
      reschedulePromise = service.reschedule(rescheduleActor, lessonA, {
        expectedVersion: 1,
        reasonCode: "client.requested",
        reasonText: "Параллельный перенос во время архива клиента",
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
          clientDecisions: [fixture.studentId, fixture.secondStudentId]
            .map((clientId) => ({ clientId })),
        },
        successor: {
          scheduledAt: new Date(
            successorSchedule.rows[0]!.scheduled_at,
          ).toISOString(),
        },
        previewToken,
        confirm: true,
      }, {
        idempotencyKey: rescheduleIdempotencyKey,
        requestId: `single-reschedule-gate-${randomUUID()}`,
      });
      expect(await promiseStateAfter(reschedulePromise, 100)).toBe("pending");
      await waitForBlockedSessionCount(pool, 2);
      await creator.query("commit");
      await waitForHeldAdvisoryLockCount(pool, archivePid, 3);
      await lessonBlocker.query("commit");
      const [archiveResult, rescheduleResult] = await Promise.allSettled([
        archivePromise,
        reschedulePromise,
      ]);
      expect(archiveResult.status).toBe("fulfilled");
      expect(rescheduleResult).toMatchObject({
        status: "rejected",
        reason: {
          status: 422,
          response: { code: "ARCHIVED_CLIENT_REFERENCE" },
        },
      });
      const evidence = await pool.query<{
        state: string;
        exclusions: number;
        facts: number;
        transitions: number;
        successors: number;
        idempotency: number;
        aggregate_version: number;
      }>(
        `select lesson.lifecycle_state as state,
           (select count(*)::int from app.lesson_participant_exclusions
             where lesson_id = lesson.id and student_id = $2) as exclusions,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = lesson.id) as facts,
           (select count(*)::int from app.lesson_transitions
             where lesson_id = lesson.id) as transitions,
           (select count(*)::int from app.lessons successor
             where successor.predecessor_id = lesson.id) as successors,
           (select count(*)::int from app.idempotency_records
             where actor_key = $3
               and operation = 'schedule.lesson.reschedule'
               and idempotency_key = $4) as idempotency,
           (select version::int from app.aggregate_versions
             where aggregate_type = 'schedule:lesson'
               and aggregate_id = lesson.id::text) as aggregate_version
         from app.lessons lesson where lesson.id = $1`,
        [
          lessonA,
          fixture.secondStudentId,
          `user:${rescheduleActor.userId}`,
          rescheduleIdempotencyKey,
        ],
      );
      expect(evidence.rows[0]).toEqual({
        state: "scheduled",
        exclusions: 1,
        facts: 0,
        transitions: 0,
        successors: 0,
        idempotency: 0,
        aggregate_version: 1,
      });
    } finally {
      await creator.query("rollback").catch(() => undefined);
      await lessonBlocker.query("rollback").catch(() => undefined);
      creator.release();
      lessonBlocker.release();
      await Promise.allSettled([
        archivePromise ?? Promise.resolve(),
        reschedulePromise ?? Promise.resolve(),
      ]);
      await cleanup(pool, fixture);
    }
  });

  it("gates planned resource edits before archive lesson rows", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const archiveActor = {
      userId: fixture.managerId,
      role: "director" as const,
    };
    const editActor = {
      userId: fixture.teacherUserId,
      role: "director" as const,
    };
    const lessonId = fixture.sourceId;
    const planBlocker = await pool.connect();
    let schedulePlanId: string | undefined;
    let archivePromise: Promise<unknown> | undefined;
    let editPromise: Promise<unknown> | undefined;
    const idempotencyKey = `planned-resource-gate-${randomUUID()}`;
    try {
      await pool.query(
        "update app.users set role = 'director' where id = any($1::uuid[])",
        [[fixture.managerId, fixture.teacherUserId]],
      );
      const scheduled = await pool.query<{ version: number | string }>(
        `update app.lessons set scheduled_at = now() + interval '1 day'
         where id = $1 returning version`,
        [lessonId],
      );
      const expectedVersion = Number(scheduled.rows[0]!.version);
      await database.transaction((client) => settlement.assignPlan(client, {
        lessonId,
        branchId: fixture.branchId,
        decision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
          clientDecisions: [{ clientId: fixture.studentId }],
        },
        selectedBy: fixture.managerId,
        reasonText: "Исходный план для гонки resource edit",
      }));
      schedulePlanId = (await pool.query<{ id: string }>(
        `insert into app.schedule_plans (
           kind, title, student_id, subscription_id, active_from, created_by
         ) values ('individual', $1, $2, $3, current_date, $4)
         returning id`,
        [
          `Planned resource gate ${randomUUID()}`,
          fixture.studentId,
          fixture.subscriptionId,
          fixture.managerId,
        ],
      )).rows[0]!.id;
      await planBlocker.query("begin");
      await planBlocker.query(
        "select id from app.schedule_plans where id = $1 for update",
        [schedulePlanId],
      );
      archivePromise = archives.archive(archiveActor, {
        type: "student",
        id: fixture.studentId,
        expectedVersion: 1,
        reason: "test.planned-resource-edit-lock-order",
        confirm: true,
      });
      const archivePid = await waitForBlockedQuery(pool, "select plan.id");
      await waitForHeldAdvisoryLockCount(pool, archivePid, 3);
      const previewToken = tokens.issueLessonTransition({
        kind: "lesson.transition",
        operation: "planned-settlement",
        actorUserId: editActor.userId,
        lessonId,
        expectedVersion,
        transitionFingerprint: "b".repeat(64),
      }).token;
      editPromise = plannedSettlements.updateSettlementPlan(editActor, lessonId, {
        expectedVersion,
        reasonText: "Перенос ресурсов до архивирования",
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
          clientDecisions: [{ clientId: fixture.studentId }],
        },
        resources: {
          teacherId: fixture.replacementTeacherId,
          branchId: fixture.branchId,
          roomId: fixture.replacementRoomId,
        },
        previewToken,
        confirm: true,
      }, {
        idempotencyKey,
        requestId: `planned-resource-gate-${randomUUID()}`,
      });
      expect(await promiseStateAfter(editPromise, 100)).toBe("pending");
      await waitForBlockedSessionCount(pool, 2);
      expect(await lessonRowLockIsAvailable(pool, lessonId)).toBe(true);
      await planBlocker.query("commit");
      const [archiveResult, editResult] = await Promise.allSettled([
        archivePromise,
        editPromise,
      ]);
      expect(archiveResult.status).toBe("fulfilled");
      expect(editResult).toMatchObject({
        status: "rejected",
        reason: {
          status: 409,
          response: { code: "STALE_VERSION" },
        },
      });
      const evidence = await pool.query<{
        state: string;
        teacher_id: string;
        branch_id: string;
        room_id: string;
        plan_state: string;
        revisions: number;
        facts: number;
        planned_audits: number;
        planned_outbox: number;
        planned_idempotency: number;
      }>(
        `select lesson.lifecycle_state as state,
           lesson.teacher_id, lesson.branch_id, lesson.room_id,
           settlement_plan.state as plan_state,
           (select count(*)::int from app.lesson_settlement_plan_revisions
             where lesson_id = lesson.id) as revisions,
           ((select count(*) from app.lesson_client_charge_facts
              where lesson_id = lesson.id) +
            (select count(*) from app.lesson_teacher_compensation_facts
              where lesson_id = lesson.id))::int as facts,
           (select count(*)::int from app.audit_events
             where actor_user_id = $2
               and action = 'crm.lesson_settlement_plan_updated'
               and entity_id = lesson.id::text) as planned_audits,
           (select count(*)::int from app.platform_outbox_events
             where aggregate_type = 'schedule:lesson'
               and aggregate_id = lesson.id::text) as planned_outbox,
           (select count(*)::int from app.idempotency_records
             where actor_key = $3
               and operation = 'schedule.lesson.settlement-plan.update'
               and idempotency_key = $4) as planned_idempotency
         from app.lessons lesson
         join app.lesson_settlement_plans settlement_plan
           on settlement_plan.lesson_id = lesson.id
         where lesson.id = $1`,
        [lessonId, editActor.userId, `user:${editActor.userId}`, idempotencyKey],
      );
      expect(evidence.rows[0]).toEqual({
        state: "cancelled",
        teacher_id: fixture.teacherId,
        branch_id: fixture.branchId,
        room_id: fixture.roomId,
        plan_state: "cancelled",
        revisions: 1,
        facts: 0,
        planned_audits: 0,
        planned_outbox: 0,
        planned_idempotency: 0,
      });
    } finally {
      await planBlocker.query("rollback").catch(() => undefined);
      planBlocker.release();
      await Promise.allSettled([
        archivePromise ?? Promise.resolve(),
        editPromise ?? Promise.resolve(),
      ]);
      if (schedulePlanId) {
        await pool.query(
          `delete from app.aggregate_versions
           where aggregate_type = 'schedule:plan' and aggregate_id = $1`,
          [schedulePlanId],
        );
        await pool.query("delete from app.schedule_plans where id = $1", [
          schedulePlanId,
        ]);
      }
      await cleanup(pool, fixture);
    }
  });

  it("materializes one routed lesson change per audience member across an outbox retry", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const financialDecision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [{ clientId: fixture.studentId }],
    };
    const successor = {
      scheduledAt: "2026-07-27T11:00:00.000Z",
      teacherId: fixture.replacementTeacherId,
      roomId: fixture.replacementRoomId,
    };
    try {
      const preview = await service.previewReschedule(actor, fixture.sourceId, {
        expectedVersion: 1,
        reasonCode: "client.requested",
        reasonText: "UAT-112 перенос с уведомлением",
        financialDecision,
        successor,
      });
      expect(preview.canConfirm).toBe(true);
      const committed = await service.reschedule(
        actor,
        fixture.sourceId,
        {
          expectedVersion: 1,
          reasonCode: "client.requested",
          reasonText: "UAT-112 перенос с уведомлением",
          financialDecision,
          successor,
          previewToken: preview.previewToken!,
          confirm: true,
        },
        {
          idempotencyKey: `uat-112-${randomUUID()}`,
          requestId: `request-uat-112-${randomUUID()}`,
        },
      );
      const successorId = committed.successor!.id;
      const outbox = await pool.query<{
        event_id: string;
        payload: Record<string, unknown>;
      }>(
        `
          select event_id::text as event_id, payload
          from app.platform_outbox_events
          where aggregate_type = 'schedule:lesson'
            and aggregate_id = $1
            and event_type = 'schedule.lesson.changed'
            and payload->>'action' = 'rescheduled'
          order by occurred_at desc
          limit 1
        `,
        [fixture.sourceId],
      );
      expect(outbox.rows[0]!.payload).toMatchObject({
        entityId: fixture.sourceId,
        action: "rescheduled",
        state: "rescheduled",
        successorId,
      });

      const notifications = createNotificationsService(database);
      const notificationInput = {
        eventId: outbox.rows[0]!.event_id,
        lessonId: fixture.sourceId,
        action: "rescheduled" as const,
        successorId,
      };
      await notifications.notifyLessonChanged(notificationInput);
      await notifications.notifyLessonChanged(notificationInput);

      const facts = await pool.query<{
        id: string;
        title: string;
        event_type: string;
        entity_id: string;
        recipient_user_ids: string[];
        delivery_count: number;
      }>(
        `
          select notification.id::text as id,
            notification.title,
            notification.data->>'eventType' as event_type,
            notification.data->>'entityId' as entity_id,
            array_agg(recipient.user_id::text order by recipient.user_id::text)
              as recipient_user_ids,
            (
              select count(*)::int
              from app.notification_deliveries delivery
              where delivery.notification_id = notification.id
                and delivery.channel = 'push'
            ) as delivery_count
          from app.notifications notification
          join app.notification_recipients recipient
            on recipient.notification_id = notification.id
          where notification.data->>'entityId' = any($1::text[])
          group by notification.id
          order by notification.data->>'eventType'
        `,
        [[fixture.sourceId, successorId]],
      );
      expect(facts.rows).toHaveLength(2);
      const current = facts.rows.find(
        (row) => row.event_type === "rescheduled",
      )!;
      const removed = facts.rows.find(
        (row) => row.event_type === "teacher_unassigned",
      )!;
      expect(current).toMatchObject({
        id: outbox.rows[0]!.event_id,
        title: "Занятие перенесено",
        entity_id: successorId,
        delivery_count: 2,
      });
      expect(new Set(current.recipient_user_ids)).toEqual(
        new Set([fixture.clientUserId, fixture.replacementTeacherUserId]),
      );
      expect(removed).toMatchObject({
        title: "Занятие переназначено",
        entity_id: fixture.sourceId,
        delivery_count: 1,
      });
      expect(removed.recipient_user_ids).toEqual([fixture.teacherUserId]);

      const clientNotification = (
        await notifications.list(
          { userId: fixture.clientUserId, role: "client" },
          { limit: 50 },
        )
      ).items.find((item) => item.id === outbox.rows[0]!.event_id)!;
      expect(clientNotification).toMatchObject({
        isRead: false,
        data: {
          entityType: "lesson",
          entityId: successorId,
          eventType: "rescheduled",
        },
      });
      await notifications.markRead(
        { userId: fixture.clientUserId, role: "client" },
        clientNotification.id,
      );
      const afterRestart = await createNotificationsService(database).list(
        { userId: fixture.clientUserId, role: "client" },
        { limit: 50 },
      );
      expect(
        afterRestart.items.find((item) => item.id === clientNotification.id),
      ).toMatchObject({ isRead: true });
    } finally {
      await cleanup(pool, fixture);
    }
  });
});

function createNotificationsService(database: DatabaseService) {
  return new NotificationsService(
    database,
    {
      record: jest.fn().mockResolvedValue(undefined),
    } as unknown as AuditService,
    new NotificationsPolicy(),
    {
      dispatchPendingEmails: jest
        .fn()
        .mockResolvedValue({ processed: 0, failed: 0 }),
      dispatchPendingPush: jest
        .fn()
        .mockResolvedValue({ processed: 0, failed: 0 }),
    } as unknown as NotificationWorker,
    {
      hash: jest.fn((token: string) => `hash-${token}`),
      encrypt: jest.fn((token: string) => `encrypted-${token}`),
    } as unknown as NotificationTokenCrypto,
    { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
  );
}

async function expectSourceUnchanged(pool: Pool, lessonId: string) {
  expect(await transitionCounts(pool, lessonId)).toEqual({
    lifecycle_state: "scheduled",
    version: 1,
    successors: 0,
    transitions: 0,
    client_facts: 0,
    teacher_facts: 0,
  });
}

async function transitionCounts(pool: Pool, lessonId: string) {
  const result = await pool.query<{
    lifecycle_state: string;
    version: number | string;
    successors: number;
    transitions: number;
    client_facts: number;
    teacher_facts: number;
  }>(
    `
      select source.lifecycle_state, source.version,
        (select count(*)::int from app.lessons
          where predecessor_id = source.id) as successors,
        (select count(*)::int from app.lesson_transitions
          where lesson_id = source.id) as transitions,
        (select count(*)::int from app.lesson_client_charge_facts
          where lesson_id = source.id) as client_facts,
        (select count(*)::int from app.lesson_teacher_compensation_facts
          where lesson_id = source.id) as teacher_facts
      from app.lessons source where source.id = $1
    `,
    [lessonId],
  );
  return { ...result.rows[0]!, version: Number(result.rows[0]!.version) };
}

async function waitForBlockedQuery(pool: Pool, fragment: string): Promise<number> {
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    const result = await pool.query<{ pid: number }>(
      `select pid from pg_stat_activity
       where datname = current_database()
         and wait_event_type = 'Lock'
         and query ilike $1
       order by query_start desc limit 1`,
      [`%${fragment}%`],
    );
    if (result.rows[0]) return result.rows[0].pid;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  const active = await pool.query<{ pid: number; state: string; wait_event_type: string | null; query: string }>(
    `select pid, state, wait_event_type, query from pg_stat_activity
     where datname = current_database() and state <> 'idle' order by query_start`,
  );
  throw new Error(
    `Timed out waiting for blocked query: ${fragment}; active=${JSON.stringify(active.rows)}`,
  );
}

async function waitForBlockedSessionCount(
  pool: Pool,
  expected: number,
): Promise<void> {
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    const result = await pool.query<{ count: number }>(
      `select count(*)::int as count from pg_stat_activity
       where datname = current_database()
         and wait_event_type = 'Lock'`,
    );
    if (result.rows[0]!.count >= expected) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  const active = await pool.query<{ state: string; wait_event_type: string | null; query: string }>(
    `select state, wait_event_type, query from pg_stat_activity
     where datname = current_database() and state <> 'idle' order by query_start`,
  );
  throw new Error(
    `Timed out waiting for ${expected} blocked sessions; active=${JSON.stringify(active.rows)}`,
  );
}

async function advisoryLockIsAvailable(pool: Pool, key: string): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    const result = await client.query<{ acquired: boolean }>(
      "select pg_try_advisory_xact_lock(hashtextextended($1::text, 0)) as acquired",
      [key],
    );
    return result.rows[0]!.acquired;
  } finally {
    await client.query("rollback").catch(() => undefined);
    client.release();
  }
}

async function lessonRowLockIsAvailable(
  pool: Pool,
  lessonId: string,
): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query(
      "select id from app.lessons where id = $1 for update nowait",
      [lessonId],
    );
    return true;
  } catch (error) {
    if ((error as { code?: string }).code === "55P03") return false;
    throw error;
  } finally {
    await client.query("rollback").catch(() => undefined);
    client.release();
  }
}

async function waitForHeldAdvisoryLockCount(
  pool: Pool,
  pid: number,
  expected: number,
): Promise<void> {
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    const result = await pool.query<{ count: number }>(
      `select count(*)::int as count from pg_locks
       where pid = $1 and locktype = 'advisory' and granted`,
      [pid],
    );
    if (result.rows[0]!.count >= expected) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(
    `Timed out waiting for ${expected} held advisory locks on pid ${pid}`,
  );
}

async function promiseStateAfter(
  promise: Promise<unknown>,
  milliseconds: number,
): Promise<"pending" | "fulfilled" | { rejected: unknown }> {
  return Promise.race([
    promise.then(
      () => "fulfilled" as const,
      (error) => ({ rejected: error }),
    ),
    new Promise<"pending">((resolve) =>
      setTimeout(() => resolve("pending"), milliseconds),
    ),
  ]);
}

async function sessionHoldsAdvisoryLock(
  pool: Pool,
  pid: number,
): Promise<boolean> {
  const result = await pool.query<{ held: boolean }>(
    `select exists(
       select 1 from pg_locks
       where pid = $1 and locktype = 'advisory' and granted
     ) as held`,
    [pid],
  );
  return result.rows[0]!.held;
}

async function effectiveSubscriptionUnits(
  pool: Pool,
  subscriptionId: string,
): Promise<string> {
  const result = await pool.query<{ units: string }>(
    `select coalesce(sum(units), 0)::numeric(8,2)::text as units
     from app.lesson_client_charge_facts_effective
     where subscription_id = $1`,
    [subscriptionId],
  );
  return result.rows[0]!.units;
}

async function createFixture(pool: Pool, lifecycle: LessonLifecycleRepository) {
  const branch = await pool.query<{ id: string }>(
    "insert into app.branches (name, timezone_name) values ($1, 'Europe/Moscow') returning id",
    [`Transition ${randomUUID()}`],
  );
  const branchId = branch.rows[0]!.id;
  await pool.query(
    "insert into app.branch_hours (branch_id, weekday, open_local, close_local) values ($1, 1, '09:00', '18:00')",
    [branchId],
  );
  const room = await pool.query<{ id: string }>(
    "insert into app.rooms (branch_id, name) values ($1, $2) returning id",
    [branchId, `Transition room ${randomUUID()}`],
  );
  const replacementRoom = await pool.query<{ id: string }>(
    "insert into app.rooms (branch_id, name) values ($1, $2) returning id",
    [branchId, `Replacement room ${randomUUID()}`],
  );
  const users = await pool.query<{ id: string; role: string }>(
    `insert into app.users (email, role, email_verified_at) values
      ($1, 'manager', now()), ($2, 'teacher', now()),
      ($3, 'client', now()), ($4, 'client', now())
      returning id, role::text as role`,
    [
      `transition-manager-${randomUUID()}@test.local`,
      `transition-teacher-${randomUUID()}@test.local`,
      `transition-client-${randomUUID()}@test.local`,
      `transition-client-two-${randomUUID()}@test.local`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const teacherUserId = users.rows.find((row) => row.role === "teacher")!.id;
  const clientUserIds = users.rows
    .filter((row) => row.role === "client")
    .map((row) => row.id);
  const clientUserId = clientUserIds[0]!;
  const secondClientUserId = clientUserIds[1]!;
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `insert into app.profiles (user_id, first_name, last_name) values
      ($1, 'Transition', 'Teacher'), ($2, 'Transition', 'Student'),
      ($3, 'Transition', 'Manager'), ($4, 'Transition', 'Student Two')
      returning id, user_id`,
    [teacherUserId, clientUserId, managerId, secondClientUserId],
  );
  await pool.query(
    `with staff as (
       insert into app.staff_members (profile_id, role) values ($1, 'manager') returning id
     ), link as (
       insert into app.user_crm_links (user_id, entity_type, entity_id, link_source, confirmed_at)
       select $2, 'staff', id, 'manual_phone', now() from staff
     ) insert into app.staff_branch_assignments (staff_member_id, branch_id)
       select id, $3 from staff`,
    [profiles.rows.find((row) => row.user_id === managerId)!.id, managerId, branchId],
  );
  const teacherProfileId = profiles.rows.find(
    (row) => row.user_id === teacherUserId,
  )!.id;
  const studentProfileId = profiles.rows.find(
    (row) => row.user_id === clientUserId,
  )!.id;
  const teacher = await pool.query<{ id: string }>(
    "insert into app.teachers (profile_id) values ($1) returning id",
    [teacherProfileId],
  );
  const teacherId = teacher.rows[0]!.id;
  const replacementTeacherUser = await pool.query<{ id: string }>(
    `insert into app.users (email, role, email_verified_at)
     values ($1, 'teacher', now()) returning id`,
    [`replacement-teacher-${randomUUID()}@test.local`],
  );
  const replacementTeacherProfile = await pool.query<{ id: string }>(
    `insert into app.profiles (user_id, first_name, last_name)
     values ($1, 'Replacement', 'Teacher') returning id`,
    [replacementTeacherUser.rows[0]!.id],
  );
  const replacementTeacher = await pool.query<{ id: string }>(
    "insert into app.teachers (profile_id) values ($1) returning id",
    [replacementTeacherProfile.rows[0]!.id],
  );
  const replacementTeacherId = replacementTeacher.rows[0]!.id;
  await pool.query(
    `insert into app.teacher_branches (teacher_id, branch_id, active_from)
      values ($1, $2, '2026-01-01')`,
    [teacherId, branchId],
  );
  await pool.query(
    `insert into app.teacher_availability_rules (
      teacher_id, kind, available, timezone_name, weekday, local_start,
      local_end, valid_from, valid_until
    ) values ($1, 'recurring', true, 'Europe/Moscow', 1, '09:00', '18:00',
      '2026-01-01', '2026-12-31')`,
    [teacherId],
  );
  await pool.query(
    `insert into app.teacher_branches (teacher_id, branch_id, active_from)
     values ($1, $2, '2026-01-01')`,
    [replacementTeacherId, branchId],
  );
  await pool.query(
    `insert into app.teacher_availability_rules (
      teacher_id, kind, available, timezone_name, weekday, local_start,
      local_end, valid_from, valid_until
    ) values ($1, 'recurring', true, 'Europe/Moscow', 1, '09:00', '18:00',
      '2026-01-01', '2026-12-31')`,
    [replacementTeacherId],
  );
  const student = await pool.query<{ id: string }>(
    `insert into app.students (profile_id, branch_id) values
       ($1, $3),
       ((select id from app.profiles where user_id = $2), $3)
     returning id`,
    [studentProfileId, secondClientUserId, branchId],
  );
  const studentId = student.rows[0]!.id;
  const secondStudentId = student.rows[1]!.id;
  const lead = await pool.query<{ id: string }>(
    `insert into app.leads (first_name, last_name, phone, branch_id)
     values ('Transition', 'Lead', $1, $2) returning id`,
    [`+7999${String(Math.floor(Math.random() * 1_000_0000)).padStart(7, "0")}`, branchId],
  );
  const leadId = lead.rows[0]!.id;
  const group = await pool.query<{ id: string }>(
    `insert into app.groups (teacher_id, branch_id, name, price_per_lesson)
     values ($1, $2, $3, 800) returning id`,
    [teacherId, branchId, `Transition group ${randomUUID()}`],
  );
  const groupId = group.rows[0]!.id;
  await pool.query(
    `insert into app.group_students (group_id, student_id, joined_at)
     values ($1, $2, '2026-01-01'), ($1, $3, '2026-01-01')`,
    [groupId, studentId, secondStudentId],
  );
  const subscription = await pool.query<{ id: string }>(
    `insert into app.subscriptions (
      student_id, lessons_total, lessons_used, status
    ) values ($1, 1, 0, 'active') returning id`,
    [studentId],
  );
  const subscriptionId = subscription.rows[0]!.id;
  const lessons = await pool.query<{ id: string }>(
    `insert into app.lessons (
      student_id, teacher_id, branch_id, room_id, scheduled_at,
      duration_minutes, created_by
    ) values
      ($1, $2, $3, $4, '2026-07-27T07:00:00Z', 60, $5),
      ($1, $2, $3, $4, '2026-07-28T07:00:00Z', 60, $5),
      ($1, $2, $3, $4, '2026-07-29T07:00:00Z', 60, $5),
      ($1, $2, $3, $4, '2026-07-27T09:00:00Z', 60, $5),
      ($1, $2, $3, $4, '2026-07-30T07:00:00Z', 60, $5),
      ($1, $2, $3, $4, '2026-07-31T07:00:00Z', 60, $5)
    returning id`,
    [studentId, teacherId, branchId, room.rows[0]!.id, managerId],
  );
  const [sourceId, cancelId, settleId, , capacityId, blockerId] =
    lessons.rows.map((row) => row.id);
  await pool.query(
    `insert into app.lessons (
      student_id, teacher_id, branch_id, room_id, scheduled_at,
      duration_minutes, created_by
    ) values ($1, $2, $3, $4, '2026-07-27T12:00:00Z', 60, $5)`,
    [
      studentId,
      replacementTeacherId,
      branchId,
      replacementRoom.rows[0]!.id,
      managerId,
    ],
  );
  const groupLesson = await pool.query<{ id: string }>(
    `insert into app.lessons (
       group_id, teacher_id, branch_id, room_id, scheduled_at,
       duration_minutes, created_by
     ) values ($1, $2, $3, $4, '2026-08-03T07:00:00Z', 60, $5)
     returning id`,
    [groupId, teacherId, branchId, room.rows[0]!.id, managerId],
  );
  const groupSourceId = groupLesson.rows[0]!.id;
  const leadLesson = await pool.query<{ id: string }>(
    `insert into app.lessons (
       lead_id, teacher_id, branch_id, room_id, scheduled_at,
       duration_minutes, created_by
     ) values ($1, $2, $3, $4, '2026-08-04T07:00:00Z', 60, $5)
     returning id`,
    [leadId, teacherId, branchId, room.rows[0]!.id, managerId],
  );
  const leadLessonId = leadLesson.rows[0]!.id;
  const funding = [
    { lessonId: sourceId!, chargeType: "none" as const, chargeValue: 0 },
    {
      lessonId: cancelId!,
      chargeType: "personal_account" as const,
      chargeValue: 1000,
    },
    {
      lessonId: settleId!,
      chargeType: "personal_account" as const,
      chargeValue: 1000,
    },
  ];
  for (const item of funding) {
    const client = await pool.connect();
    try {
      await lifecycle.createSnapshot(client, {
        lessonId: item.lessonId,
        clientType: "student",
        clientId: studentId,
        completionType: "standard.success",
        clientChargeType: item.chargeType,
        clientChargeValue: item.chargeValue,
        teacherCompensationType: "fixed",
        teacherCompensationValue: 700,
        trial: false,
      });
    } finally {
      client.release();
    }
  }
  const groupClient = await pool.connect();
  try {
    await lifecycle.createGroupSnapshot(groupClient, {
      lessonId: groupSourceId,
      groupId,
      completionType: "standard.success",
      teacherCompensationType: "fixed",
      teacherCompensationValue: 700,
      trial: false,
      participants: [
        {
          studentId,
          chargeType: "personal_account",
          chargeValue: 800,
        },
        {
          studentId: secondStudentId,
          chargeType: "none",
          chargeValue: 0,
        },
      ],
    });
  } finally {
    groupClient.release();
  }
  const leadClient = await pool.connect();
  try {
    await lifecycle.createSnapshot(leadClient, {
      lessonId: leadLessonId,
      clientType: "lead",
      clientId: leadId,
      completionType: "standard.success",
      clientChargeType: "none",
      clientChargeValue: 0,
      teacherCompensationType: "fixed",
      teacherCompensationValue: 700,
      trial: true,
    });
  } finally {
    leadClient.release();
  }
  const capacityClient = await pool.connect();
  try {
    await lifecycle.createSnapshot(capacityClient, {
      lessonId: capacityId!,
      clientType: "student",
      clientId: studentId,
      completionType: "standard.success",
      clientChargeType: "subscription",
      clientChargeValue: 1,
      teacherCompensationType: "fixed",
      teacherCompensationValue: 700,
      subscriptionId,
      trial: false,
    });
    await lifecycle.createReservation(capacityClient, {
      lessonId: capacityId!,
      subscriptionId,
      units: 1,
    });
  } finally {
    capacityClient.release();
  }
  return {
    branchId,
    roomId: room.rows[0]!.id,
    replacementRoomId: replacementRoom.rows[0]!.id,
    teacherId,
    replacementTeacherId,
    studentId,
    secondStudentId,
    leadId,
    leadLessonId,
    groupId,
    groupSourceId,
    managerId,
    teacherUserId,
    clientUserId,
    replacementTeacherUserId: replacementTeacherUser.rows[0]!.id,
    userIds: [
      managerId,
      teacherUserId,
      clientUserId,
      secondClientUserId,
      replacementTeacherUser.rows[0]!.id,
    ],
    profileIds: [
      ...profiles.rows.map((row) => row.id),
      replacementTeacherProfile.rows[0]!.id,
    ],
    sourceId: sourceId!,
    cancelId: cancelId!,
    settleId: settleId!,
    capacityId: capacityId!,
    blockerId: blockerId!,
    subscriptionId,
  };
}

async function cleanup(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    await client.query(
      `delete from app.idempotency_records
       where actor_key = $1
          or (
            actor_key = 'worker:lesson-completion'
            and idempotency_key in (
              select 'lesson-settlement-complete:' || id::text
              from app.lessons where created_by = $2
              union all
              select 'lesson-settlement-review:' || id::text
              from app.lessons where created_by = $2
            )
          )`,
      [`user:${fixture.managerId}`, fixture.managerId],
    );
    await client.query(
      `delete from app.platform_outbox_events
       where (
         aggregate_type = 'schedule:lesson'
         and aggregate_id in (
           select id::text from app.lessons where created_by = $1
         )
       ) or (
         aggregate_type = 'schedule:lesson-bulk'
         and aggregate_id in (
           select entity_id from app.audit_events
           where actor_user_id = $1 and entity_type = 'lesson_batch'
         )
       )`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.aggregate_versions
       where (
         aggregate_type = 'schedule:lesson'
         and aggregate_id in (
           select id::text from app.lessons where created_by = $1
         )
       ) or (
         aggregate_type = 'schedule:lesson-bulk'
         and aggregate_id in (
           select entity_id from app.audit_events
           where actor_user_id = $1 and entity_type = 'lesson_batch'
         )
       )`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.audit_events
       where actor_user_id = $1
          or (
            action in (
              'crm.lesson_settlement_completed',
              'crm.lesson_settlement_review_required'
            )
            and entity_id in (
              select id::text from app.lessons where created_by = $1
            )
          )`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.notifications
       where data->>'entityId' in (
         select id::text from app.lessons where created_by = $1
       )`,
      [fixture.managerId],
    );
    for (const table of [
      "lesson_completion_work",
      "lesson_transitions",
      "lesson_reservations",
      "lesson_client_charge_facts",
      "lesson_teacher_compensation_facts",
      "lesson_participant_exclusions",
      "lesson_snapshot_participants",
      "lesson_snapshots",
    ]) {
      await client.query(
        `delete from app.${table}
         where lesson_id in (
           select id from app.lessons where created_by = $1
         )`,
        [fixture.managerId],
      );
    }
    for (const table of [
      "lesson_settlement_corrections",
      "lesson_settlement_plan_revisions",
      "lesson_settlement_plans",
    ]) {
      await client.query(
        `delete from app.${table}
         where lesson_id in (
           select id from app.lessons where created_by = $1
         )`,
        [fixture.managerId],
      );
    }
    await client.query("delete from app.lessons where created_by = $1", [
      fixture.managerId,
    ]);
    await client.query("delete from app.group_students where group_id = $1", [
      fixture.groupId,
    ]);
    await client.query("delete from app.groups where id = $1", [
      fixture.groupId,
    ]);
    await client.query("delete from app.subscriptions where student_id = $1", [
      fixture.studentId,
    ]);
    await client.query("delete from app.students where id = any($1::uuid[])", [
      [fixture.studentId, fixture.secondStudentId],
    ]);
    await client.query("delete from app.leads where id = $1", [fixture.leadId]);
    await client.query(
      "delete from app.teacher_availability_rules where teacher_id = any($1::uuid[])",
      [[fixture.teacherId, fixture.replacementTeacherId]],
    );
    await client.query(
      "delete from app.teacher_branches where teacher_id = any($1::uuid[])",
      [[fixture.teacherId, fixture.replacementTeacherId]],
    );
    await client.query(
      "delete from app.teacher_rates where teacher_id = any($1::uuid[])",
      [[fixture.teacherId, fixture.replacementTeacherId]],
    );
    await client.query("delete from app.teachers where id = any($1::uuid[])", [
      [fixture.teacherId, fixture.replacementTeacherId],
    ]);
    await client.query("delete from app.rooms where id = any($1::uuid[])", [
      [fixture.roomId, fixture.replacementRoomId],
    ]);
    await client.query("delete from app.staff_branch_assignments where branch_id = $1", [fixture.branchId]);
    await client.query("delete from app.user_crm_links where user_id = any($1::uuid[])", [fixture.userIds]);
    await client.query("delete from app.staff_members where profile_id = any($1::uuid[])", [fixture.profileIds]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      fixture.profileIds,
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      fixture.userIds,
    ]);
    await client.query("delete from app.branch_hours where branch_id = $1", [
      fixture.branchId,
    ]);
    await client.query("delete from app.crm_configuration_revisions where branch_id = $1", [fixture.branchId]);
    await client.query("delete from app.branches where id = $1", [
      fixture.branchId,
    ]);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}
