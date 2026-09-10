import { PaymentLifecycleService } from "../crm/commerce/payment-lifecycle.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { PlatformIntegrityRepository } from "../platform/platform-integrity.repository";
import { ForbiddenException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { mkdir, writeFile } from "fs/promises";
import { dirname, resolve } from "path";
import * as ExcelJS from "exceljs";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { CrmPolicy } from "../crm/crm.policy";
import { FinanceService } from "../crm/finance.service";
import { ExpenseService } from "../crm/finance/expense.service";
import { FinancePaymentService } from "../crm/finance/finance-payment.service";
import { StudentAccountTransferService } from "../crm/finance/student-account-transfer.service";
import { StudentFinanceQueryService } from "../crm/finance/student-finance-query.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { ClientStatusReadService } from "./client-status-read.service";
import { OoxmlWorkbookBuilder } from "../common/ooxml-workbook.builder";
import { ReportExportService } from "./report-export.service";
import { ReportingReadService } from "./reporting-read.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const parsedDatabaseUrl = new URL(databaseUrl);
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    parsedDatabaseUrl.hostname,
  )
) {
  throw new Error("Reporting scope tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("ReportingReadService hard scopes (PostgreSQL)", () => {
  let database: DatabaseService;
  let service: ReportingReadService;
  let fixture: Awaited<ReturnType<typeof createFixture>>;
  const range = {
    from: "2026-07-01T00:00:00.000Z",
    to: "2026-08-01T00:00:00.000Z",
  };

  beforeAll(async () => {
    database = new DatabaseService(
      new ConfigService({ DATABASE_URL: databaseUrl }),
    );
    await cleanupStaleFixtures(database);
    service = new ReportingReadService(database, new CrmPolicy());
    fixture = await createFixture(database);
  });

  afterAll(async () => {
    if (fixture) await cleanupFixture(database, fixture);
    await database.onModuleDestroy();
  });

  it("derives lesson success only from terminal lifecycle with branch scope", async () => {
    const manager = await service.lessonSuccess(fixture.manager, range);
    expect(manager).toMatchObject({
      totalLessons: 2,
      successfulLessons: 1,
      successRate: 0.5,
    });
    expect(manager.drilldown.optionalFocus?.filter).toMatchObject({
      version: 1,
      status: "successfully_completed",
    });
    const managerLessons = await service.lessonSuccessList(fixture.manager, {
      ...range,
      limit: 10,
      offset: 0,
    });
    expect(managerLessons.total).toBe(manager.successfulLessons);
    expect(managerLessons.items).toEqual([
      expect.objectContaining({
        id: fixture.lessonIds[0],
        lifecycleState: "successfully_completed",
        entityLink: { entityType: "lesson", entityId: fixture.lessonIds[0] },
      }),
    ]);

    const director = await service.lessonSuccess(fixture.director, range);
    expect(director).toMatchObject({
      totalLessons: 3,
      successfulLessons: 2,
    });
    const directorLessons = await service.lessonSuccessList(
      fixture.director,
      range,
    );
    expect(directorLessons.total).toBe(director.successfulLessons);
    await expect(service.lessonSuccess(fixture.admin, range)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it("allows school finance only to Director/root and counts ActualPayment only", async () => {
    await expect(service.schoolFinance(fixture.admin, range)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    await expect(
      service.schoolFinance(fixture.manager, range),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const director = await service.schoolFinance(fixture.director, {
      ...range,
      branchId: fixture.assignedBranchId,
    });
    expect(director.revenueMinor).toBe("800000");
    expect(director.rows).toEqual([
      expect.objectContaining({
        monthStart: "2026-07-01",
        totalLessons: 2,
        successfulLessons: 1,
        revenueMinor: "800000",
        link: expect.objectContaining({
          entityType: "school_finance_month",
        }),
      }),
    ]);

    const exports = new ReportExportService(
      database,
      {} as ClientStatusReadService,
      service,
      new OoxmlWorkbookBuilder(),
      {} as AuditService,
    );
    const buffer = await exports.financeWorkbook(fixture.director, {
      ...range,
      branchId: fixture.assignedBranchId,
    });
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(Uint8Array.from(buffer).buffer);
    const sheet = workbook.getWorksheet("Финансы")!;
    const row = director.rows[0]!;
    expect(sheet.rowCount).toBe(director.rows.length + 1);
    expect(sheet.getCell("D2").value).toBe(
      Number(BigInt(row.revenueMinor)) / 100,
    );
    expect(sheet.getCell("E2").value).toBe(
      Number(BigInt(row.expensesMinor)) / 100,
    );
    expect(sheet.getCell("F2").value).toEqual({
      formula: "D2-E2",
      result:
        Number(BigInt(row.revenueMinor) - BigInt(row.expensesMinor)) / 100,
    });
    const fixturePath = resolve(
      process.cwd(),
      "..",
      "build",
      "stage7-school-finance.xlsx",
    );
    await mkdir(dirname(fixturePath), { recursive: true });
    await writeFile(fixturePath, buffer);

    const root = await service.schoolFinance(fixture.systemAdmin, {
      ...range,
      branchId: fixture.otherBranchId,
    });
    expect(root.revenueMinor).toBe("400000");
    expect(root.revenueMinor).not.toBe("11100000");
  });

  it("keeps Director expense CRUD, Manager deny and Analytics in one projection", async () => {
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const realtime = { emitCrmChanged: jest.fn() };
    const policy = new CrmPolicy();
    const typedAudit = audit as unknown as AuditService;
    const typedRealtime = realtime as unknown as RealtimeBus;
    const finance = new FinanceService(
      new FinancePaymentService(
        database,
        policy,
        {} as PaymentLifecycleService,
      ),
      new StudentFinanceQueryService(database, policy),
      new StudentAccountTransferService(
        database,
        new PlatformIntegrityService(
          database,
          new PlatformIntegrityRepository(),
        ),
        policy,
      ),
      new ExpenseService(
        database,
        new PlatformIntegrityService(
          database,
          new PlatformIntegrityRepository(),
        ),
        policy,
      ),
    );

    await expect(
      finance.listExpenses(fixture.manager, {
        branchId: fixture.assignedBranchId,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      finance.createExpense(fixture.manager, {
        amount: 1250,
        category: "rent",
        branchId: fixture.assignedBranchId,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const created = await finance.createExpense(
      fixture.director,
      {
        amount: 1250,
        category: "rent",
        description: "UAT-114 initial expense",
        occurredAt: "2026-07-15T12:00:00Z",
        branchId: fixture.assignedBranchId,
      },
      { idempotencyKey: randomUUID(), requestId: randomUUID() },
    );

    await expect(
      finance.updateExpense(fixture.manager, created.id, { amount: 9999 }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      finance.deleteExpense(fixture.manager, created.id),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const updated = await finance.updateExpense(
      fixture.director,
      created.id,
      {
        amount: 1750,
        category: "utilities",
        description: "UAT-114 corrected expense",
        expectedVersion: 1,
      },
      { idempotencyKey: randomUUID(), requestId: randomUUID() },
    );
    expect(updated).toMatchObject({
      id: created.id,
      amount: 1750,
      category: "utilities",
      description: "UAT-114 corrected expense",
      branchId: fixture.assignedBranchId,
    });

    const listed = await finance.listExpenses(fixture.director, {
      branchId: fixture.assignedBranchId,
      from: range.from,
      to: range.to,
    });
    expect(listed).toMatchObject({
      total: 1750,
      items: [expect.objectContaining({ id: created.id, amount: 1750 })],
    });
    const withExpense = await service.schoolFinance(fixture.director, {
      ...range,
      branchId: fixture.assignedBranchId,
    });
    expect(withExpense.expensesMinor).toBe("175000");
    expect(withExpense.rows[0]).toMatchObject({ expensesMinor: "175000" });

    await expect(
      finance.deleteExpense(fixture.director, created.id, 2, {
        idempotencyKey: randomUUID(),
        requestId: randomUUID(),
      }),
    ).resolves.toEqual({ success: true });
    const afterDelete = await finance.listExpenses(fixture.director, {
      branchId: fixture.assignedBranchId,
      from: range.from,
      to: range.to,
    });
    expect(afterDelete).toEqual({ items: [], total: 0, nextCursor: null });
    const analyticsAfterDelete = await service.schoolFinance(fixture.director, {
      ...range,
      branchId: fixture.assignedBranchId,
    });
    expect(analyticsAfterDelete.expensesMinor).toBe("0");

    const persisted = await database.query<{
      deleted_at: Date | null;
      amount: string;
    }>("select deleted_at, amount::text from app.expenses where id = $1", [
      created.id,
    ]);
    expect(persisted.rows[0]).toEqual({
      deleted_at: expect.any(Date),
      amount: "1750.00",
    });
    const auditRows = await database.query(
      "select action from app.audit_events where entity_type='expense' and entity_id=$1 order by created_at,id",
      [created.id],
    );
    expect(auditRows.rows.map((row) => row.action).sort()).toEqual([
      "crm.expense_created",
      "crm.expense_deleted",
      "crm.expense_updated",
    ]);
  });
});

async function createFixture(database: DatabaseService) {
  const marker = `v4-report-scope-${randomUUID()}`;
  const users = await database.query<{
    id: string;
    role: ActorContext["role"];
  }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, 'admin', now()),
        ($2, 'manager', now()),
        ($3, 'director', now()),
        ($4, 'system_admin', now()),
        ($5, 'client', now()),
        ($6, 'client', now())
      returning id, role::text as role
    `,
    [
      `${marker}-admin@example.test`,
      `${marker}-manager@example.test`,
      `${marker}-director@example.test`,
      `${marker}-root@example.test`,
      `${marker}-student-a@example.test`,
      `${marker}-student-b@example.test`,
    ],
  );
  const [admin, manager, director, systemAdmin, clientA, clientB] = users.rows;
  const branches = await database.query<{ id: string }>(
    `
      insert into app.branches (name)
      values ($1), ($2)
      returning id
    `,
    [`${marker}-assigned`, `${marker}-other`],
  );
  const [assignedBranch, otherBranch] = branches.rows;
  const profiles = await database.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name)
      values
        ($1, 'Manager'),
        ($2, 'Student A'),
        ($3, 'Student B')
      returning id
    `,
    [manager!.id, clientA!.id, clientB!.id],
  );
  const staff = await database.query<{ id: string }>(
    `
      insert into app.staff_members (profile_id, role)
      values ($1, 'manager')
      returning id
    `,
    [profiles.rows[0]!.id],
  );
  await database.query(
    `
      insert into app.staff_branch_assignments (staff_member_id, branch_id)
      values ($1, $2)
    `,
    [staff.rows[0]!.id, assignedBranch!.id],
  );
  const students = await database.query<{ id: string }>(
    `
      insert into app.students (profile_id, status, branch_id)
      values ($1, 'active', $3), ($2, 'active', $4)
      returning id
    `,
    [
      profiles.rows[1]!.id,
      profiles.rows[2]!.id,
      assignedBranch!.id,
      otherBranch!.id,
    ],
  );
  const lessons = await database.query<{ id: string }>(
    `
      insert into app.lessons (
        student_id, branch_id, scheduled_at, status, created_by
      )
      values
        ($1, $3, '2026-07-10T10:00:00Z', 'completed', $5),
        ($1, $3, '2026-07-11T10:00:00Z', 'cancelled', $5),
        ($2, $4, '2026-07-12T10:00:00Z', 'completed', $5)
      returning id
    `,
    [
      students.rows[0]!.id,
      students.rows[1]!.id,
      assignedBranch!.id,
      otherBranch!.id,
      director!.id,
    ],
  );
  const payments = await database.query<{ id: string }>(
    `
      insert into app.payments (
        student_id, branch_id, amount, payment_date, created_by
      )
      values
        ($1, $3, 8000, '2026-07-10T09:00:00Z', $5),
        ($2, $4, 4000, '2026-07-12T09:00:00Z', $5)
      returning id
    `,
    [
      students.rows[0]!.id,
      students.rows[1]!.id,
      assignedBranch!.id,
      otherBranch!.id,
      director!.id,
    ],
  );
  const expectedPayment = await database.query<{ id: string }>(
    `
      insert into app.expected_payments (
        student_id, amount, due_date, status, description
      )
      values ($1, 99000, '2026-07-20', 'pending', 'Not actual revenue')
      returning id
    `,
    [students.rows[0]!.id],
  );

  return {
    admin: { userId: admin!.id, role: "admin" } as ActorContext,
    manager: { userId: manager!.id, role: "manager" } as ActorContext,
    director: { userId: director!.id, role: "director" } as ActorContext,
    systemAdmin: {
      userId: systemAdmin!.id,
      role: "system_admin",
    } as ActorContext,
    userIds: users.rows.map((row) => row.id),
    branchIds: branches.rows.map((row) => row.id),
    assignedBranchId: assignedBranch!.id,
    otherBranchId: otherBranch!.id,
    profileIds: profiles.rows.map((row) => row.id),
    staffId: staff.rows[0]!.id,
    studentIds: students.rows.map((row) => row.id),
    lessonIds: lessons.rows.map((row) => row.id),
    paymentIds: payments.rows.map((row) => row.id),
    expectedPaymentId: expectedPayment.rows[0]!.id,
  };
}

async function cleanupStaleFixtures(database: DatabaseService) {
  const users = await database.query<{ id: string }>(
    "select id from app.users where email like 'v4-report-scope-%@example.test'",
  );
  const userIds = users.rows.map((row) => row.id);
  if (userIds.length === 0) return;
  await database.transaction(async (client) => {
    await client.query("set local session_replication_role = replica");
    const profiles = await client.query<{ id: string }>(
      "select id from app.profiles where user_id = any($1::uuid[])",
      [userIds],
    );
    const profileIds = profiles.rows.map((row) => row.id);
    const students = await client.query<{ id: string }>(
      "select id from app.students where profile_id = any($1::uuid[])",
      [profileIds],
    );
    const studentIds = students.rows.map((row) => row.id);
    await client.query(
      "delete from app.expected_payments where student_id = any($1::uuid[])",
      [studentIds],
    );
    await client.query(
      "delete from app.payments where student_id = any($1::uuid[])",
      [studentIds],
    );
    await client.query(
      "delete from app.lessons where student_id = any($1::uuid[])",
      [studentIds],
    );
    await client.query(
      "delete from app.students where id = any($1::uuid[])",
      [studentIds],
    );
    const staff = await client.query<{ id: string }>(
      "select id from app.staff_members where profile_id = any($1::uuid[])",
      [profileIds],
    );
    const staffIds = staff.rows.map((row) => row.id);
    await client.query(
      "delete from app.staff_branch_assignments where staff_member_id = any($1::uuid[])",
      [staffIds],
    );
    await client.query(
      "delete from app.staff_members where id = any($1::uuid[])",
      [staffIds],
    );
    await client.query(
      `delete from app.expenses
       where branch_id in (
         select id from app.branches where name like 'v4-report-scope-%'
       )`,
    );
    await client.query(
      "delete from app.profiles where id = any($1::uuid[])",
      [profileIds],
    );
    await client.query("delete from app.users where id = any($1::uuid[])", [
      userIds,
    ]);
    await client.query(
      "delete from app.branches where name like 'v4-report-scope-%'",
    );
  });
}

async function cleanupFixture(
  database: DatabaseService,
  fixture: Awaited<ReturnType<typeof createFixture>>,
) {
  await database.transaction(async (client) => {
    await client.query("set local session_replication_role = replica");
    await client.query("delete from app.expected_payments where id = $1", [
      fixture.expectedPaymentId,
    ]);
    await client.query("delete from app.payments where id = any($1::uuid[])", [
      fixture.paymentIds,
    ]);
    await client.query("delete from app.lessons where id = any($1::uuid[])", [
      fixture.lessonIds,
    ]);
    await client.query("delete from app.students where id = any($1::uuid[])", [
      fixture.studentIds,
    ]);
    await client.query(
      "delete from app.staff_branch_assignments where staff_member_id = $1",
      [fixture.staffId],
    );
    await client.query("delete from app.staff_members where id = $1", [
      fixture.staffId,
    ]);
    await client.query(
      "delete from app.expenses where branch_id = any($1::uuid[])",
      [fixture.branchIds],
    );
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      fixture.profileIds,
    ]);
    await client.query("delete from app.branches where id = any($1::uuid[])", [
      fixture.branchIds,
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      fixture.userIds,
    ]);
  });
}
