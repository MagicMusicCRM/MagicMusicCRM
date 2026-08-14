import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { Pool, PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { PasswordService } from "../auth/password.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { CrmPolicy } from "./crm.policy";
import { PersonAccountService } from "./person-account.service";
import { StaffService } from "./staff.service";
import { TeachersService } from "./teachers.service";
import { PlatformIntegrityRepository } from "../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
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
  let rootActor: ActorContext;
  let branchId: string;
  let secondBranchId: string;
  let disciplineId: string;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    client = await pool.connect();
    await client.query("begin");

    actor = { userId: randomUUID(), role: "director" };
    rootActor = { userId: randomUUID(), role: "system_admin" };
    branchId = randomUUID();
    secondBranchId = randomUUID();
    disciplineId = randomUUID();
    await client.query(
      `insert into app.users (id, email, role, profile_completed)
       values ($1, $2, 'director', true)`,
      [actor.userId, `${actor.userId}@test.local`],
    );
    await client.query(
      `insert into app.users (id, email, role, profile_completed)
       values ($1, $2, 'system_admin', true)`,
      [rootActor.userId, `${rootActor.userId}@test.local`],
    );
    await client.query(
      `insert into app.branches (id, name) values ($1, 'Оборонная')`,
      [branchId],
    );
    await client.query(
      `insert into app.branches (id, name) values ($1, 'Спортивная')`,
      [secondBranchId],
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
    passwords = new PasswordService({
      get: jest.fn().mockReturnValue("test-managed-password-key-at-least-32-bytes"),
    } as unknown as ConfigService);
    const policy = new CrmPolicy();
    const accounts = new PersonAccountService(database, passwords, audit);
    staff = new StaffService(database, audit, policy, accounts);
    teachers = new TeachersService(
      database,
      audit,
      policy,
      accounts,
      new PlatformIntegrityService(database, new PlatformIntegrityRepository()),
    );
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("creates optional app accounts and manages linked credentials atomically", async () => {
    const suffix = randomUUID();
    const staffEmail = `staff-${suffix}@test.local`;
    const teacherEmail = `teacher-${suffix}@test.local`;
    const legacyStaffEmail = `legacy-staff-${suffix}@test.local`;
    const legacyTeacherEmail = `legacy-teacher-${suffix}@test.local`;
    const staffPassword = "staff-password-123";
    const teacherPassword = "teacher-password-123";

    const staffWithoutLogin = await staff.createStaff(actor, {
      firstName: "Технический",
      lastName: "Администратор",
      accessRole: "manager",
      branchIds: [branchId, secondBranchId],
    });
    const teacherWithoutLogin = await teachers.createTeacher(actor, {
      firstName: "Технический",
      lastName: "Преподаватель",
      accessRole: "manager",
      branchIds: [branchId],
      disciplineIds: [disciplineId],
    });
    expect(staffWithoutLogin).toMatchObject({
      email: null,
      appRole: "manager",
      isAppAccount: false,
      passwordConfigured: false,
    });
    expect(teacherWithoutLogin).toMatchObject({
      email: null,
      appRole: "manager",
      isAppAccount: false,
      passwordConfigured: false,
    });
    const technicalAccounts = await client.query<{
      is_app_account: boolean;
      password_hash: string | null;
      link_count: string;
    }>(
      `select u.is_app_account, u.password_hash,
         count(link.id)::text as link_count
       from app.user_crm_links link
       join app.users u on u.id = link.user_id
       where (link.entity_type = 'staff' and link.entity_id = $1)
          or (link.entity_type = 'teacher' and link.entity_id = $2)
       group by u.id`,
      [staffWithoutLogin.id, teacherWithoutLogin.id],
    );
    expect(technicalAccounts.rows).toHaveLength(2);
    expect(
      technicalAccounts.rows.every(
        (row) =>
          !row.is_app_account &&
          row.password_hash === null &&
          row.link_count === "1",
      ),
    ).toBe(true);

    const directorTeacher = await teachers.createTeacher(rootActor, {
      firstName: "Технический",
      lastName: "Директор",
      accessRole: "director",
      branchIds: [branchId],
    });
    await expect(
      teachers.provisionAccess(actor, String(directorTeacher.id), {
        email: `director-teacher-${suffix}@test.local`,
        password: teacherPassword,
      }),
    ).rejects.toThrow("более низкой роли");

    const createdStaff = await staff.createStaff(actor, {
      firstName: "Анна",
      lastName: "Администратор",
      email: staffEmail,
      password: staffPassword,
      branchIds: [branchId],
    });
    const createdTeacher = await teachers.createTeacher(actor, {
      firstName: "Ирина",
      lastName: "Педагог",
      email: teacherEmail,
      password: teacherPassword,
      branchIds: [branchId],
      disciplineIds: [disciplineId],
      customDataPatch: {
        levels: ["Начальный"],
        categories: ["Дети"],
      },
      salary: 15000,
      rate: 750,
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
      salary: 15000,
      currentRate: 750,
    });

    const updatedStaff = await staff.updateStaff(
      actor,
      String(createdStaff.id),
      {
        phone: "+79990001122",
        branchIds: [branchId, secondBranchId],
      },
    );
    expect(updatedStaff).toMatchObject({
      id: createdStaff.id,
      phone: "+79990001122",
      lifecycleState: "active",
    });
    expect(updatedStaff.branches).toHaveLength(2);

    const teacherUpdateRequestId = `request-teacher-update-${suffix}`;
    const updatedTeacher = await teachers.updateTeacher(
      actor,
      String(createdTeacher.id),
      {
        customDataPatch: {
          levels: ["Начальный", "Средний"],
          categories: ["Дети"],
        },
        salary: 20000,
        rate: 900,
        branchIds: [branchId],
        disciplineIds: [disciplineId],
        payrollExpectedVersion: 0,
        payrollReasonText: "Плановое изменение условий",
      },
      {
        idempotencyKey: `teacher-update-${suffix}`,
        requestId: teacherUpdateRequestId,
      },
    );
    expect(updatedTeacher).toMatchObject({
      salary: 20000,
      currentRate: 900,
      payrollVersion: 1,
      customData: {
        levels: ["Начальный", "Средний"],
        categories: ["Дети"],
      },
    });
    const payrollIntegrity = await client.query<{
      aggregate_version: string;
      audit_count: string;
      outbox_count: string;
    }>(
      `select
         (select version::text from app.aggregate_versions
           where aggregate_type = 'teacher:payroll' and aggregate_id = $1)
           as aggregate_version,
         (select count(*)::text from app.audit_events where request_id = $2)
           as audit_count,
         (select count(*)::text from app.platform_outbox_events where request_id = $2)
           as outbox_count`,
      [createdTeacher.id, teacherUpdateRequestId],
    );
    expect(payrollIntegrity.rows[0]).toEqual({
      aggregate_version: "1",
      audit_count: "1",
      outbox_count: "1",
    });
    const compensationSettings = await client.query<{
      salary: string;
      custom_data: Record<string, unknown>;
      rate_count: string;
      current_rate: string;
    }>(
      `select t.salary::text, t.custom_data,
         count(tr.id)::text as rate_count,
         (array_agg(tr.rate order by tr.effective_from desc, tr.created_at desc, tr.id desc))[1]::text
           as current_rate
       from app.teachers t
       join app.teacher_rates tr on tr.teacher_id = t.id and tr.deleted_at is null
       where t.id = $1
       group by t.id`,
      [createdTeacher.id],
    );
    expect(compensationSettings.rows[0]).toMatchObject({
      salary: "20000.00",
      rate_count: "2",
      current_rate: "900.00",
      custom_data: {
        levels: ["Начальный", "Средний"],
        categories: ["Дети"],
      },
    });

    const rejectedEmail = `rejected-${suffix}@test.local`;
    await expect(
      teachers.createTeacher(actor, {
        firstName: "Ошибка",
        email: rejectedEmail,
        password: teacherPassword,
        branchIds: [branchId],
        disciplineIds: [randomUUID()],
        rate: 700,
      }),
    ).rejects.toThrow(
      "Выберите действующие филиалы и корректные справочные дисциплины",
    );
    const rejectedAccount = await client.query<{ count: string }>(
      `select count(*)::text as count from app.users where email = $1`,
      [rejectedEmail],
    );
    expect(rejectedAccount.rows[0]?.count).toBe("0");

    await client.query(
      `update app.teacher_branches
       set active_from = current_date - 2, active_until = current_date - 1
       where teacher_id = $1`,
      [createdTeacher.id],
    );
    await teachers.updateTeacher(actor, String(createdTeacher.id), {
      branchIds: [branchId],
      disciplineIds: [disciplineId],
    });
    const reopenedAssignment = await client.query<{
      active_until: Date | null;
    }>(`select active_until from app.teacher_branches where teacher_id = $1`, [
      createdTeacher.id,
    ]);
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
    expect(
      accounts.rows.every(
        (row) => row.is_app_account && row.link_count === "1",
      ),
    ).toBe(true);
    for (const account of accounts.rows) {
      expect(
        await passwords.verify(
          account.role === "teacher" ? teacherPassword : staffPassword,
          account.password_hash,
        ),
      ).toBe(true);
    }

    const changedStaffEmail = `changed-${legacyStaffEmail}`;
    const changedTeacherPassword = "changed-teacher-password-123";
    await expect(
      staff.provisionAccess(actor, legacyStaffId, {
        email: changedStaffEmail,
      }),
    ).resolves.toMatchObject({
      email: changedStaffEmail,
      passwordConfigured: true,
    });
    await expect(
      teachers.provisionAccess(actor, legacyTeacherId, {
        password: changedTeacherPassword,
      }),
    ).resolves.toMatchObject({
      email: legacyTeacherEmail,
      passwordConfigured: true,
    });
    const changedCredentials = await client.query<{
      email: string;
      password_hash: string;
      email_changed_at: Date | null;
      password_changed_at: Date | null;
    }>(
      `select email, password_hash, email_changed_at, password_changed_at
       from app.users
       where email = any($1::text[])
       order by email`,
      [[changedStaffEmail, legacyTeacherEmail]],
    );
    expect(changedCredentials.rows).toHaveLength(2);
    expect(
      changedCredentials.rows.find((row) => row.email === changedStaffEmail)
        ?.email_changed_at,
    ).not.toBeNull();
    const changedTeacher = changedCredentials.rows.find(
      (row) => row.email === legacyTeacherEmail,
    );
    expect(changedTeacher?.password_changed_at).not.toBeNull();
    expect(
      await passwords.verify(
        changedTeacherPassword,
        changedTeacher?.password_hash ?? "",
      ),
    ).toBe(true);
    await expect(staff.readAccess(actor, legacyStaffId)).resolves.toMatchObject({
      email: changedStaffEmail,
      password: staffPassword,
      passwordRecoverable: true,
    });
    await expect(
      teachers.readAccess(actor, legacyTeacherId),
    ).resolves.toMatchObject({
      email: legacyTeacherEmail,
      password: changedTeacherPassword,
      passwordRecoverable: true,
    });
  });
});
