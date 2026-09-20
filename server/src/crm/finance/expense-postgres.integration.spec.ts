import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { AuditService } from "../../audit/audit.service";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ExpenseService } from "./expense.service";
const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
if (
  url &&
  (!["localhost", "127.0.0.1"].includes(new URL(url).hostname) ||
    !/test|audit_fix/.test(new URL(url).pathname))
)
  throw new Error("Isolated local test database required");
(url ? describe : describe.skip)("Expense commands (PostgreSQL)", () => {
  let db: DatabaseService;
  let pool: Pool;
  let service: ExpenseService;
  let audit: AuditService;
  let integrityRepository: PlatformIntegrityRepository;
  const actor = { userId: randomUUID(), role: "director" as const };
  beforeAll(async () => {
    pool = new Pool({ connectionString: url });
    await new MigrationRunner(pool).up();
    db = new DatabaseService({
      getOrThrow: () => url,
    } as unknown as ConfigService);
    await db.query(
      "insert into app.users(id,email,role) values($1,$2,'director')",
      [actor.userId, actor.userId + "@example.test"],
    );
    audit = new AuditService(db);
    integrityRepository = new PlatformIntegrityRepository();
    service = new ExpenseService(
      db,
      new PlatformIntegrityService(db, integrityRepository),
      new CrmPolicy(),
    );
  });
  afterAll(async () => {
    await db?.onModuleDestroy();
    await pool?.end();
  });
  const meta = () => ({
    idempotencyKey: randomUUID(),
    requestId: randomUUID(),
  });
  it("replays create without a second expense", async () => {
    const identity = meta();
    const dto = { amount: 100, category: randomUUID() };
    const first = await (service.createExpense as Function)(
      actor,
      dto,
      identity,
    );
    const replay = await (service.createExpense as Function)(
      actor,
      dto,
      identity,
    );
    expect(replay.id).toBe(first.id);
    expect(
      (
        await db.query("select id from app.expenses where category=$1", [
          dto.category,
        ])
      ).rows,
    ).toHaveLength(1);
  });
  it("rejects stale edits without losing the first change", async () => {
    const created = await (service.createExpense as Function)(
      actor,
      { amount: 100, category: randomUUID() },
      meta(),
    );
    const attempts = await Promise.allSettled([
      (service.updateExpense as Function)(
        actor,
        created.id,
        { amount: 200, expectedVersion: 1 },
        meta(),
      ),
      (service.updateExpense as Function)(
        actor,
        created.id,
        { amount: 300, expectedVersion: 1 },
        meta(),
      ),
    ]);
    expect(attempts.filter((a) => a.status === "fulfilled").length).toBe(1);
  });
  it("uses the actual expense date in the list", async () => {
    const category = randomUUID();
    const created = await (service.createExpense as Function)(
      actor,
      { amount: 100, category, occurredAt: "2026-07-15T10:00:00Z" },
      meta(),
    );
    const listed = await service.listExpenses(actor, {
      category,
      from: "2026-07-01T00:00:00Z",
      to: "2026-08-01T00:00:00Z",
    });
    expect(listed.items.map((row) => row.id)).toContain(created.id);
  });
  it("retains immutable snapshots and replays the original create after edits", async () => {
    const command = meta();
    const dto = { amount: 100, category: randomUUID() };
    const created = await service.createExpense(actor, dto, command);
    await service.updateExpense(
      actor,
      created.id,
      { amount: 200, expectedVersion: 1 },
      meta(),
    );
    expect(await service.createExpense(actor, dto, command)).toMatchObject({
      amount: 100,
      version: 1,
    });
    const remove = meta();
    await service.deleteExpense(actor, created.id, 2, remove);
    await service.deleteExpense(actor, created.id, 2, remove);
    const rows = await db.query(
      "select version::int,amount::text,deleted_at is not null as deleted from app.expense_revisions where expense_id=$1 order by version",
      [created.id],
    );
    expect(rows.rows).toEqual([
      { version: 1, amount: "100.00", deleted: false },
      { version: 2, amount: "200.00", deleted: false },
      { version: 3, amount: "200.00", deleted: true },
    ]);
    await expect(
      db.query("delete from app.expense_revisions where expense_id=$1", [
        created.id,
      ]),
    ).rejects.toBeDefined();
  });
  it.each(["appendAudit", "enqueueOutbox"] as const)(
    "rolls back expense and history when %s fails",
    async (method) => {
      const category = randomUUID();
      const command = meta();
      const failure = jest
        .spyOn(integrityRepository, method)
        .mockRejectedValueOnce(new Error("storage unavailable"));
      await expect(
        service.createExpense(actor, { amount: 100, category }, command),
      ).rejects.toThrow("storage unavailable");
      failure.mockRestore();
      expect(
        (
          await db.query("select id from app.expenses where category=$1", [
            category,
          ])
        ).rows,
      ).toHaveLength(0);
      expect(
        (
          await db.query(
            "select expense_id from app.expense_revisions where category=$1",
            [category],
          )
        ).rows,
      ).toHaveLength(0);
      await service.createExpense(actor, { amount: 100, category }, command);
      expect(
        (
          await db.query("select id from app.expenses where category=$1", [
            category,
          ])
        ).rows,
      ).toHaveLength(1);
    },
  );
  it("pages equal-date expenses without duplicates or truncated history", async () => {
    const category = randomUUID();
    const expected: string[] = [];
    for (let i = 0; i < 5; i++)
      expected.push(
        (
          await service.createExpense(
            actor,
            {
              amount: 100,
              category,
              occurredAt: "2026-07-15T10:00:00.123456Z",
            },
            meta(),
          )
        ).id,
      );
    const ids: string[] = [];
    let cursor: string | undefined;
    do {
      const page: any = await service.listExpenses(actor, {
        category,
        limit: 2,
        ...(cursor ? { cursor } : {}),
      });
      expect(page.items.length).toBeLessThanOrEqual(2);
      expect(page.total).toBe(500);
      ids.push(...page.items.map((item: any) => item.id));
      cursor = page.nextCursor ?? undefined;
    } while (cursor && ids.length < 10);
    expect(ids.sort()).toEqual(expected.sort());
  });
  it("includes an expense predating lessons in the legacy monthly report", async () => {
    await pool.query("refresh materialized view app.mv_finance_monthly");
    const before = await pool.query(
      "select expenses from app.mv_finance_monthly where month_start='2000-06-01'",
    );
    await service.createExpense(
      actor,
      {
        amount: 100,
        category: randomUUID(),
        occurredAt: "2000-06-15T12:00:00Z",
      },
      meta(),
    );
    await pool.query("refresh materialized view app.mv_finance_monthly");
    const after = await pool.query(
      "select expenses from app.mv_finance_monthly where month_start='2000-06-01'",
    );
    expect(Number(after.rows[0]?.expenses)).toBe(
      Number(before.rows[0]?.expenses ?? 0) + 100,
    );
  });
});
