import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { PasswordService } from "../auth/password.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { CrmPolicy } from "./crm.policy";
import { StaffService } from "./staff.service";
import { TeachersService } from "./teachers.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (!new Set(["127.0.0.1", "localhost", "[::1]"]).has(new URL(databaseUrl).hostname)) {
  throw new Error("Person account tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Teacher and staff app accounts (PostgreSQL)", () => {
  let pool: Pool;
  let client: PoolClient;
  let staff: StaffService;
  let teachers: TeachersService;
  let passwords: PasswordService;
  let actor: ActorContext;
  let branchId: string;
  let disciplineId: string;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    client = await pool.connect();
    await client.query("begin");

    actor = { userId: randomUUID(), role: "director" };
    branchId = randomUUID();
    disciplineId = randomUUID();
    await client.query(
      `insert into app.users (id, email, role, profile_completed)
       values ($1, $2, 'director', true)`,
      [actor.userId, `${actor.userId}@test.local`],
    );
    await client.query(
      `insert into app.branches (id, name) values ($1, 'Оборонная')`,
      [branchId],
    );
    await client.query(
      `insert into app.disciplines (id, name) values ($1, 'Вокал')`,
      [disciplineId],
    );
    await client.query(
      `insert into app.branch_disciplines (branch_id, discipline_id)
       values ($1, $2)`,
      [branchId, disciplineId],
    );

    const database = {
      query: (text: string, params?: unknown[]) => client.query(text, params),
      transaction: <T>(work: (transactionClient: PoolClient) => Promise<T>) =>
        work(client),
    } as unknown as DatabaseService;
    const audit = {
      record: jest.fn().mockResolvedValue(undefined),
    } as unknown as AuditService;
    passwords = new PasswordService();
    const policy = new CrmPolicy();
    staff = new StaffService(database, audit, policy, passwords);
    teachers = new TeachersService(database, audit, policy, passwords);
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("creates new accounts atomically and provisions access for legacy records once", async () => {
    const suffix = randomUUID();
    const staffEmail = `staff-${suffix}@test.local`;
    const teacherEmail = `teacher-${suffix}@test.local`;
    const legacyStaffEmail = `legacy-staff-${suffix}@test.local`;
    const legacyTeacherEmail = `legacy-teacher-${suffix}@test.local`;
    const staffPassword = "staff-password-123";
    const teacherPassword = "teacher-password-123";

    const createdStaff = await staff.createStaff(actor, {
      firstName: "Анна",
      lastName: "Администратор",
      email: staffEmail,
      password: staffPassword,
      role: "admin",
      branchIds: [branchId],
    });
    const createdTeacher = await teachers.createTeacher(actor, {
      firstName: "Ирина",
      lastName: "Педагог",
      email: teacherEmail,
      password: teacherPassword,
      branchIds: [branchId],
      disciplineIds: [disciplineId],
    });

    expect(createdStaff).toMatchObject({
      email: staffEmail,
      appRole: "admin",
      isAppAccount: true,
    });
    expect(createdTeacher).toMatchObject({
      email: teacherEmail,
      appRole: "teacher",
      isAppAccount: true,
      specialization: "Вокал",
    });

    await client.query(
      `update app.teacher_branches
       set active_until = current_date - 1
       where teacher_id = $1`,
      [createdTeacher.id],
    );
    await teachers.updateTeacher(actor, String(createdTeacher.id), {
      branchIds: [branchId],
      disciplineIds: [disciplineId],
    });
    const reopenedAssignment = await client.query<{ active_until: Date | null }>(
      `select active_until from app.teacher_branches where teacher_id = $1`,
      [createdTeacher.id],
    );
    expect(reopenedAssignment.rows[0]?.active_until).toBeNull();

    const legacyStaffId = randomUUID();
    const legacyTeacherId = randomUUID();
    await client.query(
      `insert into app.staff_members (id, role, position)
       values ($1, 'admin', 'Администратор')`,
      [legacyStaffId],
    );
    await client.query(
      `insert into app.staff_branch_assignments (staff_member_id, branch_id)
       values ($1, $2)`,
      [legacyStaffId, branchId],
    );
    await client.query(
      `insert into app.teachers (id, status, specialization)
       values ($1, 'active', 'Вокал')`,
      [legacyTeacherId],
    );

    const provisionedStaff = await staff.provisionAccess(actor, legacyStaffId, {
      email: legacyStaffEmail,
      password: staffPassword,
      role: "admin",
    });
    const provisionedTeacher = await teachers.provisionAccess(
      actor,
      legacyTeacherId,
      { email: legacyTeacherEmail, password: teacherPassword },
    );
    expect(provisionedStaff).toMatchObject({
      email: legacyStaffEmail,
      appRole: "admin",
      isAppAccount: true,
    });
    expect(provisionedTeacher).toMatchObject({
      email: legacyTeacherEmail,
      appRole: "teacher",
      isAppAccount: true,
    });

    const accounts = await client.query<{
      email: string;
      password_hash: string;
      role: string;
      is_app_account: boolean;
      link_count: string;
    }>(
      `select u.email, u.password_hash, u.role::text as role,
         u.is_app_account, count(link.id)::text as link_count
       from app.users u
       left join app.user_crm_links link
         on link.user_id = u.id and link.deleted_at is null
       where u.email = any($1::text[])
       group by u.id
       order by u.email`,
      [[staffEmail, teacherEmail, legacyStaffEmail, legacyTeacherEmail]],
    );
    expect(accounts.rows).toHaveLength(4);
    expect(accounts.rows.every((row) => row.is_app_account && row.link_count === "1")).toBe(true);
    for (const account of accounts.rows) {
      expect(
        await passwords.verify(
          account.role === "teacher" ? teacherPassword : staffPassword,
          account.password_hash,
        ),
      ).toBe(true);
    }

    await expect(
      staff.provisionAccess(actor, legacyStaffId, {
        email: `duplicate-${legacyStaffEmail}`,
        password: staffPassword,
        role: "admin",
      }),
    ).rejects.toThrow("уже имеет аккаунт");
    await expect(
      teachers.provisionAccess(actor, legacyTeacherId, {
        email: `duplicate-${legacyTeacherEmail}`,
        password: teacherPassword,
      }),
    ).rejects.toThrow("уже имеет аккаунт");
  });
});
