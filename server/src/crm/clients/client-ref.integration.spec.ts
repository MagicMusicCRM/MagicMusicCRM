import { NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { randomUUID } from "crypto";
import { Pool } from "pg";
import {
  ActorContext,
  UserRole,
} from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import {
  ClientRefDto,
  ClientRefSearchQuery,
} from "../dto/client-ref.dto";
import { ClientReferenceService } from "./client-reference.service";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (!new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)) {
  throw new Error("ClientRef tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("ClientReferenceService (PostgreSQL)", () => {
  let database: DatabaseService;
  let service: ClientReferenceService;
  const users: string[] = [];
  const profiles: string[] = [];
  const teachers: string[] = [];
  const students: string[] = [];
  const leads: string[] = [];
  const lessons: string[] = [];
  const tasks: string[] = [];
  let admin: ActorContext;
  let client: ActorContext;
  let teacher: ActorContext;
  let unrelatedTeacher: ActorContext;
  let ownStudentId: string;
  let assignedStudentId: string;
  let foreignStudentId: string;
  let archivedStudentId: string;
  let linkedLeadId: string;
  let assignedLeadId: string;
  let taskLeadId: string;
  let foreignLeadId: string;

  async function createActor(
    role: UserRole,
    firstName: string,
    lastName: string,
  ): Promise<ActorContext & { profileId: string }> {
    const created = await database.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, $2::app.user_role, now())
        returning id
      `,
      [`v4-client-ref-${randomUUID()}@example.test`, role],
    );
    const userId = created.rows[0]!.id;
    users.push(userId);
    const profile = await database.query<{ id: string }>(
      `
        insert into app.profiles (
          user_id,
          first_name,
          last_name,
          phone
        )
        values ($1, $2, $3, '+79990000000')
        returning id
      `,
      [userId, firstName, lastName],
    );
    const profileId = profile.rows[0]!.id;
    profiles.push(profileId);
    return { userId, role, profileId };
  }

  async function createStudent(
    profileId: string,
    archived = false,
  ): Promise<string> {
    const created = await database.query<{ id: string }>(
      `
        insert into app.students (
          profile_id,
          status,
          deleted_at
        )
        values ($1, 'active', case when $2 then now() else null end)
        returning id
      `,
      [profileId, archived],
    );
    const id = created.rows[0]!.id;
    students.push(id);
    return id;
  }

  async function createLead(
    firstName: string,
    lastName: string,
    archived = false,
  ): Promise<string> {
    const created = await database.query<{ id: string }>(
      `
        insert into app.leads (
          first_name,
          last_name,
          phone,
          email,
          deleted_at
        )
        values ($1, $2, '+79991112233', 'private@example.test',
          case when $3 then now() else null end)
        returning id
      `,
      [firstName, lastName, archived],
    );
    const id = created.rows[0]!.id;
    leads.push(id);
    return id;
  }

  async function createLesson(
    teacherId: string,
    ref: { type: "student" | "lead"; id: string },
  ): Promise<void> {
    const created = await database.query<{ id: string }>(
      `
        insert into app.lessons (
          student_id,
          lead_id,
          teacher_id,
          scheduled_at,
          created_by
        )
        values (
          case when $2 = 'student' then $3::uuid else null end,
          case when $2 = 'lead' then $3::uuid else null end,
          $1,
          now(),
          $4
        )
        returning id
      `,
      [teacherId, ref.type, ref.id, admin.userId],
    );
    lessons.push(created.rows[0]!.id);
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
          where email like 'v4-client-ref-%@example.test'
        );
      delete from app.users
      where email like 'v4-client-ref-%@example.test';
    `);
    service = new ClientReferenceService(database);

    admin = await createActor("admin", "Admin", "Resolver");
    client = await createActor("client", "Клиент", "Свой");
    teacher = await createActor("teacher", "Педагог", "Назначенный");
    unrelatedTeacher = await createActor(
      "teacher",
      "Педагог",
      "Посторонний",
    );
    const assignedClient = await createActor(
      "client",
      "Анна",
      "Назначенная",
    );
    const foreignClient = await createActor("client", "Борис", "Чужой");
    const archivedClient = await createActor("client", "Вера", "Архивная");

    ownStudentId = await createStudent(
      (client as ActorContext & { profileId: string }).profileId,
    );
    assignedStudentId = await createStudent(assignedClient.profileId);
    foreignStudentId = await createStudent(foreignClient.profileId);
    archivedStudentId = await createStudent(archivedClient.profileId, true);

    linkedLeadId = await createLead("Галина", "Связанная");
    assignedLeadId = await createLead("Денис", "Пробный");
    taskLeadId = await createLead("Елена", "Задача");
    foreignLeadId = await createLead("Жанна", "Чужая");

    await database.query(
      `
        insert into app.user_crm_links (
          user_id,
          entity_type,
          entity_id,
          link_source,
          confirmed_at
        )
        values ($1, 'lead', $2, 'manual_phone', now())
      `,
      [client.userId, linkedLeadId],
    );

    for (const actorWithProfile of [
      teacher as ActorContext & { profileId: string },
      unrelatedTeacher as ActorContext & { profileId: string },
    ]) {
      const created = await database.query<{ id: string }>(
        `
          insert into app.teachers (profile_id, status)
          values ($1, 'active')
          returning id
        `,
        [actorWithProfile.profileId],
      );
      teachers.push(created.rows[0]!.id);
    }
    await createLesson(teachers[0]!, {
      type: "student",
      id: assignedStudentId,
    });
    await createLesson(teachers[0]!, {
      type: "lead",
      id: assignedLeadId,
    });

    const task = await database.query<{ id: string }>(
      `
        insert into app.tasks (
          entity_type,
          entity_id,
          title,
          assigned_to,
          created_by
        )
        values ('lead', $1, 'Связаться', $2, $3)
        returning id
      `,
      [taskLeadId, teacher.userId, admin.userId],
    );
    tasks.push(task.rows[0]!.id);
  });

  afterAll(async () => {
    if (tasks.length > 0) {
      await database.query(
        "delete from app.tasks where id = any($1::uuid[])",
        [tasks],
      );
    }
    if (lessons.length > 0) {
      await database.query(
        "delete from app.lessons where id = any($1::uuid[])",
        [lessons],
      );
    }
    await database.query(
      `
        delete from app.user_crm_links
        where user_id = any($1::uuid[])
      `,
      [users],
    );
    await database.query(
      "delete from app.students where id = any($1::uuid[])",
      [students],
    );
    await database.query(
      "delete from app.leads where id = any($1::uuid[])",
      [leads],
    );
    await database.query(
      "delete from app.teachers where id = any($1::uuid[])",
      [teachers],
    );
    await database.query(
      `
        delete from app.aggregate_versions
        where aggregate_type = 'access:user'
          and aggregate_id = any($1::text[])
      `,
      [users],
    );
    await database.query(
      "delete from app.users where id = any($1::uuid[])",
      [users],
    );
    await database.onModuleDestroy();
  });

  it("validates the discriminator and UUID instead of guessing an entity type", async () => {
    const missingType = plainToInstance(ClientRefDto, {
      id: ownStudentId,
    });
    const invalidType = plainToInstance(ClientRefDto, {
      type: "person",
      id: ownStudentId,
    });
    const invalidId = plainToInstance(ClientRefDto, {
      type: "student",
      id: "not-a-uuid",
    });

    expect(await validate(missingType)).toHaveLength(1);
    expect(await validate(invalidType)).toHaveLength(1);
    expect(await validate(invalidId)).toHaveLength(1);
  });

  it("resolves typed Lead and Student references for operational staff", async () => {
    await expect(
      service.resolve(admin, { type: "student", id: ownStudentId }),
    ).resolves.toMatchObject({
      ref: { type: "student", id: ownStudentId },
      label: "Клиент Свой",
      lifecycleState: "active",
      tombstone: false,
      archivedAt: null,
    });
    await expect(
      service.resolve(admin, { type: "lead", id: linkedLeadId }),
    ).resolves.toMatchObject({
      ref: { type: "lead", id: linkedLeadId },
      label: "Галина Связанная",
      lifecycleState: "active",
      tombstone: false,
    });
  });

  it("returns a stable tombstone for an archived allowed reference", async () => {
    const result = await service.resolve(admin, {
      type: "student",
      id: archivedStudentId,
    });

    expect(result).toMatchObject({
      ref: { type: "student", id: archivedStudentId },
      label: "Вера Архивная",
      lifecycleState: "archived",
      tombstone: true,
    });
    expect(result.archivedAt).not.toBeNull();
  });

  it("scopes teacher resolution to lessons/tasks and hides foreign existence", async () => {
    await expect(
      service.resolve(teacher, {
        type: "student",
        id: assignedStudentId,
      }),
    ).resolves.toMatchObject({
      ref: { type: "student", id: assignedStudentId },
    });
    await expect(
      service.resolve(teacher, { type: "lead", id: assignedLeadId }),
    ).resolves.toMatchObject({
      ref: { type: "lead", id: assignedLeadId },
    });
    await expect(
      service.resolve(teacher, { type: "lead", id: taskLeadId }),
    ).resolves.toMatchObject({
      ref: { type: "lead", id: taskLeadId },
    });
    await expect(
      service.resolve(unrelatedTeacher, {
        type: "student",
        id: assignedStudentId,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      service.resolve(teacher, {
        type: "student",
        id: foreignStudentId,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      service.resolve(teacher, { type: "lead", id: foreignLeadId }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it("searches both types within actor scope without contact or finance fields", async () => {
    const teacherResult = await service.search(
      teacher,
      plainToInstance(ClientRefSearchQuery, { limit: 50 }),
    );
    const teacherRefs = teacherResult.items.map(
      (item) => `${item.ref.type}:${item.ref.id}`,
    );
    expect(teacherRefs).toEqual(
      expect.arrayContaining([
        `student:${assignedStudentId}`,
        `lead:${assignedLeadId}`,
        `lead:${taskLeadId}`,
      ]),
    );
    expect(teacherRefs).not.toEqual(
      expect.arrayContaining([
        `student:${foreignStudentId}`,
        `lead:${foreignLeadId}`,
      ]),
    );

    const clientResult = await service.search(
      client,
      plainToInstance(ClientRefSearchQuery, { limit: 50 }),
    );
    expect(clientResult.items.map((item) => item.ref)).toEqual(
      expect.arrayContaining([
        { type: "student", id: ownStudentId },
        { type: "lead", id: linkedLeadId },
      ]),
    );
    const serialized = JSON.stringify({ teacherResult, clientResult });
    expect(serialized).not.toMatch(
      /phone|email|contact|finance|payment|balance|subscription/i,
    );
    expect(serialized).not.toContain("+7999");
    expect(serialized).not.toContain("private@example.test");
  });

  it("filters by name/type and excludes tombstones unless explicitly requested", async () => {
    const filtered = await service.search(admin, {
      q: "Галина",
      type: "lead",
      includeArchived: false,
      limit: 10,
    });
    expect(filtered.items).toEqual([
      expect.objectContaining({
        ref: { type: "lead", id: linkedLeadId },
        label: "Галина Связанная",
      }),
    ]);

    const defaultResults = await service.search(admin, {
      q: "Архивная",
      limit: 10,
    });
    expect(defaultResults.items).toEqual([]);
    const archivedResults = await service.search(admin, {
      q: "Архивная",
      includeArchived: true,
      limit: 10,
    });
    expect(archivedResults.items).toEqual([
      expect.objectContaining({
        ref: { type: "student", id: archivedStudentId },
        lifecycleState: "archived",
        tombstone: true,
      }),
    ]);
  });
});
