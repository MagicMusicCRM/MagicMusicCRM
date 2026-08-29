import { ForbiddenException, NotFoundException } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import * as ExcelJS from "exceljs";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { PlatformIntegrityRepository } from "../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { CrmPolicy } from "./crm.policy";
import { PayrollService } from "./payroll.service";
import { PayrollAccrualCalculator } from "./payroll/payroll-accrual-calculator";
import { PayrollReadRepository } from "./payroll/payroll-read.repository";
import { TeacherPayrollCommandService } from "./payroll/teacher-payroll-command.service";
import { TeacherPayrollQueryService } from "./payroll/teacher-payroll-query.service";
import { TeacherStatsXlsxService } from "./payroll/teacher-stats-xlsx.service";
import { OoxmlWorkbookBuilder } from "../common/ooxml-workbook.builder";
import { TeacherStatsReportService } from "./payroll/teacher-stats-report.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Teacher payroll tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Teacher payroll integrity (PostgreSQL)", () => {
  let pool: Pool;
  let client: PoolClient;
  let payroll: PayrollService;
  let actor: ActorContext;
  let teacherId: string;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await pool.query(`
      do $$
      begin
        if not exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
          create role magiccrm_app;
        end if;
      end $$
    `);
    await new MigrationRunner(pool).up();
    client = await pool.connect();
    await client.query("begin");

    const actorId = randomUUID();
    const teacherUserId = randomUUID();
    actor = { userId: actorId, role: "director" };
    const actorProfileId = randomUUID();
    const teacherProfileId = randomUUID();
    teacherId = randomUUID();
    await client.query(
      `
        insert into app.users (id, email, role, profile_completed)
        values
          ($1, $2, 'director', true),
          ($3, $4, 'teacher', true)
      `,
      [
        actorId,
        `payroll-${actorId}@test.local`,
        teacherUserId,
        `payroll-teacher-${teacherUserId}@test.local`,
      ],
    );
    await client.query(
      `
        insert into app.profiles (id, user_id, first_name, last_name)
        values
          ($1, $2, 'Диана', 'Директор'),
          ($3, $4, 'Ирина', 'Педагог')
      `,
      [actorProfileId, actorId, teacherProfileId, teacherUserId],
    );
    await client.query(
      `insert into app.teachers (id, profile_id, status) values ($1, $2, 'active')`,
      [teacherId, teacherProfileId],
    );

    const database = {
      query: (text: string, params?: unknown[]) => client.query(text, params),
      transaction: <T>(work: (transactionClient: PoolClient) => Promise<T>) =>
        work(client),
    } as unknown as DatabaseService;
    const integrity = new PlatformIntegrityService(
      database,
      new PlatformIntegrityRepository(),
    );
    const repository = new PayrollReadRepository(database);
    const policy = new CrmPolicy();
    const calculator = new PayrollAccrualCalculator();
    const report = new TeacherStatsReportService(
      repository,
      policy,
      calculator,
    );
    payroll = new PayrollService(
      new TeacherPayrollQueryService(repository, policy, calculator),
      new TeacherPayrollCommandService(
        repository,
        policy,
        integrity,
        calculator,
      ),
      report,
      new TeacherStatsXlsxService(report, new OoxmlWorkbookBuilder()),
    );
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("keeps global payroll details inside an Admin or Manager's complete teacher branch scope", async () => {
    await client.query("savepoint direct_payroll_scope");
    try {
      const branches = await client.query<{ id: string }>(
        `insert into app.branches (name)
       values ($1), ($2) returning id`,
        [
          `Payroll detail assigned ${randomUUID()}`,
          `Payroll detail foreign ${randomUUID()}`,
        ],
      );
      const assignedBranchId = branches.rows[0]!.id;
      const foreignBranchId = branches.rows[1]!.id;
      const operationalActors: ActorContext[] = [];

      for (const role of ["admin", "manager"] as const) {
        const user = await client.query<{ id: string }>(
          `insert into app.users (email, role, profile_completed)
         values ($1, $2, true) returning id`,
          [`payroll-detail-${role}-${randomUUID()}@test.local`, role],
        );
        const profile = await client.query<{ id: string }>(
          `insert into app.profiles (user_id, first_name, last_name)
         values ($1, $2, 'Payroll') returning id`,
          [user.rows[0]!.id, role],
        );
        const staff = await client.query<{ id: string }>(
          `insert into app.staff_members (profile_id, role)
         values ($1, $2) returning id`,
          [profile.rows[0]!.id, role],
        );
        await client.query(
          `insert into app.user_crm_links (
           user_id, entity_type, entity_id, link_source, confirmed_at
         ) values ($1, 'staff', $2, 'manual_email', now())`,
          [user.rows[0]!.id, staff.rows[0]!.id],
        );
        await client.query(
          `insert into app.staff_branch_assignments (staff_member_id, branch_id)
         values ($1, $2)`,
          [staff.rows[0]!.id, assignedBranchId],
        );
        operationalActors.push({ userId: user.rows[0]!.id, role });
      }

      const staleDirector = await client.query<{ id: string }>(
        `insert into app.users (email, role, profile_completed)
         values ($1, 'director', true) returning id`,
        [`payroll-detail-stale-${randomUUID()}@test.local`],
      );
      const staleProfile = await client.query<{ id: string }>(
        `insert into app.profiles (user_id, first_name, last_name)
         values ($1, 'Stale', 'Director') returning id`,
        [staleDirector.rows[0]!.id],
      );
      const staleStaff = await client.query<{ id: string }>(
        `insert into app.staff_members (profile_id, role)
         values ($1, 'manager') returning id`,
        [staleProfile.rows[0]!.id],
      );
      await client.query(
        `insert into app.user_crm_links (
           user_id, entity_type, entity_id, link_source, confirmed_at
         ) values ($1, 'staff', $2, 'manual_email', now())`,
        [staleDirector.rows[0]!.id, staleStaff.rows[0]!.id],
      );
      await client.query(
        `insert into app.staff_branch_assignments (staff_member_id, branch_id)
         values ($1, $2)`,
        [staleStaff.rows[0]!.id, assignedBranchId],
      );
      await client.query("update app.users set role = 'manager' where id = $1", [
        staleDirector.rows[0]!.id,
      ]);
      operationalActors.push({
        userId: staleDirector.rows[0]!.id,
        role: "director",
      });

      const teacherUsers = await client.query<{ id: string }>(
        `insert into app.users (email, role, profile_completed)
       values ($1, 'teacher', true), ($2, 'teacher', true),
         ($3, 'teacher', true) returning id`,
        [
          `payroll-detail-assigned-${randomUUID()}@test.local`,
          `payroll-detail-foreign-${randomUUID()}@test.local`,
          `payroll-detail-mixed-${randomUUID()}@test.local`,
        ],
      );
      const teacherProfiles = await client.query<{ id: string }>(
        `insert into app.profiles (user_id, first_name, last_name)
       values ($1, 'Assigned', 'Payroll'), ($2, 'Foreign', 'Payroll'),
         ($3, 'Mixed', 'Payroll') returning id`,
        [
          teacherUsers.rows[0]!.id,
          teacherUsers.rows[1]!.id,
          teacherUsers.rows[2]!.id,
        ],
      );
      const teachers = await client.query<{ id: string }>(
        `insert into app.teachers (profile_id, status)
       values ($1, 'active'), ($2, 'active'), ($3, 'active') returning id`,
        [
          teacherProfiles.rows[0]!.id,
          teacherProfiles.rows[1]!.id,
          teacherProfiles.rows[2]!.id,
        ],
      );
      const assignedTeacherId = teachers.rows[0]!.id;
      const foreignTeacherId = teachers.rows[1]!.id;
      const mixedTeacherId = teachers.rows[2]!.id;
      await client.query(
        `insert into app.teacher_branches (teacher_id, branch_id)
       values ($1, $4), ($2, $5), ($3, $4), ($3, $5)`,
        [
          assignedTeacherId,
          foreignTeacherId,
          mixedTeacherId,
          assignedBranchId,
          foreignBranchId,
        ],
      );
      await client.query(
        `insert into app.teacher_branches (
           teacher_id, branch_id, active_from, active_until
         ) values ($1, $2, current_date - 2, current_date - 1)`,
        [assignedTeacherId, foreignBranchId],
      );
      await client.query(
        `insert into app.teacher_rates (teacher_id, rate, effective_from, created_by)
       values ($1, 1111, '2026-08-01', $4),
         ($2, 2222, '2026-08-01', $4),
         ($3, 3333, '2026-08-01', $4)`,
        [assignedTeacherId, foreignTeacherId, mixedTeacherId, actor.userId],
      );
      await client.query(
        `insert into app.teacher_payouts (
         teacher_id, amount, kind, comment, paid_at, created_by
       ) values
         ($1, 111, 'payout', 'assigned-sensitive', '2026-08-10T12:00:00.000Z', $4),
         ($2, 222, 'payout', 'foreign-sensitive', '2026-08-10T12:00:00.000Z', $4),
         ($3, 333, 'payout', 'mixed-sensitive', '2026-08-10T12:00:00.000Z', $4)`,
        [assignedTeacherId, foreignTeacherId, mixedTeacherId, actor.userId],
      );

      for (const operationalActor of operationalActors) {
        const assigned = await payroll.getTeacherPayroll(
          operationalActor,
          assignedTeacherId,
        );
        expect(assigned).toMatchObject({
          teacherId: assignedTeacherId,
          currentRate: 1111,
          paidTotal: 111,
        });
        expect(assigned.payouts[0]).toMatchObject({
          amount: 111,
          comment: "assigned-sensitive",
        });
        await expect(
          payroll.getTeacherPayroll(operationalActor, foreignTeacherId),
        ).rejects.toBeInstanceOf(NotFoundException);
        await expect(
          payroll.getTeacherPayroll(operationalActor, mixedTeacherId),
        ).rejects.toBeInstanceOf(NotFoundException);
      }

      await expect(
        payroll.getTeacherPayroll(
          { userId: teacherUsers.rows[0]!.id, role: "teacher" },
          assignedTeacherId,
        ),
      ).rejects.toBeInstanceOf(ForbiddenException);
      await expect(
        payroll.getTeacherPayroll(
          { userId: randomUUID(), role: "client" },
          assignedTeacherId,
        ),
      ).rejects.toBeInstanceOf(ForbiddenException);

      const directorForeign = await payroll.getTeacherPayroll(
        actor,
        foreignTeacherId,
      );
      expect(directorForeign).toMatchObject({
        teacherId: foreignTeacherId,
        currentRate: 2222,
        paidTotal: 222,
      });
      const directorMixed = await payroll.getTeacherPayroll(
        actor,
        mixedTeacherId,
      );
      expect(directorMixed).toMatchObject({
        teacherId: mixedTeacherId,
        currentRate: 3333,
        paidTotal: 333,
      });
      const systemAdminForeign = await payroll.getTeacherPayroll(
        { userId: actor.userId, role: "system_admin" },
        foreignTeacherId,
      );
      expect(systemAdminForeign).toMatchObject({
        teacherId: foreignTeacherId,
        currentRate: 2222,
        paidTotal: 222,
      });
    } finally {
      await client.query("rollback to savepoint direct_payroll_scope");
    }
  });

  it("commits one payout, audit, outbox and version across replay/stale retries", async () => {
    const initial = await payroll.getTeacherPayroll(actor, teacherId);
    expect(initial.version).toBe(0);

    const command = {
      kind: "payout" as const,
      amount: 1500,
      comment: "За июль",
      reasonText: "Выплата задолженности за июль",
      expectedVersion: 0,
    };
    const first = await payroll.createTeacherPayout(actor, teacherId, command, {
      idempotencyKey: `payout-${teacherId}`,
      requestId: `request-${teacherId}`,
    });
    const replay = await payroll.createTeacherPayout(
      actor,
      teacherId,
      command,
      {
        idempotencyKey: `payout-${teacherId}`,
        requestId: `request-${teacherId}`,
      },
    );
    expect(first).toMatchObject({ amount: 1500, version: 1, replayed: false });
    expect(replay).toMatchObject({ id: first.id, version: 1, replayed: true });

    await expect(
      payroll.createTeacherPayout(
        actor,
        teacherId,
        { ...command, amount: 100, expectedVersion: 0 },
        {
          idempotencyKey: `stale-${teacherId}`,
          requestId: `stale-request-${teacherId}`,
        },
      ),
    ).rejects.toMatchObject({ status: 409 });

    const facts = await client.query<{
      payouts: string;
      audits: string;
      outbox: string;
      idempotency: string;
      version: string;
    }>(
      `
        select
          (select count(*)::text from app.teacher_payouts where teacher_id = $1) as payouts,
          (select count(*)::text from app.audit_events
            where entity_type = 'teacher' and entity_id = $1::text
              and action = 'crm.teacher_payout_created') as audits,
          (select count(*)::text from app.platform_outbox_events
            where aggregate_type = 'teacher:payroll' and aggregate_id = $1::text) as outbox,
          (select count(*)::text from app.idempotency_records
            where actor_key = $2 and operation = 'crm.teacher-payout.create'
              and status = 'completed') as idempotency,
          (select version::text from app.aggregate_versions
            where aggregate_type = 'teacher:payroll' and aggregate_id = $1::text) as version
      `,
      [teacherId, actor.userId],
    );
    expect(facts.rows[0]).toEqual({
      payouts: "1",
      audits: "1",
      outbox: "1",
      idempotency: "1",
      version: "1",
    });
  });

  it("keeps append-only rate history while the report stays accrual-only", async () => {
    const rate = await payroll.setTeacherRate(
      actor,
      teacherId,
      {
        rate: 900,
        effectiveFrom: "2026-08-01",
        expectedVersion: 1,
        reasonText: "Новая ставка с августа",
      },
      {
        idempotencyKey: `rate-${teacherId}`,
        requestId: `rate-request-${teacherId}`,
      },
    );
    expect(rate).toMatchObject({ rate: 900, version: 2 });

    const summary = await payroll.getTeacherPayroll(actor, teacherId);
    expect(summary.version).toBe(2);
    expect(summary.rateHistory).toEqual([
      expect.objectContaining({
        rate: 900,
        effectiveFrom: "2026-08-01",
        authorName: "Диана Директор",
      }),
    ]);

    const report = await payroll.getTeacherStatsReport(actor, {
      from: "2026-01-01T00:00:00.000Z",
      to: "2027-01-01T00:00:00.000Z",
    });
    expect(report.items).toEqual([]);
    expect(report.totals.paidTotal).toBe(0);
  });

  it("intersects Admin and Manager teacher reports and XLSX with assigned branches", async () => {
    const branches = await client.query<{ id: string }>(
      `insert into app.branches (name)
       values ($1), ($2) returning id`,
      [`Payroll assigned ${randomUUID()}`, `Payroll foreign ${randomUUID()}`],
    );
    const assignedBranchId = branches.rows[0]!.id;
    const foreignBranchId = branches.rows[1]!.id;
    const operationalActors: ActorContext[] = [];

    for (const role of ["admin", "manager"] as const) {
      const user = await client.query<{ id: string }>(
        `insert into app.users (email, role, profile_completed)
         values ($1, $2, true) returning id`,
        [`payroll-scope-${role}-${randomUUID()}@test.local`, role],
      );
      const profile = await client.query<{ id: string }>(
        `insert into app.profiles (user_id, first_name, last_name)
         values ($1, $2, 'Scope') returning id`,
        [user.rows[0]!.id, role],
      );
      const staff = await client.query<{ id: string }>(
        `insert into app.staff_members (profile_id, role)
         values ($1, $2) returning id`,
        [profile.rows[0]!.id, role],
      );
      await client.query(
        `insert into app.user_crm_links (
           user_id, entity_type, entity_id, link_source, confirmed_at
         ) values ($1, 'staff', $2, 'manual_email', now())`,
        [user.rows[0]!.id, staff.rows[0]!.id],
      );
      await client.query(
        `insert into app.staff_branch_assignments (staff_member_id, branch_id)
         values ($1, $2)`,
        [staff.rows[0]!.id, assignedBranchId],
      );
      operationalActors.push({ userId: user.rows[0]!.id, role });
    }

    const teacherUsers = await client.query<{ id: string }>(
      `insert into app.users (email, role, profile_completed)
       values ($1, 'teacher', true), ($2, 'teacher', true) returning id`,
      [
        `payroll-assigned-${randomUUID()}@test.local`,
        `payroll-foreign-${randomUUID()}@test.local`,
      ],
    );
    const teacherProfiles = await client.query<{ id: string }>(
      `insert into app.profiles (user_id, first_name, last_name)
       values ($1, 'Assigned', 'Teacher'), ($2, 'Foreign', 'Teacher')
       returning id`,
      [teacherUsers.rows[0]!.id, teacherUsers.rows[1]!.id],
    );
    const scopedTeachers = await client.query<{ id: string }>(
      `insert into app.teachers (profile_id, status)
       values ($1, 'active'), ($2, 'active') returning id`,
      [teacherProfiles.rows[0]!.id, teacherProfiles.rows[1]!.id],
    );
    const clientUsers = await client.query<{ id: string }>(
      `insert into app.users (email, role, profile_completed)
       values ($1, 'client', true), ($2, 'client', true) returning id`,
      [
        `payroll-client-assigned-${randomUUID()}@test.local`,
        `payroll-client-foreign-${randomUUID()}@test.local`,
      ],
    );
    const clientProfiles = await client.query<{ id: string }>(
      `insert into app.profiles (user_id, first_name, last_name)
       values ($1, 'Assigned', 'Client'), ($2, 'Foreign', 'Client')
       returning id`,
      [clientUsers.rows[0]!.id, clientUsers.rows[1]!.id],
    );
    const scopedStudents = await client.query<{ id: string }>(
      `insert into app.students (profile_id, branch_id, status)
       values ($1, $3, 'active'), ($2, $4, 'active') returning id`,
      [
        clientProfiles.rows[0]!.id,
        clientProfiles.rows[1]!.id,
        assignedBranchId,
        foreignBranchId,
      ],
    );
    await client.query(
      `insert into app.lessons (
         student_id, teacher_id, branch_id, scheduled_at, duration_minutes,
         teacher_rate, status, created_by
       ) values
         ($1, $2, $3, '2026-08-10T10:00:00.000Z', 60, 1000, 'completed', $7),
         ($4, $5, $6, '2026-08-11T10:00:00.000Z', 60, 2000, 'completed', $7)`,
      [
        scopedStudents.rows[0]!.id,
        scopedTeachers.rows[0]!.id,
        assignedBranchId,
        scopedStudents.rows[1]!.id,
        scopedTeachers.rows[1]!.id,
        foreignBranchId,
        actor.userId,
      ],
    );
    await client.query(
      `insert into app.teacher_payouts (
         teacher_id, amount, kind, comment, paid_at, created_by
       ) values ($1, 777, 'payout', 'global-movement',
         '2026-08-12T12:00:00.000Z', $2)`,
      [scopedTeachers.rows[0]!.id, actor.userId],
    );

    for (const operationalActor of operationalActors) {
      const noFilter = await payroll.getTeacherStatsReport(operationalActor, {
        from: "2026-08-01T00:00:00.000Z",
        to: "2026-09-01T00:00:00.000Z",
      });
      expect(noFilter.items.map((item) => item.teacherName)).toEqual([
        "Assigned Teacher",
      ]);
      expect(noFilter.totals.accruedTotal).toBe(1000);
      expect(noFilter.items[0]).toMatchObject({
        paidTotal: 0,
        bonusTotal: 0,
        deductionTotal: 0,
        periodBalance: 1000,
      });
      expect(noFilter.totals).toMatchObject({
        paidTotal: 0,
        bonusTotal: 0,
        deductionTotal: 0,
        periodBalance: 1000,
      });

      const foreignFilter = await payroll.getTeacherStatsReport(
        operationalActor,
        {
          branchId: foreignBranchId,
          from: "2026-08-01T00:00:00.000Z",
          to: "2026-09-01T00:00:00.000Z",
        },
      );
      expect(foreignFilter.items).toEqual([]);
      expect(foreignFilter.totals.accruedTotal).toBe(0);

      const bytes = await payroll.exportTeacherStatsReport(operationalActor, {
        from: "2026-08-01T00:00:00.000Z",
        to: "2026-09-01T00:00:00.000Z",
      });
      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.load(Uint8Array.from(bytes).buffer);
      const worksheet = workbook.worksheets[0]!;
      const values = worksheet
        .getColumn(1)
        .values.map((value) => String(value ?? ""));
      expect(values).toContain("Assigned Teacher");
      expect(values).not.toContain("Foreign Teacher");
    }

    const staleDirectorUser = await client.query<{ id: string }>(
      `insert into app.users (email, role, profile_completed)
       values ($1, 'director', true) returning id`,
      [`payroll-stale-director-${randomUUID()}@test.local`],
    );
    const staleDirectorProfile = await client.query<{ id: string }>(
      `insert into app.profiles (user_id, first_name, last_name)
       values ($1, 'Stale', 'Director') returning id`,
      [staleDirectorUser.rows[0]!.id],
    );
    const staleDirectorStaff = await client.query<{ id: string }>(
      `insert into app.staff_members (profile_id, role)
       values ($1, 'manager') returning id`,
      [staleDirectorProfile.rows[0]!.id],
    );
    await client.query(
      `insert into app.user_crm_links (
         user_id, entity_type, entity_id, link_source, confirmed_at
       ) values ($1, 'staff', $2, 'manual_email', now())`,
      [staleDirectorUser.rows[0]!.id, staleDirectorStaff.rows[0]!.id],
    );
    await client.query(
      `insert into app.staff_branch_assignments (staff_member_id, branch_id)
       values ($1, $2)`,
      [staleDirectorStaff.rows[0]!.id, assignedBranchId],
    );
    await client.query("update app.users set role = 'manager' where id = $1", [
      staleDirectorUser.rows[0]!.id,
    ]);
    const staleDirectorActor: ActorContext = {
      userId: staleDirectorUser.rows[0]!.id,
      role: "director",
    };
    const downgradedReport = await payroll.getTeacherStatsReport(
      staleDirectorActor,
      {
        from: "2026-08-01T00:00:00.000Z",
        to: "2026-09-01T00:00:00.000Z",
      },
    );
    expect(downgradedReport.items.map((item) => item.teacherName)).toEqual([
      "Assigned Teacher",
    ]);
    expect(downgradedReport.totals).toMatchObject({
      accruedTotal: 1000,
      paidTotal: 0,
      bonusTotal: 0,
      deductionTotal: 0,
    });

    const directorReport = await payroll.getTeacherStatsReport(actor, {
      teacherId: scopedTeachers.rows[0]!.id,
      from: "2026-08-01T00:00:00.000Z",
      to: "2026-09-01T00:00:00.000Z",
    });
    expect(directorReport.items[0]).toMatchObject({
      accruedTotal: 1000,
      paidTotal: 0,
      periodBalance: 1000,
    });
  });

  it("lets only the director correct and void rate/payout history", async () => {
    const before = await payroll.getTeacherPayroll(actor, teacherId);
    const rateId = before.rateHistory[0]!.id!;
    const payoutId = before.payouts[0]!.id;
    await expect(
      payroll.updateTeacherRate(
        { userId: randomUUID(), role: "manager" },
        teacherId,
        rateId,
        {
          rate: 950,
          effectiveFrom: "2026-08-01",
          expectedVersion: 2,
          reasonText: "Попытка управляющего",
        },
        {
          idempotencyKey: "manager-rate-update",
          requestId: "manager-rate-request",
        },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);

    await payroll.updateTeacherRate(
      actor,
      teacherId,
      rateId,
      {
        rate: 950,
        effectiveFrom: "2026-08-15",
        expectedVersion: 2,
        reasonText: "Исправлена ошибочная дата и ставка",
      },
      {
        idempotencyKey: `rate-update-${teacherId}`,
        requestId: `rate-update-request-${teacherId}`,
      },
    );
    await payroll.updateTeacherPayout(
      actor,
      teacherId,
      payoutId,
      {
        kind: "bonus",
        amount: 1200,
        paidAt: "2026-08-10T12:00:00.000Z",
        comment: "Исправленная доплата",
        expectedVersion: 3,
        reasonText: "Выплата была внесена неверным типом",
      },
      {
        idempotencyKey: `payout-update-${teacherId}`,
        requestId: `payout-update-request-${teacherId}`,
      },
    );
    const corrected = await payroll.getTeacherPayroll(actor, teacherId);
    expect(corrected.version).toBe(4);
    expect(corrected.rateHistory[0]).toMatchObject({
      rate: 950,
      effectiveFrom: "2026-08-15",
    });
    expect(corrected.payouts[0]).toMatchObject({
      kind: "bonus",
      amount: 1200,
      comment: "Исправленная доплата",
    });

    await payroll.deleteTeacherRate(
      actor,
      teacherId,
      rateId,
      { expectedVersion: 4, reasonText: "Дублирующая запись ставки" },
      {
        idempotencyKey: `rate-delete-${teacherId}`,
        requestId: `rate-delete-request-${teacherId}`,
      },
    );
    await payroll.deleteTeacherPayout(
      actor,
      teacherId,
      payoutId,
      { expectedVersion: 5, reasonText: "Ошибочная выплата" },
      {
        idempotencyKey: `payout-delete-${teacherId}`,
        requestId: `payout-delete-request-${teacherId}`,
      },
    );
    const after = await payroll.getTeacherPayroll(actor, teacherId);
    expect(after).toMatchObject({ version: 6, rateHistory: [], payouts: [] });
    expect(after.paidTotal).toBe(0);

    const retained = await client.query<{
      rate_deleted: boolean;
      payout_deleted: boolean;
      audits: string;
    }>(
      `select
         (select deleted_at is not null from app.teacher_rates where id = $1) as rate_deleted,
         (select deleted_at is not null from app.teacher_payouts where id = $2) as payout_deleted,
         (select count(*)::text from app.audit_events
          where entity_id = $3::text
            and action in ('crm.teacher_rate_updated', 'crm.teacher_payout_updated',
              'crm.teacher_rate_deleted', 'crm.teacher_payout_deleted')) as audits`,
      [rateId, payoutId, teacherId],
    );
    expect(retained.rows[0]).toEqual({
      rate_deleted: true,
      payout_deleted: true,
      audits: "4",
    });
  });

  it("denies client/teacher policy and keeps physical DELETE revoked", async () => {
    for (const role of ["client", "teacher"] as const) {
      await expect(
        payroll.getTeacherPayroll({ userId: randomUUID(), role }, teacherId),
      ).rejects.toBeInstanceOf(ForbiddenException);
    }
    const privileges = await client.query<{
      rates_update: boolean;
      rates_delete: boolean;
      payouts_update: boolean;
      payouts_delete: boolean;
    }>(`
      select
        has_table_privilege('magiccrm_app', 'app.teacher_rates', 'UPDATE') as rates_update,
        has_table_privilege('magiccrm_app', 'app.teacher_rates', 'DELETE') as rates_delete,
        has_table_privilege('magiccrm_app', 'app.teacher_payouts', 'UPDATE') as payouts_update,
        has_table_privilege('magiccrm_app', 'app.teacher_payouts', 'DELETE') as payouts_delete
    `);
    expect(privileges.rows[0]).toEqual({
      rates_update: true,
      rates_delete: false,
      payouts_update: true,
      payouts_delete: false,
    });
  });
});
