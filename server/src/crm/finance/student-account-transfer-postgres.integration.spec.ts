import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { CrmPolicy } from "../crm.policy";
import { StudentAccountTransferService } from "./student-account-transfer.service";

const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
const describeDb = url ? describe : describe.skip;
if (
  url &&
  (!["localhost", "127.0.0.1"].includes(new URL(url).hostname) ||
    (!new URL(url).pathname.includes("test") &&
      !new URL(url).pathname.includes("audit_fix")))
) {
  throw new Error("Transfers require an isolated local test database.");
}
jest.setTimeout(60000);

describeDb("Account transfers (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let service: StudentAccountTransferService;
  let integrityRepository: PlatformIntegrityRepository;
  beforeAll(async () => {
    pool = new Pool({ connectionString: url });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => url,
    } as unknown as ConfigService);
    integrityRepository = new PlatformIntegrityRepository();
    service = new StudentAccountTransferService(
      database,
      new PlatformIntegrityService(database, integrityRepository),
      new CrmPolicy(),
    );
  });
  afterAll(async () => {
    await database?.onModuleDestroy();
    await pool?.end();
  });

  async function fixture() {
    const actor = { userId: randomUUID(), role: "director" as const };
    await pool.query(
      "insert into app.users(id,email,role) values($1,$2,'director')",
      [actor.userId, `${actor.userId}@example.test`],
    );
    const branch = await pool.query(
      "insert into app.branches(name) values($1) returning id",
      [`Transfer ${randomUUID()}`],
    );
    const students: string[] = [];
    for (let i = 0; i < 2; i++) {
      const user = await pool.query(
        "insert into app.users(email,role) values($1,'client') returning id",
        [`${randomUUID()}@example.test`],
      );
      const profile = await pool.query(
        "insert into app.profiles(user_id,first_name,last_name) values($1,'Transfer','Test') returning id",
        [user.rows[0].id],
      );
      const student = await pool.query(
        "insert into app.students(profile_id,branch_id) values($1,$2) returning id",
        [profile.rows[0].id, branch.rows[0].id],
      );
      students.push(student.rows[0].id);
    }
    await pool.query(
      "insert into app.payments(student_id,amount,currency,branch_id) values($1,100,'RUB',$2)",
      [students[0], branch.rows[0].id],
    );
    return { actor, students };
  }
  const metadata = () => ({
    idempotencyKey: randomUUID(),
    requestId: randomUUID(),
  });
  const transfer = (
    f: Awaited<ReturnType<typeof fixture>>,
    amount: number,
    meta = metadata(),
  ) =>
    service.createAccountTransfer(
      f.actor,
      f.students[0],
      { toStudentId: f.students[1], amount },
      meta,
    );

  it("rejects overdraft without either leg", async () => {
    const f = await fixture();
    await expect(transfer(f, 100.01)).rejects.toMatchObject({
      response: { code: "TRANSFER_INSUFFICIENT_BALANCE" },
    });
    expect(
      (
        await pool.query(
          "select id from app.account_adjustments where student_id=any($1::uuid[])",
          [f.students],
        )
      ).rows,
    ).toHaveLength(0);
  });
  it("conserves money, replays one command and prevents concurrent overdraft", async () => {
    const f = await fixture();
    const meta = metadata();
    const first = await transfer(f, 60, meta);
    const replay = await transfer(f, 60, meta);
    expect(replay.fromAdjustmentId).toBe(first.fromAdjustmentId);
    const attempts = await Promise.allSettled([
      transfer(f, 30),
      transfer(f, 30),
    ]);
    expect(attempts.filter((x) => x.status === "fulfilled")).toHaveLength(1);
    const balances = await pool.query(
      "select student_id,balance_minor::text from app.commerce_student_account_projection where student_id=any($1::uuid[])",
      [f.students],
    );
    expect(balances.rows).toEqual(
      expect.arrayContaining([
        { student_id: f.students[0], balance_minor: "1000" },
        { student_id: f.students[1], balance_minor: "9000" },
      ]),
    );
  });
  it("uses the current database role and rejects a caller outside both branches", async () => {
    const f = await fixture();
    await pool.query("update app.users set role='manager' where id=$1", [
      f.actor.userId,
    ]);
    await expect(transfer(f, 10)).rejects.toMatchObject({ status: 404 });
  });
  it("rolls back both legs when audit fails, then retries the same identity once", async () => {
    const f = await fixture();
    const meta = metadata();
    const failure = jest
      .spyOn(integrityRepository, "appendAudit")
      .mockRejectedValueOnce(new Error("audit unavailable"));
    await expect(transfer(f, 25, meta)).rejects.toThrow("audit unavailable");
    failure.mockRestore();
    expect(
      (
        await pool.query(
          "select id from app.account_adjustments where student_id=any($1::uuid[])",
          [f.students],
        )
      ).rows,
    ).toHaveLength(0);
    await transfer(f, 25, meta);
    expect(
      (
        await pool.query(
          "select id from app.account_adjustments where student_id=any($1::uuid[])",
          [f.students],
        )
      ).rows,
    ).toHaveLength(2);
    await expect(transfer(f, 30, meta)).rejects.toMatchObject({ status: 409 });
  });
  it("keeps transferred facts immutable and rejects an unpaired transfer at commit", async () => {
    const f = await fixture();
    const result = await transfer(f, 100);
    await expect(
      pool.query("delete from app.account_adjustments where id=$1", [
        result.fromAdjustmentId,
      ]),
    ).rejects.toBeDefined();
    await expect(
      pool.query(
        "insert into app.account_adjustments(student_id,counterparty_student_id,kind,amount,transfer_peer_id) values($1,$2,'transfer_out',-1,$3)",
        [f.students[0], f.students[1], randomUUID()],
      ),
    ).rejects.toBeDefined();
    const amounts = await pool.query(
      "select sum(amount_minor)::text as total, count(*)::int as count from app.account_adjustments where student_id=any($1::uuid[])",
      [f.students],
    );
    expect(amounts.rows[0]).toEqual({ total: "0", count: 2 });
  });
});
