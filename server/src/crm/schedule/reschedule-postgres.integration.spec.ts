import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { LessonSettlementPort } from "../commerce/lesson-settlement.port";
import { LessonSettlementRepository } from "../commerce/lesson-settlement.repository";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import { AvailabilityRepository } from "./availability.repository";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
import { LessonTransitionService } from "./lesson-transition.service";

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
    const reservations = new SubscriptionReservationService(
      database,
      {
        emitCrmChanged: jest.fn(),
        emitFinanceChanged: jest.fn(),
      } as unknown as RealtimeBus,
    );
    const tokens = new SubscriptionPreviewTokenService(config);
    const base = [
      database,
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      new CrmPolicy(),
      new LessonRequiredFieldValidator(),
      constraints,
      lifecycle,
    ] as const;
    service = new LessonTransitionService(
      ...base,
      new LessonSettlementService(
        database,
        new LessonSettlementRepository(),
      ),
      reservations,
      tokens,
    );
    failingService = new LessonTransitionService(
      ...base,
      {
        settle: async () => {
          throw new Error("injected commerce failure");
        },
      } as LessonSettlementPort,
      reservations,
      tokens,
    );
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

      const preview = await service.previewReschedule(
        actor,
        fixture.sourceId,
        {
          expectedVersion: 1,
          reasonCode: "client.requested",
          reasonText: "Клиент попросил другое время",
          financialDecision: freeDecision,
          successor: { scheduledAt: "2026-07-27T11:00:00.000Z" },
        },
      );
      expect(preview).toMatchObject({
        canConfirm: true,
        financialPreview: {
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

      const cancelPreview = await service.previewCancel(
        actor,
        fixture.cancelId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText: "Отмена по решению школы",
          financialDecision: freeDecision,
        },
      );
      const cancelled = await service.cancel(
        actor,
        fixture.cancelId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          reasonText: "Отмена по решению школы",
          financialDecision: freeDecision,
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
      };
      await pool.query(
        "update app.lessons set lifecycle_state = 'settlement_pending' where id = $1",
        [fixture.settleId],
      );
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

      const persisted = await pool.query<{
        transitions: number;
        client_facts: number;
        teacher_facts: number;
        successors: number;
        reason_text: string;
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
              where lesson_id = $2) as reason_text
        `,
        [[fixture.sourceId, fixture.cancelId, fixture.settleId], fixture.sourceId],
      );
      expect(persisted.rows[0]).toEqual({
        transitions: 3,
        client_facts: 3,
        teacher_facts: 3,
        successors: 1,
        reason_text: "Клиент попросил другое время",
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
    };
    const preview = (scheduledAt: string) => service.previewReschedule(
      actor,
      fixture.sourceId,
      {
        expectedVersion: 1,
        reasonCode: "schedule.concurrent",
        reasonText: "Проверка конкурентного переноса",
        financialDecision: decision,
        successor: { scheduledAt },
      },
    );
    const metadata = (label: string) => ({
      idempotencyKey: `race-${label}-${randomUUID()}`,
      requestId: `race-request-${label}-${randomUUID()}`,
    });
    try {
      const left = await preview("2026-07-27T11:00:00.000Z");
      const right = await preview("2026-07-27T12:00:00.000Z");
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

      const capacityPreview = await service.previewSettle(
        actor,
        fixture.capacityId,
        {
          expectedVersion: 1,
          reasonCode: "attendance.confirmed",
          financialDecision: {
            settlementTypeKey: "lesson",
            teacherCompensationRuleKey: "standard",
          },
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
            expectedVersion: 1,
            reasonCode: "attendance.confirmed",
            financialDecision: {
              settlementTypeKey: "lesson",
              teacherCompensationRuleKey: "standard",
            },
            previewToken: capacityPreview.previewToken!,
            confirm: true,
          },
          metadata("insufficient-capacity"),
        ),
      ).rejects.toMatchObject({ status: 422 });
      await expectSourceUnchanged(pool, fixture.capacityId);

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
            successor: { scheduledAt: "2026-07-27T12:00:00.000Z" },
            previewToken: right.previewToken!,
            confirm: true,
          },
          metadata("right"),
        ),
      ]);
      expect(results.filter((result) => result.status === "fulfilled"))
        .toHaveLength(1);
      expect(results.filter((result) => result.status === "rejected"))
        .toHaveLength(1);
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
    const decision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
    };
    const lifecycle = new LessonLifecycleRepository(database);
    const successFixture = await createFixture(pool, lifecycle);
    try {
      const actor = actorFor(successFixture.managerId);
      const previewDto = {
        reasonCode: "attendance.bulk",
        reasonText: "Массовая проверка занятий",
        items: [successFixture.cancelId, successFixture.settleId].map(
          (lessonId) => ({
            lessonId,
            operation: "settle" as const,
            expectedVersion: 1,
            financialDecision: decision,
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
      await expect(service.bulk(actor, command, metadata)).resolves.toMatchObject({
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
      const ordered = [rollbackFixture.cancelId, rollbackFixture.settleId]
        .sort();
      const previewDto = {
        reasonCode: "attendance.bulk",
        reasonText: "Проверка полного отката",
        items: ordered.map((lessonId) => ({
          lessonId,
          operation: "settle" as const,
          expectedVersion: 1,
          financialDecision: decision,
        })),
      };
      const preview = await service.previewBulk(actor, previewDto);
      await pool.query(
        "update app.lessons set notes = 'stale' where id = $1",
        [ordered[1]],
      );
      await expect(service.bulk(
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
      )).rejects.toMatchObject({ status: 409 });
      await expectSourceUnchanged(pool, ordered[0]!);
      expect(await transitionCounts(pool, ordered[1]!)).toEqual({
        lifecycle_state: "scheduled",
        version: 2,
        successors: 0,
        transitions: 0,
        client_facts: 0,
        teacher_facts: 0,
      });
    } finally {
      await cleanup(pool, rollbackFixture);
    }
  });
});

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

async function createFixture(
  pool: Pool,
  lifecycle: LessonLifecycleRepository,
) {
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
  const users = await pool.query<{ id: string; role: string }>(
    `insert into app.users (email, role, email_verified_at) values
      ($1, 'manager', now()), ($2, 'teacher', now()), ($3, 'client', now())
      returning id, role::text as role`,
    [
      `transition-manager-${randomUUID()}@test.local`,
      `transition-teacher-${randomUUID()}@test.local`,
      `transition-client-${randomUUID()}@test.local`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const teacherUserId = users.rows.find((row) => row.role === "teacher")!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `insert into app.profiles (user_id, first_name, last_name) values
      ($1, 'Transition', 'Teacher'), ($2, 'Transition', 'Student')
      returning id, user_id`,
    [teacherUserId, clientUserId],
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
  const student = await pool.query<{ id: string }>(
    "insert into app.students (profile_id, branch_id) values ($1, $2) returning id",
    [studentProfileId, branchId],
  );
  const studentId = student.rows[0]!.id;
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
  for (const lessonId of [sourceId, cancelId, settleId]) {
    const client = await pool.connect();
    try {
      await lifecycle.createSnapshot(client, {
        lessonId,
        clientType: "student",
        clientId: studentId,
        completionType: "standard.success",
        clientChargeType: "none",
        clientChargeValue: 0,
        teacherCompensationType: "fixed",
        teacherCompensationValue: 700,
        trial: false,
      });
    } finally {
      client.release();
    }
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
    teacherId,
    studentId,
    managerId,
    userIds: [managerId, teacherUserId, clientUserId],
    profileIds: profiles.rows.map((row) => row.id),
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
      "delete from app.idempotency_records where actor_key = $1",
      [`user:${fixture.managerId}`],
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
    await client.query("delete from app.audit_events where actor_user_id = $1", [
      fixture.managerId,
    ]);
    for (const table of [
      "lesson_transitions",
      "lesson_reservations",
      "lesson_client_charge_facts",
      "lesson_teacher_compensation_facts",
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
    await client.query("delete from app.lessons where created_by = $1", [
      fixture.managerId,
    ]);
    await client.query("delete from app.subscriptions where id = $1", [
      fixture.subscriptionId,
    ]);
    await client.query("delete from app.students where id = $1", [fixture.studentId]);
    await client.query(
      "delete from app.teacher_availability_rules where teacher_id = $1",
      [fixture.teacherId],
    );
    await client.query("delete from app.teacher_branches where teacher_id = $1", [
      fixture.teacherId,
    ]);
    await client.query("delete from app.teachers where id = $1", [fixture.teacherId]);
    await client.query("delete from app.rooms where id = $1", [fixture.roomId]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      fixture.profileIds,
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      fixture.userIds,
    ]);
    await client.query("delete from app.branch_hours where branch_id = $1", [
      fixture.branchId,
    ]);
    await client.query("delete from app.branches where id = $1", [fixture.branchId]);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}
