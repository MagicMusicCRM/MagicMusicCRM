import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { AvailabilityRepository } from "./availability.repository";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(testDatabaseUrl).hostname,
  )
) {
  throw new Error("Availability tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

async function expectConstraint(
  client: PoolClient,
  work: () => Promise<unknown>,
  expectedCode: "23514",
) {
  const savepoint = `sp_${randomUUID().replace(/-/g, "")}`;
  await client.query(`savepoint ${savepoint}`);
  try {
    await work();
    throw new Error(`Expected PostgreSQL constraint ${expectedCode}.`);
  } catch (error) {
    expect((error as { code?: string }).code).toBe(expectedCode);
    await client.query(`rollback to savepoint ${savepoint}`);
  } finally {
    await client.query(`release savepoint ${savepoint}`);
  }
}

describe("Availability reference data (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let repository: AvailabilityRepository;

  beforeAll(async () => {
    pool = new Pool({ connectionString: testDatabaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    repository = new AvailabilityRepository(database);
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("resolves recurring hours, exceptions, multi-branch and DST to UTC", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const branches = await client.query<{ id: string }>(
        `
          insert into app.branches (name)
          values ($1), ($2)
          returning id
        `,
        [`Berlin ${randomUUID()}`, `Moscow ${randomUUID()}`],
      );
      const user = await client.query<{ id: string }>(
        `
          insert into app.users (email, role, email_verified_at)
          values ($1, 'teacher', now())
          returning id
        `,
        [`availability-${randomUUID()}@example.test`],
      );
      const profile = await client.query<{ id: string }>(
        `
          insert into app.profiles (user_id, first_name, last_name)
          values ($1, 'DST', 'Teacher')
          returning id
        `,
        [user.rows[0]!.id],
      );
      const teacher = await client.query<{ id: string }>(
        `
          insert into app.teachers (profile_id)
          values ($1)
          returning id
        `,
        [profile.rows[0]!.id],
      );
      const branchId = branches.rows[0]!.id;
      const secondBranchId = branches.rows[1]!.id;
      const teacherId = teacher.rows[0]!.id;

      const branchWrite = await repository.replaceBranchHours(client, {
        branchId,
        expectedVersion: 1,
        timezone: "Europe/Berlin",
        weekly: [{ weekday: 7, open: "01:30", close: "03:30" }],
        exceptions: [
          {
            date: "2026-03-30",
            closed: false,
            open: "10:00",
            close: "12:00",
            reason: "extended",
          },
        ],
      });
      expect(branchWrite).toEqual({
        branchId,
        timezone: "Europe/Berlin",
        version: 2,
      });
      await expect(
        repository.getBranchHours(branchId, client),
      ).resolves.toEqual({
        id: branchId,
        timezone: "Europe/Berlin",
        version: 2,
        weekly: [{ weekday: 7, open: "01:30", close: "03:30" }],
        exceptions: [
          {
            date: "2026-03-30",
            closed: false,
            open: "10:00",
            close: "12:00",
            reason: "extended",
          },
        ],
      });
      expect(
        await repository.replaceBranchHours(client, {
          branchId,
          expectedVersion: 1,
          timezone: "Europe/Berlin",
          weekly: [{ weekday: 7, open: "01:30", close: "03:30" }],
          exceptions: [],
        }),
      ).toBeNull();

      const branchAssignments = await repository.replaceTeacherBranches(
        client,
        {
          teacherId,
          expectedVersion: 1,
          assignments: [
            {
              branchId,
              activeFrom: "2026-01-01",
              activeUntil: "2026-12-31",
            },
            {
              branchId: secondBranchId,
              activeFrom: "2026-01-01",
            },
          ],
        },
      );
      expect(branchAssignments?.version).toBe(2);

      const availability = await repository.replaceTeacherAvailability(client, {
        teacherId,
        expectedVersion: 2,
        rules: [
          {
            kind: "recurring",
            available: true,
            timezone: "Europe/Berlin",
            weekday: 7,
            localStart: "01:00",
            localEnd: "04:00",
            validFrom: "2026-01-01",
          },
          {
            kind: "interval",
            available: false,
            startsAt: "2026-03-29T01:00:00Z",
            endsAt: "2026-03-29T01:15:00Z",
            reason: "break",
          },
          {
            kind: "interval",
            available: false,
            startsAt: "2026-12-01T00:00:00Z",
            reason: "indefinite",
          },
        ],
      });
      expect(availability?.version).toBe(3);

      const resolved = await repository.resolve(
        branchId,
        teacherId,
        new Date("2026-03-28T22:00:00Z"),
        new Date("2026-03-30T23:00:00Z"),
        client,
      );
      expect(resolved).not.toBeNull();
      expect(resolved!.teacherBranchAssigned).toBe(true);
      expect(resolved!.branch).toMatchObject({
        id: branchId,
        timezone: "Europe/Berlin",
        version: 2,
        weekly: [{ weekday: 7, open: "01:30", close: "03:30" }],
        exceptions: [
          {
            date: "2026-03-30",
            closed: false,
            open: "10:00",
            close: "12:00",
            reason: "extended",
          },
        ],
      });
      expect(resolved!.teacher.assignments).toHaveLength(2);
      expect(resolved!.teacher.availability).toHaveLength(3);
      expect(
        resolved!.branchWindows.map((row) => ({
          date: row.localDate,
          opensAt: new Date(row.opensAt).toISOString(),
          closesAt: new Date(row.closesAt).toISOString(),
          source: row.source,
        })),
      ).toEqual([
        {
          date: "2026-03-29",
          opensAt: "2026-03-29T00:30:00.000Z",
          closesAt: "2026-03-29T01:30:00.000Z",
          source: "weekly",
        },
        {
          date: "2026-03-30",
          opensAt: "2026-03-30T08:00:00.000Z",
          closesAt: "2026-03-30T10:00:00.000Z",
          source: "exception",
        },
      ]);
      const recurring = resolved!.teacherRules.find(
        (row) => row.source === "recurring",
      )!;
      expect(new Date(recurring.startsAt).toISOString()).toBe(
        "2026-03-29T00:00:00.000Z",
      );
      expect(new Date(recurring.endsAt!).toISOString()).toBe(
        "2026-03-29T02:00:00.000Z",
      );
      expect(
        resolved!.teacherRules.filter((row) => row.source === "interval"),
      ).toHaveLength(1);

      await expectConstraint(
        client,
        () =>
          client.query(
            `
              update app.branches
              set timezone_name = 'Mars/Olympus'
              where id = $1
            `,
            [branchId],
          ),
        "23514",
      );
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
