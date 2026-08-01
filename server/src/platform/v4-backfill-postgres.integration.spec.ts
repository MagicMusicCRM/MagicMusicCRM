import { randomUUID } from "crypto";
import { Pool } from "pg";
import { runBackfill } from "./v4-backfill";

const databaseUrl = process.env.V4_PLATFORM_TEST_DATABASE_URL
  ?? process.env.DATABASE_URL
  ?? "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";

describe("T8.3.1 production backfill", () => {
  const pool = new Pool({ connectionString: databaseUrl, max: 2 });
  const userId = randomUUID();
  let profileId = "";
  let staffId = "";

  beforeAll(async () => {
    await pool.query(
      `insert into app.users (
         id, email, role, is_app_account, profile_completed
       ) values ($1, $2, 'manager', true, true)`,
      [userId, `v4-backfill-${userId}@example.invalid`],
    );
    const profile = await pool.query<{ id: string }>(
      `insert into app.profiles (user_id, first_name, last_name)
       values ($1, 'Backfill', 'Fixture') returning id`,
      [userId],
    );
    profileId = profile.rows[0]!.id;
    const staff = await pool.query<{ id: string }>(
      `insert into app.staff_members (profile_id, role, status)
       values ($1, 'manager', 'working') returning id`,
      [profileId],
    );
    staffId = staff.rows[0]!.id;
  });

  afterAll(async () => {
    await pool.query("delete from app.user_crm_links where user_id = $1", [userId]);
    if (staffId) {
      await pool.query("delete from app.staff_members where id = $1", [staffId]);
    }
    if (profileId) {
      await pool.query("delete from app.profiles where id = $1", [profileId]);
    }
    await pool.query("delete from app.users where id = $1", [userId]);
    await pool.end();
  });

  it("plans one deterministic row, applies it once, and is restartable", async () => {
    const dryRun = await runBackfill(pool, "dry-run");
    expect(dryRun.candidates).toContainEqual({
      kind: "access-link",
      entityId: userId,
      relatedId: staffId,
    });
    expect(dryRun.summary.reviewQueue).toBe(0);

    const before = await pool.query<{ count: string }>(
      "select count(*)::text as count from app.user_crm_links where user_id = $1",
      [userId],
    );
    expect(before.rows[0]?.count).toBe("0");

    const first = await runBackfill(pool, "apply");
    expect(first.summary.applied).toBe(1);
    expect(first.summary.reviewQueue).toBe(0);

    const second = await runBackfill(pool, "apply");
    expect(second.summary).toMatchObject({
      candidates: 0,
      applied: 0,
      reviewQueue: 0,
    });
  });
});
