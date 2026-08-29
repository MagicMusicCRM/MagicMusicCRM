import { ConfigService } from "@nestjs/config";
import { NotFoundException } from "@nestjs/common";
import { randomUUID } from "crypto";
import { Pool } from "pg";
import { AccessMutationsRepository } from "../../access-control/access-mutations.repository";
import { EffectiveAccessEvaluator } from "../../access-control/effective-access-evaluator";
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
        with task as (
          insert into app.shared_tasks (
            title, all_day, start_at, linked_entity_type,
            linked_entity_id, created_by
          )
          values ('Позвонить', true, now(), 'student', $1, $2)
          returning id
        )
        insert into app.task_audiences (task_id, audience_type, target_id)
        select id, 'user', $3 from task
        returning task_id as id
      `,
      [studentId, admin.userId, manager.userId],
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
      new EffectiveAccessEvaluator(),
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
    await database.query(
      "delete from app.task_audiences where task_id = any($1::uuid[])",
      [tasks],
    );
    await database.query(
      "delete from app.shared_tasks where id = any($1::uuid[])",
      [tasks],
    );
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

  it("returns explicit zero cancellation indicators when effective facts are absent", async () => {
    const result = await service.load(manager, {
      type: "student",
      id: studentId,
    });

    expect(result.indicators).toMatchObject({
      paidMisses: 0,
      partiallyPaidMisses: 0,
      unpaidMisses: 0,
    });
  });

  it("counts only effective cancellation facts and scopes them to the Teacher's lessons", async () => {
    const extraLessons = await database.query<{ id: string }>(
      `
        insert into app.lessons (
          student_id, teacher_id, branch_id, scheduled_at, created_by
        )
        values
          ($1, $2, $3, now() + interval '3 days', $4),
          ($1, $2, $3, now() + interval '4 days', $4)
        returning id
      `,
      [
        studentId,
        teachers[0],
        branches[0],
        admin.userId,
      ],
    );
    const [partiallyPaidLessonId, unpaidLessonId] = extraLessons.rows.map(
      (row) => row.id,
    );
    const revision = await database.query<{ id: string }>(
      `select id from app.crm_configuration_revisions
       order by created_at asc, id asc limit 1`,
    );
    const configurationRevisionId = revision.rows[0]!.id;
    const facts: string[] = [];

    const insertFact = async (
      lessonId: string,
      settlementTypeKey: string,
      settlementLabel: string,
      supersedesFactId?: string,
    ): Promise<string> => {
      const result = await database.query<{ id: string }>(
        `
          insert into app.lesson_client_charge_facts (
            lesson_id, client_type, client_id, charge_type, snapshot_value,
            amount_minor, units, settlement_type_key, settlement_label,
            settlement_color_token, hour_share_basis_points,
            fixed_penalty_minor, configuration_revision_id, supersedes_fact_id
          )
          values (
            $1, 'student', $2, 'none', 0, 0, 0, $3, $4,
            'settlement.miss', 0, 0, $5, $6
          )
          returning id
        `,
        [
          lessonId,
          studentId,
          settlementTypeKey,
          settlementLabel,
          configurationRevisionId,
          supersedesFactId ?? null,
        ],
      );
      const factId = result.rows[0]!.id;
      facts.push(factId);
      return factId;
    };

    try {
      const supersededUnpaidFactId = await insertFact(
        assignedLessonId,
        "unpaid_miss",
        "Неоплаченный пропуск",
      );
      await insertFact(
        assignedLessonId,
        "paid_miss",
        "Оплачиваемый пропуск",
        supersededUnpaidFactId,
      );
      await insertFact(
        partiallyPaidLessonId!,
        "partially_paid_miss",
        "Частично оплачиваемый пропуск",
      );
      await insertFact(
        unpaidLessonId!,
        "unpaid_miss",
        "Неоплаченный пропуск",
      );
      await insertFact(
        otherLessonId,
        "paid_miss",
        "Оплачиваемый пропуск",
      );

      const managerResult = await service.load(manager, {
        type: "student",
        id: studentId,
      });
      const teacherResult = await service.load(assignedTeacher, {
        type: "student",
        id: studentId,
      });

      expect({
        paidMisses: managerResult.indicators.paidMisses,
        partiallyPaidMisses: managerResult.indicators.partiallyPaidMisses,
        unpaidMisses: managerResult.indicators.unpaidMisses,
      }).toEqual({
        paidMisses: 2,
        partiallyPaidMisses: 1,
        unpaidMisses: 1,
      });
      expect({
        paidMisses: teacherResult.indicators.paidMisses,
        partiallyPaidMisses: teacherResult.indicators.partiallyPaidMisses,
        unpaidMisses: teacherResult.indicators.unpaidMisses,
      }).toEqual({
        paidMisses: 1,
        partiallyPaidMisses: 1,
        unpaidMisses: 1,
      });
    } finally {
      await database.transaction(async (transaction) => {
        await transaction.query("set local session_replication_role = replica");
        await transaction.query(
          "delete from app.lesson_client_charge_facts where id = any($1::uuid[])",
          [facts],
        );
        await transaction.query("delete from app.lessons where id = any($1::uuid[])", [
          extraLessons.rows.map((row) => row.id),
        ]);
      });
    }
  });

  it("keeps expiry inclusive and burns the remainder on the next branch-local day", async () => {
    const subscriptionId = subscriptions[0]!;
    const branchId = branches[0]!;
    try {
      await database.query(
        "update app.branches set timezone_name = 'Asia/Yekaterinburg' where id = $1",
        [branchId],
      );
      await database.query(
        `update app.students
         set branch_id = null,
             custom_data = jsonb_set(
               coalesce(custom_data, '{}'::jsonb),
               '{branchId}',
               to_jsonb($1::text)
             )
         where id = $2`,
        [branchId, studentId],
      );
      await database.query(
        `update app.subscriptions
         set expires_at = timezone('Asia/Yekaterinburg', now())::date
         where id = $1`,
        [subscriptionId],
      );

      const finalDay = await service.load(manager, {
        type: "student",
        id: studentId,
      });
      expect(finalDay.indicators.activeSubscriptionRemaining).toBe(6);

      await database.query(
        `
          update app.subscriptions
          set expires_at = timezone('Asia/Yekaterinburg', now())::date - 1
          where id = $1
        `,
        [subscriptionId],
      );

      const nextDay = await service.load(manager, {
        type: "student",
        id: studentId,
      });
      expect(nextDay.indicators.activeSubscriptionRemaining).toBeNull();
      expect(nextDay.sections.finance).toMatchObject({
        activeSubscription: null,
      });
    } finally {
      await database.query(
        `update app.students
         set branch_id = $1,
             custom_data = coalesce(custom_data, '{}'::jsonb)
               - 'branchId' - 'branch_id'
         where id = $2`,
        [branchId, studentId],
      );
      await database.query(
        "update app.branches set timezone_name = 'Europe/Moscow' where id = $1",
        [branchId],
      );
      await database.query(
        `update app.subscriptions
         set expires_at = timezone('Europe/Moscow', now())::date + 30
         where id = $1`,
        [subscriptionId],
      );
    }
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
