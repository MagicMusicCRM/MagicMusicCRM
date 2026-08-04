import { ConfigService } from "@nestjs/config";
import { NotFoundException } from "@nestjs/common";
import { randomUUID } from "crypto";
import { Pool } from "pg";
import { AccessMutationsRepository } from "../../access-control/access-mutations.repository";
import { EffectiveAccessEvaluator } from "../../access-control/effective-access-evaluator";
import { HardInvariantPolicy } from "../../access-control/hard-invariant.policy";
import { ActorContext, UserRole } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { ClientCardReadService } from "./client-card-read.service";
import { ClientReferenceService } from "./client-reference.service";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)
) {
  throw new Error("Client Card tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("ClientCardReadService (PostgreSQL)", () => {
  let database: DatabaseService;
  let service: ClientCardReadService;
  const users: string[] = [];
  const profiles: string[] = [];
  const teachers: string[] = [];
  const students: string[] = [];
  const branches: string[] = [];
  const lessons: string[] = [];
  const tasks: string[] = [];
  const homework: string[] = [];
  const comments: string[] = [];
  const subscriptions: string[] = [];
  let admin: ActorContext;
  let manager: ActorContext;
  let client: ActorContext;
  let assignedTeacher: ActorContext;
  let unrelatedTeacher: ActorContext;
  let studentId: string;
  let assignedLessonId: string;
  let otherLessonId: string;

  async function createActor(
    role: UserRole,
    firstName: string,
    lastName: string,
  ): Promise<ActorContext & { profileId: string }> {
    const user = await database.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, $2::app.user_role, now())
        returning id
      `,
      [`v4-client-card-${randomUUID()}@example.test`, role],
    );
    const userId = user.rows[0]!.id;
    users.push(userId);
    const profile = await database.query<{ id: string }>(
      `
        insert into app.profiles (user_id, first_name, last_name, phone)
        values ($1, $2, $3, '+79990000000')
        returning id
      `,
      [userId, firstName, lastName],
    );
    const profileId = profile.rows[0]!.id;
    profiles.push(profileId);
    return { userId, role, profileId };
  }

  async function createTeacher(profileId: string): Promise<string> {
    const result = await database.query<{ id: string }>(
      `
        insert into app.teachers (profile_id, status)
        values ($1, 'active')
        returning id
      `,
      [profileId],
    );
    const id = result.rows[0]!.id;
    teachers.push(id);
    return id;
  }

  beforeAll(async () => {
    const migrationPool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await new MigrationRunner(migrationPool).up();
    } finally {
      await migrationPool.end();
    }
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    await database.query(`
      delete from app.aggregate_versions
      where aggregate_type = 'access:user'
        and aggregate_id in (
          select id::text from app.users
          where email like 'v4-client-card-%@example.test'
        );
      delete from app.users
      where email like 'v4-client-card-%@example.test';
    `);

    admin = await createActor("admin", "Админ", "Карточки");
    manager = await createActor("manager", "Управляющий", "Карточки");
    client = await createActor("client", "Анна", "Клиент");
    assignedTeacher = await createActor("teacher", "Пётр", "Назначенный");
    unrelatedTeacher = await createActor("teacher", "Олег", "Посторонний");
    const otherTeacherActor = await createActor(
      "teacher",
      "Ирина",
      "Другой педагог",
    );
    const branch = await database.query<{ id: string }>(
      `
        insert into app.branches (name)
        values ('Центр')
        returning id
      `,
    );
    const branchId = branch.rows[0]!.id;
    branches.push(branchId);
    const student = await database.query<{ id: string }>(
      `
        insert into app.students (profile_id, status, branch_id)
        values ($1, 'active', $2)
        returning id
      `,
      [(client as ActorContext & { profileId: string }).profileId, branchId],
    );
    studentId = student.rows[0]!.id;
    students.push(studentId);
    const assignedTeacherId = await createTeacher(
      (assignedTeacher as ActorContext & { profileId: string }).profileId,
    );
    await createTeacher(
      (unrelatedTeacher as ActorContext & { profileId: string }).profileId,
    );
    const otherTeacherId = await createTeacher(otherTeacherActor.profileId);

    const lessonResult = await database.query<{ id: string }>(
      `
        insert into app.lessons (
          student_id, teacher_id, branch_id, scheduled_at, created_by
        )
        values
          ($1, $2, $3, now() + interval '1 day', $4),
          ($1, $5, $3, now() + interval '2 days', $4)
        returning id
      `,
      [studentId, assignedTeacherId, branchId, admin.userId, otherTeacherId],
    );
    [assignedLessonId, otherLessonId] = lessonResult.rows.map((row) => row.id);
    lessons.push(assignedLessonId!, otherLessonId!);

    const task = await database.query<{ id: string }>(
      `
        insert into app.tasks (
          entity_type, entity_id, title, status, assigned_to, created_by
        )
        values ('student', $1, 'Позвонить', 'open', $2, $2)
        returning id
      `,
      [studentId, admin.userId],
    );
    tasks.push(task.rows[0]!.id);

    const homeworkResult = await database.query<{ id: string }>(
      `
        insert into app.lesson_homeworks (
          lesson_id, student_id, assigned_by, title, status
        )
        values
          ($1, $3, $4, 'Распевка', 'assigned'),
          ($2, $3, $4, 'Гамма', 'assigned')
        returning id
      `,
      [assignedLessonId, otherLessonId, studentId, admin.userId],
    );
    homework.push(...homeworkResult.rows.map((row) => row.id));

    const commentResult = await database.query<{ id: string }>(
      `
        insert into app.entity_comments (
          entity_type, entity_id, author_id, body, kind,
          shared_with_teacher
        )
        values
          ('student', $1, $2, 'Внутренний', 'admin_comment', false),
          ('student', $1, $2, 'Педагогу', 'teacher_note', true),
          ('student', $1, $2, 'Прогресс', 'progress', true)
        returning id
      `,
      [studentId, admin.userId],
    );
    comments.push(...commentResult.rows.map((row) => row.id));

    await database.query(
      `
        insert into app.student_balances (student_id, balance)
        values ($1, 123.45)
      `,
      [studentId],
    );
    const subscription = await database.query<{ id: string }>(
      `
        insert into app.subscriptions (
          student_id, lessons_total, lessons_used, status, expires_at
        )
        values ($1, 10, 4, 'active', current_date + 30)
        returning id
      `,
      [studentId],
    );
    subscriptions.push(subscription.rows[0]!.id);

    const references = new ClientReferenceService(database);
    const access = new AccessMutationsRepository(database);
    service = new ClientCardReadService(
      database,
      references,
      access,
      new EffectiveAccessEvaluator(new HardInvariantPolicy()),
    );
  });

  afterAll(async () => {
    await database.query(
      "delete from app.student_balances where student_id = any($1::uuid[])",
      [students],
    );
    await database.query(
      "delete from app.subscriptions where id = any($1::uuid[])",
      [subscriptions],
    );
    await database.query(
      "delete from app.entity_comments where id = any($1::uuid[])",
      [comments],
    );
    await database.query(
      "delete from app.lesson_homeworks where id = any($1::uuid[])",
      [homework],
    );
    await database.query("delete from app.tasks where id = any($1::uuid[])", [
      tasks,
    ]);
    await database.query("delete from app.lessons where id = any($1::uuid[])", [
      lessons,
    ]);
    await database.query(
      "delete from app.students where id = any($1::uuid[])",
      [students],
    );
    await database.query(
      "delete from app.teachers where id = any($1::uuid[])",
      [teachers],
    );
    await database.query(
      "delete from app.branches where id = any($1::uuid[])",
      [branches],
    );
    await database.query(
      `
        delete from app.aggregate_versions
        where aggregate_type = 'access:user'
          and aggregate_id = any($1::text[])
      `,
      [users],
    );
    await database.query("delete from app.users where id = any($1::uuid[])", [
      users,
    ]);
    await database.onModuleDestroy();
  });

  afterEach(() => jest.restoreAllMocks());

  it("composes the full Manager card in three bounded queries", async () => {
    const query = jest.spyOn(database, "query");
    const result = await service.load(manager, {
      type: "student",
      id: studentId,
    });

    expect(query).toHaveBeenCalledTimes(3);
    expect(result).toMatchObject({
      projection: "full",
      header: {
        type: "student",
        id: studentId,
        displayName: "Анна Клиент",
        branchName: "Центр",
      },
      indicators: {
        activeSubscriptionRemaining: 6,
        comments: 3,
      },
      sections: {
        lessons: { count: 2 },
        tasks: { count: 1 },
        homework: { count: 2 },
        comments: { count: 3 },
        finance: { balanceMinor: 12345 },
      },
    });
  });

  it("keeps client Tasks out of the Admin projection", async () => {
    const result = await service.load(admin, {
      type: "student",
      id: studentId,
    });

    expect(result.sections).toMatchObject({ tasks: { count: 0 } });
    expect(result.tasks).toEqual([]);
  });

  it("returns only assigned learning context and shared comments to Teacher", async () => {
    const query = jest.spyOn(database, "query");
    const result = await service.load(assignedTeacher, {
      type: "student",
      id: studentId,
    });
    const serialized = JSON.stringify(result);

    expect(query).toHaveBeenCalledTimes(3);
    expect(result.projection).toBe("teacher");
    expect(result.lessons.map((lesson) => lesson.id)).toEqual([
      assignedLessonId,
    ]);
    expect(result.homework).toHaveLength(1);
    expect(result.comments.map((comment) => comment.body)).toEqual(
      expect.arrayContaining(["Прогресс", "Педагогу"]),
    );
    expect(result.comments).toHaveLength(2);
    expect(result.sections).not.toHaveProperty("tasks");
    expect(result.sections).not.toHaveProperty("groups");
    expect(result.sections).not.toHaveProperty("finance");
    expect(serialized).not.toMatch(
      /phone|email|contact|representative|finance|payment|subscription|balance/i,
    );
    expect(serialized).not.toContain("Внутренний");
    expect(serialized).not.toContain(otherLessonId);
  });

  it("returns own finance and progress-only comments to Client", async () => {
    const result = await service.load(client, {
      type: "student",
      id: studentId,
    });

    expect(result.projection).toBe("client");
    expect(result.sections).toHaveProperty("finance");
    expect(result.sections).not.toHaveProperty("tasks");
    expect(result.comments.map((comment) => comment.body)).toEqual([
      "Прогресс",
    ]);
  });

  it("hides foreign existence from an unrelated Teacher", async () => {
    await expect(
      service.load(unrelatedTeacher, {
        type: "student",
        id: studentId,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
