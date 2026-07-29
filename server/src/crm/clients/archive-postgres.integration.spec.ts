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
        insert into app.tasks (
          entity_type, entity_id, title, status, assigned_to, created_by
        )
        values ('student', $1, 'Не потерять', 'open', $2, $2)
        returning id
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
    await database.query("delete from app.subscriptions where id = $1", [
      subscriptionId,
    ]);
    await database.transaction(async (client) => {
      await client.query("set local session_replication_role = replica");
      await client.query("delete from app.payments where id = $1", [paymentId]);
    });
    await database.query("delete from app.tasks where id = $1", [taskId]);
    await database.query("delete from app.lessons where id = $1", [lessonId]);
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
        futureLessons: 1,
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
          (select count(*)::text from app.tasks where id = $3) as tasks,
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
