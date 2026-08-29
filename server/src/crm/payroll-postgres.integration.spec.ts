import { ForbiddenException } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
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

  it("keeps append-only rate history with author and includes payout-only statistics", async () => {
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
    expect(report.items).toEqual([
      expect.objectContaining({
        teacherId,
        completedLessons: 0,
        paidTotal: 1500,
        periodBalance: -1500,
      }),
    ]);
    expect(report.totals.paidTotal).toBe(1500);
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
        { idempotencyKey: "manager-rate-update", requestId: "manager-rate-request" },
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
      { idempotencyKey: `rate-update-${teacherId}`, requestId: `rate-update-request-${teacherId}` },
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
      { idempotencyKey: `payout-update-${teacherId}`, requestId: `payout-update-request-${teacherId}` },
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
      { idempotencyKey: `rate-delete-${teacherId}`, requestId: `rate-delete-request-${teacherId}` },
    );
    await payroll.deleteTeacherPayout(
      actor,
      teacherId,
      payoutId,
      { expectedVersion: 5, reasonText: "Ошибочная выплата" },
      { idempotencyKey: `payout-delete-${teacherId}`, requestId: `payout-delete-request-${teacherId}` },
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
