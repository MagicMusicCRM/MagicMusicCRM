import { ConfigService } from "@nestjs/config";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { existsSync, readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { resolve } from "node:path";
import { Pool, PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import {
  ExistingLessonDraft,
  LessonRequiredFieldValidator,
} from "./lesson-required-field.validator";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !["127.0.0.1", "localhost", "[::1]"].includes(new URL(databaseUrl).hostname)
) {
  throw new Error("No-attendance contract tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("T4.2.5 no-attendance mutation contract", () => {
  let pool: Pool;
  let database: DatabaseService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("has no attendance API/service/DTO and rejects manual completion input", async () => {
    const sourceRoot = resolve(process.cwd(), "src", "crm");
    const controller = readFileSync(
      resolve(sourceRoot, "crm-schedule.controller.ts"),
      "utf8",
    );
    const moduleSource = readFileSync(
      resolve(sourceRoot, "crm.module.ts"),
      "utf8",
    );

    expect(controller).not.toMatch(/lessons\/:id\/attendance/i);
    expect(controller).not.toMatch(/AttendanceService|UpsertAttendanceDto/);
    expect(moduleSource).not.toMatch(/AttendanceService/);
    expect(existsSync(resolve(sourceRoot, "attendance.service.ts"))).toBe(
      false,
    );
    expect(
      existsSync(resolve(sourceRoot, "dto", "upsert-attendance.dto.ts")),
    ).toBe(false);

    const dto = plainToInstance(UpsertLessonDto, { status: "completed" });
    const errors = await validate(dto);
    expect(errors).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          property: "status",
          constraints: expect.objectContaining({ isIn: expect.any(String) }),
        }),
      ]),
    );

    const existing: ExistingLessonDraft = {
      id: randomUUID(),
      version: 1,
      studentId: randomUUID(),
      leadId: null,
      teacherId: randomUUID(),
      branchId: randomUUID(),
      roomId: randomUUID(),
      scheduledAt: "2026-07-27T09:00:00.000Z",
      durationMinutes: 60,
      isTrial: false,
      notes: null,
      snapshot: {
        clientType: "student",
        clientId: randomUUID(),
        completionType: "standard.success",
        clientChargeType: "none",
        clientChargeValue: 0,
        teacherCompensationType: "none",
        teacherCompensationValue: 0,
        subscriptionId: null,
        trial: false,
        validationState: "valid",
      },
    };
    let lifecycleError: unknown;
    try {
      new LessonRequiredFieldValidator().update(
        { status: "completed" },
        existing,
      );
    } catch (error) {
      lifecycleError = error;
    }
    expect(lifecycleError).toMatchObject({
      response: expect.objectContaining({
        code: "MANUAL_LESSON_LIFECYCLE_FORBIDDEN",
      }),
    });
  });

  it("keeps legacy evidence read-only and derives count from terminal lessons", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const fixture = await createMetricFixture(client);
      const metric = await client.query<{
        successfully_completed_lessons: string | number;
      }>(
        `
          select successfully_completed_lessons
          from app.client_lesson_success_metrics
          where client_type = 'student' and client_id = $1
        `,
        [fixture.studentId],
      );
      const direct = await client.query<{ count: string | number }>(
        `
          select count(*) as count
          from app.lessons lesson
          join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
          where snapshot.client_type = 'student'
            and snapshot.client_id = $1
            and lesson.deleted_at is null
            and lesson.lifecycle_state = 'successfully_completed'
        `,
        [fixture.studentId],
      );
      expect(Number(metric.rows[0]?.successfully_completed_lessons)).toBe(2);
      expect(Number(metric.rows[0]?.successfully_completed_lessons)).toBe(
        Number(direct.rows[0]?.count),
      );

      const privileges = await client.query<{
        can_select: boolean;
        can_insert: boolean;
        can_update: boolean;
        can_delete: boolean;
        can_truncate: boolean;
      }>(
        `
          select
            has_table_privilege(
              'magiccrm_app', 'app.lesson_participation', 'SELECT'
            ) as can_select,
            has_table_privilege(
              'magiccrm_app', 'app.lesson_participation', 'INSERT'
            ) as can_insert,
            has_table_privilege(
              'magiccrm_app', 'app.lesson_participation', 'UPDATE'
            ) as can_update,
            has_table_privilege(
              'magiccrm_app', 'app.lesson_participation', 'DELETE'
            ) as can_delete,
            has_table_privilege(
              'magiccrm_app', 'app.lesson_participation', 'TRUNCATE'
            ) as can_truncate
        `,
      );
      expect(privileges.rows[0]).toEqual({
        can_select: true,
        can_insert: false,
        can_update: false,
        can_delete: false,
        can_truncate: false,
      });

      const evidence = await client.query<{ count: string | number }>(
        `
          select count(*) as count
          from app.lesson_participation
          where lesson_id = $1 and student_id = $2
        `,
        [fixture.scheduledLessonId, fixture.studentId],
      );
      expect(Number(evidence.rows[0]?.count)).toBe(1);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});

async function createMetricFixture(client: PoolClient) {
  const branch = await client.query<{ id: string }>(
    "insert into app.branches (name) values ($1) returning id",
    [`Attendance-free ${randomUUID()}`],
  );
  const users = await client.query<{ id: string; role: string }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, 'manager', now()),
        ($2, 'client', now())
      returning id, role::text as role
    `,
    [
      `attendance-manager-${randomUUID()}@example.test`,
      `attendance-client-${randomUUID()}@example.test`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const profile = await client.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values ($1, 'Derived', 'Metric')
      returning id
    `,
    [clientUserId],
  );
  const student = await client.query<{ id: string }>(
    `
      insert into app.students (profile_id, branch_id)
      values ($1, $2)
      returning id
    `,
    [profile.rows[0]!.id, branch.rows[0]!.id],
  );
  const studentId = student.rows[0]!.id;
  const lessons = await client.query<{ id: string; lifecycle_state: string }>(
    `
      insert into app.lessons (
        student_id, branch_id, scheduled_at, status, created_by
      )
      values
        ($1, $2, now() - interval '3 hours', 'completed', $3),
        ($1, $2, now() - interval '2 hours', 'completed', $3),
        ($1, $2, now() - interval '1 hour', 'scheduled', $3)
      returning id, lifecycle_state
    `,
    [studentId, branch.rows[0]!.id, managerId],
  );
  for (const lesson of lessons.rows) {
    await client.query(
      `
        insert into app.lesson_snapshots (
          lesson_id, client_type, client_id, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          trial, validation_state, origin
        )
        values (
          $1, 'student', $2, 'standard.success',
          'none', 0, 'none', 0, false, 'valid', 'runtime'
        )
      `,
      [lesson.id, studentId],
    );
  }
  const scheduledLessonId = lessons.rows.find(
    (lesson) => lesson.lifecycle_state === "scheduled",
  )!.id;
  await client.query(
    `
      insert into app.lesson_participation (
        lesson_id, student_id, status, pass_reason, attendance_kind
      )
      values ($1, $2, 'present', 'legacy evidence', 'attended')
    `,
    [scheduledLessonId, studentId],
  );
  return { studentId, scheduledLessonId };
}
