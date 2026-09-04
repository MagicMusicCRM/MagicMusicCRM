import { ConflictException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { RealtimeBus } from "../../realtime/realtime-bus";
import type { ConfigSnapshot } from "../crm-configuration.contracts";
import { LessonLifecycleRepository } from "../schedule/lesson-lifecycle.repository";
import type { CalculatedLessonClientFact } from "./lesson-settlement-facts.persistence";
import { LessonSettlementService } from "./lesson-settlement.service";
import { assertCorrectionSubscriptionCapacity } from "./lesson-settlement-subscription-capacity";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Lesson settlement tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Idempotent Lesson settlement (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let service: LessonSettlementService;
  let reservations: SubscriptionReservationService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    service = new LessonSettlementService(database);
    reservations = new SubscriptionReservationService(
      database,
      {} as RealtimeBus,
    );
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("keeps partial preview, result, reservation, and immutable facts on one effective share", async () => {
    const fixture = await createFixture(pool, database);
    try {
      const decision = {
        settlementTypeKey: "partially_paid_lesson",
        teacherCompensationRuleKey: "fixed",
        teacherCompensationValueMinor: "60000",
        teacherCompensationSource: "manual" as const,
        clientDecisions: [
          {
            clientId: fixture.studentId,
            chargeType: "subscription" as const,
            subscriptionId: fixture.groupSubscriptionId,
            chargeDurationMinutes: 15,
          },
          {
            clientId: fixture.secondStudentId,
            chargeType: "personal_account" as const,
            basePriceMinor: "80000",
            chargeDurationMinutes: 45,
          },
        ],
      };
      const input = {
        context: "settle" as const,
        reasonText: "Согласованы точные длительности участников",
        decision,
      };

      const preview = await database.transaction((client) =>
        service.preview(client, fixture.groupFundingLessonId, input)
      );
      expect(preview.clientFacts).toEqual(expect.arrayContaining([
        expect.objectContaining({
          clientId: fixture.studentId,
          settlementTypeKey: "partially_paid_lesson",
          hourShareBasisPoints: 2_500,
          units: "0.25",
          amountMinor: "0",
        }),
        expect.objectContaining({
          clientId: fixture.secondStudentId,
          settlementTypeKey: "partially_paid_lesson",
          hourShareBasisPoints: 7_500,
          units: "0.75",
          amountMinor: "60000",
        }),
      ]));

      const settled = await database.transaction(async (client) => {
        const result = await service.settle(
          client,
          fixture.groupFundingLessonId,
          input,
        );
        await reservations.terminalize(client, result);
        return result;
      });
      expect(settled.clientFacts).toEqual(expect.arrayContaining([
        expect.objectContaining({
          clientId: fixture.studentId,
          settlementTypeKey: "partially_paid_lesson",
          hourShareBasisPoints: 2_500,
          units: "0.25",
          amountMinor: "0",
        }),
        expect.objectContaining({
          clientId: fixture.secondStudentId,
          settlementTypeKey: "partially_paid_lesson",
          hourShareBasisPoints: 7_500,
          units: "0.75",
          amountMinor: "60000",
        }),
      ]));
      const persisted = await pool.query<{
        client_id: string;
        settlement_type_key: string;
        hour_share_basis_points: number;
        units: string;
        amount_minor: string;
      }>(
        `select client_id, settlement_type_key, hour_share_basis_points,
           units::text, amount_minor::text
         from app.lesson_client_charge_facts_effective
         where lesson_id = $1
         order by client_id`,
        [fixture.groupFundingLessonId],
      );
      expect(persisted.rows).toEqual(expect.arrayContaining([
        {
          client_id: fixture.studentId,
          settlement_type_key: "partially_paid_lesson",
          hour_share_basis_points: 2_500,
          units: "0.25",
          amount_minor: "0",
        },
        {
          client_id: fixture.secondStudentId,
          settlement_type_key: "partially_paid_lesson",
          hour_share_basis_points: 7_500,
          units: "0.75",
          amount_minor: "60000",
        },
      ]));
      const reservation = await pool.query<{ state: string; units: string }>(
        `select state, units::text from app.lesson_reservations
         where lesson_id = $1 and subscription_id = $2`,
        [fixture.groupFundingLessonId, fixture.groupSubscriptionId],
      );
      expect(reservation.rows[0]).toEqual({ state: "consumed", units: "0.25" });
      expect(decision).toMatchObject({
        settlementTypeKey: "partially_paid_lesson",
        clientDecisions: [
          { clientId: fixture.studentId, chargeDurationMinutes: 15 },
          { clientId: fixture.secondStudentId, chargeDurationMinutes: 45 },
        ],
      });

      await expect(service.settleStandalone(fixture.groupLessonId, {
        ...input,
        decision: {
          ...decision,
          clientDecisions: [
            {
              clientId: fixture.studentId,
              chargeType: "personal_account",
              basePriceMinor: "80000",
              chargeDurationMinutes: 61,
            },
            {
              clientId: fixture.secondStudentId,
              chargeType: "personal_account",
              basePriceMinor: "80000",
              chargeDurationMinutes: 30,
            },
          ],
        },
      })).rejects.toMatchObject({
        status: 422,
        response: { code: "PARTIAL_DURATION_EXCEEDS_LESSON" },
      });
      const invalidFacts = await pool.query<{ count: number }>(
        `select count(*)::int as count from app.lesson_client_charge_facts
         where lesson_id = $1`,
        [fixture.groupLessonId],
      );
      expect(invalidFacts.rows[0]?.count).toBe(0);
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("persists personal-account payer pricing, replays exactly and transfers only effective debits on correction", async () => {
    const fixture = await createFixture(pool, database);
    try {
      const decision = {
        settlementTypeKey: "lesson", teacherCompensationRuleKey: "standard",
        teacherCompensationSource: "automatic" as const,
        clientDecisions: [{ clientId: fixture.studentId, payerStudentId: fixture.secondStudentId,
          chargeType: "personal_account" as const, basePriceMinor: "100001",
          discount: { type: "percent" as const, percent: 10, reason: "Скидка" },
          surcharge: { amountMinor: "1999", reason: "Доплата" } }],
      };
      await database.transaction(async (client) => {
        const plan = await service.preparePlan(client, fixture.branchId, decision);
        expect(await service.plannedSubscriptionAllocations(client, fixture.subscriptionLessonId, plan)).toEqual([]);
        const first = await service.settle(client, fixture.subscriptionLessonId, { context: "settle", decision });
        await reservations.terminalize(client, first);
        expect(first.clientFact).toMatchObject({ clientId: fixture.studentId, payerStudentId: fixture.secondStudentId,
          chargeType: "personal_account", subscriptionId: null, amountMinor: "92000", snapshotValue: "920.00",
          pricingSnapshot: { basePriceMinor: "100001", finalPriceMinor: "92000" } });
        expect(await service.settle(client, fixture.subscriptionLessonId, { context: "settle", decision })).toEqual(first);
        const balances = await client.query("select student_id, balance_minor::text from app.commerce_student_account_projection where student_id = any($1::uuid[])", [[fixture.studentId, fixture.secondStudentId]]);
        expect(balances.rows).toContainEqual({ student_id: fixture.secondStudentId, balance_minor: "-92000" });
        expect(balances.rows.some((row) => row.student_id === fixture.studentId && row.balance_minor !== "0")).toBe(false);
      });
      await expect(service.settleStandalone(fixture.subscriptionLessonId, { context: "settle", decision: { ...decision, clientDecisions: [{ ...decision.clientDecisions[0]!, basePriceMinor: "110001" }] } })).rejects.toMatchObject({ response: { code: "LESSON_ALREADY_SETTLED_WITH_DIFFERENT_DECISION" } });
      const connection = await pool.connect();
      try {
        await connection.query("begin");
        const corrected = {
          ...decision,
          teacherCompensationSource: "manual" as const,
          clientDecisions: [{ clientId: fixture.studentId, payerStudentId: fixture.studentId, chargeType: "personal_account" as const, basePriceMinor: "50000" }],
        };
        const plan = await service.preparePlan(connection, fixture.branchId, corrected);
        const correctionId = randomUUID();
        await connection.query("insert into app.lesson_settlement_corrections (id, lesson_id, version, decision, settlement_revision_id, compensation_revision_id, reason_text, actor_user_id) values ($1,$2,1,$3::jsonb,$4,$5,'Исправление плательщика',$6)", [correctionId, fixture.subscriptionLessonId, JSON.stringify(corrected), plan.settlementRevisionId, plan.compensationRevisionId, fixture.managerId]);
        const result = await service.settle(connection, fixture.subscriptionLessonId, { context: "settle", decision: corrected, correction: { id: correctionId } });
        expect(result.clientFact).toMatchObject({ payerStudentId: fixture.studentId, amountMinor: "50000" });
        expect(result.teacherFact).toMatchObject({
          compensationOverrideReason: null,
          compensationSource: "manual",
        });
        expect(result.teacherFact.compensationActualValue)
          .toBe(result.teacherFact.compensationDefaultValue);
        const balances = await connection.query("select student_id, balance_minor::text from app.commerce_student_account_projection where student_id = any($1::uuid[])", [[fixture.studentId, fixture.secondStudentId]]);
        expect(balances.rows).toContainEqual({ student_id: fixture.studentId, balance_minor: "-50000" });
        expect(balances.rows.some((row) => row.student_id === fixture.secondStudentId && row.balance_minor !== "0")).toBe(false);
        const history = await connection.query("select count(*)::int as count from app.lesson_client_charge_facts where lesson_id=$1", [fixture.subscriptionLessonId]);
        expect(history.rows[0].count).toBe(2);
        const teacherHistory = await connection.query(
          `select compensation_source, supersedes_fact_id is not null as supersedes
           from app.lesson_teacher_compensation_facts
           where lesson_id = $1 order by created_at, id`,
          [fixture.subscriptionLessonId],
        );
        expect(teacherHistory.rows).toEqual([
          { compensation_source: "automatic", supersedes: false },
          { compensation_source: "manual", supersedes: true },
        ]);
      } finally { await connection.query("rollback"); connection.release(); }
    } finally { await cleanupFixture(pool, fixture); }
  });

  it("creates one stable pair under concurrency and supports fixed/hourly/none", async () => {
    const fixture = await createFixture(pool, database);
    try {
      const parallel = await Promise.all(
        Array.from({ length: 12 }, () =>
          service.settleStandalone(fixture.fixedLessonId),
        ),
      );
      for (const result of parallel) expect(result).toEqual(parallel[0]);
      expect(parallel[0]).toMatchObject({
        lessonId: fixture.fixedLessonId,
        clientFact: {
          clientType: "student",
          clientId: fixture.studentId,
          chargeType: "personal_account",
          snapshotValue: "1234.56",
          subscriptionId: null,
          amountMinor: "123456",
          units: "0.00",
          currencyCode: "RUB",
        },
        teacherFact: {
          teacherId: fixture.teacherId,
          compensationType: "fixed",
          snapshotRate: "700.00",
          rateMinor: "70000",
          durationMinutes: 60,
          amountMinor: "70000",
          currencyCode: "RUB",
        },
      });
      const counts = await pool.query<{
        client_count: number;
        teacher_count: number;
      }>(
        `
          select
            (
              select count(*)::int
              from app.lesson_client_charge_facts
              where lesson_id = $1
            ) as client_count,
            (
              select count(*)::int
              from app.lesson_teacher_compensation_facts
              where lesson_id = $1
            ) as teacher_count
        `,
        [fixture.fixedLessonId],
      );
      expect(counts.rows[0]).toEqual({
        client_count: 1,
        teacher_count: 1,
      });

      const hourly = await service.settleStandalone(fixture.hourlyLessonId);
      expect(hourly.teacherFact).toMatchObject({
        compensationType: "hourly",
        snapshotRate: "1000.01",
        rateMinor: "100001",
        durationMinutes: 45,
        amountMinor: "75001",
      });
      expect(hourly.clientFact).toMatchObject({
        chargeType: "none",
        amountMinor: "0",
        units: "0.00",
      });

      const none = await service.settleStandalone(fixture.noneLessonId);
      expect(none.teacherFact).toMatchObject({
        compensationType: "none",
        snapshotRate: "0.00",
        rateMinor: "0",
        durationMinutes: 90,
        amountMinor: "0",
      });
      expect(none.clientFact).toMatchObject({
        chargeType: "none",
        snapshotValue: "0.00",
        amountMinor: "0",
        units: "0.00",
      });

      await expect(
        pool.query(
          `
            update app.lesson_teacher_compensation_facts
            set amount_minor = amount_minor + 1
            where lesson_id = $1
          `,
          [fixture.fixedLessonId],
        ),
      ).rejects.toMatchObject({ code: "23514" });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("rejects non-completed Lessons without creating a partial fact", async () => {
    const fixture = await createFixture(pool, database, true);
    try {
      await expect(
        service.settleStandalone(fixture.fixedLessonId),
      ).rejects.toBeInstanceOf(ConflictException);
      const counts = await pool.query<{ count: number }>(
        `
          select (
            select count(*) from app.lesson_client_charge_facts
            where lesson_id = $1
          ) + (
            select count(*) from app.lesson_teacher_compensation_facts
            where lesson_id = $1
          ) as count
        `,
        [fixture.fixedLessonId],
      );
      expect(Number(counts.rows[0]?.count)).toBe(0);
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("creates one client fact per frozen group participant and one teacher fact", async () => {
    const fixture = await createFixture(pool, database);
    try {
      const parallel = await Promise.all(
        Array.from({ length: 8 }, () =>
          service.settleStandalone(fixture.groupLessonId),
        ),
      );
      for (const result of parallel) expect(result).toEqual(parallel[0]);
      expect(parallel[0]!.clientFacts).toHaveLength(2);
      expect(
        parallel[0]!.clientFacts.map((fact) => fact.clientId).sort(),
      ).toEqual([fixture.studentId, fixture.secondStudentId].sort());
      expect(
        parallel[0]!.clientFacts.every(
          (fact) =>
            fact.chargeType === "personal_account" &&
            fact.amountMinor === "80000",
        ),
      ).toBe(true);
      expect(parallel[0]!.teacherFact).toMatchObject({
        teacherId: fixture.teacherId,
        compensationType: "fixed",
        amountMinor: "90000",
      });
      const counts = await pool.query<{
        client_count: number;
        teacher_count: number;
      }>(
        `
        select
          (select count(*)::int from app.lesson_client_charge_facts where lesson_id = $1) as client_count,
          (select count(*)::int from app.lesson_teacher_compensation_facts where lesson_id = $1) as teacher_count
      `,
        [fixture.groupLessonId],
      );
      expect(counts.rows[0]).toEqual({ client_count: 2, teacher_count: 1 });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("uses another student's subscription without moving the lesson or teacher fact", async () => {
    const fixture = await createFixture(pool, database);
    try {
      const input = {
        context: "settle" as const,
        decision: {
          settlementTypeKey: "free_lesson",
          clientDecisions: [
            {
              clientId: fixture.secondStudentId,
              settlementTypeKey: "lesson",
              payerStudentId: fixture.studentId,
              subscriptionId: fixture.groupSubscriptionId,
            },
          ],
          teacherCompensationRuleKey: "standard",
        },
      } as unknown as NonNullable<
        Parameters<LessonSettlementService["settleStandalone"]>[1]
      >;

      const plannedAllocations = await database.transaction(async (client) => {
        const plan = await service.preparePlan(
          client,
          fixture.branchId,
          input.decision,
        );
        const allocations = await service.plannedSubscriptionAllocations(
          client,
          fixture.groupLessonId,
          plan,
        );
        for (const allocation of allocations) {
          await reservations.allocate(client, {
            lessonId: fixture.groupLessonId,
            chargeType: "subscription",
            ...allocation,
          });
        }
        return allocations;
      });
      expect(plannedAllocations).toEqual([
        {
          clientType: "student",
          clientId: fixture.secondStudentId,
          payerStudentId: fixture.studentId,
          subscriptionId: fixture.groupSubscriptionId,
          units: 1,
        },
      ]);

      const settled = await database.transaction(async (client) => {
        const result = await service.settle(
          client,
          fixture.groupLessonId,
          input,
        );
        await reservations.terminalize(client, result);
        return result;
      });
      await expect(
        service.settleStandalone(fixture.groupLessonId, input),
      ).resolves.toEqual(settled);
      await expect(
        service.settleStandalone(fixture.groupLessonId, {
          ...input,
          decision: {
            ...input.decision,
            clientDecisions: input.decision.clientDecisions!.map(
              (decision) => ({
                ...decision,
                payerStudentId: fixture.secondStudentId,
              }),
            ),
          },
        }),
      ).rejects.toMatchObject({
        response: { code: "SUBSCRIPTION_CAPACITY" },
      });

      expect(
        settled.clientFacts.find(
          (fact) => fact.clientId === fixture.secondStudentId,
        ),
      ).toMatchObject({
        chargeType: "subscription",
        subscriptionId: fixture.groupSubscriptionId,
        amountMinor: "0",
        units: "1.00",
      });
      expect(
        settled.clientFacts.find((fact) => fact.clientId === fixture.studentId),
      ).toMatchObject({
        chargeType: "personal_account",
        amountMinor: "0",
        units: "0.00",
      });
      expect(settled.teacherFact).toMatchObject({
        teacherId: fixture.teacherId,
        compensationRuleKey: "standard",
        amountMinor: "90000",
      });

      const persisted = await pool.query<{
        client_count: number;
        teacher_count: number;
        unexpected_teacher_count: number;
        consumed_count: number;
      }>(
        `select
           (select count(*)::int from app.lesson_client_charge_facts_effective
             where lesson_id = $1) as client_count,
           (select count(*)::int from app.lesson_teacher_compensation_facts_effective
             where lesson_id = $1) as teacher_count,
           (select count(*)::int from app.lesson_teacher_compensation_facts_effective
             where lesson_id = $1 and teacher_id <> $2) as unexpected_teacher_count,
           (select count(*)::int from app.lesson_reservations
             where lesson_id = $1 and subscription_id = $3
               and state = 'consumed') as consumed_count`,
        [
          fixture.groupLessonId,
          fixture.teacherId,
          fixture.groupSubscriptionId,
        ],
      );
      expect(persisted.rows[0]).toEqual({
        client_count: 2,
        teacher_count: 1,
        unexpected_teacher_count: 0,
        consumed_count: 1,
      });

      const realtime = {
        emitCrmChanged: jest.fn(),
        emitFinanceChanged: jest.fn(),
      };
      await new SubscriptionReservationService(
        database,
        realtime as unknown as RealtimeBus,
      ).publishLessonSettlementPostCommit(fixture.groupLessonId);
      expect(realtime.emitFinanceChanged).toHaveBeenCalledWith(
        expect.arrayContaining(fixture.clientUserIds),
      );
      expect(realtime.emitFinanceChanged.mock.calls[0]?.[0]).toHaveLength(2);
      expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
        entity: "subscription",
        action: "updated",
        id: fixture.groupSubscriptionId,
        affectedUserIds: expect.arrayContaining(fixture.clientUserIds),
      });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("requires the original cross-payer decision on idempotent retry", async () => {
    const fixture = await createFixture(pool, database);
    try {
      const input = {
        context: "settle" as const,
        decision: {
          settlementTypeKey: "lesson",
          clientDecisions: [
            {
              clientId: fixture.secondStudentId,
              settlementTypeKey: "lesson",
              payerStudentId: fixture.studentId,
              subscriptionId: fixture.groupSubscriptionId,
            },
          ],
          teacherCompensationRuleKey: "standard",
        },
      } as unknown as NonNullable<
        Parameters<LessonSettlementService["settleStandalone"]>[1]
      >;
      const settled = await service.settleStandalone(
        fixture.groupLessonId,
        input,
      );
      await expect(
        service.settleStandalone(fixture.groupLessonId, input),
      ).resolves.toEqual(settled);

      const retries = await Promise.allSettled([
        service.settleStandalone(fixture.groupLessonId, {
          ...input,
          decision: { ...input.decision, clientDecisions: [] },
        }),
        service.settleStandalone(fixture.groupLessonId, {
          ...input,
          decision: {
            settlementTypeKey: input.decision.settlementTypeKey,
            teacherCompensationRuleKey:
              input.decision.teacherCompensationRuleKey,
          },
        }),
      ]);
      for (const retry of retries) {
        expect(retry).toMatchObject({
          status: "rejected",
          reason: {
            response: {
              code: "LESSON_ALREADY_SETTLED_WITH_DIFFERENT_DECISION",
            },
          },
        });
      }
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("uses lesson-local date for an expired-now subscription that covered a historical lesson", async () => {
    const fixture = await createFixture(pool, database, false, {
      startsAt: "2026-07-01",
      expiresAt: "2026-07-31",
    });
    try {
      await expect(
        database.transaction((client) =>
          assertCorrectionSubscriptionCapacity(
            client,
            fixture.groupLessonId,
            [crossPayerCapacityFact(fixture)],
          ),
        ),
      ).resolves.toBeUndefined();

      const settled = await service.settleStandalone(fixture.groupLessonId, {
        context: "settle",
        decision: crossPayerDecision(fixture),
      });
      expect(
        settled.clientFacts.find(
          (fact) => fact.clientId === fixture.secondStudentId,
        ),
      ).toMatchObject({
        subscriptionId: fixture.groupSubscriptionId,
        units: "1.00",
      });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("rejects a subscription that became valid only after the historical lesson", async () => {
    const fixture = await createFixture(pool, database, false, {
      startsAt: "2026-08-01",
      expiresAt: "2099-12-31",
    });
    try {
      await expect(
        database.transaction((client) =>
          assertCorrectionSubscriptionCapacity(
            client,
            fixture.groupLessonId,
            [crossPayerCapacityFact(fixture)],
          ),
        ),
      ).rejects.toMatchObject({
        response: { code: "SUBSCRIPTION_CAPACITY" },
      });
      await expect(
        service.settleStandalone(fixture.groupLessonId, {
          context: "settle",
          decision: crossPayerDecision(fixture),
        }),
      ).rejects.toMatchObject({
        response: { code: "SUBSCRIPTION_CAPACITY" },
      });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("rejects a selected payer subscription when the actual recipient is outside the lesson branch", async () => {
    const fixture = await createFixture(pool, database);
    const foreignBranch = await pool.query<{ id: string }>(
      `insert into app.branches (name, timezone_name)
       values ($1, 'Europe/Moscow') returning id`,
      [`Settlement foreign ${randomUUID()}`],
    );
    const foreignBranchId = foreignBranch.rows[0]!.id;
    try {
      await pool.query("update app.students set branch_id = $2 where id = $1", [
        fixture.secondStudentId,
        foreignBranchId,
      ]);
      const decision = {
        settlementTypeKey: "free_lesson",
        clientDecisions: [
          {
            clientId: fixture.secondStudentId,
            settlementTypeKey: "lesson",
            payerStudentId: fixture.studentId,
            subscriptionId: fixture.groupSubscriptionId,
          },
        ],
        teacherCompensationRuleKey: "standard",
      };
      await expect(
        database.transaction(async (client) => {
          const plan = await service.preparePlan(
            client,
            fixture.branchId,
            decision,
          );
          const allocations = await service.plannedSubscriptionAllocations(
            client,
            fixture.groupLessonId,
            plan,
          );
          for (const allocation of allocations) {
            await reservations.allocate(client, {
              lessonId: fixture.groupLessonId,
              chargeType: "subscription",
              ...allocation,
            });
          }
        }),
      ).rejects.toMatchObject({
        response: {
          code: "LESSON_CONSTRAINT_VIOLATIONS",
          violations: [
            expect.objectContaining({ code: "SUBSCRIPTION_CAPACITY" }),
          ],
        },
      });
      await expect(
        service.settleStandalone(fixture.groupLessonId, {
          context: "settle",
          decision,
        }),
      ).rejects.toMatchObject({
        response: { code: "SUBSCRIPTION_CAPACITY" },
      });
      const persisted = await pool.query<{ count: number }>(
        `select count(*)::int as count
         from app.lesson_client_charge_facts where lesson_id = $1`,
        [fixture.groupLessonId],
      );
      expect(persisted.rows[0]?.count).toBe(0);
    } finally {
      await pool.query("update app.students set branch_id = $2 where id = $1", [
        fixture.secondStudentId,
        fixture.branchId,
      ]);
      await pool.query("delete from app.branches where id = $1", [
        foreignBranchId,
      ]);
      await cleanupFixture(pool, fixture);
    }
  });

  it("rejects a subscription that is not owned by the explicit payer", async () => {
    const fixture = await createFixture(pool, database);
    try {
      await expect(
        service.settleStandalone(fixture.groupLessonId, {
          context: "settle",
          decision: {
            settlementTypeKey: "free_lesson",
            clientDecisions: [
              {
                clientId: fixture.secondStudentId,
                settlementTypeKey: "lesson",
                payerStudentId: fixture.secondStudentId,
                subscriptionId: fixture.groupSubscriptionId,
              },
            ],
            teacherCompensationRuleKey: "standard",
          },
        }),
      ).rejects.toMatchObject({
        response: { code: "SUBSCRIPTION_CAPACITY" },
      });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("ignores an archived participant in group settlement and on idempotent retry", async () => {
    const fixture = await createFixture(pool, database);
    try {
      await pool.query(
        `insert into app.lesson_participant_exclusions (
           lesson_id, student_id, reason_code, actor_user_id
         ) values ($1, $2, 'client.archive:test', $3)`,
        [fixture.groupLessonId, fixture.studentId, fixture.managerId],
      );
      const input = {
        context: "settle" as const,
        decision: {
          settlementTypeKey: "lesson",
          clientDecisions: [
            {
              clientId: fixture.studentId,
              settlementTypeKey: "free_lesson",
            },
            {
              clientId: fixture.secondStudentId,
              settlementTypeKey: "lesson",
            },
          ],
          teacherCompensationRuleKey: "fixed",
        },
      };

      const settled = await service.settleStandalone(
        fixture.groupLessonId,
        input,
      );
      expect(settled.clientFacts).toHaveLength(1);
      expect(settled.clientFacts[0]?.clientId).toBe(fixture.secondStudentId);
      expect(settled.clientFacts[0]?.settlementTypeKey).toBe("lesson");
      await expect(
        service.settleStandalone(fixture.groupLessonId, input),
      ).resolves.toEqual(settled);
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("persists the 0-200%/penalty/group decision and keeps its catalog snapshot", async () => {
    const fixture = await createFixture(pool, database);
    try {
      await publishBranchCatalog(pool, fixture, 1, (snapshot) => ({
        ...snapshot,
        lessonSettlementTypes: snapshot.lessonSettlementTypes.map((type) =>
          type.stableKey === "penalty_lesson"
            ? {
                ...type,
                label: "Двойное занятие со штрафом",
                colorToken: "violet",
                hourShareBasisPoints: 20_000,
                fixedPenaltyMinor: "250",
              }
            : type,
        ),
      }));

      await pool.query(
        `insert into app.lesson_reservations (lesson_id, subscription_id, units)
         values ($1, $2, 18.5)`,
        [fixture.groupLessonId, fixture.subscriptionId],
      );
      await expect(
        service.settleStandalone(fixture.subscriptionLessonId, {
          context: "settle",
          decision: {
            settlementTypeKey: "penalty_lesson",
            teacherCompensationRuleKey: "percent",
          },
        }),
      ).rejects.toMatchObject({
        response: { code: "SUBSCRIPTION_CAPACITY" },
      });
      const rolledBack = await pool.query<{ count: number; units: string }>(
        `select
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = $1) as count,
           (select units::text from app.lesson_reservations
             where lesson_id = $1) as units`,
        [fixture.subscriptionLessonId],
      );
      expect(rolledBack.rows[0]).toEqual({ count: 0, units: "1.00" });
      await pool.query(
        `update app.lesson_reservations set state = 'released'
         where lesson_id = $1 and subscription_id = $2`,
        [fixture.groupLessonId, fixture.subscriptionId],
      );

      const penaltyRuns = await Promise.all(
        Array.from({ length: 8 }, () =>
          service.settleStandalone(fixture.subscriptionLessonId, {
            context: "settle",
            decision: {
              settlementTypeKey: "penalty_lesson",
              teacherCompensationRuleKey: "percent",
            },
          }),
        ),
      );
      const penalty = penaltyRuns[0]!;
      for (const result of penaltyRuns) expect(result).toEqual(penalty);
      expect(penalty.clientFact).toMatchObject({
        settlementTypeKey: "penalty_lesson",
        settlementLabel: "Двойное занятие со штрафом",
        settlementColorToken: "violet",
        hourShareBasisPoints: 20_000,
        fixedPenaltyMinor: "250",
        units: "2.00",
        amountMinor: "250",
        chargeType: "subscription",
        subscriptionId: fixture.subscriptionId,
      });
      expect(penalty.teacherFact).toMatchObject({
        compensationRuleKey: "percent",
        compensationRuleLabel: "Процент ставки",
        compensationMode: "percent",
        compensationDefaultValue: "70000",
        compensationActualValue: "10000",
        amountMinor: "70000",
      });
      const reservation = await pool.query<{ units: string }>(
        "select units::text from app.lesson_reservations where lesson_id = $1",
        [fixture.subscriptionLessonId],
      );
      expect(reservation.rows[0]?.units).toBe("2.00");

      const groupDecision = {
        context: "settle" as const,
        reasonText: "Согласованная ставка за групповое занятие",
        decision: {
          settlementTypeKey: "partially_paid_lesson",
          clientDecisions: [
            {
              clientId: fixture.studentId,
              settlementTypeKey: "lesson",
            },
          ],
          teacherCompensationRuleKey: "fixed",
          teacherCompensationValueMinor: "60000",
        },
      };
      const groupTransition = await database.transaction(async (client) => {
        const before = await reservations.lockSettlementCoverage(
          client,
          fixture.groupFundingLessonId,
        );
        const settled = await service.settle(
          client,
          fixture.groupFundingLessonId,
          groupDecision,
        );
        await reservations.terminalize(client, settled);
        const after = await reservations.lockSettlementCoverage(
          client,
          fixture.groupFundingLessonId,
        );
        return { before, settled, after };
      });
      const group = groupTransition.settled;
      expect(groupTransition.before.reservations).toEqual([
        expect.objectContaining({
          subscriptionId: fixture.groupSubscriptionId,
          state: "reserved",
          units: "1.00",
        }),
      ]);
      expect(groupTransition.before.subscriptions).toEqual([
        expect.objectContaining({
          id: fixture.groupSubscriptionId,
          settledUnits: "0",
          reservedUnits: "1.00",
        }),
      ]);
      expect(groupTransition.after.reservations).toEqual([
        expect.objectContaining({
          subscriptionId: fixture.groupSubscriptionId,
          state: "consumed",
          units: "1.00",
        }),
      ]);
      expect(groupTransition.after.subscriptions).toEqual([
        expect.objectContaining({
          id: fixture.groupSubscriptionId,
          settledUnits: "1.00",
          reservedUnits: "0",
        }),
      ]);
      const groupRuns = await Promise.all(
        Array.from({ length: 8 }, () =>
          service.settleStandalone(fixture.groupFundingLessonId, groupDecision),
        ),
      );
      for (const result of groupRuns) expect(result).toEqual(group);
      expect(group.clientFacts).toHaveLength(2);
      expect(
        group.clientFacts.find((fact) => fact.clientId === fixture.studentId),
      ).toMatchObject({
        settlementTypeKey: "lesson",
        settlementLabel: "Занятие",
        settlementColorToken: "success",
        hourShareBasisPoints: 10_000,
        units: "1.00",
        amountMinor: "0",
        chargeType: "subscription",
        subscriptionId: fixture.groupSubscriptionId,
        configurationRevisionId: expect.any(String),
      });
      expect(
        group.clientFacts.find(
          (fact) => fact.clientId === fixture.secondStudentId,
        ),
      ).toMatchObject({
        settlementTypeKey: "partially_paid_lesson",
        settlementLabel: "Частично оплачиваемое занятие",
        settlementColorToken: "info",
        hourShareBasisPoints: 5_000,
        units: "0.50",
        amountMinor: "40000",
        configurationRevisionId: expect.any(String),
      });
      expect(group.teacherFact).toMatchObject({
        compensationRuleKey: "fixed",
        compensationRuleLabel: "Фиксированная сумма",
        compensationMode: "fixed",
        compensationActualValue: "60000",
        compensationOverrideReason: "Согласованная ставка за групповое занятие",
        amountMinor: "60000",
        configurationRevisionId: expect.any(String),
      });
      const persistedGroup = await pool.query<{
        client_count: number;
        teacher_count: number;
        settlements: string[];
        consumed_reservations: number;
      }>(
        `select
           (select count(*)::int from app.lesson_client_charge_facts_effective
              where lesson_id = $1) as client_count,
           (select count(*)::int from app.lesson_teacher_compensation_facts_effective
              where lesson_id = $1) as teacher_count,
           (select array_agg(settlement_type_key order by client_id)
              from app.lesson_client_charge_facts_effective
              where lesson_id = $1) as settlements,
           (select count(*)::int from app.lesson_reservations
              where lesson_id = $1 and state = 'consumed') as consumed_reservations`,
        [fixture.groupFundingLessonId],
      );
      expect(persistedGroup.rows[0]).toEqual({
        client_count: 2,
        teacher_count: 1,
        settlements: expect.arrayContaining([
          "lesson",
          "partially_paid_lesson",
        ]),
        consumed_reservations: 1,
      });

      const free = await service.settleStandalone(fixture.hourlyLessonId, {
        context: "settle",
        decision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "standard",
        },
      });
      expect(free.clientFact).toMatchObject({
        settlementTypeKey: "free_lesson",
        hourShareBasisPoints: 0,
        units: "0.00",
        amountMinor: "0",
      });
      expect(free.teacherFact).toMatchObject({
        compensationRuleKey: "standard",
        compensationDefaultValue: "75001",
        compensationActualValue: "75001",
        amountMinor: "75001",
      });

      await pool.query(
        `insert into app.lesson_reservations (lesson_id, subscription_id, units)
         values ($1, $2, 1)`,
        [fixture.noneLessonId, fixture.subscriptionId],
      );
      const zeroSubscription = await service.settleStandalone(
        fixture.noneLessonId,
        {
          context: "settle",
          decision: {
            settlementTypeKey: "free_lesson",
            clientDecisions: [
              {
                clientId: fixture.studentId,
                subscriptionId: fixture.subscriptionId,
              },
            ],
            teacherCompensationRuleKey: "none",
          },
        },
      );
      expect(zeroSubscription.clientFact).toMatchObject({
        chargeType: "subscription",
        units: "0.00",
        amountMinor: "0",
      });
      await database.transaction((client) =>
        reservations.terminalize(client, zeroSubscription),
      );
      const released = await pool.query<{ state: string }>(
        `select state from app.lesson_reservations
         where lesson_id = $1 and subscription_id = $2`,
        [fixture.noneLessonId, fixture.subscriptionId],
      );
      expect(released.rows[0]?.state).toBe("released");

      await publishBranchCatalog(pool, fixture, 2, (snapshot) => ({
        ...snapshot,
        lessonSettlementTypes: snapshot.lessonSettlementTypes.map((type) =>
          type.stableKey === "penalty_lesson"
            ? { ...type, label: "Новое название", colorToken: "danger" }
            : type,
        ),
        teacherCompensationRules: snapshot.teacherCompensationRules.map(
          (rule) =>
            rule.stableKey === "percent"
              ? { ...rule, label: "Новый процент", value: "5000" }
              : rule,
        ),
      }));
      const replay = await service.settleStandalone(
        fixture.subscriptionLessonId,
        {
          context: "settle",
          decision: {
            settlementTypeKey: "penalty_lesson",
            teacherCompensationRuleKey: "percent",
          },
        },
      );
      expect(replay).toEqual(penalty);
      expect(replay.clientFact.settlementLabel).toBe(
        "Двойное занятие со штрафом",
      );
      expect(replay.teacherFact.compensationRuleLabel).toBe("Процент ставки");
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("persists all five teacher pay rules and requires a reason for manual override", async () => {
    const fixture = await createFixture(pool, database);
    try {
      await publishBranchCatalog(pool, fixture, 1, (snapshot) => ({
        ...snapshot,
        teacherCompensationRules: snapshot.teacherCompensationRules.map(
          (rule) => {
            if (rule.stableKey === "percent") {
              return { ...rule, value: "6250" };
            }
            if (rule.stableKey === "fixed") {
              return { ...rule, value: "85000" };
            }
            if (rule.stableKey === "hourly") {
              return { ...rule, value: "120000" };
            }
            return rule;
          },
        ),
      }));

      await expect(
        service.settleStandalone(fixture.fixedLessonId, {
          context: "settle",
          decision: {
            settlementTypeKey: "lesson",
            teacherCompensationRuleKey: "fixed",
            teacherCompensationValueMinor: "95000",
          },
        }),
      ).rejects.toMatchObject({
        response: { code: "TEACHER_OVERRIDE_REASON_REQUIRED" },
      });
      const rejectedCounts = await pool.query<{
        client_count: number;
        teacher_count: number;
      }>(
        `select
           (select count(*)::int from app.lesson_client_charge_facts
              where lesson_id = $1) as client_count,
           (select count(*)::int from app.lesson_teacher_compensation_facts
              where lesson_id = $1) as teacher_count`,
        [fixture.fixedLessonId],
      );
      expect(rejectedCounts.rows[0]).toEqual({
        client_count: 0,
        teacher_count: 0,
      });

      const results = await Promise.all([
        service.settleStandalone(fixture.noneLessonId, {
          context: "settle",
          decision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "none",
          },
        }),
        service.settleStandalone(fixture.hourlyLessonId, {
          context: "settle",
          decision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "standard",
          },
        }),
        service.settleStandalone(fixture.subscriptionLessonId, {
          context: "settle",
          decision: {
            settlementTypeKey: "lesson",
            teacherCompensationRuleKey: "percent",
          },
        }),
        service.settleStandalone(fixture.fixedLessonId, {
          context: "settle",
          reasonText: "Индивидуальная ставка согласована директором",
          decision: {
            settlementTypeKey: "lesson",
            teacherCompensationRuleKey: "fixed",
            teacherCompensationValueMinor: "95000",
          },
        }),
        service.settleStandalone(fixture.groupLessonId, {
          context: "settle",
          decision: {
            settlementTypeKey: "lesson",
            teacherCompensationRuleKey: "hourly",
          },
        }),
      ]);

      expect(results.map((result) => result.teacherFact)).toEqual([
        expect.objectContaining({
          compensationRuleKey: "none",
          compensationMode: "none",
          compensationDefaultValue: "0",
          compensationActualValue: "0",
          amountMinor: "0",
          compensationOverrideReason: null,
        }),
        expect.objectContaining({
          compensationRuleKey: "standard",
          compensationMode: "standard",
          compensationDefaultValue: "75001",
          compensationActualValue: "75001",
          amountMinor: "75001",
          compensationOverrideReason: null,
        }),
        expect.objectContaining({
          compensationRuleKey: "percent",
          compensationMode: "percent",
          compensationDefaultValue: "70000",
          compensationActualValue: "6250",
          amountMinor: "43750",
          compensationOverrideReason: null,
        }),
        expect.objectContaining({
          compensationRuleKey: "fixed",
          compensationMode: "fixed",
          compensationDefaultValue: "85000",
          compensationActualValue: "95000",
          amountMinor: "95000",
          compensationOverrideReason:
            "Индивидуальная ставка согласована директором",
        }),
        expect.objectContaining({
          compensationRuleKey: "hourly",
          compensationMode: "hourly",
          compensationDefaultValue: "120000",
          compensationActualValue: "120000",
          amountMinor: "120000",
          compensationOverrideReason: null,
        }),
      ]);

      const persisted = await pool.query<{
        lesson_id: string;
        compensation_rule_key: string;
        compensation_rule_label: string;
        compensation_mode: string;
        compensation_default_value: string;
        compensation_actual_value: string;
        compensation_override_reason: string | null;
        amount_minor: string;
      }>(
        `select lesson_id, compensation_rule_key, compensation_rule_label,
           compensation_mode, compensation_default_value::text,
           compensation_actual_value::text, compensation_override_reason,
           amount_minor::text
         from app.lesson_teacher_compensation_facts_effective
         where lesson_id = any($1::uuid[])
         order by compensation_rule_key`,
        [fixture.lessonIds],
      );
      expect(persisted.rows).toEqual([
        {
          lesson_id: fixture.fixedLessonId,
          compensation_rule_key: "fixed",
          compensation_rule_label: "Фиксированная сумма",
          compensation_mode: "fixed",
          compensation_default_value: "85000",
          compensation_actual_value: "95000",
          compensation_override_reason:
            "Индивидуальная ставка согласована директором",
          amount_minor: "95000",
        },
        {
          lesson_id: fixture.groupLessonId,
          compensation_rule_key: "hourly",
          compensation_rule_label: "Почасовая сумма",
          compensation_mode: "hourly",
          compensation_default_value: "120000",
          compensation_actual_value: "120000",
          compensation_override_reason: null,
          amount_minor: "120000",
        },
        {
          lesson_id: fixture.noneLessonId,
          compensation_rule_key: "none",
          compensation_rule_label: "Не оплачивать",
          compensation_mode: "none",
          compensation_default_value: "0",
          compensation_actual_value: "0",
          compensation_override_reason: null,
          amount_minor: "0",
        },
        {
          lesson_id: fixture.subscriptionLessonId,
          compensation_rule_key: "percent",
          compensation_rule_label: "Процент ставки",
          compensation_mode: "percent",
          compensation_default_value: "70000",
          compensation_actual_value: "6250",
          compensation_override_reason: null,
          amount_minor: "43750",
        },
        {
          lesson_id: fixture.hourlyLessonId,
          compensation_rule_key: "standard",
          compensation_rule_label: "Полная стандартная ставка",
          compensation_mode: "standard",
          compensation_default_value: "75001",
          compensation_actual_value: "75001",
          compensation_override_reason: null,
          amount_minor: "75001",
        },
      ]);
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });
});

async function publishBranchCatalog(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
  version: number,
  mutate: (snapshot: ConfigSnapshot) => ConfigSnapshot,
) {
  const school = await pool.query<{ effective_snapshot: ConfigSnapshot }>(
    `select effective_snapshot from app.crm_configuration_revisions
     where branch_id is null order by version desc limit 1`,
  );
  const snapshot = mutate(school.rows[0]!.effective_snapshot);
  const patch = {
    lessonSettlementTypes: snapshot.lessonSettlementTypes,
    teacherCompensationRules: snapshot.teacherCompensationRules,
  };
  await pool.query(
    `insert into app.crm_configuration_revisions (
       branch_id, version, patch, effective_snapshot, impact, reason, created_by
     ) values ($1, $2, $3::jsonb, $4::jsonb, '{}'::jsonb, $5, $6)`,
    [
      fixture.branchId,
      version,
      JSON.stringify(patch),
      JSON.stringify(snapshot),
      `Settlement catalog test v${version}`,
      fixture.managerId,
    ],
  );
}

async function createFixture(
  pool: Pool,
  database: DatabaseService,
  scheduled = false,
  groupSubscriptionDates: {
    startsAt?: string;
    expiresAt?: string;
  } = {},
) {
  const branch = await pool.query<{ id: string }>(
    `
      insert into app.branches (name, timezone_name)
      values ($1, 'Europe/Moscow')
      returning id
    `,
    [`Settlement ${randomUUID()}`],
  );
  const branchId = branch.rows[0]!.id;
  const users = await pool.query<{ id: string; role: string }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, 'manager', now()),
        ($2, 'teacher', now()),
        ($3, 'client', now()),
        ($4, 'client', now())
      returning id, role::text as role
    `,
    [
      `settlement-manager-${randomUUID()}@example.test`,
      `settlement-teacher-${randomUUID()}@example.test`,
      `settlement-client-${randomUUID()}@example.test`,
      `settlement-client-two-${randomUUID()}@example.test`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const teacherUserId = users.rows.find((row) => row.role === "teacher")!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const clientUserIds = users.rows
    .filter((row) => row.role === "client")
    .map((row) => row.id);
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values
        ($1, 'Settlement', 'Teacher'),
        ($2, 'Settlement', 'Student'),
        ($3, 'Settlement', 'Student Two')
      returning id, user_id
    `,
    [teacherUserId, clientUserIds[0], clientUserIds[1]],
  );
  const teacherProfileId = profiles.rows.find(
    (row) => row.user_id === teacherUserId,
  )!.id;
  const studentProfileId = profiles.rows.find(
    (row) => row.user_id === clientUserIds[0],
  )!.id;
  const secondStudentProfileId = profiles.rows.find(
    (row) => row.user_id === clientUserIds[1],
  )!.id;
  const teacher = await pool.query<{ id: string }>(
    "insert into app.teachers (profile_id) values ($1) returning id",
    [teacherProfileId],
  );
  const teacherId = teacher.rows[0]!.id;
  const student = await pool.query<{ id: string }>(
    `
      insert into app.students (profile_id, branch_id)
      values ($1, $2)
      returning id
    `,
    [studentProfileId, branchId],
  );
  const studentId = student.rows[0]!.id;
  const secondStudent = await pool.query<{ id: string }>(
    `insert into app.students (profile_id, branch_id) values ($1, $2) returning id`,
    [secondStudentProfileId, branchId],
  );
  const secondStudentId = secondStudent.rows[0]!.id;
  const group = await pool.query<{ id: string }>(
    `insert into app.groups (teacher_id, branch_id, name, price_per_lesson)
     values ($1, $2, $3, 800) returning id`,
    [teacherId, branchId, `Settlement group ${randomUUID()}`],
  );
  const groupId = group.rows[0]!.id;
  await pool.query(
    `insert into app.group_students (group_id, student_id, joined_at)
     values ($1, $2, '2026-01-01'), ($1, $3, '2026-01-01')`,
    [groupId, studentId, secondStudentId],
  );
  const packageRow = await pool.query<{ id: string }>(
    `insert into app.subscription_packages (
       name, lessons_total, base_price_minor, currency_code, validity_days,
       is_active, version
     ) values ($1, 20, 800000, 'RUB', 90, true, 1) returning id`,
    [`Settlement package ${randomUUID()}`],
  );
  const subscription = await pool.query<{ id: string }>(
    `insert into app.subscriptions (
       student_id, lessons_total, lessons_used, starts_at, expires_at, status,
       package_id, commercial_snapshot, snapshot_version, package_version,
       base_price_minor, currency_code, final_price_minor, version
     ) values (
       $1, 20, 0, date '2026-01-01', current_date + 90, 'active', $2,
       $3::jsonb, 1, 1, 800000, 'RUB', 800000, 1
     ) returning id`,
    [
      studentId,
      packageRow.rows[0]!.id,
      JSON.stringify({ snapshotVersion: 1, displayName: "Settlement package" }),
    ],
  );
  const subscriptionId = subscription.rows[0]!.id;
  const groupSubscription = await pool.query<{ id: string }>(
    `insert into app.subscriptions (
       student_id, lessons_total, lessons_used, starts_at, expires_at, status,
       package_id, commercial_snapshot, snapshot_version, package_version,
       base_price_minor, currency_code, final_price_minor, version
     ) values (
       $1, 20, 0, coalesce($4::date, date '2026-01-01'),
       coalesce($5::date, current_date + 90), 'active', $2,
       $3::jsonb, 1, 1, 800000, 'RUB', 800000, 1
     ) returning id`,
    [
      studentId,
      packageRow.rows[0]!.id,
      JSON.stringify({
        snapshotVersion: 1,
        displayName: "Group settlement package",
      }),
      groupSubscriptionDates.startsAt ?? null,
      groupSubscriptionDates.expiresAt ?? null,
    ],
  );
  const groupSubscriptionId = groupSubscription.rows[0]!.id;
  const lessons = await pool.query<{ id: string; duration_minutes: number }>(
    `
      insert into app.lessons (
        student_id, teacher_id, branch_id, scheduled_at, duration_minutes,
        status, created_by
      )
      values
        ($1, $2, $3, '2026-07-29T07:00:00Z', 60, $4, $5),
        ($1, $2, $3, '2026-07-29T09:00:00Z', 45, 'completed', $5),
        ($1, $2, $3, '2026-07-29T11:00:00Z', 90, 'completed', $5),
        ($1, $2, $3, '2026-07-29T15:00:00Z', 60, 'completed', $5)
      returning id, duration_minutes
    `,
    [
      studentId,
      teacherId,
      branchId,
      scheduled ? "scheduled" : "completed",
      managerId,
    ],
  );
  const fixedLessonId = lessons.rows[0]!.id;
  const hourlyLessonId = lessons.rows[1]!.id;
  const noneLessonId = lessons.rows[2]!.id;
  const subscriptionLessonId = lessons.rows[3]!.id;
  const groupLesson = await pool.query<{ id: string }>(
    `insert into app.lessons (
       group_id, teacher_id, branch_id, scheduled_at, duration_minutes,
       status, created_by
     ) values ($1, $2, $3, '2026-07-29T13:00:00Z', 60, 'completed', $4)
     returning id`,
    [groupId, teacherId, branchId, managerId],
  );
  const groupLessonId = groupLesson.rows[0]!.id;
  const groupFundingLesson = await pool.query<{ id: string }>(
    `insert into app.lessons (
       group_id, teacher_id, branch_id, scheduled_at, duration_minutes,
       status, created_by
     ) values ($1, $2, $3, '2026-07-29T14:00:00Z', 60, 'completed', $4)
     returning id`,
    [groupId, teacherId, branchId, managerId],
  );
  const groupFundingLessonId = groupFundingLesson.rows[0]!.id;
  const lifecycle = new LessonLifecycleRepository(database);
  await database.transaction(async (client) => {
    await lifecycle.createSnapshot(client, {
      lessonId: fixedLessonId,
      clientType: "student",
      clientId: studentId,
      completionType: "standard.success",
      clientChargeType: "personal_account",
      clientChargeValue: 1234.56,
      teacherCompensationType: "fixed",
      teacherCompensationValue: 700,
      trial: false,
    });
    await lifecycle.createSnapshot(client, {
      lessonId: subscriptionLessonId,
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
    await lifecycle.createReservation(client, {
      lessonId: subscriptionLessonId,
      subscriptionId,
      units: 1,
    });
    await lifecycle.createGroupSnapshot(client, {
      lessonId: groupLessonId,
      groupId,
      completionType: "standard.success",
      teacherCompensationType: "fixed",
      teacherCompensationValue: 900,
      trial: false,
      participants: [studentId, secondStudentId].map((participantId) => ({
        studentId: participantId,
        chargeType: "personal_account" as const,
        chargeValue: 800,
      })),
    });
    await lifecycle.createGroupSnapshot(client, {
      lessonId: groupFundingLessonId,
      groupId,
      completionType: "standard.success",
      teacherCompensationType: "fixed",
      teacherCompensationValue: 900,
      trial: false,
      participants: [
        {
          studentId,
          chargeType: "subscription",
          chargeValue: 1,
          subscriptionId: groupSubscriptionId,
        },
        {
          studentId: secondStudentId,
          chargeType: "personal_account",
          chargeValue: 800,
        },
      ],
    });
    await lifecycle.createReservation(client, {
      lessonId: groupFundingLessonId,
      subscriptionId: groupSubscriptionId,
      units: 1,
    });
    await lifecycle.createSnapshot(client, {
      lessonId: hourlyLessonId,
      clientType: "student",
      clientId: studentId,
      completionType: "standard.success",
      clientChargeType: "none",
      clientChargeValue: 0,
      teacherCompensationType: "hourly",
      teacherCompensationValue: 1000.01,
      trial: false,
    });
    await lifecycle.createSnapshot(client, {
      lessonId: noneLessonId,
      clientType: "student",
      clientId: studentId,
      completionType: "standard.success",
      clientChargeType: "none",
      clientChargeValue: 250,
      teacherCompensationType: "none",
      teacherCompensationValue: 500,
      trial: false,
    });
  });

  // Settlement must use the immutable snapshot duration, not a later mutable
  // Lesson projection.
  await pool.query(
    "update app.lessons set duration_minutes = 120 where id = $1",
    [hourlyLessonId],
  );

  return {
    branchId,
    teacherId,
    studentId,
    secondStudentId,
    groupId,
    managerId,
    clientUserIds,
    userIds: [managerId, teacherUserId, ...clientUserIds],
    profileIds: profiles.rows.map((row) => row.id),
    lessonIds: [
      ...lessons.rows.map((row) => row.id),
      groupLessonId,
      groupFundingLessonId,
    ],
    fixedLessonId,
    hourlyLessonId,
    noneLessonId,
    groupLessonId,
    groupFundingLessonId,
    subscriptionLessonId,
    subscriptionId,
    groupSubscriptionId,
    packageId: packageRow.rows[0]!.id,
  };
}

function crossPayerDecision(
  fixture: Awaited<ReturnType<typeof createFixture>>,
) {
  return {
    settlementTypeKey: "free_lesson",
    clientDecisions: [
      {
        clientId: fixture.secondStudentId,
        settlementTypeKey: "lesson",
        payerStudentId: fixture.studentId,
        subscriptionId: fixture.groupSubscriptionId,
      },
    ],
    teacherCompensationRuleKey: "standard",
  };
}

function crossPayerCapacityFact(
  fixture: Awaited<ReturnType<typeof createFixture>>,
): CalculatedLessonClientFact {
  return {
    charge: {
      client_type: "student",
      client_id: fixture.secondStudentId,
      charge_type: "subscription",
      charge_value: "1",
      subscription_id: fixture.groupSubscriptionId,
    },
    chargeType: "subscription",
    subscriptionId: fixture.groupSubscriptionId,
    payerStudentId: fixture.studentId,
    settlement: {
      stableKey: "lesson",
      label: "Занятие",
      colorToken: "success",
      hourShareBasisPoints: 10_000,
      clientDurationMode: "full",
      teacherDurationMode: "full",
      defaultTeacherCompensationRuleKey: "standard",
      allowedContexts: ["settle"],
      active: true,
      order: 0,
    },
    calculation: {
      hourShareBasisPoints: 10_000,
      units: "1.00",
      amountMinor: "0",
    },
  };
}

async function cleanupFixture(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    await client.query(
      "delete from app.lesson_teacher_compensation_facts where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_client_charge_facts where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_participant_exclusions where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_snapshot_participants where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_reservations where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_snapshots where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.aggregate_versions where aggregate_type = 'schedule:lesson' and aggregate_id = any($1::text[])",
      [fixture.lessonIds],
    );
    await client.query("delete from app.lessons where id = any($1::uuid[])", [
      fixture.lessonIds,
    ]);
    await client.query("delete from app.group_students where group_id = $1", [
      fixture.groupId,
    ]);
    await client.query("delete from app.groups where id = $1", [
      fixture.groupId,
    ]);
    await client.query(
      "delete from app.subscriptions where id = any($1::uuid[])",
      [[fixture.subscriptionId, fixture.groupSubscriptionId]],
    );
    await client.query("delete from app.subscription_packages where id = $1", [
      fixture.packageId,
    ]);
    await client.query("delete from app.students where id = any($1::uuid[])", [
      [fixture.studentId, fixture.secondStudentId],
    ]);
    await client.query("delete from app.teachers where id = $1", [
      fixture.teacherId,
    ]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      fixture.profileIds,
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      fixture.userIds,
    ]);
    await client.query(
      "delete from app.crm_configuration_revisions where branch_id = $1",
      [fixture.branchId],
    );
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
