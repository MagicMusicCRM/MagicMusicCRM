import {
  ConflictException,
  ForbiddenException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ArchiveClientCommandDto } from "../dto/client-archive.dto";
import { ClientArchiveService } from "./client-archive.service";
import { ClientReferenceService } from "./client-reference.service";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(testDatabaseUrl).hostname,
  )
) {
  throw new Error("Client archive tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Client archive preview and tombstone (PostgreSQL)", () => {
  let database: DatabaseService;
  let archive: ClientArchiveService;
  let references: ClientReferenceService;
  let branchId: string;
  let studentId: string;
  let profileId: string;
  let clientUserId: string;
  let linkedUserId: string;
  let adminId: string;
  let directorId: string;
  let lessonId: string;
  let recurringLessonId: string;
  let schedulePlanId: string;
  let scheduleSeriesId: string;
  let groupId: string;
  let taskId: string;
  let subscriptionId: string;
  let paymentId: string;
  let expectedPaymentId: string;
  let adjustmentId: string;

  beforeAll(async () => {
    const pool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await new MigrationRunner(pool).up();
    } finally {
      await pool.end();
    }
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    archive = new ClientArchiveService(
      database,
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      new CrmPolicy(),
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );
    references = new ClientReferenceService(database);

    const branch = await database.query<{ id: string }>(
      "insert into app.branches (name) values ($1) returning id",
      [`Archive ${randomUUID()}`],
    );
    branchId = branch.rows[0]!.id;
    const users = await database.query<{ id: string; role: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values
          ($1, 'client', now()),
          ($2, 'client', now()),
          ($3, 'admin', now()),
          ($4, 'director', now())
        returning id, role::text as role
      `,
      [
        `archive-client-${randomUUID()}@example.test`,
        `archive-linked-${randomUUID()}@example.test`,
        `archive-admin-${randomUUID()}@example.test`,
        `archive-director-${randomUUID()}@example.test`,
      ],
    );
    const clients = users.rows.filter((row) => row.role === "client");
    [clientUserId, linkedUserId] = clients.map((row) => row.id);
    adminId = users.rows.find((row) => row.role === "admin")!.id;
    directorId = users.rows.find((row) => row.role === "director")!.id;

    const profile = await database.query<{ id: string }>(
      `
        insert into app.profiles (user_id, first_name, last_name, phone)
        values ($1, 'Архивный', 'Клиент', '+79990001122')
        returning id
      `,
      [clientUserId],
    );
    profileId = profile.rows[0]!.id;
    const student = await database.query<{ id: string }>(
      `
        insert into app.students (profile_id, branch_id, status)
        values ($1, $2, 'active')
        returning id
      `,
      [profileId, branchId],
    );
    studentId = student.rows[0]!.id;
    await database.query(
      `
        insert into app.user_crm_links (
          user_id, entity_type, entity_id, link_source, created_by, confirmed_at
        )
        values ($1, 'student', $2, 'manual_phone', $3, now())
      `,
      [linkedUserId, studentId, directorId],
    );

    const lesson = await database.query<{ id: string }>(
      `
        insert into app.lessons (
          student_id, branch_id, scheduled_at, status, created_by
        )
        values ($1, $2, now() + interval '7 days', 'scheduled', $3)
        returning id
      `,
      [studentId, branchId, directorId],
    );
    lessonId = lesson.rows[0]!.id;
    const task = await database.query<{ id: string }>(
      `
        with task as (
          insert into app.shared_tasks (
            title, all_day, start_at, linked_entity_type,
            linked_entity_id, created_by
          )
          values ('Не потерять', true, now(), 'student', $1, $2)
          returning id
        )
        insert into app.task_audiences (task_id, audience_type, target_id)
        select id, 'user', $2 from task
        returning task_id as id
      `,
      [studentId, directorId],
    );
    taskId = task.rows[0]!.id;
    const subscription = await database.query<{ id: string }>(
      `
        insert into app.subscriptions (
          student_id, lessons_total, lessons_used, starts_at, expires_at, status
        )
        values ($1, 10, 2, current_date, current_date + 30, 'active')
        returning id
      `,
      [studentId],
    );
    subscriptionId = subscription.rows[0]!.id;
    const group = await database.query<{ id: string }>(
      `insert into app.groups (branch_id, name)
       values ($1, $2) returning id`,
      [branchId, `Archive recurring ${randomUUID()}`],
    );
    groupId = group.rows[0]!.id;
    await database.query(
      `insert into app.group_students (group_id, student_id)
       values ($1, $2)`,
      [groupId, studentId],
    );
    const plan = await database.query<{ id: string }>(
      `insert into app.schedule_plans (
         kind, title, group_id, active_from, created_by
       ) values ('group', $1, $2, current_date, $3)
       returning id`,
      [`Archive plan ${randomUUID()}`, groupId, directorId],
    );
    schedulePlanId = plan.rows[0]!.id;
    await database.query(
      `insert into app.schedule_plan_participants (
         plan_id, student_id, subscription_id, effective_from
       ) values ($1, $2, $3, current_date)`,
      [schedulePlanId, studentId, subscriptionId],
    );
    const series = await database.query<{ id: string }>(
      `insert into app.schedule_series (
         group_id, branch_id, weekday, begin_time, duration_minutes,
         valid_from, plan_id, created_by
       ) values ($1, $2, 1, '10:00', 60, current_date, $3, $4)
       returning id`,
      [groupId, branchId, schedulePlanId, directorId],
    );
    scheduleSeriesId = series.rows[0]!.id;
    const recurringLesson = await database.query<{ id: string }>(
      `insert into app.lessons (
         group_id, branch_id, scheduled_at, status, series_id, series_date,
         created_by
       ) values (
         $1, $2, now() + interval '8 days', 'scheduled', $3,
         current_date + 8, $4
       ) returning id`,
      [groupId, branchId, scheduleSeriesId, directorId],
    );
    recurringLessonId = recurringLesson.rows[0]!.id;
    await database.query(
      `insert into app.lesson_snapshots (
         lesson_id, group_id, completion_type, client_charge_type,
         client_charge_value, teacher_compensation_type,
         teacher_compensation_value
       ) values ($1, $2, 'standard.success', 'none', 0, 'none', 0)`,
      [recurringLessonId, groupId],
    );
    await database.query(
      `insert into app.lesson_snapshot_participants (
         lesson_id, student_id, charge_type, charge_value
       ) values ($1, $2, 'personal_account', 100)`,
      [recurringLessonId, studentId],
    );
    const payment = await database.query<{ id: string }>(
      `
        insert into app.payments (
          student_id, branch_id, amount, payment_date, created_by
        )
        values ($1, $2, 5000, now(), $3)
        returning id
      `,
      [studentId, branchId, directorId],
    );
    paymentId = payment.rows[0]!.id;
    const expected = await database.query<{ id: string }>(
      `
        insert into app.expected_payments (
          student_id, amount, due_date, status, description
        )
        values ($1, 2000, current_date + 5, 'pending', 'Сохранить факт')
        returning id
      `,
      [studentId],
    );
    expectedPaymentId = expected.rows[0]!.id;
    const adjustment = await database.query<{ id: string }>(
      `
        insert into app.account_adjustments (
          student_id, branch_id, kind, amount, description, created_by
        )
        values ($1, $2, 'adjustment', 100, 'Сохранить корректировку', $3)
        returning id
      `,
      [studentId, branchId, directorId],
    );
    adjustmentId = adjustment.rows[0]!.id;
  });

  afterAll(async () => {
    await database.query(
      `
        delete from app.idempotency_records
        where operation = 'crm.client.archive'
          and result_ref->>'entityId' = $1
      `,
      [studentId],
    );
    await database.query(
      `
        delete from app.platform_outbox_events
        where aggregate_type = 'crm:student' and aggregate_id = $1
      `,
      [studentId],
    );
    await database.query(
      `
        delete from app.audit_events
        where entity_type = 'crm:student' and entity_id = $1
      `,
      [studentId],
    );
    await database.query(
      `
        delete from app.aggregate_versions
        where aggregate_type = 'crm:student' and aggregate_id = $1
      `,
      [studentId],
    );
    await database.query("delete from app.account_adjustments where id = $1", [
      adjustmentId,
    ]);
    await database.query("delete from app.expected_payments where id = $1", [
      expectedPaymentId,
    ]);
    await database.transaction(async (client) => {
      await client.query("set local session_replication_role = replica");
      await client.query("delete from app.payments where id = $1", [paymentId]);
    });
    await database.query("delete from app.task_audiences where task_id = $1", [taskId]);
    await database.query("delete from app.shared_tasks where id = $1", [taskId]);
    await database.transaction(async (client) => {
      await client.query("set local session_replication_role = replica");
      await client.query(
        "delete from app.lesson_transitions where lesson_id = $1",
        [recurringLessonId],
      );
      await client.query(
        "delete from app.lesson_participant_exclusions where lesson_id = $1",
        [recurringLessonId],
      );
      await client.query(
        "delete from app.lesson_snapshot_participants where lesson_id = $1",
        [recurringLessonId],
      );
      await client.query("delete from app.lesson_snapshots where lesson_id = $1", [
        recurringLessonId,
      ]);
      await client.query("delete from app.lessons where id = any($1::uuid[])", [
        [lessonId, recurringLessonId],
      ]);
      await client.query("delete from app.schedule_series where id = $1", [
        scheduleSeriesId,
      ]);
      await client.query(
        "delete from app.schedule_plan_participants where plan_id = $1",
        [schedulePlanId],
      );
      await client.query(
        `delete from app.aggregate_versions
         where aggregate_type = 'schedule:plan' and aggregate_id = $1`,
        [schedulePlanId],
      );
      await client.query("delete from app.schedule_plans where id = $1", [
        schedulePlanId,
      ]);
      await client.query("delete from app.group_students where group_id = $1", [
        groupId,
      ]);
      await client.query("delete from app.groups where id = $1", [groupId]);
    });
    await database.query("delete from app.subscriptions where id = $1", [
      subscriptionId,
    ]);
    await database.query(
      "delete from app.user_crm_links where entity_type = 'student' and entity_id = $1",
      [studentId],
    );
    await database.query("delete from app.students where id = $1", [studentId]);
    await database.query("delete from app.profiles where id = $1", [profileId]);
    await database.query("delete from app.branches where id = $1", [branchId]);
    await database.query(
      "delete from app.users where id = any($1::uuid[])",
      [[clientUserId, linkedUserId, adminId, directorId]],
    );
    await database.onModuleDestroy();
  });

  it("denies Admin, requires versioned confirmation, and preserves every linked fact", async () => {
    const ref = { type: "student" as const, id: studentId };
    await expect(
      archive.preview({ userId: adminId, role: "admin" }, ref),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const preview = await archive.preview(
      { userId: directorId, role: "director" },
      ref,
    );
    expect(preview).toMatchObject({
      ref,
      version: 1,
      tombstone: false,
      confirmRequired: true,
      linkedUserCount: 1,
      impact: {
        futureLessons: 2,
        openTasks: 1,
        activeSubscriptions: 1,
        financeFacts: 3,
        payments: 1,
        expectedPayments: 1,
        accountAdjustments: 1,
      },
      blockers: [],
    });
    expect(preview.warnings.map((warning) => warning.code)).toEqual([
      "FUTURE_LESSONS_PRESERVED",
      "OPEN_TASKS_PRESERVED",
      "ACTIVE_SUBSCRIPTIONS_PRESERVED",
      "FINANCE_FACTS_PRESERVED",
    ]);

    await expect(
      archive.archive(
        { userId: directorId, role: "director" },
        {
          ...ref,
          expectedVersion: 1,
          confirm: false,
          reason: "test.client-archive",
        } as unknown as ArchiveClientCommandDto,
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(
      archive.archive(
        { userId: directorId, role: "director" },
        {
          ...ref,
          expectedVersion: 99,
          confirm: true,
          reason: "test.client-archive",
        },
      ),
    ).rejects.toBeInstanceOf(ConflictException);

    const archived = await archive.archive(
      { userId: directorId, role: "director" },
      {
        ...ref,
        expectedVersion: 1,
        confirm: true,
        reason: "test.client-archive",
      },
    );
    expect(archived).toMatchObject({
      replayed: false,
      tombstone: {
        ref,
        lifecycleState: "archived",
        tombstone: true,
        version: 2,
        linkedUserCount: 1,
      },
    });
    expect(archived.tombstone.archivedAt).not.toBeNull();

    const recurring = await database.query<{
      plan_status: string;
      plan_ended: boolean;
      series_ended: boolean;
      membership_ended: boolean;
      participant_period_ended: boolean;
      lesson_state: string;
      exclusion_count: number;
      transition_count: number;
    }>(
      `select
         (select status from app.schedule_plans where id = $1) as plan_status,
         (select ended_at is not null from app.schedule_plans where id = $1)
           as plan_ended,
         (select valid_until is not null and valid_until <= current_date
           from app.schedule_series where id = $2) as series_ended,
         (select left_at is not null from app.group_students
           where group_id = $3 and student_id = $4) as membership_ended,
         (select effective_until is not null from app.schedule_plan_participants
           where plan_id = $1 and student_id = $4) as participant_period_ended,
         (select lifecycle_state from app.lessons where id = $5) as lesson_state,
         (select count(*)::int from app.lesson_participant_exclusions
           where lesson_id = $5 and student_id = $4) as exclusion_count,
         (select count(*)::int from app.lesson_transitions
           where lesson_id = $5 and to_state = 'cancelled') as transition_count`,
      [
        schedulePlanId,
        scheduleSeriesId,
        groupId,
        studentId,
        recurringLessonId,
      ],
    );
    expect(recurring.rows[0]).toEqual({
      plan_status: "ended",
      plan_ended: true,
      series_ended: true,
      membership_ended: true,
      participant_period_ended: true,
      lesson_state: "cancelled",
      exclusion_count: 1,
      transition_count: 1,
    });

    await expect(
      archive.archive(
        { userId: directorId, role: "director" },
        {
          ...ref,
          expectedVersion: 1,
          confirm: true,
          reason: "test.client-archive",
        },
      ),
    ).resolves.toMatchObject({
      replayed: true,
      tombstone: { ref, tombstone: true, version: 2 },
    });
    await expect(
      references.resolve(
        { userId: directorId, role: "director" },
        ref,
      ),
    ).resolves.toMatchObject({
      ref,
      lifecycleState: "archived",
      tombstone: true,
      version: 2,
    });

    const preserved = await database.query<{
      lessons: string;
      tasks: string;
      subscriptions: string;
      payments: string;
      expected_payments: string;
      adjustments: string;
      crm_links: string;
      audits: string;
      outbox_events: string;
    }>(
      `
        select
          (select count(*)::text from app.lessons where id = $2) as lessons,
          (select count(*)::text from app.shared_tasks where id = $3) as tasks,
          (select count(*)::text from app.subscriptions where id = $4)
            as subscriptions,
          (select count(*)::text from app.payments where id = $5) as payments,
          (select count(*)::text from app.expected_payments where id = $6)
            as expected_payments,
          (select count(*)::text from app.account_adjustments where id = $7)
            as adjustments,
          (select count(*)::text from app.user_crm_links
            where entity_type = 'student' and entity_id = $1::uuid
              and deleted_at is null) as crm_links,
          (select count(*)::text from app.audit_events
            where action = 'crm.client_archived'
              and entity_type = 'crm:student' and entity_id = $1::text)
            as audits,
          (select count(*)::text from app.platform_outbox_events
            where event_type = 'crm.client.archived'
              and aggregate_type = 'crm:student'
              and aggregate_id = $1::text)
            as outbox_events
      `,
      [
        studentId,
        lessonId,
        taskId,
        subscriptionId,
        paymentId,
        expectedPaymentId,
        adjustmentId,
      ],
    );
    expect(preserved.rows[0]).toEqual({
      lessons: "1",
      tasks: "1",
      subscriptions: "1",
      payments: "1",
      expected_payments: "1",
      adjustments: "1",
      crm_links: "1",
      audits: "1",
      outbox_events: "1",
    });
  });
});
